# CT110 Edge Proxy Domain Routes

Date: 2026-06-22

## Summary

CT `110 nginx` is the single edge reverse proxy for the lab services. Cloudflare
handles TLS for vinisantana.com, so these origin vhosts listen on HTTP and do
not require Certbot certificates. Let's Encrypt remains scoped to
`esus.presidenteepitacio.sp.gov.br`, which now represents the production PEC
installation upstream.

Let's Encrypt remains scoped to esus.presidenteepitacio.sp.gov.br.

## Routes

| Public host | Origin upstream | Notes |
|---|---|---|
| `esus.vinisantana.com` | `http://192.168.1.209:8080` | Development PEC install. |
| `s3.vinisantana.com` | `https://192.168.1.210:9000` | MinIO S3 API; WAL-G remains on the internal MinIO endpoint. |
| `minio.vinisantana.com` | `https://192.168.1.210:9001` | MinIO console. |
| `infisical.vinisantana.com` | `http://192.168.1.226:8080` | Infisical UI/API public URL. |
| `proxmox.vinisantana.com` | `https://192.168.1.149:8006` | Proxmox UI, proxied with WebSocket headers. |
| `grafana.vinisantana.com` | `http://192.168.1.190:3000` | Grafana UI/API. |
| `prometheus.vinisantana.com` | `http://192.168.1.190:9090` | Protected by `EDGE_PROXY_PROMETHEUS_BASIC_AUTH_HTPASSWD`. |
| `esus.presidenteepitacio.sp.gov.br` | `https://192.168.1.253` | Production PEC; keep Certbot/Let's Encrypt on CT110. |

`192.168.1.253` is the functional and accessible production PEC server. Do not alter the host, services, edge proxy reference, DNS mapping, TLS upstream, or related Infisical variables without explicit operator authorization for the specific production change.

The CT110 origin must define explicit `listen 80 default_server` and `listen 443 ssl default_server` blocks that return `404`. Unknown Host headers must never fall through to `esus.vinisantana.com`; that route is only the development PEC host, not the Nginx fallback.

Cloudflare currently reaches the origin over HTTPS/443 for proxied `vinisantana.com` hosts. Each `vinisantana.com` route therefore needs both port `80` and port `443` origin listeners. The CT110 origin certificate is local to Nginx and is not the public browser-facing certificate; Cloudflare terminates public TLS.

## Variables

Store route metadata in Infisical `/test/EdgeProxy`:

- `EDGE_PROXY_LXC_CTID=110`
- `EDGE_PROXY_LXC_IP=192.168.1.139`
- `EDGE_PROXY_LXC_NAME=nginx`
- `EDGE_PROXY_ESUS_DEV_DOMAIN=esus.vinisantana.com`
- `EDGE_PROXY_ESUS_DEV_UPSTREAM_URL=http://192.168.1.209:8080`
- `EDGE_PROXY_S3_DOMAIN=s3.vinisantana.com`
- `EDGE_PROXY_S3_UPSTREAM_URL=https://192.168.1.210:9000`
- `EDGE_PROXY_MINIO_DOMAIN=minio.vinisantana.com`
- `EDGE_PROXY_MINIO_UPSTREAM_URL=https://192.168.1.210:9001`
- `EDGE_PROXY_INFISICAL_DOMAIN=infisical.vinisantana.com`
- `EDGE_PROXY_INFISICAL_UPSTREAM_URL=http://192.168.1.226:8080`
- `EDGE_PROXY_PROXMOX_DOMAIN=proxmox.vinisantana.com`
- `EDGE_PROXY_PROXMOX_UPSTREAM_URL=https://192.168.1.149:8006`
- `EDGE_PROXY_GRAFANA_DOMAIN=grafana.vinisantana.com`
- `EDGE_PROXY_GRAFANA_UPSTREAM_URL=http://192.168.1.190:3000`
- `EDGE_PROXY_PROMETHEUS_DOMAIN=prometheus.vinisantana.com`
- `EDGE_PROXY_PROMETHEUS_UPSTREAM_URL=http://192.168.1.190:9090`
- `EDGE_PROXY_PROMETHEUS_BASIC_AUTH_HTPASSWD`
- `EDGE_PROXY_PROMETHEUS_BASIC_AUTH_USERNAME`
- `EDGE_PROXY_PROMETHEUS_BASIC_AUTH_PASSWORD`
- `CLOUDFLARE_ZONE_ID_VINISANTANA`
- `CLOUDFLARE_ZONE_NAME_VINISANTANA=vinisantana.com`
- `CLOUDFLARE_ACCOUNT_ID`
- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_TOKEN`

Store public service URLs in their service folders:

- `ESUS_PEC_PUBLIC_DOMAIN=esus.vinisantana.com`
- `ESUS_PEC_PUBLIC_BASE_URL=https://esus.vinisantana.com`
- `ESUS_PEC_PRODUCTION_DOMAIN=esus.presidenteepitacio.sp.gov.br`
- `ESUS_PEC_PRODUCTION_UPSTREAM_URL=https://192.168.1.253`
- `ESUS_PEC_OBJECT_STORAGE_PUBLIC_API_URL=https://s3.vinisantana.com`
- `ESUS_PEC_OBJECT_STORAGE_PUBLIC_CONSOLE_URL=https://minio.vinisantana.com`
- `ESUS_PEC_WALG_AWS_ENDPOINT=https://192.168.1.210:9000`
- `grafana_url=https://grafana.vinisantana.com`
- `prometheus_url=https://prometheus.vinisantana.com`
- `INFISICAL_PUBLIC_URL=https://infisical.vinisantana.com`
- `PROXMOX_PUBLIC_URL=https://proxmox.vinisantana.com`

