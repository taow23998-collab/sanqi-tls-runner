#!/usr/bin/env bash
set -Eeuo pipefail
set +x

ROOT_DOMAIN="${ROOT_DOMAIN:-37psychology.cn}"
ACME_SERVER="${ACME_SERVER:-https://acme-staging-v02.api.letsencrypt.org/directory}"
ACME_COMMIT="${ACME_COMMIT:-3661fd86b6304115e42f43910e6dd452ab9866d6}"
WORK_ROOT="${WORK_ROOT:-${RUNNER_TEMP:-/tmp}/sanqi-tls-runner}"
SOURCE_DIR="${WORK_ROOT}/acme-src"
ACME_HOME="${WORK_ROOT}/home"
ACME_CONFIG_HOME="${WORK_ROOT}/config"
OUTPUT_DIR="${WORK_ROOT}/output"
CERT_KEY="${OUTPUT_DIR}/wildcard-${ROOT_DOMAIN}.key"
CERT_CHAIN="${OUTPUT_DIR}/wildcard-${ROOT_DOMAIN}.fullchain.pem"

: "${Tencent_SecretId:?Tencent_SecretId is required}"
: "${Tencent_SecretKey:?Tencent_SecretKey is required}"

for cmd in git openssl; do
  command -v "${cmd}" >/dev/null 2>&1 || {
    echo "Required command not found: ${cmd}" >&2
    exit 1
  }
done

rm -rf "${WORK_ROOT}"
install -d -m 0700 "${SOURCE_DIR}" "${ACME_HOME}" "${ACME_CONFIG_HOME}" "${OUTPUT_DIR}"

git -C "${SOURCE_DIR}" init -q
git -C "${SOURCE_DIR}" remote add origin https://github.com/acmesh-official/acme.sh.git
git -C "${SOURCE_DIR}" fetch -q --depth=1 origin "${ACME_COMMIT}"
git -C "${SOURCE_DIR}" checkout -q --detach FETCH_HEAD

actual_commit="$(git -C "${SOURCE_DIR}" rev-parse HEAD)"
if [[ "${actual_commit}" != "${ACME_COMMIT}" ]]; then
  echo "acme.sh commit mismatch: expected ${ACME_COMMIT}, got ${actual_commit}" >&2
  exit 1
fi

(
  cd "${SOURCE_DIR}"
  ./acme.sh --install \
    --home "${ACME_HOME}" \
    --config-home "${ACME_CONFIG_HOME}" \
    --nocron
)

ACME_BIN="${ACME_HOME}/acme.sh"

"${ACME_BIN}" --set-default-ca \
  --server "${ACME_SERVER}" \
  --home "${ACME_HOME}" \
  --config-home "${ACME_CONFIG_HOME}"

if [[ "${ACME_SERVER}" == *"staging"* ]]; then
  cert_mode="staging"
else
  cert_mode="production"
fi
echo "Issuing ${cert_mode} wildcard certificate for ${ROOT_DOMAIN} and *.${ROOT_DOMAIN}"
echo "Pinned acme.sh commit: ${ACME_COMMIT}"

"${ACME_BIN}" --issue \
  --server "${ACME_SERVER}" \
  --dns dns_tencent \
  --dnssleep 120 \
  --keylength ec-256 \
  -d "${ROOT_DOMAIN}" \
  -d "*.${ROOT_DOMAIN}" \
  --home "${ACME_HOME}" \
  --config-home "${ACME_CONFIG_HOME}"

"${ACME_BIN}" --install-cert \
  -d "${ROOT_DOMAIN}" --ecc \
  --key-file "${CERT_KEY}" \
  --fullchain-file "${CERT_CHAIN}" \
  --home "${ACME_HOME}" \
  --config-home "${ACME_CONFIG_HOME}"

chmod 0600 "${CERT_KEY}"
chmod 0644 "${CERT_CHAIN}"

openssl x509 -in "${CERT_CHAIN}" -noout -subject -issuer -dates
openssl x509 -in "${CERT_CHAIN}" -checkhost "${ROOT_DOMAIN}" -noout
openssl x509 -in "${CERT_CHAIN}" -checkhost "sma.${ROOT_DOMAIN}" -noout

echo "${cert_mode^^}_WILDCARD_ISSUANCE=PASS"
