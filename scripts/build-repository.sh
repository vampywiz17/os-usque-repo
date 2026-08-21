#!/bin/sh
set -eu
[ "$#" -eq 3 ] || { echo "usage: USQUE_REPO_SIGNING_KEY=/path/key USQUE_REPO_PKG=/path/pkg-static $0 <release> <plugin.pkg> <runtime.pkg>" >&2; exit 64; }
release="$1"; plugin="$2"; runtime="$3"; key="${USQUE_REPO_SIGNING_KEY:-}"; repo_pkg="${USQUE_REPO_PKG:-}"
case "$release" in ''|*[!0-9.]*|.*|*..*|*.) exit 64;; esac
[ -x "$repo_pkg" ] || { echo "USQUE_REPO_PKG must point to target OPNsense pkg-static" >&2; exit 66; }
repo_pkg="$(realpath "$repo_pkg")"
[ "$("$repo_pkg" -v)" = "2.3.1" ] || { echo "OPNsense 26.7 pkg-static 2.3.1 is required" >&2; exit 65; }
[ -f "$key" ] || { echo "valid signing key required" >&2; exit 66; }
[ "$(stat -f '%Lp' "$key")" = 400 ] || { echo "signing key mode must be 0400" >&2; exit 77; }
dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"; root="$(CDPATH= cd -- "$dir/.." && pwd)"; key="$(realpath "$key")"
case "$key" in "$root"/*) echo "signing key must be outside repository" >&2; exit 77;; esac
public_key="$root/docs/bootstrap/usque-repo.pub"
tmp="$(mktemp -d -t usque-repo)"; trap 'rm -rf "$tmp"' EXIT HUP INT TERM; stage="$tmp/catalog"; mkdir -p "$stage/All"
abi="FreeBSD:15:amd64"; have_p=0; have_r=0
for file in "$plugin" "$runtime"; do
  [ -f "$file" ] || exit 66
  meta="$("$repo_pkg" query -F "$file" '%n|%v|%q|%o')"; oldifs="$IFS"; IFS='|'; set -- $meta; IFS="$oldifs"
  name="$1"; version="$2"; package_abi="$3"; origin="$4"
  [ "$package_abi" = "$abi" ] || { echo "unexpected ABI: $package_abi" >&2; exit 65; }
  case "$name|$origin" in
    os-usque\|opnsense/os-usque) have_p=$((have_p + 1));;
    usque-nativetun\|security/usque-nativetun) have_r=$((have_r + 1));;
    *) echo "unexpected package: $name ($origin)" >&2; exit 65;;
  esac
  install -m 0644 "$file" "$stage/All/$name-$version.pkg"
done
[ "$have_p" -eq 1 ] && [ "$have_r" -eq 1 ] || { echo "exactly two required packages expected" >&2; exit 65; }
target="$root/docs/packages/$release/$abi"
case "$target" in "$root/docs/packages/"*) ;; *) exit 70;; esac
if [ -d "$target" ]; then
  for new in "$stage"/All/*.pkg; do
    name="$("$repo_pkg" query -F "$new" '%n')"; version="$("$repo_pkg" query -F "$new" '%v')"
    old="$(find "$target" -maxdepth 2 -type f -name "$name-*.pkg" | head -n 1)"; [ -n "$old" ] || continue
    old_version="$("$repo_pkg" query -F "$old" '%v')"
    if [ "$version" = "$old_version" ]; then
      cmp -s "$new" "$old" || { echo "$name $version changed without version bump" >&2; exit 65; }
    elif [ "$("$repo_pkg" version -t "$version" "$old_version")" = "<" ]; then
      echo "version rollback rejected: $name $old_version -> $version" >&2; exit 65
    fi
  done
fi
# Do not request filesite generation here. OPNsense 26.7 ships pkg 2.3.1,
# whose repository reader dereferences checksum-less file entries when a
# two-package dependency set embeds file lists in data.pkg.
"$repo_pkg" repo "$stage" signing_command: "$dir/sign-repository.sh" "$key" "$public_key"
(CDPATH= cd -- "$stage" && sha256 All/*.pkg > SHA256)
USQUE_REPO_VALIDATOR="$repo_pkg" "$dir/validate-repository.sh" "$stage" "$root/docs/bootstrap/usque-repo.pub"
parent="$(dirname -- "$target")"; mkdir -p "$parent"
if [ -e "$target" ]; then
  case "$(realpath "$parent")" in "$root/docs/packages/"*) ;; *) exit 70;; esac
  rm -rf "$target"
fi
mv "$stage" "$target"; echo "Published signed catalog: $target"
