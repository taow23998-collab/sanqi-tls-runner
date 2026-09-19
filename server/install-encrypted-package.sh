#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run as root: sudo bash server/install-encrypted-package.sh <encrypted-package>" >&2
  exit 1
fi

PACKAGE="${1:-}"
PASSPHRASE_FILE="${SMA_TLS_PACKAGE_PASSPHRASE_FILE:-/root/.sanqi-tls-deploy-bootstrap/package-passphrase}"
RECEIVER="${SMA_TLS_RECEIVER:-/usr/local/sbin/sanqi-tls-receive}"

[[ -n "${PACKAGE}" && -f "${PACKAGE}" ]] || {
  echo "Usage: sudo bash server/install-encrypted-package.sh <encrypted-package>" >&2
  exit 1
}
[[ -f "${PASSPHRASE_FILE}" ]] || {
  echo "Missing package passphrase file: ${PASSPHRASE_FILE}" >&2
  exit 1
}
[[ -x "${RECEIVER}" ]] || {
  echo "Missing TLS receiver: ${RECEIVER}" >&2
  exit 1
}

openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -md sha256 \
  -in "${PACKAGE}" \
  -pass file:"${PASSPHRASE_FILE}" |
  "${RECEIVER}"
