# Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepare a safe implementation path for the missing setup specification without changing live Proxmox services during the read-only assessment.

**Architecture:** Treat the current Proxmox node as an existing live environment with running infrastructure CTs and reusable golden-image templates. Implementation must be staged, reversible, and preceded by explicit confirmation because the requested spec file is empty.

**Tech Stack:** Proxmox VE 9.1.1, QEMU VMs, LXC CTs, cloud-init templates, PowerShell orchestration, SSH read-only validation.

---

## Current Blocker

`Setup.md` is empty (`0` bytes) and no file named `SPEC Setup.md` exists in the repository. The phases below are therefore a safe execution framework, not an implementation of unknown spec requirements.

## Phase 0: Spec Intake and Freeze

- [ ] Replace or populate `Setup.md` with the actual spec.
- [ ] Identify exact phase 0-3 deliverables from the spec text.
- [ ] Mark every action as read-only, safe-change, or disruptive-change.
- [ ] Confirm whether nginx, firewall, network, CT, or VM changes are allowed in any later phase.
- [ ] Confirm rollback requirements: backups, snapshots, or full config export.

## Phase 1: Inventory Validation

- [ ] Re-run read-only inventory against Proxmox:

```powershell
rtk ssh root@192.168.1.149 "pveversion && qm list && pct list && pvesm status"
```

- [ ] Export VM configs with `qm config <vmid>` for all affected VMIDs.
- [ ] Export CT configs with `pct config <ctid>` for all affected CTIDs.
- [ ] If approved, inspect CT `110` nginx internally with read-only commands only:

```bash
nginx -T
systemctl status nginx --no-pager
ss -tulpn
```

## Phase 2: Risk and Rollback Design

- [ ] Create a before-change evidence bundle from Proxmox configs.
- [ ] Define exact rollback commands, but do not execute them until implementation is approved.
- [ ] Confirm maintenance window for anything that may touch CT `100`, `110`, `120`, networking, or firewall.
- [ ] Confirm whether protected CT `120` must be excluded from automation.

## Phase 3: Implementation Package

- [ ] Convert the populated spec into a task list with one change per commit.
- [ ] Add tests or validation scripts before implementation.
- [ ] Prepare dry-run commands where supported.
- [ ] Stop before any live change and request explicit approval.
- [ ] After approval, apply changes atomically and validate after each step.

## Validation Gates

Before any future non-read-only implementation:

- [ ] Spec file is non-empty and reviewed.
- [ ] Inventory is refreshed.
- [ ] Affected resources are explicitly listed.
- [ ] Rollback is documented.
- [ ] User approves the transition out of read-only mode.
