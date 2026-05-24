# Napkin Runbook

## Curation Rules
- Re-prioritize on every read.
- Keep recurring, high-value notes only.
- Max 10 items per category.
- Each item includes date + "Do instead".

## Execution & Validation (Highest Priority)
1. **[2026-05-22] Validate Packer targets before build**
   Do instead: run `rtk packer init <target>` and `rtk packer validate -var-file="config/Proxmox.pkrvars.hcl" <target>` before any image build.
2. **[2026-05-23] Wait after deleting Proxmox VMID 9101**
   Do instead: after cleanup deletes VM/template 9101, wait for Proxmox deletion to settle before reusing the VMID; otherwise delayed deletion can remove the next build VM.
3. **[2026-05-23] Use Packer debug logs for WinRM waits**
   Do instead: rerun with `PACKER_LOG=1` and inspect `Error getting WinRM host` lines before changing Windows setup scripts.

## Shell & Command Reliability
1. **[2026-05-22] Use RTK prefix for shell commands**
   Do instead: prefix repository commands with `rtk`, including git and validation commands.

## Domain Behavior Guardrails
1. **[2026-05-22] Keep secrets out of tracked files**
   Do instead: store Proxmox credentials in ignored `config/*.pkrvars.hcl` files and track only `.example` files.
2. **[2026-05-23] Debian cloud images require Proxmox CLI access**
   Do instead: create Debian cloud-init templates by SSHing to the Proxmox node and running `qm` with `import-from`; the Packer ISO/API path is not the right mechanism for importing QCOW2 cloud images.
3. **[2026-05-23] Windows 11 Proxmox media and ACL requirements**
   Do instead: attach install/VirtIO ISOs as SATA, enable TPM 2.0, install NetKVM before WinRM, and grant `VM.GuestAgent.Audit` plus `VM.GuestAgent.Unrestricted` on the build VM.

## User Directives
1. **[2026-05-23] Commit before new work**
   Do instead: make a checkpoint commit before starting new analysis/build work, then use atomic follow-up commits for fixes and documentation.
2. **[2026-05-22] Prefer HCL2 Packer templates**
   Do instead: create Packer definitions as `.pkr.hcl` files and put variables in `variables.pkr.hcl`.
