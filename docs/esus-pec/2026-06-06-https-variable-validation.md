# e-SUS PEC HTTPS Variable Validation

## Scope

Validated the CT `133 esus-pec-lxc-5437` HTTPS endpoint at `192.168.1.209` and inventoried variables that either store HTTPS/TLS state or depend on HTTPS-only PEC screens.

No VM `101` or CT `100` changes were made. No secret values, PEM bodies, cookies, or tokens were copied to this repository.

## Variables That Require HTTPS Context

TLS material and endpoint metadata in Infisical `/test/InstallationConfig`:

- `ESUS_PEC_TLS_CERTIFICATE_PEM`
- `ESUS_PEC_TLS_PRIVATE_KEY_PEM`
- `ESUS_PEC_TLS_HTTPS_URL`
- `ESUS_PEC_TLS_CERTIFICATE_SHA256`
- `ESUS_PEC_TLS_CERTIFICATE_NOT_AFTER`
- `ESUS_PEC_TLS_CERTIFICATE_SAN`
- `ESUS_PEC_TLS_CERTIFICATE_KIND`
- `ESUS_PEC_TLS_TERMINATION`
- `ESUS_PEC_LXC_TEST_HTTPS_URL`

PEC installation configuration variables whose UI collection was blocked over HTTP:

- `ESUS_PEC_BASE_UNIFICATION_ENABLED`
- `ESUS_PEC_BASE_UNIFICATION_MODE`

Related URL variables should prefer HTTPS for external automation and user-facing flows, but `ESUS_PEC_BASE_URL` and `ESUS_PEC_LXC_TEST_URL` remain useful for the internal HTTP service path.

## HTTPS Validation

External checks from the workstation:

```text
https://192.168.1.209/ -> HTTP 200, ssl_verify_result=0
https://192.168.1.209/configuracoes/instalacao/unificacaobase -> HTTP 200, ssl_verify_result=0
```

Observed response properties:

```text
server=nginx
strict-transport-security=present
xsrf-cookie-secure=present
```

CT `133` service checks through Proxmox SSH:

```text
nginx=active
e-SUS-PEC.service=active
listen443=0.0.0.0:443
listen8080=0.0.0.0:8080
certificate_subject=CN=esus-pec-lxc-5437
certificate_issuer=CN=esus-pec-lxc-5437
certificate_not_after=Sep 7 16:47:52 2028 GMT
certificate_san_has_192.168.1.209=true
```

Infisical comparison by name, length, and non-secret metadata only:

```text
tls_secret_keys_present=8
ESUS_PEC_LXC_TEST_HTTPS_URL_present=true
ESUS_PEC_BASE_UNIFICATION_ENABLED_present=true
ESUS_PEC_BASE_UNIFICATION_MODE_present=true
tls_url_matches_live_endpoint=true
lxc_https_url_matches_live_endpoint=true
fingerprint_matches_live_certificate=true
san_matches_live_certificate=true
certificate_kind_self_signed=true
tls_termination_nginx_lxc=true
```

## Result

HTTPS is being applied correctly for CT `133`: requests reach nginx on port `443`, nginx proxies the PEC application, the unification route is reachable over HTTPS, and Infisical metadata matches the deployed certificate and endpoint.

The base-unification variables are now safe to use as desired-state inputs for future authenticated automation. Credential fields for unification still require a logged-in PEC session and must not be added until they are collected without duplicating existing variable names.
