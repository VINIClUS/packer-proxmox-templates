# e-SUS PEC JVM and PostgreSQL Exporters Design

Date: 2026-06-20
Workspace: `C:\Users\Vinicius\Projetos\packer-proxmox-templates`

## Objective

Extend centralized monitoring for LXC `133 esus-pec-lxc-5437` with:

- PostgreSQL metrics from the embedded PostgreSQL 9.6 server.
- JVM metrics from the Java 17 process running `e-SUS-PEC.service`.
- Prometheus scrape targets on monitoring core CT `190`.
- Dense Grafana panels for database and JVM operations.

The implementation must be idempotent, reversible, secret-safe, and validated
against live metrics before completion.

## Current State

- PEC service: `e-SUS-PEC.service`.
- PEC launch script: `/opt/e-SUS/webserver/standalone.sh`.
- Java runtime: Zulu OpenJDK `17.0.13`.
- Application endpoint: port `8080`.
- Embedded PostgreSQL: `9.6.13`.
- PostgreSQL service: `e-SUS-AB-PostgreSQL.service`.
- PostgreSQL endpoint: `127.0.0.1:5433`.
- Existing exporters:
  - node exporter: `9100`
  - Nginx exporter: `9113`
- Reserved exporter ports:
  - PostgreSQL exporter: `9187`
  - JMX exporter: `9404`

## Selected Architecture

Use native exporters and systemd-compatible configuration on CT `133`.

### PostgreSQL

Install Prometheus Community PostgreSQL Exporter `0.19.1` as a dedicated
systemd service. The exporter connects only to the local embedded PostgreSQL
endpoint using a dedicated `prometheus_exporter` login.

Because PostgreSQL `9.6` predates the built-in `pg_monitor` role, create the
officially recommended compatibility schema, `SECURITY DEFINER` functions, and
views required to expose `pg_stat_activity` and replication statistics to a
non-superuser. Grant only:

- `CONNECT` to the selected monitoring database.
- `USAGE` on the exporter compatibility schema.
- `SELECT` on the compatibility views and explicitly required statistics.

The account must not receive `SUPERUSER`, database ownership, write privileges,
or application-table access.

### JVM

Install JMX Exporter Java Agent `1.6.0`, which is compatible with the PEC Java
17 runtime. Keep the vendor-owned `/usr/lib/systemd/system/e-SUS-PEC.service`
and `/opt/e-SUS/webserver/standalone.sh` unchanged.

Create a managed systemd drop-in:

`/etc/systemd/system/e-SUS-PEC.service.d/monitoring-jmx.conf`

The drop-in clears the vendor `ExecStart` and points the service to:

`/opt/monitoring/run-esus-pec-with-jmx.sh`

The wrapper preserves the PEC certificate import step without JMX and launches
the final PEC JVM with the Java agent before `-jar`:

- `/opt/monitoring/jmx_prometheus_javaagent.jar`
- port `9404`
- `/etc/monitoring/jmx-exporter.yml`

The existing vendor unit and `/opt/e-SUS/webserver/standalone.sh` are not
edited. This avoids depending on `JAVA_TOOL_OPTIONS`, which was consumed by
helper JVM invocations before the application JVM and did not expose the
desired metrics reliably.

## Artifact Integrity

Download release artifacts only from the official Prometheus Community GitHub
release locations. Pin versions and SHA-256 checksums in the provisioning
script. Abort before installation when a checksum does not match.

Installed paths:

- `/usr/local/bin/postgres_exporter`
- `/opt/monitoring/jmx_prometheus_javaagent.jar`
- `/opt/monitoring/run-esus-pec-with-jmx.sh`
- `/etc/monitoring/jmx-exporter.yml`
- `/etc/monitoring/postgres-exporter.env`

## Secret Lifecycle

Generate a cryptographically random PostgreSQL exporter password locally during
provisioning. Never print it in command output, JSON summaries, logs, chat, or
documentation.

Store the password in:

- Infisical project `esus-pec-z-px-c`
- environment `dev`
- path `/test/InstallationConfig`
- key `ESUS_PEC_POSTGRES_EXPORTER_PASSWORD`

Store the derived DSN in a root-owned file inside CT `133`:

`/etc/monitoring/postgres-exporter.env`

Permissions must be `0600`. The DSN uses `127.0.0.1:5433` and is never committed
to Git or sent to Prometheus.

On reruns, reuse the existing Infisical password instead of rotating it
implicitly. Password rotation requires an explicit operator action.

## Network Exposure

