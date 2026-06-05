# e-SUS PEC LXC TLS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add reproducible TLS termination for the e-SUS PEC LXC test instance and store certificate material in Infisical.

**Architecture:** Keep PEC unchanged on port `8080`; terminate HTTPS with `nginx` inside CT `133` on port `443`. Generate a self-signed certificate with SAN entries for `192.168.1.209`, `127.0.0.1`, `localhost`, and `esus-pec-lxc-5437`, then store PEMs and metadata in Infisical.

**Tech Stack:** PowerShell, Proxmox `pct exec`, Debian 13 LXC, OpenSSL, nginx, Infisical API v3.

---

### Task 1: TLS Apply Script

**Files:**
- Create: `scripts/esus-pec/Enable-EsusPecLxcTls.ps1`

- [x] Write an idempotent script that reads Proxmox SSH values from `config/Proxmox.pkrvars.hcl`.
- [x] Execute remote CT commands through Proxmox SSH and `pct exec 133`.
- [x] Generate or reuse `/etc/esus-pec/tls/tls.crt` and `/etc/esus-pec/tls/tls.key`.
- [x] Install only `nginx ca-certificates` when nginx is missing.
- [x] Configure `/etc/nginx/sites-available/esus-pec-tls.conf` to proxy `443 -> 127.0.0.1:8080`.
- [x] Upsert TLS PEMs and metadata in Infisical without printing secret values.

### Task 2: Apply And Validate

**Commands:**

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/esus-pec/Enable-EsusPecLxcTls.ps1 -SkipInfisical
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/esus-pec/Enable-EsusPecLxcTls.ps1
rtk curl.exe -k -sS -o NUL -w "%{http_code} %{ssl_verify_result}" https://192.168.1.209/
```

- [x] Confirm `nginxActive=active` and `pecActive=active`.
- [x] Confirm `https://192.168.1.209/` returns HTTP `200`.
- [x] Confirm Infisical contains all TLS keys by name and length only.

### Task 3: Documentation And Tests

**Files:**
- Create: `docs/esus-pec/2026-06-05-lxc-tls.md`
- Modify: `docs/credentials/esus-pec-infisical-secrets.html`
- Modify: `config/esus-pec.infisical.env.example`
- Create: `tests/Validate-EsusPecTlsDocs.ps1`

- [x] Document scope, implementation, Infisical keys, validation evidence, and rollback.
- [x] Add placeholder names only; do not add PEM values.
- [x] Add a validation test that checks required fragments and rejects PEM material in Git.
