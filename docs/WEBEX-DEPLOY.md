# Webex Calling trunk — standalone FreeSWITCH deploy

Deploy a **dedicated** FreeSWITCH instance for Webex Calling registration trunk testing
(fax, inbound/outbound voice). This is separate from the recording portal stack on
`hyetech@172.25.100.83`.

## Dev host

| Item | Value |
|------|-------|
| SSH | `root@srv1608468.hstgr.cloud` |
| Public IPv4 | `2.24.221.60` |
| Remote path | `/opt/freeswitch-webex-lgw` |
| Container | `freeswitch` (host network) |

### Legacy `ccc-fax` native FreeSWITCH

This host previously ran a **systemd-managed** native FreeSWITCH (`freeswitch.service`
from `/opt/ccc-fax`). It also binds host SIP ports and conflicts with the Docker
container. For the Webex dev instance, the legacy service was **stopped and disabled**:

```bash
systemctl stop freeswitch && systemctl disable freeswitch
docker restart freeswitch
```

To restore the old `ccc-fax` stack, stop the Docker container and re-enable the service.

## Deploy from workspace root

```bash
cd /path/to/Projects   # workspace root (parent of freeswitch-webex-lgw)
make deploy-webex
# or
./deploy/deploy-freeswitch.sh
```

The deploy script rsyncs the repo, sets `external_sip_ip` / `external_rtp_ip` / `local_ip_v4`
to the host public IP, and runs `docker compose up -d --build`.

## Control Hub credentials (required before registration works)

Edit on the server:

```bash
ssh root@srv1608468.hstgr.cloud
nano /opt/freeswitch-webex-lgw/runtime/config/vars.xml
```

Replace the six `webex_*` placeholders (from **Control Hub → Calling → Call Routing → Trunks →
Add Trunk → Registration based**):

| var | Control Hub field |
|-----|-------------------|
| `webex_registrar` | Registrar FQDN |
| `webex_outbound_proxy` | Outbound proxy FQDN (DNS SRV → port 8934) |
| `webex_line_port` | Line/Port user part (before `@`) |
| `webex_username` | Trunk username (digest auth) |
| `webex_password` | Trunk password |
| `webex_otg` | Outbound trunk group tag |

Then reload:

```bash
cd /opt/freeswitch-webex-lgw
docker exec freeswitch fs_cli -x "reloadxml"
docker exec freeswitch fs_cli -x "sofia profile external restart"
docker exec freeswitch fs_cli -x "sofia status gateway webex"
```

**Registration OK** shows `State REGED`. Until credentials are pasted, expect `FAIL_WAIT` or auth errors.

## CUBE Local Gateway impersonation

Control Hub shows device type **Cisco CUBE Local Gateway**. FreeSWITCH is not certified, but this mapping mirrors CUBE IOS XE behavior:

| CUBE IOS XE | FreeSWITCH | Runtime note |
|-------------|------------|--------------|
| `registrar dns:16855334…bcld.webex.com` | `from-domain` = `webex_registrar` | **No public A/SRV DNS** — identity in From/To only |
| `outbound-proxy dns:da07…sipconnect…` | `proxy` + `register-proxy` = `webex_outbound_proxy` | **SRV lives here**: `_sips._tcp.da07…` → `sse-b5…:8934` |
| `credentials … realm BroadWorks` | `realm=BroadWorks`, `auth-username` ≠ Line/Port | Digest auth |
| Contact rewrite to LGW FQDN | `contact-host` + `extension-in-contact` | **Must match FQDN provisioned in Control Hub** |

### Registrar vs outbound proxy (SRV is dynamic on da07, not registrar)

Runtime DNS on srv1608468:

```bash
dig +short SRV _sips._tcp.16855334.us10.bcld.webex.com @8.8.8.8    # empty
dig +short SRV _sips._tcp.da07.sipconnect-us.bcld.webex.com @8.8.8.8
# 5 50 8934 sse-b5.public.wdfwwxc-p-2.prod.infra.webex.com.
# 10 50 8934 sse-b7.public.wjfkwxc-p-2.prod.infra.webex.com.
```

Store the **Control Hub outbound proxy hostname** (no port) in `webex_outbound_proxy`, then resolve SRV before restart:

