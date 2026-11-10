# freeswitch-webex-lgw

Lean FreeSWITCH Docker image for **Webex Calling registration-based trunks** (local gateway / fax / PSTN breakout). No SignalWire modules; TLS 1.2 toward Webex SBCs; optional T.38 inbound fax dialplan.

**Image:** `ghcr.io/jmetdev/freeswitch-webex-lgw`

## Quick start (new host)

```bash
git clone https://github.com/jmetdev/freeswitch-webex-lgw.git
cd freeswitch-webex-lgw
cp .env.example .env
# Set ESL_PASSWORD and WEBEX_* (including WEBEX_OTG). Leave EXTERNAL_* empty.
mkdir -p runtime/recordings runtime/fax runtime/logs
docker compose pull
docker compose up -d
./scripts/webex-register-status.sh
```

Or build locally with `docker compose up -d --build`. The published image is `ghcr.io/jmetdev/freeswitch-webex-lgw:latest` (linux/amd64 and linux/arm64).

Expect `State    REGED` once Control Hub credentials are in `.env`. **REGED is not Control Hub Online.** A registration trunk goes Online when the From URI is `sip:LINEPORT@REGISTRAR;otg=WEBEX_OTG`. Control Hub does not ask for a public IP or DNS name on this trunk type. See [docs/WEBEX-DEPLOY.md](docs/WEBEX-DEPLOY.md).

### Alert Office on the same host

The image includes `mod_conference`. Dialing an Alert Office Group extension from Webex joins conference `<extension>` (silent while alone, auto-recorded). Connected-party identity is **Alert Office**.

The image doesn't hard-code any extension. `profiles/webex/dialplan/default.xml` includes `default/*.xml` and `public/*.xml`, and Alert Office writes `alertoffice.xml` into both from its phone groups, then runs `reloadxml`. Until it does, the includes match nothing and the rest of the dial plan loads as usual.

1. In Control Hub, route each Group extension to this registration trunk.
2. Set `ESL_LISTEN_IP` to the host LAN IP or `0.0.0.0`. Do not leave it on `127.0.0.1` if Alert Office is another container.
3. Point Alert Office `FREESWITCH_ESL_HOST` at that LAN IP, port `8021`, and set `FREESWITCH_ESL_PASSWORD` to the same value as `ESL_PASSWORD`. A compose recreate of Alert Office from a new `.env` will break ESL if those passwords differ.
4. Share recordings: in this `.env` set `RECORDINGS_HOST_DIR` and `RECORDINGS_CONTAINER_DIR` to the host directory Alert Office mounts as `/recordings` (for example `/opt/alertoffice/recordings`). Recreate this container after changing those variables.
5. Let Alert Office write the dial plan: in its `.env` set `FREESWITCH_DIALPLAN_DIR=/freeswitch-dialplan` and `FREESWITCH_DIALPLAN_HOST_DIR` to this deployment's `runtime/config/dialplan` (for example `/opt/freeswitch-webex-lgw/runtime/config/dialplan`). Alert Office compares the dial plan FreeSWITCH loaded with its groups every few minutes and repairs it.

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

Alert Office uses this image for ESL (`conference json_list`, kick-all) and conference recordings. Alert Office writes its Group extension routes into `runtime/config/dialplan/default/` and `public/`, which `profiles/webex/dialplan/default.xml` includes. Other overlays can still be added in `runtime/config` on the host.

From workspace root: `make deploy-webex` (uses `COMPOSE_MODE=pull` and `ghcr.io/jmetdev/freeswitch-webex-lgw:latest` by default).

### Migrating from `/opt/ccc-freeswitch-webex`

On an existing host, copy `runtime/config/vars.xml` and `.env` into `/opt/freeswitch-webex-lgw`, then run deploy with `REMOTE_DIR=/opt/freeswitch-webex-lgw`. Stop the old compose stack under `/opt/ccc-freeswitch-webex` when satisfied.
