# Production TLS Preflight

## Scope

This preflight prepares the production TLS issuance for `esus.presidenteepitacio.sp.gov.br` without running Certbot issuance. No DNS records, firewall rules, services, CTs, or certificates were modified during this check.

## Current Routing

| Role | Value |
| --- | --- |
| Production domain | `esus.presidenteepitacio.sp.gov.br` |
| Production PEC upstream | `https://192.168.1.253` |
| Development domain | `esus.vinisantana.com` |
| Development PEC upstream | `http://192.168.1.209:8080` |
| Edge Nginx CT | `110 nginx` at `192.168.1.139` |
| Public IP | `177.190.79.26` |
| ACME contact | `cpd.saude@presidenteepitacio.sp.gov.br` |

## Production Protection

`192.168.1.253` hosts the functional and accessible e-SUS PEC production server for `esus.presidenteepitacio.sp.gov.br`. Do not modify that machine, its services, CT/VM state, edge proxy references, TLS upstream, or related Infisical variables without explicit operator authorization for the specific change. Default production interactions are read-only validation.

## Read-Only Validation

Cloudflare token validation was attempted with `GET /user/tokens/verify`, `GET /zones?name=vinisantana.com`, and `GET /dns_records`. The local `CLOUDFLARE_TOKEN` variable is present, but Cloudflare returned HTTP `401` / `Invalid API Token`; `CLOUDFLARE_API_TOKEN` is not defined. No Cloudflare changes were made.

CT `110` is reachable through Proxmox SSH. It has listeners on ports `80` and `443`. From CT `110`, `http://192.168.1.253/` and `http://192.168.1.253:8080/` timed out, while `https://192.168.1.253/` returned `prod_upstream_status=200` with the upstream's internal certificate verification bypassed. The development upstream returned `dev_upstream_status=200`.

## Issuance Result

Certificate issuance completed on 2026-06-23 using CT `110` and `ESUS_PEC_PRODUCTION_UPSTREAM_URL=https://192.168.1.253`. The first run issued the certificate but timed out during `certbot renew --dry-run` because Certbot introduced a random renewal sleep. The script now uses `--no-random-sleep-on-renew`; the second run completed with `certbotRenewDryRunStatus=success` and `infisicalUpdated=true`.

Validation evidence:

```text
http://esus.presidenteepitacio.sp.gov.br/ -> HTTP 301 to https://esus.presidenteepitacio.sp.gov.br/
https://esus.presidenteepitacio.sp.gov.br/ -> HTTP 200, ssl_verify_result=0
issuer=C=US, O=Let's Encrypt, CN=YE1
SAN=DNS:esus.presidenteepitacio.sp.gov.br
notAfter=Sep 21 12:41:09 2026 GMT
nginx_active=active
pec_upstream_status=200
certbot.timer=enabled/active
certbotRenewDryRunStatus=success
```

## Ready Command

Reusable command:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/esus-pec/Enable-EsusPecLxcTls.ps1 `
  -ProxyCtid 110 `
  -ProxyIp 192.168.1.139 `
  -ProxyExpectedHostname nginx `
  -PecIp 192.168.1.253 `
  -Domain esus.presidenteepitacio.sp.gov.br `
  -PublicIp 177.190.79.26 `
  -LetsEncryptEmail cpd.saude@presidenteepitacio.sp.gov.br `
  -SkipPublicAcmePreflight
```

Expected preconditions before running:

- `ESUS_PEC_PRODUCTION_UPSTREAM_URL=https://192.168.1.253` is present in `.env` or Infisical.
- CT `110` can fetch `https://192.168.1.253/` successfully.
- Public HTTP-01 traffic for `esus.presidenteepitacio.sp.gov.br:80` reaches CT `110`.
- Use `-SkipPublicAcmePreflight` only when an external HTTP-01 manual probe returns `200` but CT `110` cannot hairpin through the public IP.
- Certbot renewal is validated through `certbot.timer` or cron after issuance.