## Apply

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/esus-pec/Configure-EdgeProxyRoutes.ps1
```

Use `-SkipCloudflare` only when the Cloudflare token is intentionally absent.
The script validates the CT hostname guard, writes the managed Nginx vhost,
runs `nginx -t`, reloads Nginx, probes every route locally with the public Host
header, and updates Infisical without printing secret values.

Run the production certificate path separately for
`esus.presidenteepitacio.sp.gov.br`; vinisantana.com routes do not need local
certificates because Cloudflare terminates TLS.

## Validation Evidence

2026-06-22 CT110 validation:

- `systemctl is-active nginx` returned `active`.
- `nginx -t` returned successful syntax validation.
- Host-header probes through CT110 returned:
  - `esus.vinisantana.com` -> HTTP `200`
  - `s3.vinisantana.com/minio/health/ready` -> HTTP `200`
  - `minio.vinisantana.com` -> HTTP `200`
  - `infisical.vinisantana.com` -> HTTP `200`
  - `proxmox.vinisantana.com` -> HTTP `200`
  - `grafana.vinisantana.com/api/health` -> HTTP `200`
  - `prometheus.vinisantana.com/-/ready` -> HTTP `401`, expected because Basic Auth is enabled.
  - `unknown.vinisantana.com` -> HTTP `404`, expected from the explicit default server.
- Direct internal MinIO readiness remained HTTP `200` on
  `https://192.168.1.210:9000/minio/health/ready`.

2026-06-23 fallback diagnosis:

- CT110 local Host-header probes route known hosts correctly on HTTP.
- Unknown Host headers previously fell through to `esus.vinisantana.com`; the explicit default server now returns HTTP `404`.
- Public probes for `s3.vinisantana.com`, `infisical.vinisantana.com`, `grafana.vinisantana.com`, and `prometheus.vinisantana.com` returned e-SUS HTML before adding 443 origin listeners, which indicates Cloudflare was reaching CT110 over HTTPS/443 and hitting the wrong default.
- `minio.vinisantana.com` did not resolve in public DNS, and `infisical.vinisantana` without `.com` is not a valid configured hostname.
- The local Cloudflare token check returned HTTP `401` / `Invalid API Token`; update the token before creating the missing `minio.vinisantana.com` DNS record through automation.

2026-06-23 post-fix validation:

- CT110 local HTTP and HTTPS Host-header probes returned:
  - `esus.vinisantana.com` -> HTTP `200`
  - `s3.vinisantana.com/minio/health/ready` -> HTTP `200`
  - `minio.vinisantana.com` -> HTTP `200`
  - `infisical.vinisantana.com` -> HTTP `200`
  - `grafana.vinisantana.com/api/health` -> HTTP `200`
  - `prometheus.vinisantana.com/-/ready` -> HTTP `401`, expected because Basic Auth is enabled.
  - `unknown.vinisantana.com` -> HTTP `404`.
- Public Cloudflare probes returned the expected service content for `s3.vinisantana.com`, `infisical.vinisantana.com`, `grafana.vinisantana.com`, and `prometheus.vinisantana.com` instead of e-SUS HTML.
- `minio.vinisantana.com` still returned DNS failure and requires a Cloudflare DNS record after the token is corrected.

Pending items:

- Infisical folder provisioning reported `/test/EdgeProxy` as existing and
  `missingCount=0`.
- Infisical secret update stopped with HTTP `403` because the current token can
  create secrets in existing paths but not in `/test/EdgeProxy`. Grant
  create/update/delete for secrets on `/test/EdgeProxy`, then rerun the script
  without `-SkipInfisical`.
- The local `.env` visible to this session did not expose `CLOUDFLARE_TOKEN`,
  `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN`,
  `CLOUDFLARE_ZONE_ID_VINISANTANA`, or
  `CLOUDFLARE_ZONE_NAME_VINISANTANA`. After those are visible, rerun without
  `-SkipCloudflare` to create/update the proxied A records.
