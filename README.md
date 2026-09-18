# Sanqi TLS Runner

Minimal public GitHub Actions runner for the Sanqi wildcard TLS certificate.

## Current architecture

```text
Let's Encrypt
↓
Tencent DNSPod DNS-01
↓
37psychology.cn + *.37psychology.cn
↓
encrypted short-lived GitHub artifact
↓
administrator downloads artifact
↓
SCP from trusted local Windows PC
↓
SMA server decrypts locally
↓
/usr/local/sbin/sanqi-tls-receive validates and installs
```

The SMA server itself does not contact Let's Encrypt and does not store DNSPod API credentials.

## Verified status

Completed successfully:

- free GitHub-hosted Ubuntu runner;
- Let's Encrypt Staging DNS-01;
- Let's Encrypt Production DNS-01;
- root domain and wildcard hostname validation;
- DNSPod TXT create / verify / cleanup;
- Base64 SSH deploy identity validation.

Direct GitHub-hosted-runner SSH to the SMA server was abandoned because the overseas runner timed out connecting to the server's public SSH NAT port. The production certificate package therefore uses encrypted artifact handoff instead.

## Security model

- No `pull_request` workflow uses Repository Secrets.
- `actions/checkout` is pinned to an exact commit.
- `actions/upload-artifact` is pinned to an exact commit.
- `acme.sh 3.1.4` is pinned to exact upstream commit `3661fd86b6304115e42f43910e6dd452ab9866d6`.
- Production certificate/private key are encrypted before artifact upload.
- The artifact does not contain the encryption passphrase.
- Artifact retention is one day.
- Plaintext certificate private key and passphrase files are deleted from the ephemeral runner after packaging.
- The server validates certificate, hostname, issuer, key match, and nginx before installation.

## Repository Secrets used by production packaging

```text
TENCENT_SECRET_ID
TENCENT_SECRET_KEY
SMA_TLS_PACKAGE_PASSPHRASE
```

The package passphrase is generated on the SMA server, stored root-only there, and copied once into GitHub Repository Secrets. Do not paste it into chat, commits, screenshots, or issues.

## Production workflow

`.github/workflows/wildcard-production.yml`

The workflow name displayed in Actions is:

```text
wildcard-production-package
```

It is manual-only. Before contacting Let's Encrypt it validates that all required secrets exist and the package passphrase is at least 32 characters.

After successful production issuance it creates:

```text
sanqi-tls-production.tar.gz.enc
sanqi-tls-production.tar.gz.enc.sha256
INSTALL.txt
```

inside a one-day encrypted artifact.

## Server-side installation

The existing root-owned receiver remains:

```text
/usr/local/sbin/sanqi-tls-receive
```

It validates and installs only:

```text
wildcard-37psychology.cn.key
wildcard-37psychology.cn.fullchain.pem
```

into:

```text
/etc/sanqi/tls/
```

Automatic renewal can be designed later using a China-reachable relay or other trusted handoff. The immediate goal is to finish the first HTTPS deployment safely without exposing the TLS private key.
