# e-SUS PEC LXC Conversion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate whether e-SUS PEC 5.4.37 can run in an isolated Proxmox LXC container and document the exact minimal path.

**Architecture:** Create a new Debian 13 LXC test container rather than modifying the existing VM installation. Use the PEC bundled PostgreSQL and Java runtime after installation; only install the minimum host prerequisites needed to bootstrap the installer. Keep VM `101` and CT `100` untouched.

**Tech Stack:** Proxmox VE LXC, Debian 13 standard template, Java headless bootstrap, e-SUS PEC 5.4.37 Linux installer, bundled PostgreSQL 9.6, systemd services.

---

## Files

- Create: `docs/esus-pec/2026-05-27-lxc-conversion-plan.md`
- Create: `docs/esus-pec/2026-05-27-lxc-ct133-installation.md`
- Create: `scripts/esus-pec/bootstrap-lxc.sh`
- Create: `scripts/esus-pec/install-lxc.sh`
- Create: `tests/Validate-EsusPecLxcDocs.ps1`
- Modify: `docs/setup-readonly/2026-05-25-implementation-plan.md`
- Modify: `docs/credentials/esus-pec-infisical-secrets.html`

## Task 1: Preflight And Guardrails

- [x] Confirm VM `101 ESUS-TESTE` is not modified.
- [x] Confirm CT `100 Netbird` is not modified.
- [x] Confirm Debian 13 LXC template exists: `local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst`.
- [x] Confirm CTID `130` is free for the first probe, then use CTID `133` for the validated clean run.
- [x] Confirm `192.168.1.206` and final `192.168.1.209` do not answer ICMP before use.
- [x] Confirm local PEC installer SHA-256:
  `9975a55184a6dd1f66d8a837bbc533376e0400069485e8acb45100c23a535bfb`.

## Task 2: Create Minimal LXC Test Container

- [x] Create CT `130 esus-pec-lxc-5437` from the Debian 13 standard template as a first probe.
- [x] Use unprivileged mode first with `nesting=1,keyctl=1`.
- [x] Allocate `2` cores, `6144 MB` memory, `1024 MB` swap, and `40G` rootfs.
- [x] Assign static IP `192.168.1.206/24` on `vmbr0` for the first probe and `192.168.1.209/24` for the validated CT `133`.
- [x] Keep only validated CT `133` running; remove failed probe CTs `130`, `131`, and `132`.

## Task 3: Minimal PEC Bootstrap

- [x] Install only `default-jre-headless` and `locales`.
- [x] Generate `pt_BR.UTF-8` and `en_US.UTF-8` before the first installer run.
- [x] Configure `RemoveIPC=no` before installation so systemd-logind does not remove PostgreSQL SysV semaphores.
- [x] Copy `eSUS-AB-PEC-5.4.37-Linux64.jar` into `/opt/esus-pec-staging`.
- [x] Validate the installer SHA-256 inside the CT.
- [x] Confirm no external `psql` or `pg_restore` package was installed.

## Task 4: Install And Validate PEC In LXC

- [x] Run `java -jar eSUS-AB-PEC-5.4.37-Linux64.jar -console -continue` as root inside CT `133`.
- [x] Validate `e-SUS-AB-PostgreSQL.service` and `e-SUS-PEC.service`.
- [x] Validate bundled PostgreSQL listens only on localhost port `5433`.
- [x] Validate PEC HTTP responds on `http://192.168.1.209:8080/`.
- [x] Restrict `/opt/e-SUS/webserver/config/credenciais.txt` to `root:root` mode `600`.

## Task 5: Documentation And Tests

- [x] Document exact commands, evidence, limitations, and rollback cleanup for CT `133`.
- [x] Update Infisical credential documentation with the CT path and `credenciais.txt` handling.
- [x] Add a PowerShell validation script that checks the LXC documentation and secret hygiene.
- [x] Run all e-SUS PEC validation scripts.
- [x] Commit documentation atomically.
