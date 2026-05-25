# app e-SUS PEC Setup Specification Correction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct `Setup.md` into an actionable implementation specification for app e-SUS PEC deployment once the missing source requirements are supplied.

**Architecture:** Treat `appEsusPEC.md` as the upstream product/spec input and `Setup.md` as the normalized implementation specification. The current repository state blocks content-level correction because both files are empty, so this plan first enforces source validation before allowing any infrastructure or setup procedure to be authored.

**Tech Stack:** Markdown specifications, Proxmox VE inventory, PowerShell validation scripts, SSH read-only evidence collection.

---

## Current Evidence

- `appEsusPEC.md` now contains extracted source notes from the shared Gemini URL.
- `Setup.md` now contains a full Proxmox app-platform specification.
- The Gemini source is accessible through Playwright text extraction; direct `web.open` exposes only the Gemini sign-in shell.
- Existing read-only inventory artifacts are under `docs/setup-readonly/`.

## File Responsibilities

- `appEsusPEC.md`: upstream source of app e-SUS PEC requirements, constraints, version assumptions, deployment topology, and operational expectations.
- `Setup.md`: corrected implementation specification derived from `appEsusPEC.md`; must be executable by an infrastructure engineer without guessing.
- `docs/setup-readonly/2026-05-25-inventory.md`: current Proxmox evidence baseline.
- `docs/setup-readonly/2026-05-25-risks.md`: current risk register and confirmation gaps.
- `docs/setup-readonly/2026-05-25-implementation-plan.md`: previous read-only implementation framework.

## Task 1: Validate Source Specification Presence

- [ ] **Step 1: Confirm source files are non-empty**

Run:

```powershell
rtk powershell -NoProfile -Command "Get-Item appEsusPEC.md,Setup.md | Select-Object Name,Length"
```

Expected before proceeding:

```text
appEsusPEC.md  > 0
Setup.md       any length
```

If `appEsusPEC.md` remains `0`, stop. Do not infer product requirements.

- [ ] **Step 2: Read `appEsusPEC.md` completely**

Run:

```powershell
rtk powershell -NoProfile -Command "Get-Content -LiteralPath appEsusPEC.md -Raw"
```

Expected: complete upstream requirements for app e-SUS PEC, including deployment assumptions and operational constraints.

- [ ] **Step 3: Extract requirement IDs**

Create a requirement map in the plan notes with this schema:

```markdown
| ID | Requirement | Source section | Setup.md section |
|---|---|---|---|
| REQ-001 | <exact requirement summary from appEsusPEC.md> | <heading or line evidence> | <target section in Setup.md> |
```

Do not continue until every actionable requirement has one row.

## Task 2: Correct `Setup.md` Structure

- [ ] **Step 1: Replace empty or ambiguous structure with this exact heading model**

`Setup.md` must use this outline:

```markdown
# app e-SUS PEC Setup Specification

## 1. Objective
## 2. Source Requirements Traceability
## 3. Current Environment Baseline
## 4. Target Architecture
## 5. Resource Plan
## 6. Network and DNS Plan
## 7. Storage and Backup Plan
## 8. Security and Secrets Plan
## 9. Deployment Phases
### Phase 0: Read-Only Discovery
### Phase 1: Preflight and Backups
### Phase 2: Provisioning
### Phase 3: Application Setup and Validation
## 10. Rollback Plan
## 11. Validation and Acceptance Criteria
## 12. Pending Confirmations
```

- [ ] **Step 2: Add traceability table**

`Setup.md` must include one row per requirement from `appEsusPEC.md`:

```markdown
| Requirement ID | Source evidence | Implementation section | Status |
|---|---|---|---|
| REQ-001 | appEsusPEC.md:<line or heading> | Setup.md:<section> | planned |
```

- [ ] **Step 3: Add explicit no-change guardrails**

Include this guardrail block near the top:

```markdown
Until an implementation window is approved, all commands are read-only. Do not restart services, change firewall rules, modify network interfaces, edit nginx, or change CT/VM configuration.
```

## Task 3: Define Implementation Phases

- [ ] **Step 1: Phase 0 must remain read-only**

Phase 0 must include only inventory commands such as:

```powershell
rtk ssh root@192.168.1.149 "pveversion && qm list && pct list && pvesm status"
rtk ssh root@192.168.1.149 "qm config <vmid>"
rtk ssh root@192.168.1.149 "pct config <ctid>"
```

- [ ] **Step 2: Phase 1 must define backups before change**

Phase 1 must list the exact CTs/VMs affected by the corrected spec and require a backup or snapshot decision for each one.

- [ ] **Step 3: Phase 2 must describe provisioning without live commands**

Phase 2 must describe target VM/CT creation, image/template choice, storage, CPU, memory, disk, and network requirements, but leave execution commands gated behind approval.

- [ ] **Step 4: Phase 3 must define validation**

Phase 3 must define user-visible acceptance checks, service health checks, and rollback triggers.

## Task 4: Validate Corrected Specification

- [ ] **Step 1: Check required headings**

Run:

```powershell
rtk powershell -NoProfile -Command "$text = Get-Content -LiteralPath Setup.md -Raw; @('Objective','Source Requirements Traceability','Target Architecture','Deployment Phases','Rollback Plan','Validation and Acceptance Criteria','Pending Confirmations') | ForEach-Object { if ($text -notmatch [regex]::Escape($_)) { throw \"Missing heading: $_\" } }; 'Setup.md heading validation passed.'"
```

Expected:

```text
Setup.md heading validation passed.
```

- [ ] **Step 2: Check unresolved confirmation markers**

Run:

```powershell
rtk rg -n "NEEDS-CONFIRMATION|BLOCKED|UNKNOWN" Setup.md
```

Expected: only deliberate pending confirmation entries remain in `## 12. Pending Confirmations`.

- [ ] **Step 3: Check no secret material is present**

Run:

```powershell
rtk rg -n -i "password|token|secret|private key|api key" Setup.md appEsusPEC.md
```

Expected: no literal secret values; only placeholder references or process descriptions.

## Task 5: Commit and Handoff

- [ ] **Step 1: Review diff**

Run:

```powershell
rtk git diff -- Setup.md docs/superpowers/plans/2026-05-25-app-esus-pec-setup-spec-correction.md
```

- [ ] **Step 2: Commit corrected specification**

Run:

```powershell
rtk git add Setup.md docs/superpowers/plans/2026-05-25-app-esus-pec-setup-spec-correction.md
rtk git commit -m "Correct app e-SUS PEC setup specification"
```

## Stop Conditions

- `appEsusPEC.md` is empty.
- `appEsusPEC.md` lacks deployment requirements.
- The target CTs/VMs are not identified.
- The user has not approved leaving read-only mode.
- Any step requires firewall, network, nginx, CT, or VM changes without an approved change window.

## Current Status

Task 1 source validation is unblocked. `appEsusPEC.md` has been populated with extracted requirements, and `Setup.md` has been corrected to include app e-SUS PEC-specific discovery, risk, rollback, PostgreSQL, backup/restore, disk, and swap requirements. Next implementation work must remain gated by the stop conditions in `Setup.md`, especially the prohibition on service, firewall, network, CT, or VM changes without explicit approval.
