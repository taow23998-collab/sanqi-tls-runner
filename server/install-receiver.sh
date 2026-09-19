#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run as root: sudo bash server/install-receiver.sh" >&2
  exit 1
fi

RECEIVER="/usr/local/sbin/sanqi-tls-receive"
STATE_DIR="/root/.sanqi-tls-deploy-bootstrap"
PASSPHRASE_FILE="${STATE_DIR}/package-passphrase"

for cmd in install openssl tar sha256sum awk stat cmp systemctl; do
  command -v "${cmd}" >/dev/null 2>&1 || {
    echo "Missing required command: ${cmd}" >&2
    exit 1
  }
done

cat >"${RECEIVER}" <<'RECEIVER_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
ulimit -f 4096

ROOT_DOMAIN="37psychology.cn"
TLS_DIR="/etc/sanqi/tls"
KEY_NAME="wildcard-${ROOT_DOMAIN}.key"
CHAIN_NAME="wildcard-${ROOT_DOMAIN}.fullchain.pem"
ARCHIVE="$(mktemp /var/tmp/sanqi-tls-upload.XXXXXX.tar.gz)"
WORK="$(mktemp -d /var/tmp/sanqi-tls-work.XXXXXX)"
NEW_KEY="${TLS_DIR}/.${KEY_NAME}.new.$$"
NEW_CHAIN="${TLS_DIR}/.${CHAIN_NAME}.new.$$"

cleanup() {
  rm -f "${ARCHIVE}" "${NEW_KEY}" "${NEW_CHAIN}"
  rm -rf "${WORK}"
}
trap cleanup EXIT

cat >"${ARCHIVE}"

bytes="$(stat -c %s "${ARCHIVE}")"
if (( bytes <= 0 || bytes > 2097152 )); then
  echo "TLS package size is invalid: ${bytes} bytes" >&2
  exit 1
fi

mapfile -t entries < <(tar -tzf "${ARCHIVE}")
if [[ "${#entries[@]}" -ne 2 ]]; then
  echo "TLS package must contain exactly two files." >&2
  exit 1
fi

printf '%s\n' "${entries[@]}" | sort >"${WORK}/actual.list"
printf '%s\n' "${KEY_NAME}" "${CHAIN_NAME}" | sort >"${WORK}/expected.list"
cmp -s "${WORK}/actual.list" "${WORK}/expected.list" || {
  echo "TLS package contains unexpected paths." >&2
  exit 1
}

tar -xzf "${ARCHIVE}" -C "${WORK}" --no-same-owner --no-same-permissions

KEY="${WORK}/${KEY_NAME}"
CHAIN="${WORK}/${CHAIN_NAME}"

openssl pkey -in "${KEY}" -check -noout >/dev/null
openssl x509 -in "${CHAIN}" -noout >/dev/null
openssl x509 -in "${CHAIN}" -checkend 86400 -noout >/dev/null
openssl x509 -in "${CHAIN}" -checkhost "${ROOT_DOMAIN}" -noout >/dev/null
openssl x509 -in "${CHAIN}" -checkhost "sma.${ROOT_DOMAIN}" -noout >/dev/null

issuer="$(openssl x509 -in "${CHAIN}" -noout -issuer)"
if grep -qi 'STAGING' <<<"${issuer}"; then
  echo "Refusing to install a staging certificate." >&2
  exit 1
fi
if ! grep -qi "Let's Encrypt" <<<"${issuer}"; then
  echo "Unexpected certificate issuer: ${issuer}" >&2
  exit 1
fi

key_pub="$(openssl pkey -in "${KEY}" -pubout 2>/dev/null | sha256sum | awk '{print $1}')"
cert_pub="$(openssl x509 -in "${CHAIN}" -pubkey -noout 2>/dev/null | sha256sum | awk '{print $1}')"
[[ "${key_pub}" == "${cert_pub}" ]] || {
  echo "Certificate and private key do not match." >&2
  exit 1
}

install -d -m 0700 -o root -g root "${TLS_DIR}"
install -m 0600 -o root -g root "${KEY}" "${NEW_KEY}"
install -m 0644 -o root -g root "${CHAIN}" "${NEW_CHAIN}"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
if [[ -f "${TLS_DIR}/${KEY_NAME}" || -f "${TLS_DIR}/${CHAIN_NAME}" ]]; then
  backup="${TLS_DIR}/archive/${timestamp}"
  install -d -m 0700 -o root -g root "${backup}"
  [[ -f "${TLS_DIR}/${KEY_NAME}" ]] && cp -a "${TLS_DIR}/${KEY_NAME}" "${backup}/"
  [[ -f "${TLS_DIR}/${CHAIN_NAME}" ]] && cp -a "${TLS_DIR}/${CHAIN_NAME}" "${backup}/"
fi

mv -f "${NEW_KEY}" "${TLS_DIR}/${KEY_NAME}"
mv -f "${NEW_CHAIN}" "${TLS_DIR}/${CHAIN_NAME}"
chmod 0600 "${TLS_DIR}/${KEY_NAME}"
chmod 0644 "${TLS_DIR}/${CHAIN_NAME}"

if command -v nginx >/dev/null 2>&1; then
  nginx -t
  if systemctl is-active --quiet nginx; then
    systemctl reload nginx
  fi
fi

serial="$(openssl x509 -in "${TLS_DIR}/${CHAIN_NAME}" -noout -serial)"
expiry="$(openssl x509 -in "${TLS_DIR}/${CHAIN_NAME}" -noout -enddate)"
echo "TLS_DEPLOY=PASS ${serial} ${expiry}"
RECEIVER_EOF

chmod 0755 "${RECEIVER}"
chown root:root "${RECEIVER}"

install -d -m 0700 "${STATE_DIR}"
if [[ ! -f "${PASSPHRASE_FILE}" ]]; then
  openssl rand -hex 32 >"${PASSPHRASE_FILE}"
fi
chmod 0600 "${PASSPHRASE_FILE}"

echo "TLS receiver installed: ${RECEIVER}"
echo "Package passphrase stored root-only at: ${PASSPHRASE_FILE}"
echo "Copy that passphrase once into GitHub Repository Secret SMA_TLS_PACKAGE_PASSPHRASE."
