# Sanqi TLS Runner

Minimal public GitHub Actions runner for the Sanqi wildcard TLS certificate.

## Scope

This repository contains **no SMA application source code, business data, server passwords, root SSH private keys, or user information**.

It provides:

```text
Let's Encrypt
↓
Tencent DNSPod DNS-01
↓
37psychology.cn + *.37psychology.cn
↓
restricted certificate-only SSH deployment
```

The SMA server itself does not contact Let's Encrypt and does not store DNSPod API credentials.

## Verified status

Let's Encrypt **Staging DNS-01 has passed** for both:

- `37psychology.cn`
- `*.37psychology.cn`

The test confirmed TXT creation, validation, TXT cleanup, certificate issuance, hostname validation, and ephemeral private-key cleanup.

## Security model

- No `pull_request` workflow uses Repository Secrets.
- `actions/checkout` is pinned to an exact commit.
- `acme.sh 3.1.4` is pinned to exact upstream commit `3661fd86b6304115e42f43910e6dd452ab9866d6`.
- No certificate/private-key artifact is uploaded.
- Staging and Production private keys exist only on the ephemeral runner until Production is sent directly to the restricted server account.
- Production does **not** use root SSH credentials.
- The server deploy account is forced to one root-owned certificate receiver command and cannot obtain an interactive shell through the authorized deploy key.
- The SSH host key is pinned through a Repository Secret; `StrictHostKeyChecking=yes` is enforced.

## Repository Secrets

DNSPod:

```text
TENCENT_SECRET_ID
TENCENT_SECRET_KEY
```

After the restricted server deploy account is bootstrapped:

```text
SMA_TLS_DEPLOY_SSH_KEY
SMA_TLS_DEPLOY_KNOWN_HOSTS
```

Do not paste secret values into commits, issues, chat, screenshots, or workflow YAML.

## Workflows

`.github/workflows/runner-smoke.yml`

Validates scripts, confirms the free GitHub-hosted Ubuntu runner, and checks Let's Encrypt Staging reachability.

`.github/workflows/wildcard-staging.yml`

Performs the real Let's Encrypt Staging DNS-01 test. It never persists the resulting certificate.

`.github/workflows/wildcard-production.yml`

Manual-only. It:

1. issues the real Let's Encrypt production wildcard certificate;
2. validates the pinned restricted SSH identity and host key;
3. pipes only the certificate package to `sanqi-tls-deploy`;
4. relies on the server forced command to validate the certificate/key before installation;
5. deletes all private material from the ephemeral runner.

It does not run until both deploy Repository Secrets exist.

## One-time server bootstrap

Run `server/bootstrap-restricted-deploy.sh` as root on the SMA server with its public SSH host and public SSH NAT port.

The script:

- creates `sanqi-tls-deploy`;
- installs a root-owned certificate receiver;
- restricts the deploy SSH key to that receiver command;
- generates a dedicated ED25519 client key;
- writes the exact SSH known-hosts entry.

It then tells the administrator where to copy the two deploy secret values from. The temporary server copy of the client private key should be deleted after Production deployment succeeds.

## Renewal

Automatic scheduled Production renewal will be enabled only after the first manual Production issue/deploy run passes end to end.
