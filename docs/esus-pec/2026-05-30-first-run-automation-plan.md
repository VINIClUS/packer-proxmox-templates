# e-SUS PEC First-Run Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the three-step e-SUS PEC first-run web wizard reproducible and suitable for unattended configuration.

**Architecture:** Inspect the live wizard on CT `133`, document every visible field, and automate the final GraphQL mutation with a script that reads values from environment variables. The script defaults to dry-run and requires an explicit apply flag before it submits configuration.

**Tech Stack:** Proxmox LXC, e-SUS PEC 5.4.37, GraphQL over HTTP, PowerShell, Infisical-compatible `.env.example`, Playwright CLI for UI evidence.

---

## Tasks

- [x] Confirm CT `133` services are active and HTTP `8080` responds.
- [x] Inspect step 1, "Identificar instalação", with Playwright.
- [x] Inspect step 2, "Cadastrar instalador", with Playwright.
- [x] Inspect step 3, "Finalizar instalação", with Playwright.
- [x] Capture final mutation using a Proxmox snapshot/rollback probe.
- [x] Add a first-run automation script with dry-run as the default.
- [x] Add first-run variables to `config/esus-pec.infisical.env.example`.
- [x] Update `docs/credentials/esus-pec-infisical-secrets.html`.
- [x] Document field requirements, mutation shape, dry-run, apply, validation, and rollback.
- [x] Add a validation test for documentation and script hygiene.
- [x] Run validation commands and commit atomically.
