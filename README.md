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
AES-256-CBC encrypted, one-day GitHub artifact
↓
administrator downloads artifact
↓
SCP from trusted local Windows PC
↓
SMA server decrypts locally
↓
/usr/local/sbin/sanqi-tls-receive validates and installs
```

The SMA server does not contact Let's Encrypt / ZeroSSL and does not store DNSPod API credentials.

## Verified production baseline

Completed successfully on 2026-09-19:

- free GitHub-hosted Ubuntu runner;
- Let's Encrypt Staging and Production DNS-01;
- DNSPod TXT create / verify / cleanup;
- wildcard coverage for `37psychology.cn` and `*.37psychology.cn`;
- encrypted production artifact creation and one-day upload;
- local decryption on the SMA server;
- receiver validation of certificate, hostname, issuer and private-key match;
- installation into `/etc/sanqi/tls/`;
- Nginx HTTPS gateway;
- public SMA access at `https://sma.37psychology.cn:48939`.

Direct GitHub-hosted-runner SSH deployment was abandoned because the overseas runner could not reach the server's public SSH NAT port reliably. It is not part of the supported production path.

## Security model

- No `pull_request` workflow uses Repository Secrets.
- `actions/checkout` and `actions/upload-artifact` are pinned to exact commits.
- `acme.sh 3.1.4` is pinned to upstream commit `3661fd86b6304115e42f43910e6dd452ab9866d6`.
- Production certificate/private key are encrypted before artifact upload.
- The artifact does not contain the decryption passphrase.
- Artifact retention is one day.
- Plaintext certificate private key and temporary passphrase file are deleted from the ephemeral runner.
- DNSPod credentials exist only as GitHub Repository Secrets.
- The server keeps only the installed certificate/key and a root-only package passphrase.
- The application port remains loopback-only; Nginx is the public HTTPS gateway.

## Repository Secrets

Production packaging uses only:

```text
TENCENT_SECRET_ID
TENCENT_SECRET_KEY
SMA_TLS_PACKAGE_PASSPHRASE
```

Do not store or paste these values in source, chat, screenshots, issues, or logs.

## Production workflow

Workflow file:

```text
.github/workflows/wildcard-production.yml
```

Actions display name:

```text
wildcard-production-package
```

It is manual-only. Before contacting Let's Encrypt it validates all required secrets and the package passphrase.

A successful run produces a one-day artifact containing:

```text
sanqi-tls-production.tar.gz.enc
sanqi-tls-production.tar.gz.enc.sha256
INSTALL.txt
```

## Server bootstrap

For a new server, run as root:

```bash
bash server/install-receiver.sh
```

This installs the root-owned validation receiver and creates a root-only package passphrase when missing. Copy the passphrase once into GitHub Repository Secret `SMA_TLS_PACKAGE_PASSPHRASE`.

## Server installation

After downloading and SCPing the encrypted package to the server:

```bash
bash server/install-encrypted-package.sh /tmp/sanqi-tls-production.tar.gz.enc
```

The receiver accepts only the expected key and fullchain, validates the certificate and key match, rejects staging/unexpected issuers, backs up an existing certificate, installs the new files, runs `nginx -t`, and reloads active Nginx.

Installed paths:

```text
/etc/sanqi/tls/wildcard-37psychology.cn.key
/etc/sanqi/tls/wildcard-37psychology.cn.fullchain.pem
```

## Renewal

The current workflow is deliberately manual. Do not schedule the present production issuance workflow daily or weekly: the runner is ephemeral and a naive schedule would create unnecessary new certificates.

Before the current certificate approaches expiry, add a renewal guard that checks the deployed certificate's remaining lifetime and only issues when renewal is actually due. The current certificate expires in December 2026.
