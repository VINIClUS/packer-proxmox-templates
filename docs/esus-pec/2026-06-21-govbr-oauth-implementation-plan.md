# e-SUS PEC Gov.br OAuth Implementation Plan

## Scope

`GovBrOAuth.txt` is an ignored production reference file and contains live credentials. It was analyzed without printing secret values. File evidence:

- Size: `652` bytes.
- SHA-256: `7F308D919AF4F4493CA86601D02BF291C905D76F1F686C9A8259A90AEBC96501`.
- Sensitive fields present: datasource password, PKCS12 keystore password, Gov.br OAuth client secret.
- Non-secret structure present: PostgreSQL URL on `localhost:5433/esus`, Spring HTTPS on port `443`, PKCS12 keystore at `config/esusaps.p12`, key alias `esus`, and Gov.br properties under `bridge.security.oauth2.client.registration.govbr`.

## Current Local State

CT `133` is active as `esus-pec-lxc-5437`. The local PEC service is active and enabled. Current `/opt/e-SUS/webserver/config/application.properties` only contains datasource properties; no Gov.br OAuth properties are present.

The local installation uses nginx TLS termination on `443` and proxies to PEC on `127.0.0.1:8080`. nginx already sends:

- `Host $host`
- `X-Forwarded-Proto https`
- `X-Forwarded-For`
- `X-Real-IP`

This is preferable for the first implementation because setting `server.port=443` in PEC would conflict with nginx and bypass the existing TLS/certificate automation.

## External Constraints

Gov.br Login Unico requires HTTPS and uses redirect URIs registered for the client domain. The official integration guide recommends using a development domain mapped locally instead of IP-based redirect URLs. It also requires `state`, `nonce`, and PKCE in the authorization flow. Official common errors confirm that:

- `invalid_grant` often means the redirect URL is not registered.
- `invalid_client` or token `401` can be caused by wrong `client_id`, wrong `client_secret`, or trailing whitespace in `application.properties`.
- invalid ID token claims can be caused by wrong server time.
- connection reset to the token endpoint can indicate a Gov.br firewall/IP allowlist issue.

Sources:

- `https://acesso.gov.br/roteiro-tecnico/iniciarintegracao.html`
- `https://acesso.gov.br/roteiro-tecnico/erroscomuns.html`

## Variables To Register

Store these in Infisical `/test/InstallationConfig` first. Mirror to `/prod/InstallationConfig` only during approved cutover.

| Variable | Secret | Purpose |
| --- | --- | --- |
| `ESUS_PEC_GOVBR_ENABLED` | No | Desired runtime flag, expected `true`. |
| `ESUS_PEC_GOVBR_OAUTH_PROPERTY_PREFIX` | No | `bridge.security.oauth2.client.registration.govbr`. |
| `ESUS_PEC_GOVBR_OAUTH_CLIENT_ID` | Treat as sensitive | Gov.br client ID from the production reference. |
| `ESUS_PEC_GOVBR_OAUTH_CLIENT_SECRET` | Yes | Gov.br client secret from the production reference. |
| `ESUS_PEC_GOVBR_OAUTH_ALLOWED_DOMAIN` | No | `esus.presidenteepitacio.sp.gov.br`. |
| `ESUS_PEC_GOVBR_OAUTH_REDIRECT_BASE_URL` | No | `https://esus.presidenteepitacio.sp.gov.br`. |
| `ESUS_PEC_GOVBR_OAUTH_TEST_HOST_OVERRIDE` | No | Temporary hosts entry: `192.168.1.209 esus.presidenteepitacio.sp.gov.br`. |
| `ESUS_PEC_GOVBR_OAUTH_TEST_STRATEGY` | No | `hosts-file-split-dns`. |
| `ESUS_PEC_GOVBR_OAUTH_SOURCE_FILE_SHA256` | No | Source file hash for provenance. |
| `ESUS_PEC_GOVBR_OAUTH_APP_PROPERTIES_PATH` | No | `/opt/e-SUS/webserver/config/application.properties`. |
| `ESUS_PEC_GOVBR_OAUTH_TLS_MODE` | No | `nginx-termination`. |
| `ESUS_PEC_GOVBR_OAUTH_NATIVE_TLS_FALLBACK` | No | `false` initially. |
| `ESUS_PEC_GOVBR_SSL_KEYSTORE_TYPE` | Fallback | `PKCS12`, only needed if native Spring TLS is required. |
| `ESUS_PEC_GOVBR_SSL_KEYSTORE_PATH` | Fallback | `config/esusaps.p12`, only needed if native Spring TLS is required. |
| `ESUS_PEC_GOVBR_SSL_KEYSTORE_PASSWORD` | Yes | Only needed if native Spring TLS is required. |
| `ESUS_PEC_GOVBR_SSL_KEY_ALIAS` | Fallback | `esus`, only needed if native Spring TLS is required. |
| `ESUS_PEC_GOVBR_DEBUG_MITM_REQUIRED` | No | `false` initially. |
| `ESUS_PEC_GOVBR_DEBUG_PROXY_TOOL` | No | `mitmproxy` if deeper diagnosis is approved. |

