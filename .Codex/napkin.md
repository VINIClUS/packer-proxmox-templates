# Napkin Runbook

## Curation Rules
- Re-prioritize on every read.
- Keep recurring, high-value notes only.
- Max 10 items per category.
- Each item includes date + "Do instead".

## Execution & Validation (Highest Priority)
1. **[2026-05-22] Validate Packer targets before build**
   Do instead: run `rtk packer init <target>` and `rtk packer validate -var-file="config/Proxmox.pkrvars.hcl" <target>` before any image build.

## Shell & Command Reliability
1. **[2026-05-22] Use RTK prefix for shell commands**
   Do instead: prefix repository commands with `rtk`, including git and validation commands.

## Domain Behavior Guardrails
1. **[2026-05-22] Keep secrets out of tracked files**
   Do instead: store Proxmox credentials in ignored `config/*.pkrvars.hcl` files and track only `.example` files.

## User Directives
1. **[2026-05-23] Commit before new work**
   Do instead: make a checkpoint commit before starting new analysis/build work, then use atomic follow-up commits for fixes and documentation.
2. **[2026-05-22] Prefer HCL2 Packer templates**
   Do instead: create Packer definitions as `.pkr.hcl` files and put variables in `variables.pkr.hcl`.
