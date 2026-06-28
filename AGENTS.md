# Repository Guidelines

## Project Structure & Module Organization

This repository builds reproducible Proxmox VE golden images with HashiCorp Packer. The current source of truth is `README.md`; the intended layout separates global configuration from OS-specific templates:

- `config/`: local Proxmox variables and credentials. Keep real `*.pkrvars.hcl` files untracked.
- `shared/`: cross-OS helper scripts such as network checks or notifications.
- `windows/<version>/`: Windows Packer templates, `http/` unattended files, and `scripts/` provisioning steps.
- `linux/<distro>/`: Linux Packer templates, `http/` preseed/kickstart files, and `scripts/` hardening and cleanup.

## Build, Test, and Development Commands

Prefix shell commands with `rtk` when working in this repository.

- `rtk packer init ./windows/server-2022`: install required Packer plugins for a target template.
- `rtk packer validate -var-file="config/Proxmox.pkrvars.hcl" ./windows/server-2022`: validate HCL syntax and variables before a build.
- `rtk packer build -var-file="config/Proxmox.pkrvars.hcl" ./windows/server-2022`: create and seal the Proxmox template.
- `rtk git diff`: review local changes before committing.

Adjust the target path for each OS or distribution.

## Coding Style & Naming Conventions

Use Packer HCL2 only; do not add legacy JSON templates. Name Packer files with `.pkr.hcl`, keep variable declarations in `variables.pkr.hcl`, and reference runtime values through `var.<name>`. Use lowercase, hyphenated directory names such as `windows/server-2022` or `linux/debian-12`. Make Bash and PowerShell provisioning scripts idempotent and safe to rerun.

## Testing Guidelines

There is no standalone test framework yet. Treat `packer validate` as the minimum required check for every template change. For script changes, run the relevant script in a disposable VM or template build path and document the validation performed in the PR.

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

Git history is minimal, so use concise imperative commit subjects, for example `Add Debian 12 Packer template`. Pull requests should describe the target OS, Proxmox assumptions, validation commands run, and any required local variables. Never include credentials, API tokens, generated ISOs, or real `config/*.pkrvars.hcl` files.

## Security & Configuration Tips

Track example variable files only, such as `config/Proxmox.pkrvars.hcl.example`. Keep templates immutable: rebuild images instead of manually patching existing Proxmox templates. Ensure Windows images run Sysprep and Linux images clear machine identity, SSH host keys, logs, and shell history before sealing.

## Production Environment Guardrails

The host `192.168.1.253` is the functional and accessible e-SUS PEC production server behind `esus.presidenteepitacio.sp.gov.br`. Do not modify this machine, its services, TLS upstream mapping, DNS/proxy references, or related Infisical variables without explicit operator authorization for that specific action. Treat routine work against production as read-only unless the user clearly approves a change.


<!-- headroom:rtk-instructions -->
# RTK (Rust Token Killer) - Token-Optimized Commands

When running shell commands, **always prefix with `rtk`**. This reduces context
usage by 60-90% with zero behavior change. If rtk has no filter for a command,
it passes through unchanged � so it is always safe to use.

## Key Commands
```bash
# Git (59-80% savings)
rtk git status          rtk git diff            rtk git log

# Files & Search (60-75% savings)
rtk ls <path>           rtk read <file>         rtk grep <pattern>
rtk find <pattern>      rtk diff <file>

# Test (90-99% savings) � shows failures only
rtk pytest tests/       rtk cargo test          rtk test <cmd>

# Build & Lint (80-90% savings) � shows errors only
rtk tsc                 rtk lint                rtk cargo build
rtk prettier --check    rtk mypy                rtk ruff check

# Analysis (70-90% savings)
rtk err <cmd>           rtk log <file>          rtk json <file>
rtk summary <cmd>       rtk deps                rtk env

# GitHub (26-87% savings)
rtk gh pr view <n>      rtk gh run list         rtk gh issue list

# Infrastructure (85% savings)
rtk docker ps           rtk kubectl get         rtk docker logs <c>

# Package managers (70-90% savings)
rtk pip list            rtk pnpm install        rtk npm run <script>
```

## Rules
- In command chains, prefix each segment: `rtk git add . && rtk git commit -m "msg"`
- For debugging, use raw command without rtk prefix
- `rtk proxy <cmd>` runs command without filtering but tracks usage
<!-- /headroom:rtk-instructions -->