## Implementation Plan

1. Copy `client-id` and `client-secret` from `GovBrOAuth.txt` into Infisical only. Do not commit them or print them.
2. Build `Configure-EsusPecGovBrOAuth.ps1` to read Infisical, back up `application.properties`, and idempotently upsert only:
   - `bridge.security.oauth2.client.registration.govbr.client-id`
   - `bridge.security.oauth2.client.registration.govbr.client-secret`
3. Do not copy `server.port=443`, `security.require-ssl`, or `server.ssl.*` in the first pass. Keep nginx as TLS terminator and PEC on `8080`.
4. Update nginx `server_name` to include `esus.presidenteepitacio.sp.gov.br` only when testing starts. Preserve `Host $host` and `X-Forwarded-Proto https`.
5. Restart only `e-SUS-PEC.service` after backing up properties and recording rollback commands.
6. Validate GraphQL `/api/graphql` `info.govBREnabled` changes from `false` to `true`.
7. Test Gov.br login using hosts/split-DNS from a controlled test workstation:
   - add `192.168.1.209 esus.presidenteepitacio.sp.gov.br` locally;
   - open `https://esus.presidenteepitacio.sp.gov.br`;
   - confirm the browser reaches CT `133`, not production;
   - start login and verify redirect uses the registered domain, not the IP.
8. If login fails, inspect PEC logs and nginx logs first. Only install MITM tooling if the failure cannot be diagnosed from logs, redirect URL, HTTP status, and Gov.br error page.

## Debugging Strategy

Start with tools already present on CT `133`: `curl`, `openssl`, `java`, `keytool`, `ss`, and `journalctl`.

Recommended first checks:

```bash
curl -kI https://esus.presidenteepitacio.sp.gov.br/
openssl s_client -connect esus.presidenteepitacio.sp.gov.br:443 -servername esus.presidenteepitacio.sp.gov.br
journalctl -u e-SUS-PEC.service -f
tail -f /var/log/nginx/access.log /var/log/nginx/error.log
```

Extra tools are not required initially. If deeper network inspection becomes necessary, install `tcpdump` first for metadata-only checks. Use `mitmproxy` only as a last resort because Java TLS interception would require a temporary CA import into the Java truststore and explicit JVM proxy settings, which adds risk and must be rolled back.

## Risks And Rollback

- Domain-bound OAuth means IP-based testing will fail or produce misleading redirects.
- Hosts/split-DNS testing can accidentally shadow production for the tester; keep it limited to a test workstation and remove the entry after validation.
- `client-secret` must not contain trailing spaces or line breaks.
- The earlier local gap `serverTimezoneOffset=0` must be fixed before OAuth validation because Gov.br ID token validation is time-sensitive.
- If nginx termination fails Gov.br validation, evaluate native Spring TLS as a fallback using the PKCS12 variables above.

Rollback is to restore the backed-up `application.properties`, remove the test hosts entry, restart `e-SUS-PEC.service`, and confirm `govBREnabled=false` or the previous known state.
