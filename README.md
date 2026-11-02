# freeswitch-webex-lgw

Lean FreeSWITCH Docker image for **Webex Calling registration-based trunks** (local gateway / fax / PSTN breakout). No SignalWire modules; TLS 1.2 toward Webex SBCs; optional T.38 inbound fax dialplan.

**Image:** `ghcr.io/jmetdev/freeswitch-webex-lgw`

## Quick start (new host)

```bash
git clone https://github.com/jmetdev/freeswitch-webex-lgw.git
cd freeswitch-webex-lgw
cp .env.example .env
# Set ESL_PASSWORD, EXTERNAL_SIP_IP, EXTERNAL_RTP_IP, and WEBEX_*
mkdir -p runtime/recordings runtime/fax runtime/logs
docker compose pull
docker compose up -d
./scripts/webex-register-status.sh
```

Or build locally with `docker compose up -d --build`. The published image is `ghcr.io/jmetdev/freeswitch-webex-lgw:latest` (linux/amd64 and linux/arm64).

Expect `State    REGED` once Control Hub credentials and the public IP are correct. **REGED is not Control Hub Online.** A registration trunk goes Online only when the From URI is `sip:LINEPORT@REGISTRAR;otg=WEBEX_OTG`. No public DNS name is involved. See [docs/WEBEX-DEPLOY.md](docs/WEBEX-DEPLOY.md).

### Alert Office on the same host

The image includes `mod_conference`. Dialing **2111** from Webex joins conference `2111` (silent while alone, auto-recorded). Connected-party identity is **Alert Office**.

1. In Control Hub, route **2111** to this registration trunk.
2. Set `ESL_LISTEN_IP` to the host LAN IP or `0.0.0.0`. Do not leave it on `127.0.0.1` if Alert Office is another container.
3. Point Alert Office `FREESWITCH_ESL_HOST` at that LAN IP, port `8021`, and set `FREESWITCH_ESL_PASSWORD` to the same value as `ESL_PASSWORD`. A compose recreate of Alert Office from a new `.env` will break ESL if those passwords differ.
4. Share recordings: in this `.env` set `RECORDINGS_HOST_DIR` and `RECORDINGS_CONTAINER_DIR` to the host directory Alert Office mounts as `/recordings` (for example `/opt/alertoffice/recordings`). Recreate this container after changing those variables.

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
| `scripts/enable-webex-contact-fqdn.sh` | Certificate-based Contact FQDN only. Do not run on a registration trunk |
| `scripts/smoke-test.sh` | Module / ESL smoke test |

## Networking

Linux VPS: use `network_mode: host` (default compose). Open inbound **TCP 5071** and **UDP 16384–32768**; outbound **TCP 8934** to Webex SBC ranges. Details: [docs/HOSTINGER-FIREWALL.md](docs/HOSTINGER-FIREWALL.md).

ESL listens on `127.0.0.1:8021` unless `ESL_LISTEN_IP` is set to this host's LAN address or `0.0.0.0`. Other containers must use that address. Access is the `esl` ACL (loopback and RFC1918). Without it, FreeSWITCH answers non-loopback clients with `text/rude-rejection` before password auth. Do not publish `8021` publicly.

## Deploy alternatives

Compose on a VPS is the primary path. Other options (Podman, cloud-init, Ansible, K8s hostNetwork) are summarized in [docs/DEPLOY-OPTIONS.md](docs/DEPLOY-OPTIONS.md).

## Consumers

Alert Office uses this image for ESL (`conference json_list`, kick-all) and conference recordings. The 2111 dialplan ships in `profiles/webex/`. Other overlays can still be added in `runtime/config` on the host.

From workspace root: `make deploy-webex` (uses `COMPOSE_MODE=pull` and `ghcr.io/jmetdev/freeswitch-webex-lgw:latest` by default).

### Migrating from `/opt/ccc-freeswitch-webex`

On an existing host, copy `runtime/config/vars.xml` and `.env` into `/opt/freeswitch-webex-lgw`, then run deploy with `REMOTE_DIR=/opt/freeswitch-webex-lgw`. Stop the old compose stack under `/opt/ccc-freeswitch-webex` when satisfied.
