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

## Commit & Pull Request Guidelines

Git history is minimal, so use concise imperative commit subjects, for example `Add Debian 12 Packer template`. Pull requests should describe the target OS, Proxmox assumptions, validation commands run, and any required local variables. Never include credentials, API tokens, generated ISOs, or real `config/*.pkrvars.hcl` files.

## Security & Configuration Tips

Track example variable files only, such as `config/Proxmox.pkrvars.hcl.example`. Keep templates immutable: rebuild images instead of manually patching existing Proxmox templates. Ensure Windows images run Sysprep and Linux images clear machine identity, SSH host keys, logs, and shell history before sealing.
