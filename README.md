# freeswitch-webex-lgw

Lean FreeSWITCH Docker image for **Webex Calling registration-based trunks** (local gateway / fax / PSTN breakout). No SignalWire modules; TLS 1.2 toward Webex SBCs; optional T.38 inbound fax dialplan.

**Image:** `ghcr.io/jmetdev/freeswitch-webex-lgw`

## Quick start

```bash
cp .env.example .env
# Fill WEBEX_* and EXTERNAL_*_IP in .env (or edit runtime/config/vars.xml after sync)
make sync
docker compose up -d --build   # or pull IMAGE:TAG from GHCR
./scripts/webex-register-status.sh
```

Expect `State    REGED` once Control Hub credentials and public IP are correct. **REGED ≠ Control Hub Online** — see [docs/WEBEX-DEPLOY.md](docs/WEBEX-DEPLOY.md).

## Layout

| Layer | Path | Role |
|-------|------|------|
| Image | `Dockerfile` | FreeSWITCH + entrypoint + seed config |
| Profile | `profiles/webex/` | Gateway XML, dialplan, Webex vars |
| Runtime | `runtime/` (gitignored) | Live config, logs, fax spool |

`FS_PROFILE=webex` (default) overlays the Webex gateway and dialplan at container start. Secrets belong in `.env` or `runtime/config/vars.xml`, not in git.

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/sync-config-to-runtime.sh` | Seed `runtime/config` from `config/` + profile |
| `scripts/resolve-webex-srv.sh` | Resolve sipconnect outbound proxy SRV on the host |
| `scripts/webex-register-status.sh` | Gateway registration snapshot |
| `scripts/webex-siptrace.sh` | Sofia SIP trace on/off |
| `scripts/enable-webex-contact-fqdn.sh` | Uncomment Contact FQDN params after Control Hub provisions FQDN |
| `scripts/smoke-test.sh` | Module / ESL smoke test |

## Networking

Linux VPS: use `network_mode: host` (default compose). Open inbound **TCP 5071** and **UDP 16384–32768**; outbound **TCP 8934** to Webex SBC ranges. Details: [docs/HOSTINGER-FIREWALL.md](docs/HOSTINGER-FIREWALL.md).

ESL listens on `127.0.0.1:8021` unless `ESL_LISTEN_IP` is set to this host's LAN address or `0.0.0.0`. Other containers must use that address. Access is the `esl` ACL (loopback and RFC1918). Without it, FreeSWITCH answers non-loopback clients with `text/rude-rejection` before password auth. Do not publish `8021` publicly.

## Deploy alternatives

Compose on a VPS is the primary path. Other options (Podman, cloud-init, Ansible, K8s hostNetwork) are summarized in [docs/DEPLOY-OPTIONS.md](docs/DEPLOY-OPTIONS.md).

## Consumers

Projects such as CCC recording portal can deploy this image and add their own dialplan overlays separately — this repo stays Webex-LGW-only.

From workspace root: `make deploy-webex` (uses `COMPOSE_MODE=pull` and `ghcr.io/jmetdev/freeswitch-webex-lgw:latest` by default).

### Migrating from `/opt/ccc-freeswitch-webex`

On an existing host, copy `runtime/config/vars.xml` and `.env` into `/opt/freeswitch-webex-lgw`, then run deploy with `REMOTE_DIR=/opt/freeswitch-webex-lgw`. Stop the old compose stack under `/opt/ccc-freeswitch-webex` when satisfied.
