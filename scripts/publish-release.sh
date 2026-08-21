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
case "$release" in
  26.7)
    pkg_url="https://pkg.opnsense.org/FreeBSD:15:amd64/26.7/latest/All/pkg-2.3.1_1.pkg"
    pkg_sha256="cac4fba478adbaffdcccb3c3ef80899c85d88ca45b3bf6b47b5b54e064512d94"
    ;;
  *) echo "no pinned OPNsense pkg tool for release $release" >&2; exit 65;;
esac
tmp="$(mktemp -d -t usque-release)"; trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/release" "$tmp/pkg-root"
fetch -qo "$tmp/opnsense-pkg.pkg" "$pkg_url"
[ "$(sha256 -q "$tmp/opnsense-pkg.pkg")" = "$pkg_sha256" ] || { echo "OPNsense pkg tool checksum mismatch" >&2; exit 65; }
tar -xf "$tmp/opnsense-pkg.pkg" -C "$tmp/pkg-root"
repo_pkg="$tmp/pkg-root/usr/local/sbin/pkg-static"
[ "$("$repo_pkg" -v)" = "2.3.1" ] || exit 65
gh release download "$tag" --repo vampywiz17/os-usque --pattern '*.pkg' --dir "$tmp/release"
set -- "$tmp/release"/*.pkg; [ "$#" -eq 2 ] || { echo "exactly two pkg assets required" >&2; exit 65; }
plugin=''; runtime=''
for file in "$@"; do
  case "$("$repo_pkg" query -F "$file" '%n')" in
    os-usque) plugin="$file";;
    usque-nativetun) runtime="$file";;
    *) echo "unexpected asset: $file" >&2; exit 65;;
  esac
done
[ -n "$plugin" ] && [ -n "$runtime" ] || exit 65
USQUE_REPO_PKG="$repo_pkg" "$dir/build-repository.sh" "$release" "$plugin" "$runtime"
if [ "$push" -eq 1 ]; then
  git -C "$root" add -- "docs/packages/$release"
  git -C "$root" commit -m "Publish OPNsense $release catalog from $tag"
  git -C "$root" push origin main
fi