Prometheus on `192.168.1.190` must reach ports `9187` and `9404`.

Both exporters may listen on the CT network interface, but CT `133` firewall
rules must allow these ports only from `192.168.1.190`. Existing unrelated
firewall rules must remain untouched. Local health checks from `127.0.0.1`
must remain permitted.

PostgreSQL itself remains bound to `127.0.0.1:5433`; no PostgreSQL listener or
`pg_hba.conf` network expansion is required.

## Prometheus Configuration

Extend the existing `esus-pec-lxc-5437` static target set with:

- `192.168.1.209:9187`
- `192.168.1.209:9404`

Keep the observed labels:

- `host="esus-pec-lxc-5437"`
- `ctid="133"`
- `app="esus-pec"`
- `job="esus-pec-lxc-5437"`

Exporter type continues to be distinguished by the `instance` port, matching
the current node and Nginx target pattern.

Prometheus configuration must be checked with `promtool check config` before
reload. A failed validation must leave the active configuration unchanged.

## Grafana Dashboard

Extend `e-SUS PEC CT 133` with at least these PostgreSQL panels:

- exporter availability
- database up state
- connections by state
- database size
- transactions committed and rolled back
- cache hit ratio
- deadlocks
- tuple insert/update/delete rates

Add at least these JVM panels:

- JMX exporter availability
- process uptime
- heap used and maximum
- non-heap memory
- GC pause rate and duration
- live threads and daemon threads
- class loading
- process CPU

Queries must use the live `host` and `instance` labels rather than inventing
separate job names.

## Deployment Sequence

1. Verify CT identity, service state, Java version, PostgreSQL version, and free
   exporter ports.
2. Retrieve or create the exporter password in Infisical.
3. Create/update the PostgreSQL role and compatibility objects idempotently.
4. Install and start `postgres_exporter`.
5. Download and verify the JMX agent and write its configuration.
6. Create the managed wrapper and systemd `ExecStart` drop-in.
7. Restart `e-SUS-PEC.service`.
8. Wait for the PEC endpoint on `8080` and JMX metrics on `9404`.
9. Update and validate Prometheus configuration.
10. Verify both new targets are `up`.
11. Publish the updated Grafana dashboard.

## Failure Handling and Rollback

### PostgreSQL exporter

If service startup or metric validation fails:

- Stop and disable `prometheus-postgres-exporter.service`.
- Preserve the PostgreSQL account and compatibility objects for diagnosis.
- Do not expose or regenerate the password.
- Do not modify the PEC database service or network listener.

### JMX exporter

Before restarting PEC, capture:

- current `e-SUS-PEC.service` state
- existing drop-in state
- PEC HTTP readiness

If the service, port `8080`, or JMX endpoint does not become ready:

1. Remove or restore the managed JMX drop-in.
2. Run `systemctl daemon-reload`.
3. Restart `e-SUS-PEC.service`.
4. Require port `8080` to become ready again.
5. Report failure without leaving the PEC unavailable.

The original service unit and launch script are never edited.

## Validation

Static validation must prove:

- pinned exporter versions and checksums exist
- PostgreSQL 9.6 compatibility SQL is present
- password values are absent from tracked files
- the JMX systemd drop-in and wrapper are managed and reversible
- Prometheus includes `9187` and `9404`
- Grafana includes PostgreSQL and JVM panels

Live validation must prove:

- `prometheus-postgres-exporter.service` is active
- `curl http://127.0.0.1:9187/metrics` returns PostgreSQL metrics
- `e-SUS-PEC.service` is active after JMX injection
- `curl http://127.0.0.1:9404/metrics` returns JVM metrics
- PEC port `8080` remains reachable
- Prometheus reports both new instances as `up`
- representative PostgreSQL and JVM PromQL queries return non-empty vectors
- Grafana dashboard publication succeeds

## Documentation

Update:

- `docs/monitoring/2026-06-14-centralized-monitoring.md`
- `config/esus-pec.infisical.env.example`
- the existing Obsidian centralized-monitoring engineering finding

Documentation records variable names, paths, versions, checksums, service state,
and validation results, but never secret values.

## References

- Prometheus Community PostgreSQL Exporter:
  <https://github.com/prometheus-community/postgres_exporter>
- PostgreSQL Exporter releases:
  <https://github.com/prometheus-community/postgres_exporter/releases>
- Prometheus JMX Exporter:
  <https://github.com/prometheus/jmx_exporter>
- JMX Exporter releases:
  <https://github.com/prometheus/jmx_exporter/releases>
