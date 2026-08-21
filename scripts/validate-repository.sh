#!/bin/sh
set -eu
[ "$#" -eq 2 ] || exit 64
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 || { echo "sudo is required for pkg validation" >&2; exit 77; }
  exec sudo -n "$0" "$@"
fi
repo="$(realpath "$1")"; pub="$(realpath "$2")"
for file in meta.conf data.pkg packagesite.pkg filesite.pkg SHA256; do [ -f "$repo/$file" ] || { echo "missing $file" >&2; exit 65; }; done
tmp="$(mktemp -d -t usque-repo-check)"; trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/repos" "$tmp/db" "$tmp/cache" "$tmp/repository"
cp -R "$repo/." "$tmp/repository/"
repo="$tmp/repository"
cat > "$tmp/repos/Usque.conf" <<EOF
Usque: {
  url: "file://$repo",
  mirror_type: "none",
  signature_type: "pubkey",
  pubkey: "$pub",
  enabled: yes
}
EOF
REPOS_DIR="$tmp/repos" PKG_DBDIR="$tmp/db" PKG_CACHEDIR="$tmp/cache" pkg update -f
catalog="$(REPOS_DIR="$tmp/repos" PKG_DBDIR="$tmp/db" PKG_CACHEDIR="$tmp/cache" pkg rquery -r Usque '%n|%v|%q|%o' | sort)"
[ "$(printf '%s\n' "$catalog" | sed '/^$/d' | wc -l | tr -d ' ')" -eq 2 ] || { printf '%s\n' "$catalog" >&2; exit 65; }
printf '%s\n' "$catalog" | grep -q '^os-usque|' || exit 65
printf '%s\n' "$catalog" | grep -q '^usque-nativetun|' || exit 65
count=0
for package in "$repo"/os-usque-*.pkg "$repo"/usque-nativetun-*.pkg; do
  [ "$(pkg query -F "$package" '%q')" = "FreeBSD:15:amd64" ] || exit 65
  count=$((count + 1))
done
[ "$count" -eq 2 ] || exit 65
(CDPATH= cd -- "$repo" && sha256 -c SHA256)
echo "Repository signature and package set validated"
