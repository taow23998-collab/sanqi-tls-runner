# Sanqi TLS Runner

Minimal public GitHub Actions runner for issuing the Sanqi wildcard TLS certificate.

## Scope

This repository contains **no SMA application source code, business data, server credentials, SSH private keys, or user information**.

It exists only to validate and later automate:

```text
Let's Encrypt
    ↓
Tencent DNSPod DNS-01
    ↓
37psychology.cn + *.37psychology.cn
```

The SMA server itself does not contact Let's Encrypt and does not store DNSPod API credentials.

## Security model

- No `pull_request` workflow uses repository secrets.
- Wildcard issuance is triggered only by an explicit staging trigger file change or manual workflow dispatch.
- GitHub Actions permissions are `contents: read` only.
- `actions/checkout` is pinned to an exact commit.
- `acme.sh 3.1.4` is pinned to exact upstream commit:
  `3661fd86b6304115e42f43910e6dd452ab9866d6`.
- Staging certificates/private keys stay only in the ephemeral GitHub-hosted runner and are deleted at the end of the job.
- No certificate artifact is uploaded.
- Production deployment to the SMA server is intentionally not implemented yet.

## Required Repository Secrets

Configure these only in:

```text
Settings
→ Secrets and variables
→ Actions
→ Repository secrets
```

Names:

```text
TENCENT_SECRET_ID
TENCENT_SECRET_KEY
```

Do not paste either value into issues, commits, README files, chat, screenshots, or workflow YAML.

## Current workflow

`.github/workflows/runner-smoke.yml`

Verifies that the public repository can obtain a GitHub-hosted Ubuntu runner and reach the Let's Encrypt staging directory. It uses no secrets and performs no DNS changes.

`.github/workflows/wildcard-staging.yml`

Runs only for manual dispatch or a change to `triggers/staging.txt`.

If both Repository Secrets are present, it performs a real **Let's Encrypt Staging** DNS-01 issuance for:

- `37psychology.cn`
- `*.37psychology.cn`

If the secrets are absent, it exits successfully with a notice and performs no DNS changes.

## Production

Production issuance and secure certificate deployment will be added only after Staging passes.
