# Repository Guidelines

## Project Structure & Module Organization

This repository builds reproducible Proxmox VE templates. `README.md` is the human-facing overview; keep agent-only rules (such as the `rtk` prefix) in this file.

- `config/`: shared Proxmox variables. Only `Proxmox.pkrvars.hcl.example` is tracked; the real `config/Proxmox.pkrvars.hcl` stays untracked.
- `windows/win11-24h2/`: Packer HCL2 template (`windows-11.pkr.hcl`, `variables.pkr.hcl`), `http/` unattended files, and `scripts/` provisioning steps (VirtIO, Cloudbase-Init, Sysprep).
- `linux/<distro>-cloudinit/`: not Packer builds. Each target imports the official cloud image through `scripts/New-*CloudInitTemplate.ps1` over SSH with `qm`, with defaults in `<target>.pkrvars.hcl.example`.
- `shared/scripts/New-ProxmoxCloudInitTemplate.ps1`: common implementation behind the Linux target scripts.
- `tests/`: PowerShell validators and read-only Proxmox preflights.
- `docs/`: runbooks, dated build reports, and `docs/_templates/`.

## Repository Boundary

The e-SUS PEC bootstrap and operations domain is no longer maintained in this
repository. Use `..\esus-pec-bootstrap` locally and
`https://github.com/VINIClUS/esus-pec-bootstrap.git` remotely for PEC scripts,
tests, documentation, monitoring, WAL-G/MinIO, and `INFISICAL_*` variables.
Do not add new PEC operational artifacts back to this Packer/template
repository unless the user explicitly requests a cross-repository migration.

The SIHA NAS and SIHA/DATASUS bootstrap domain is also no longer maintained in
this repository. Use `..\sus-siha-bootstrap` for SIHA NAS scripts, tests,
documentation, Samba/SMB operations, Windows `S:` mapping, and
`SIHA_INFISICAL_*` / `SIHA_NAS_*` variables. Do not add new SIHA operational
artifacts back to this Packer/template repository unless explicitly requested.

## Build, Test, and Development Commands

Prefix shell commands with `rtk` when working in this repository. Human-facing docs (`README.md`, target READMEs) show plain commands.

- `rtk packer fmt -check -diff windows\win11-24h2`: check HCL formatting.
- `rtk packer init windows\win11-24h2`: install required Packer plugins.
- `rtk packer validate -var-file="config\Proxmox.pkrvars.hcl" windows\win11-24h2`: validate HCL syntax and variables before a build.
- `rtk packer build -var-file="config\Proxmox.pkrvars.hcl" windows\win11-24h2`: create and seal the Windows template.
- `rtk powershell -NoProfile -ExecutionPolicy Bypass -File linux\debian-13-cloudinit\scripts\New-DebianCloudInitTemplate.ps1 [-Force]`: create a Linux cloud-init template (same pattern for AlmaLinux and Ubuntu). `-Force` replaces an existing VMID; only use it when the user asked for a rebuild.
- `rtk git diff`: review local changes before committing.

## Coding Style & Naming Conventions

Use Packer HCL2 only; do not add legacy JSON templates. Name Packer files with `.pkr.hcl`, keep variable declarations in `variables.pkr.hcl`, and reference runtime values through `var.<name>`. Use lowercase, hyphenated directory names such as `windows/win11-24h2` or `linux/debian-13-cloudinit`. Make Bash and PowerShell provisioning scripts idempotent and safe to rerun.

## Testing Guidelines

Run the validators in `tests/` that match the change, all with `rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests\<script>.ps1`:

- Windows template changes: `Validate-WindowsTemplate.ps1`, plus `packer fmt -check` and `packer validate`.
- Linux cloud-init changes: `Test-CloudInitTemplateScripts.ps1` and the matching `Validate-<Distro>CloudInitTemplate.ps1`.
- Any documentation change: `Validate-DocumentationStandard.ps1`. It pins required terms in `AGENTS.md`, the skill, `docs/README.md`, and `docs/_templates/`, so keep those terms when editing.
- `Test-ProxmoxPreflight.ps1`, `Get-ProxmoxNodes.ps1`, and `Get-ProxmoxIsoInventory.ps1` query the live Proxmox API read-only and need a filled local `config/Proxmox.pkrvars.hcl`.

