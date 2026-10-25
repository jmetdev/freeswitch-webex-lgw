# Hostinger firewall ports for Webex Calling LGW (srv1608468.hstgr.cloud / 2.24.221.60)
#
# Runtime proof (2026-07-06): external `nc -zv 2.24.221.60 5071` → TIMEOUT while
# FreeSWITCH listens on 5071 locally. Webex cannot deliver INVITE/OPTIONS inbound
# until these ports are open in hPanel → VPS → Firewall.

| Port | Protocol | Direction | Purpose |
|------|----------|-----------|---------|
| 5071 | TCP | Inbound | SIP TLS (Contact in REGISTER) |
| 5070 | UDP/TCP | Inbound | SIP (non-TLS fallback) |
| 16384-32768 | UDP | Inbound | RTP/SRTP media |

Outbound (usually allowed by default):
| 8934 | TCP | Outbound | Webex access SBC (TLS REGISTER/OPTIONS)

After opening ports, verify from your Mac:
  nc -zv 2.24.221.60 5071

Then refresh Control Hub trunk status (~3 min) and test inbound call with:
  ssh root@srv1608468.hstgr.cloud 'timeout 30 tcpdump -i any -n tcp port 5071'