```bash
./deploy/resolve-webex-srv.sh /opt/freeswitch-webex-lgw/runtime/config/vars.xml
docker exec freeswitch fs_cli -H 127.0.0.1 -P 8021 -p ChangeMe-ESL-Password -x "reloadxml"
docker exec freeswitch fs_cli -H 127.0.0.1 -P 8021 -p ChangeMe-ESL-Password -x "sofia profile external restart"
```

FreeSWITCH `sofia_dig da07.sipconnect-us.bcld.webex.com` also resolves targets inside the container.

### Why Control Hub stays "Unknown" while Sofia shows REGED

Webex requires **Contact header with the LGW FQDN provisioned in Control Hub** (Cisco sip-profile Contact rewrite). Runtime test:

| Contact header | Sofia state |
|----------------|-------------|
| `gw+webex@2.24.221.60:5071` (IP) | **REGED** |
| `CloudCoreFax…@srv1608468.hstgr.cloud:5071` (FQDN) | **TRYING** (Webex rejects until FQDN is provisioned) |

**Fix:** In Control Hub, configure the trunk/LGW FQDN to `srv1608468.hstgr.cloud` (must resolve to `2.24.221.60`), then uncomment `extension-in-contact` + `contact-host` in `webex_gateway.xml`.

### Check registration on docker host

```bash
alias fs='docker exec freeswitch fs_cli -H 127.0.0.1 -P 8021 -p ChangeMe-ESL-Password -x'
fs "sofia status gateway webex"      # gateway + profile external
fs "sofia status profile external"   # SIP/TLS bind IPs
fs "sofia_dig da07.sipconnect-us.bcld.webex.com"  # SRV targets
```

## SIP registration (registrar vs outbound proxy)

Control Hub still lists a **Registrar FQDN** (e.g. `16855334…bcld.webex.com`), but that hostname
**does not resolve on the public Internet** from the dev host. Do not point FreeSWITCH REGISTER
at the registrar FQDN alone — registration will fail with DNS or timeout errors.

**Required behavior** (see `config/sip_profiles/external/webex_gateway.xml`):

| Setting | Value |
|---------|--------|
| `proxy` | Outbound proxy FQDN with port **8934** (e.g. `da07…sipconnect.bcld.webex.com:8934`) |
| `register-proxy` | Same outbound proxy (REGISTER must hit the SBC, not the registrar name) |
| `outbound-proxy` | Same outbound proxy |
| `realm` | **`BroadWorks`** — digest realm from Webex; **not** the registrar domain |
| `from-domain` | Registrar FQDN (identity in From/Contact only) |

Set `webex_outbound_proxy` in `vars.xml` to the Control Hub outbound proxy host **including `:8934`**.
Keep `webex_registrar` as the Control Hub registrar FQDN for headers; signaling uses the proxy.


## Ports / firewall

FreeSWITCH uses **host networking**. Ensure these are open on the cloud firewall:

| Port | Protocol | Purpose |
|------|----------|---------|
| 5070 | UDP/TCP | External SIP (non-default to avoid clashes) |
| 5071 | TCP | External SIP TLS |
| 16384-32768 | UDP | RTP/SRTP |
| 8021 | TCP | ESL (localhost only — do not expose publicly) |

Outbound: TLS to Webex on port **8934** (via DNS SRV on `webex_outbound_proxy`).

### Hostinger VPS (srv1608468)

**Runtime proof:** external `nc -zv 2.24.221.60 5071` times out while FreeSWITCH listens locally — **hPanel firewall blocks inbound SIP**. Webex cannot send INVITE/OPTIONS until TCP **5071** is opened. See [HOSTINGER-FIREWALL.md](HOSTINGER-FIREWALL.md).

## Troubleshooting registration failures

Run from workspace root:

```bash
./deploy/debug-webex-registration.sh
# logs → /tmp/freeswitch-webex-lgw-debug.log
```

### Common failure modes (with runtime evidence)