Static validators do not replace a real build. For provisioning script changes, run the relevant build in a disposable VMID and record the result in `docs/build-reports/`.

## Operational Documentation Standard

Any change to provisioning scripts, backup or restore procedures, scheduled jobs, timers, administrative routines, infrastructure runbooks, or secret-backed operational variables must update the matching documentation in the same commit. Do not merge operational behavior without the runbook that lets another operator execute, validate, roll back, and audit it later.

Use the repository-local skill `.agents/skills/documentar-operacao/SKILL.md` as the default checklist for operational work. Before editing operational scripts, inspect the nearest runbook under `docs/` and the templates in `docs/_templates/`; before finishing, verify that the changed script/config, matching documentation, tracked examples, and validation evidence can be committed as one atomic operational slice.

Use Brazilian Portuguese for operational docs unless the surrounding document is already in English. Keep the tone procedural and evidence-oriented: state the objective, scope, target environment, exact commands, expected results, validation evidence, rollback, risks, and remaining manual checks. Prefer absolute dates, CTIDs/VMIDs, hostnames, IPs, paths, storage names, service names, and log locations over vague descriptions.

Required sections for new or materially changed operational docs:

- Objetivo/Escopo.
- Topologia, campos de implantacao, or variaveis operacionais.
- Pre-requisitos and safety checks, including dry-run when the script supports it.
- Execucao with exact commands and placeholders clearly marked.
- Validacao with concrete expected outputs or pass/fail criteria.
- Backup/restauracao impact and a real restore-test requirement when data durability is involved.
- Rollback or stop procedure that preserves data by default.
- Seguranca, secrets, firewall/exposure, and least-privilege notes.
- Evidencias, logs, report paths, and acceptance checklist.
- Pendencias manuais and explicit items that are not production-ready yet.

For Infisical or other secret-backed configuration, update tracked example files and documentation with variable names and logical paths, but never commit real values. Sync scripts must report only metadata such as key name, path, action, and value presence. Any password, token, private key, credential file, or health/faturamento data must stay out of chat, logs, docs, and git history.

Infisical namespaces are not interchangeable. In this workspace, `INFISICAL_*` targets the ESUS PEC project, `TEMPLATE_INFISICAL_*` or the local compatibility alias `TEMPLATES_INFISICAL_*` targets template projects, and `SIHA_INFISICAL_*` targets SIHA projects. Scripts must make the intended namespace explicit and must not silently fall back to `INFISICAL_*` for template or SIHA operations.

Keep commits atomic for operational work. A commit should contain one coherent operational slice: script/config change, matching docs, tracked examples, and validation updates. Do not mix unrelated infrastructure changes, generated reports, or cleanup into the same commit.

## Commit & Pull Request Guidelines

Use concise imperative commit subjects, for example `Add Debian 13 cloud-init template`. Pull requests should describe the target OS, Proxmox assumptions, validation commands run, and any required local variables. Never include credentials, API tokens, generated ISOs, or real `config/*.pkrvars.hcl` files.

## Security & Configuration Tips

Track example variable files only, such as `config/Proxmox.pkrvars.hcl.example`. Keep templates immutable: rebuild images instead of manually patching existing Proxmox templates. Ensure Windows images run Sysprep and Linux images clear machine identity, SSH host keys, logs, and shell history before sealing.

## Production Environment Guardrails

The host `192.168.1.253` is the functional and accessible e-SUS PEC production server behind `esus.presidenteepitacio.sp.gov.br`. Do not modify this machine, its services, TLS upstream mapping, DNS/proxy references, or related Infisical variables without explicit operator authorization for that specific action. Treat routine work against production as read-only unless the user clearly approves a change. Authorized PEC operational changes belong in `..\esus-pec-bootstrap`, not in this repository.
