# os-usque package repository

Signed FreeBSD pkg repository for the unofficial os-usque OPNsense plugin and its usque-nativetun runtime dependency.

> WARNING: This is a third-party repository. It is not an official OPNsense repository, and OPNsense does not support installations modified with third-party repositories. The software is experimental and is not recommended for production use. Back up the configuration and take a VM snapshot before installation, and be prepared to restore or reinstall the firewall.

The repository is intentionally narrow. Every catalog contains only os-usque and usque-nativetun.

## Supported catalogs

| OPNsense release | FreeBSD package ABI | Catalog |
| --- | --- | --- |
| 26.7 | FreeBSD:15:amd64 | packages/26.7/FreeBSD:15:amd64 |

Catalogs are separated by OPNsense major release and ABI. Never configure a catalog for a different OPNsense release or ABI.

## Install on OPNsense 26.7

Run as root:

    fetch -o /tmp/usque-repo.pub \
      https://vampywiz17.github.io/os-usque-repo/bootstrap/usque-repo.pub

    test "$(sha256 -q /tmp/usque-repo.pub)" = \
      "4b2380b1f601011f8d31fc0c97e5a0b7d4d3f77964e14d3f84d6e044b120e404" \
      || { echo "Unexpected repository public-key fingerprint" >&2; exit 1; }

    install -d -m 0755 /usr/local/etc/pkg/keys
    install -m 0644 /tmp/usque-repo.pub \
      /usr/local/etc/pkg/keys/usque-repo.pub

    fetch -o /usr/local/etc/pkg/repos/Usque.conf \
      https://vampywiz17.github.io/os-usque-repo/bootstrap/26.7/Usque.conf

    pkg update -f
    pkg install os-usque

The plugin declares its runtime dependency, so pkg installs or updates both packages together. Review the os-usque source repository before configuration: https://github.com/vampywiz17/os-usque

## Update

    pkg update -f
    pkg upgrade os-usque usque-nativetun

## Remove the repository

    rm /usr/local/etc/pkg/repos/Usque.conf
    rm /usr/local/etc/pkg/keys/usque-repo.pub
    pkg update -f

Removing the repository configuration does not uninstall already installed packages.

## Publishing

Publishing runs on a trusted FreeBSD 15 builder. The private EdDSA key must stay outside this Git repository and must have mode 0400.

    USQUE_REPO_SIGNING_KEY=/secure/path/repo.key \
      ./scripts/publish-release.sh 26.7 v0.2.21

The script downloads exactly two pkg assets from the selected os-usque release, validates package names, origins and ABI, rejects unintended packages and version rollback, signs the repository, and validates the signature with an isolated pkg database.

After reviewing the generated catalog, commit the explicit docs/packages/26.7 path. The optional --push mode performs this step only when main is completely clean before generation.

## Signing-key policy

The public key is stored at docs/bootstrap/usque-repo.pub. The private key must never be committed or uploaded. Keep an offline backup: losing it requires distributing a new public key to every installed firewall.