| Symptom | Cause | Fix |
|---------|-------|-----|
| `503 DNS Error`, `FAIL_WAIT` | `proxy` points at **registrar FQDN** (`16855334…`) — no public A record | Set `proxy` + `register-proxy` to **outbound proxy** with `:8934` |
| `FAIL_WAIT`, cannot connect to `da07…` | Control Hub proxy hostname has **SRV only**, no A record; FreeSWITCH may not SRV-resolve the proxy | Resolve SRV manually and set `webex_outbound_proxy` to `<srv-target>:8934` |
| `401` then `403` / never `REGED` | Wrong **realm** (must be `BroadWorks`, not registrar domain) or **auth-username** ≠ trunk username | Split Line/Port (`username`) from digest user (`auth-username`) |
| `401` loop | Same value used for Line/Port and trunk username | `webex_line_port` ≠ `webex_username` in vars.xml |
| TLS handshake error | `external_tls_verify_policy=out` without `cafile.pem` | Entrypoint seeds CA bundle; temporarily set policy to `none` for debug only |
| `FAIL_WAIT` after `make deploy-webex` | Credentials wiped | Fixed: deploy merges `webex_*` from server runtime vars |

### SRV target rotation

Webex SRV for `da07.sipconnect-us.bcld.webex.com` can return multiple targets (e.g. `sse-b5…`, `sse-b7…`). If registration drops after infra changes, re-resolve:

```bash
dig +short SRV _sips._tcp.da07.sipconnect-us.bcld.webex.com @8.8.8.8
```

Update `webex_outbound_proxy` to the highest-priority target with `:8934`, then `reloadxml` + `sofia profile external restart`.

Per FreeSWITCH Sofia docs: `proxy` is the outbound SIP target; `register-proxy` can differ when registration goes to a separate host. For Webex, both must hit the SBC on port **8934** over **TLS 1.2**.


```bash
# Container health
docker ps --filter name=freeswitch
docker exec freeswitch fs_cli -H 127.0.0.1 -P 8021 -p ChangeMe-ESL-Password -x "status"

# Gateway registration
docker exec freeswitch fs_cli -H 127.0.0.1 -P 8021 -p ChangeMe-ESL-Password -x "sofia status gateway webex"

# SIP trace (temporary)
docker exec freeswitch fs_cli -H 127.0.0.1 -P 8021 -p ChangeMe-ESL-Password -x "sofia profile external siptrace on"

# Logs
docker logs freeswitch --tail 100
tail -f /opt/freeswitch-webex-lgw/runtime/logs/freeswitch.log
```

### Inbound test

With registration up, dial the Line/Port number from Webex. The default dialplan transfers
to extension `9191` (health-check tone).

### Outbound test

```bash
docker exec freeswitch fs_cli -x "originate {origination_caller_id_number=+1XXXXXXXXXX}sofia/gateway/webex/+1YYYYYYYYYY &echo"
```

### Fax (Phase 2)

Inbound fax example is commented in `config/dialplan/default.xml`. Uncomment `inbound_fax`,
sync config, and test T.38 after voice trunk is stable.

## Update after local changes

```bash
# From workspace root, after committing freeswitch-webex-lgw changes:
make deploy-webex
```

### Credential preservation on redeploy

`webex_*` values live only in **`runtime/config/vars.xml`** on the server (and in your
local `freeswitch-webex-lgw/runtime/config/vars.xml` after first paste). The tracked
`config/vars.xml` keeps `CHANGE_ME` placeholders and must never contain real passwords.

Redeploy is safe: `make deploy-webex` runs `sync-config-to-runtime.sh`, which copies
versioned `config/` into `runtime/config/` but **merges** any non-placeholder `webex_*`
values from the existing runtime file instead of wiping them. The deploy script does the
same merge against the server's `runtime/config/vars.xml` before uploading.

To refresh config without losing credentials locally:

```bash
make sync-fs-config   # merges webex_* from runtime/config/vars.xml
```

If you need to rotate trunk credentials, edit `runtime/config/vars.xml` on the server
(or locally), then redeploy or `reloadxml` + `sofia profile external restart`.

## What's left

- [ ] Paste Control Hub `webex_*` values into server `vars.xml`
- [ ] Confirm `sofia status gateway webex` → `REGED`
- [ ] Place test inbound/outbound calls
- [ ] Enable and test T.38 fax dialplan
