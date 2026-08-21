#!/bin/sh
set -eu
[ "$#" -eq 2 ] || exit 64
validator="${USQUE_REPO_VALIDATOR:-$(command -v pkg)}"
[ -x "$validator" ] || { echo "a native pkg validator is required" >&2; exit 66; }
validator="$(realpath "$validator")"
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 || { echo "sudo is required for pkg validation" >&2; exit 77; }
  exec sudo -n env USQUE_REPO_VALIDATOR="$validator" "$0" "$@"
fi
repo="$(realpath "$1")"; pub="$(realpath "$2")"
for file in meta.conf data.pkg packagesite.pkg SHA256; do [ -f "$repo/$file" ] || { echo "missing $file" >&2; exit 65; }; done
for member in data.sig data.pub data; do tar -tf "$repo/data.pkg" | grep -qx "$member" || { echo "missing signed data member: $member" >&2; exit 65; }; done
tmp="$(mktemp -d -t usque-repo-check)"; trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/repos" "$tmp/db" "$tmp/cache" "$tmp/repository" "$tmp/fingerprints/trusted" "$tmp/fingerprints/revoked"
tar -xOf "$repo/data.pkg" data > "$tmp/data.json"
! grep -q '"files":' "$tmp/data.json" || { echo "data.pkg must not embed file lists for OPNsense pkg 2.3.1" >&2; exit 65; }
cp -R "$repo/." "$tmp/repository/"; repo="$tmp/repository"
printf 'function: sha256\nfingerprint: "%s"\n' "$(sha256 -q "$pub")" > "$tmp/fingerprints/trusted/usque"
cat > "$tmp/repos/Usque.conf" <<EOF
Usque: {
  url: "file://$repo",
  mirror_type: "none",
  signature_type: "fingerprints",
  fingerprints: "$tmp/fingerprints",
  enabled: yes
}
EOF
REPOS_DIR="$tmp/repos" PKG_DBDIR="$tmp/db" PKG_CACHEDIR="$tmp/cache" "$validator" update -f
catalog="$(REPOS_DIR="$tmp/repos" PKG_DBDIR="$tmp/db" PKG_CACHEDIR="$tmp/cache" "$validator" rquery -r Usque '%n|%v|%q|%o' | sort)"
[ "$(printf '%s\n' "$catalog" | sed '/^$/d' | wc -l | tr -d ' ')" -eq 2 ] || { printf '%s\n' "$catalog" >&2; exit 65; }
printf '%s\n' "$catalog" | grep -q '^os-usque|' || exit 65
printf '%s\n' "$catalog" | grep -q '^usque-nativetun|' || exit 65
count=0
for package in "$repo"/All/os-usque-*.pkg "$repo"/All/usque-nativetun-*.pkg; do
  [ "$("$validator" query -F "$package" '%q')" = "FreeBSD:15:amd64" ] || exit 65
  count=$((count + 1))
done
[ "$count" -eq 2 ] || exit 65
(CDPATH= cd -- "$repo" && sha256 -c SHA256)
echo "Repository signature and package set validated with pkg $("$validator" -v)"
