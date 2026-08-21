#!/bin/sh
set -eu
[ "$#" -eq 3 ] || { echo "usage: USQUE_REPO_SIGNING_KEY=/path/key $0 <release> <plugin.pkg> <runtime.pkg>" >&2; exit 64; }
release="$1"; plugin="$2"; runtime="$3"; key="${USQUE_REPO_SIGNING_KEY:-}"
case "$release" in ''|*[!0-9.]*|.*|*..*|*.) exit 64;; esac
[ -f "$key" ] || { echo "valid signing key required" >&2; exit 66; }
[ "$(stat -f '%Lp' "$key")" = 400 ] || { echo "signing key mode must be 0400" >&2; exit 77; }
dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"; root="$(CDPATH= cd -- "$dir/.." && pwd)"; key="$(realpath "$key")"
case "$key" in "$root"/*) echo "signing key must be outside repository" >&2; exit 77;; esac
tmp="$(mktemp -d -t usque-repo)"; trap 'rm -rf "$tmp"' EXIT HUP INT TERM; stage="$tmp/catalog"; mkdir -p "$stage"
abi="FreeBSD:15:amd64"; have_p=0; have_r=0
for file in "$plugin" "$runtime"; do
  [ -f "$file" ] || exit 66
  meta="$(pkg query -F "$file" '%n|%v|%q|%o')"; oldifs="$IFS"; IFS='|'; set -- $meta; IFS="$oldifs"
  name="$1"; version="$2"; package_abi="$3"; origin="$4"
  [ "$package_abi" = "$abi" ] || { echo "unexpected ABI: $package_abi" >&2; exit 65; }
  case "$name|$origin" in
    os-usque\|opnsense/os-usque) have_p=$((have_p + 1));;
    usque-nativetun\|security/usque-nativetun) have_r=$((have_r + 1));;
    *) echo "unexpected package: $name ($origin)" >&2; exit 65;;
  esac
  install -m 0644 "$file" "$stage/$name-$version.pkg"
done
[ "$have_p" -eq 1 ] && [ "$have_r" -eq 1 ] || { echo "exactly two required packages expected" >&2; exit 65; }
target="$root/docs/packages/$release/$abi"
case "$target" in "$root/docs/packages/"*) ;; *) exit 70;; esac
if [ -d "$target" ]; then
  for new in "$stage"/*.pkg; do
    name="$(pkg query -F "$new" '%n')"; version="$(pkg query -F "$new" '%v')"
    old="$(find "$target" -maxdepth 1 -type f -name "$name-*.pkg" | head -n 1)"; [ -n "$old" ] || continue
    old_version="$(pkg query -F "$old" '%v')"
    if [ "$version" = "$old_version" ]; then
      cmp -s "$new" "$old" || { echo "$name $version changed without version bump" >&2; exit 65; }
    elif [ "$(pkg version -t "$version" "$old_version")" = "<" ]; then
      echo "version rollback rejected: $name $old_version -> $version" >&2; exit 65
    fi
  done
fi
pkg repo -l "$stage" "eddsa:$key"
(CDPATH= cd -- "$stage" && sha256 *.pkg > SHA256)
"$dir/validate-repository.sh" "$stage" "$root/docs/bootstrap/usque-repo.pub"
parent="$(dirname -- "$target")"; mkdir -p "$parent"
if [ -e "$target" ]; then
  case "$(realpath "$parent")" in "$root/docs/packages/"*) ;; *) exit 70;; esac
  rm -rf "$target"
fi
mv "$stage" "$target"; echo "Published signed catalog: $target"
