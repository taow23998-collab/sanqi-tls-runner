#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run as root: sudo bash server/bootstrap-restricted-deploy.sh <public-host> <public-ssh-port>" >&2
  exit 1
fi

PUBLIC_HOST="${1:-}"
PUBLIC_PORT="${2:-}"
DEPLOY_USER="sanqi-tls-deploy"
BOOTSTRAP_DIR="/root/.sanqi-tls-deploy-bootstrap"
PRIVATE_KEY="${BOOTSTRAP_DIR}/id_ed25519"
PUBLIC_KEY="${PRIVATE_KEY}.pub"
KNOWN_HOSTS_OUT="${BOOTSTRAP_DIR}/known_hosts"
RECEIVER="/usr/local/sbin/sanqi-tls-receive"
SUDOERS="/etc/sudoers.d/sanqi-tls-deploy"

[[ -n "${PUBLIC_HOST}" && -n "${PUBLIC_PORT}" ]] || {
  echo "Usage: sudo bash server/bootstrap-restricted-deploy.sh <public-host> <public-ssh-port>" >&2
  exit 1
}
[[ "${PUBLIC_PORT}" =~ ^[0-9]+$ ]] || {
  echo "SSH port must be numeric." >&2
  exit 1
}

for cmd in useradd install ssh-keygen openssl tar sha256sum awk sed stat sudo visudo; do
  command -v "${cmd}" >/dev/null 2>&1 || {
    echo "Missing required command: ${cmd}" >&2
    exit 1
  }
done

if ! id "${DEPLOY_USER}" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "${DEPLOY_USER}"
fi

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

cat >"${SUDOERS}" <<EOF
${DEPLOY_USER} ALL=(root) NOPASSWD: ${RECEIVER}
EOF
chmod 0440 "${SUDOERS}"
visudo -cf "${SUDOERS}" >/dev/null

install -d -m 0700 "${BOOTSTRAP_DIR}"
if [[ ! -f "${PRIVATE_KEY}" ]]; then
  ssh-keygen -q -t ed25519 -N '' -C 'sanqi-tls-runner' -f "${PRIVATE_KEY}"
fi
chmod 0600 "${PRIVATE_KEY}"
chmod 0644 "${PUBLIC_KEY}"

home_dir="$(getent passwd "${DEPLOY_USER}" | cut -d: -f6)"
install -d -m 0700 -o "${DEPLOY_USER}" -g "${DEPLOY_USER}" "${home_dir}/.ssh"
pub_line="$(cat "${PUBLIC_KEY}")"
printf 'restrict,command="sudo -n %s" %s\n' "${RECEIVER}" "${pub_line}" >"${home_dir}/.ssh/authorized_keys"
chown "${DEPLOY_USER}:${DEPLOY_USER}" "${home_dir}/.ssh/authorized_keys"
chmod 0600 "${home_dir}/.ssh/authorized_keys"

host_pub="/etc/ssh/ssh_host_ed25519_key.pub"
[[ -f "${host_pub}" ]] || {
  echo "Missing OpenSSH ED25519 host public key: ${host_pub}" >&2
  exit 1
}
host_type="$(awk '{print $1}' "${host_pub}")"
host_key="$(awk '{print $2}' "${host_pub}")"
printf '[%s]:%s %s %s\n' "${PUBLIC_HOST}" "${PUBLIC_PORT}" "${host_type}" "${host_key}" >"${KNOWN_HOSTS_OUT}"
chmod 0600 "${KNOWN_HOSTS_OUT}"

cat <<EOF

Restricted TLS deploy account is ready.

Create these two additional GitHub Repository Secrets in sanqi-tls-runner:

1) SMA_TLS_DEPLOY_SSH_KEY
   Copy the COMPLETE contents of:
   ${PRIVATE_KEY}

2) SMA_TLS_DEPLOY_KNOWN_HOSTS
   Copy the COMPLETE contents of:
   ${KNOWN_HOSTS_OUT}

Do not paste either value into chat.

After both GitHub Secrets are saved and Production deployment succeeds,
delete the temporary local copy of the client private key with:

  shred -u "${PRIVATE_KEY}"

The public key and forced-command account remain on the server for renewals.
EOF
