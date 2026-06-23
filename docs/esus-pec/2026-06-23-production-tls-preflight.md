# Production TLS Preflight

## Scope

This preflight prepares the production TLS issuance for `esus.presidenteepitacio.sp.gov.br` without running Certbot issuance. No DNS records, firewall rules, services, CTs, or certificates were modified during this check.

## Current Routing

| Role | Value |
| --- | --- |
| Production domain | `esus.presidenteepitacio.sp.gov.br` |
| Production PEC upstream | `http://192.168.1.253:8080` |
| Development domain | `esus.vinisantana.com` |
| Development PEC upstream | `http://192.168.1.209:8080` |
| Edge Nginx CT | `110 nginx` at `192.168.1.139` |
| Public IP | `177.190.79.26` |
| ACME contact | `cpd.saude@presidenteepitacio.sp.gov.br` |

## Read-Only Validation

Cloudflare token validation was attempted with `GET /user/tokens/verify`, `GET /zones?name=vinisantana.com`, and `GET /dns_records`. The local `CLOUDFLARE_TOKEN` variable is present, but Cloudflare returned HTTP `401` / `Invalid API Token`; `CLOUDFLARE_API_TOKEN` is not defined. No Cloudflare changes were made.

CT `110` is reachable through Proxmox SSH. It has listeners on ports `80` and `443`, but the service-manager check returned `nginx_active=inactive`; reconcile that before issuance. From CT `110`, the development upstream returned `dev_upstream_status=200`, while the production upstream `http://192.168.1.253:8080/` timed out with `prod_upstream_status=000`.

## Ready Command

Run this only after the Cloudflare token is replaced and CT `110` can reach the production upstream:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/esus-pec/Enable-EsusPecLxcTls.ps1 `
  -ProxyCtid 110 `
  -ProxyIp 192.168.1.139 `
  -ProxyExpectedHostname nginx `
  -PecIp 192.168.1.253 `
  -Domain esus.presidenteepitacio.sp.gov.br `
  -PublicIp 177.190.79.26 `
  -LetsEncryptEmail cpd.saude@presidenteepitacio.sp.gov.br
```

Expected preconditions before running:

- `ESUS_PEC_PRODUCTION_UPSTREAM_URL=http://192.168.1.253:8080` is present in `.env` or Infisical.
- CT `110` can fetch `http://192.168.1.253:8080/` successfully.
- Public HTTP-01 traffic for `esus.presidenteepitacio.sp.gov.br:80` reaches CT `110`.
- Certbot renewal is validated through `certbot.timer` or cron after issuance.
