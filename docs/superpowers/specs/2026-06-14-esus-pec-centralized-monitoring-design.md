# e-SUS PEC Centralized Monitoring Design

Date: 2026-06-14
Workspace: `C:\Users\Vinicius\Projetos\packer-proxmox-templates`

## Decision

Provision a single native systemd monitoring LXC at CTID `190` with Prometheus,
Grafana, Loki, and local Grafana Alloy. Keep CTIDs `191-199` reserved for future
monitoring expansion.

Use Grafana Alloy, not Promtail, for new log and telemetry agents because the
Grafana Loki documentation marks Promtail as end of life as of 2026-03-02 and
states that future feature development occurs in Alloy.

## Scope

The first implementation must create reusable repository tooling for:

- Creating or updating LXC `190` on Proxmox `192.168.1.149`.
- Installing Prometheus, Grafana, Loki, and Alloy as systemd services in CT `190`.
- Generating non-secret baseline configuration for Prometheus scrape jobs, Loki,
  Alloy, and Grafana datasources.
- Installing or configuring collection agents first on the e-SUS PEC LXC test
  host `133 esus-pec-lxc-5437`; SIHA VM `7001` remains in scope as the next
  target when the billing systems and target OS are ready.
- Testing service health and scrape/log ingestion without printing credentials.
- Documenting install, validation, rollback, and secret-handling procedures.

The first implementation will not tune production alert thresholds or install
business dashboards beyond baseline operational views. Those are follow-up tasks
after enough time-series and log data exists.

## Topology

### Monitoring Core

- CTID: `190`
- Hostname: `monitoring-core`
- Base OS: Debian LXC template already available on Proxmox, defaulting to the
  existing Debian 13 standard template pattern used by PEC/MinIO automation.
- Runtime model: native packages or upstream binaries managed by systemd.
- Services:
  - Prometheus on `:9090`
  - Grafana on `:3000`
  - Loki on `:3100`
  - Alloy local service for CT `190` logs and host-level metrics

### Targets

- Initial PEC target: LXC `133 esus-pec-lxc-5437`, the validated e-SUS PEC
  5.4.37 LXC test instance. It currently runs the PEC Java service on `:8080`
  and uses Nginx inside the same LXC for TLS termination.
- Future PEC production target: `esus.presidenteepitacio.sp.gov.br`, reachable
  through the internal `192.168.1.25x:8080` address family. It is not part of
  the first agent rollout and differs from LXC `133` because it uses Tomcat on
  the same machine instead of the Nginx termination pattern used by CT `133`.
- Future SIHA target: VM `7001`, containing billing systems.

The PEC production IP must remain parameterized because the user provided
`192.168.1.25x`, not a complete address. The tooling must accept target
parameters instead of hardcoding a guessed production IP.

## Data Collection

### Operating System

Linux targets use Alloy plus node-exporter-compatible metrics. Windows targets
use windows_exporter for metrics and Alloy for logs when Windows access is
available.

Minimum OS metrics:

- CPU, memory, disk, filesystem, network, systemd service status on Linux.
- CPU, memory, disk, network, service status, and event log collection on
  Windows targets.

### Database

The PEC bundled PostgreSQL must be observed through postgres_exporter with a
least-privilege monitoring role. The exporter DSN is a secret and must not be
committed, printed, or written to documentation.

The script may create or update exporter configuration only if a credential
source is explicitly provided through a local ignored env file, Infisical, or an
operator-provided secure channel. Otherwise it must leave a documented pending
step instead of guessing credentials.

### Application, Java, and JVM

The design target is JMX exporter for JVM metrics. Because the PEC installer owns
the service startup path, the first automation must inspect the service unit and
write an explicit proposed change before enabling a `-javaagent` option on a live
production PEC service.

The implementation may configure JMX exporter automatically on disposable or
test PEC instances. For production PEC, it must require an explicit apply flag
and create a rollback file for the original service configuration.

### Nginx

For PEC hosts that terminate traffic with Nginx, enable a local-only
`stub_status` endpoint and scrape it through an Nginx exporter or Alloy
Prometheus scrape component. The `stub_status` endpoint must bind to localhost or
be restricted to the monitoring network, not exposed publicly.

This applies to the first target, CT `133`. The future production PEC target must
be handled through Tomcat/JVM collection instead of assuming Nginx exists.

### Logs

Grafana Alloy ships logs to Loki. Baseline sources:

- systemd journal for Linux targets.
- `/var/log/nginx/*.log` where Nginx exists.
- PEC application logs under `/opt/e-SUS` when present and readable.
- PostgreSQL logs when discoverable without exposing database credentials.
- Windows Event Logs on SIHA if VM `7001` is Windows.

Log labels must avoid high-cardinality values and must not include passwords,
tokens, patient data, or request bodies.

## Repository Deliverables

Expected new or updated artifacts:

- `scripts/monitoring/Provision-MonitoringCore.ps1`
- `scripts/monitoring/Install-MonitoringTargetAgent.ps1`
- `scripts/monitoring/templates/prometheus.yml`
- `scripts/monitoring/templates/loki.yml`
- `scripts/monitoring/templates/alloy-core.alloy`
- `scripts/monitoring/templates/alloy-linux-target.alloy`
- `scripts/monitoring/templates/grafana-datasources.yml`
- `tests/Validate-MonitoringStack.ps1`
- `docs/monitoring/2026-06-14-centralized-monitoring.md`

The scripts must follow existing repository patterns:

- Read Proxmox SSH settings from `config/Proxmox.pkrvars.hcl`.
- Use SSH and `pct exec` for LXC operations.
- Keep secrets in ignored files or external secret stores.
- Print names, paths, HTTP status codes, versions, and lengths only; never print
  secret values.
- Be idempotent and safe to rerun.

## Validation Strategy

Static validation:

- Required scripts, templates, docs, and tests exist.
- Template placeholders are present for target hosts and secret file paths.
- No obvious secret values are committed.
- Promtail is not introduced.
- CTID `190` is used for the monitoring core and `191-199` are documented as
  reserved.

Live validation:

- CT `190` exists and is running.
- systemd reports Prometheus, Grafana, Loki, and Alloy active.
- Prometheus `/-/ready` returns success.
- Grafana `/api/health` returns success without printing admin credentials.
- Loki `/ready` returns success.
- Prometheus targets include the monitoring core and CT `133` exporters.
- Production PEC and SIHA targets are documented as future additions, not
  required live-validation targets for the first implementation.
- Loki receives at least one non-secret log entry from CT `190`.

## Rollback

Core rollback:

- Stop and disable `prometheus`, `grafana-server`, `loki`, and `alloy` inside
  CT `190`.
- Preserve `/etc/prometheus`, `/etc/loki`, `/etc/alloy`, `/etc/grafana`, and data
  directories unless destructive removal is explicitly requested.
- Destroy CT `190` only with an explicit operator confirmation outside the
  default script path.

Target rollback:

- Disable Alloy/exporter systemd units on targets.
- Restore original Nginx and Java service files from timestamped backups.
- Remove monitoring users only after confirming no other monitoring process uses
  them.

## References

- Grafana Loki Promtail documentation: `https://grafana.com/docs/loki/latest/send-data/promtail/`
- Grafana Alloy Linux install documentation: `https://grafana.com/docs/alloy/latest/set-up/install/linux/`
- Grafana Debian/Ubuntu install documentation: `https://grafana.com/docs/grafana/latest/setup-grafana/installation/debian/`
- Prometheus installation documentation: `https://prometheus.io/docs/prometheus/latest/installation/`
