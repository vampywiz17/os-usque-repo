#!/bin/sh
set -eu
[ "$#" -eq 2 ] || [ "$#" -eq 3 ] || exit 64
release="$1"; tag="$2"; push=0
if [ "$#" -eq 3 ]; then [ "$3" = --push ] || exit 64; push=1; fi
dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"; root="$(CDPATH= cd -- "$dir/.." && pwd)"
if [ "$push" -eq 1 ]; then
  [ "$(git -C "$root" branch --show-current)" = main ] || { echo "--push requires main" >&2; exit 65; }
  [ -z "$(git -C "$root" status --porcelain)" ] || { echo "--push requires a clean tree" >&2; exit 65; }
fi
tmp="$(mktemp -d -t usque-release)"; trap 'rm -rf "$tmp"' EXIT HUP INT TERM
gh release download "$tag" --repo vampywiz17/os-usque --pattern '*.pkg' --dir "$tmp"
set -- "$tmp"/*.pkg; [ "$#" -eq 2 ] || { echo "exactly two pkg assets required" >&2; exit 65; }
plugin=''; runtime=''
for file in "$@"; do
  case "$(pkg query -F "$file" '%n')" in
    os-usque) plugin="$file";;
    usque-nativetun) runtime="$file";;
    *) echo "unexpected asset: $file" >&2; exit 65;;
  esac
done
[ -n "$plugin" ] && [ -n "$runtime" ] || exit 65
"$dir/build-repository.sh" "$release" "$plugin" "$runtime"
if [ "$push" -eq 1 ]; then
  git -C "$root" add -- "docs/packages/$release"
  git -C "$root" commit -m "Publish OPNsense $release catalog from $tag"
  git -C "$root" push origin main
fi
