# Deploy options

Primary supported path: **Docker Compose + `network_mode: host`** on a single Linux VPS with a public IP.

| Option | When to use |
|--------|-------------|
| Compose + host network | Default LGW / fax on one VPS |
| Podman + systemd quadlet | Rootless Linux hosts |
| VM + cloud-init + Compose | Repeatable customer “LGW box” |
| Native FreeSWITCH + Ansible | Sites that forbid containers |
| Kubernetes `hostNetwork` | Only if the platform already requires K8s (RTP is painful) |
| Cisco CUBE / vCUBE | Certified LGW with TAC support |

This repository ships Compose, sync scripts, and GHCR images. Pull
`ghcr.io/jmetdev/freeswitch-webex-lgw:latest` on a new host; do not bake VM IPs into the image.
Other paths are operational choices documented here only.
