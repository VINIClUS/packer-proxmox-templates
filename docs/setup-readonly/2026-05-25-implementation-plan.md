# Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepare a safe implementation path for e-SUS PEC 5.4.37 without changing live Proxmox services during the read-only assessment.

**Architecture:** Treat the current Proxmox node as an existing live environment with running infrastructure CTs and reusable golden-image templates. Implementation must be staged, reversible, and preceded by explicit confirmation before any live infrastructure change.

**Tech Stack:** Proxmox VE 9.1.1, QEMU VMs, LXC CTs, cloud-init templates, PowerShell orchestration, SSH read-only validation.

---

## Current Status

`Setup.md` is populated and references the e-SUS PEC source notes in
`appEsusPEC.md`. The current PEC target is `5.4.37`, published on 2026-05-15 by
the Ministry of Health.

Official release page:
<https://sisaps.saude.gov.br/sistemas/esusaps/blog/versao-5-4-37/>

Resolved Linux installer target:
<https://arquivos.esusaps.ufsc.br/PEC/687651a247e537a3/5.4.37/eSUS-AB-PEC-5.4.37-Linux64.jar>

## Phase 0: Spec Intake and Freeze

- [x] Replace or populate `Setup.md` with the actual spec.
- [x] Identify exact phase 0-3 deliverables from the spec text.
- [x] Mark every action as read-only, safe-change, or disruptive-change.
- [ ] Confirm whether nginx, firewall, network, CT, or VM changes are allowed in any later phase. Current state: not approved; keep blocked.
- [x] Confirm rollback requirements: backups, snapshots, or full config export. Current state: documented as required before live changes.
- [x] Record PEC 5.4.37 release source and Linux installer URL.
- [x] Add a local installer acquisition script with dry-run support and
  post-download SHA-256 reporting.

## Phase 1: Inventory Validation

- [x] Re-run read-only inventory against Proxmox:

```powershell
rtk ssh root@192.168.1.149 "pveversion && qm list && pct list && pvesm status"
```

- [x] Export VM configs with `qm config <vmid>` for all affected VMIDs.
- [x] Export CT configs with `pct config <ctid>` for all affected CTIDs.
- [x] Inspect CT `110` nginx internally with read-only commands only:

```bash
nginx -t
systemctl status nginx --no-pager
ss -tulpn
```

- [ ] Confirm whether e-SUS PEC is on VM `101 ESUS-TESTE`, CT `120`, or another guest. Current evidence: CT `120` is `infisical`; VM `101` is likely target but stopped.
- [x] Locate any staged `eSUS-AB-PEC-*.jar` without executing it.
- [x] If an installer is staged, record byte size and SHA-256. Current state: no installer found, so no hash exists.
- [x] Use `shared/scripts/Get-EsusPecInstaller.ps1 -DryRun` before any approved
  download.

## Phase 2: Risk and Rollback Design

- [x] Create a before-change evidence bundle from Proxmox configs.
- [x] Define exact rollback commands, but do not execute them until implementation is approved.
- [ ] Confirm maintenance window for anything that may touch CT `100`, `110`, `120`, networking, or firewall.
- [ ] Confirm whether protected CT `120` must be excluded from automation. Current evidence: CT `120` has `protection: 1`; exclude until explicitly approved.

## Phase 3: Implementation Package

- [x] Convert the populated spec into a task list with one change per commit.
- [x] Add tests or validation scripts before implementation.
- [x] Add local validation for e-SUS PEC release/spec documentation.
- [x] Prepare dry-run commands where supported.
- [x] Stop before any live change and request explicit approval.
- [x] After approval, apply changes atomically and validate after each step. Current approved scope: new VM `102` only; VM `101` and CT `100` were not modified.

## Phase 4: Isolated Test VM Bootstrap

- [x] Create isolated Debian test VM `102 test-esus-pec-5437` from template `9200`.
- [x] Keep VM `101 ESUS-TESTE` read-only and unmodified.
- [x] Keep CT `100 Netbird` untouched.
- [x] Install test prerequisites on VM `102`: Java, PostgreSQL client tools,
  qemu guest agent, `file`, and `unzip`.
- [x] Stage PEC 5.4.37 Linux installer on VM `102`.
- [x] Validate installer SHA-256 on local host and VM.
- [x] Smoke-test installer `-console` path as non-root to avoid installation.
- [x] Document required Infisical secret placeholders without storing values.

## Phase 5: Clean Installer Run

- [x] Create clean Debian test VM `104 test-esus-pec-clean104-5437`.
- [x] Keep VM `101 ESUS-TESTE` read-only and unmodified.
- [x] Keep CT `100 Netbird` untouched.
- [x] Install only Java headless and generate `pt_BR.UTF-8` before first PEC run.
- [x] Avoid external PostgreSQL packages; use PEC bundled PostgreSQL only.
- [x] Install PEC 5.4.37 with `sudo java -jar ... -console -continue`.
- [x] Validate `e-SUS-AB-PostgreSQL.service` and `e-SUS-PEC.service` running.
- [x] Validate HTTP `200` on `http://192.168.1.204:8080/`.
- [x] Locate `credenciais.txt`, restrict it to mode `600`, and document Infisical follow-up without exposing values.

## Validation Gates

Before any future non-read-only implementation:

- [x] Spec file is non-empty and reviewed.
- [x] Inventory is refreshed.
- [x] Affected resources are explicitly listed.
- [x] Rollback is documented.
- [x] User approves the transition out of read-only mode for smallest safe implementation.
