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
1. **[2026-06-28] Keep e-SUS PEC work in its dedicated repository**
   Do instead: use `..\esus-pec-bootstrap` for PEC scripts, tests, docs, monitoring, WAL-G/MinIO, and `INFISICAL_*`; keep this repo focused on Packer/templates.
2. **[2026-06-28] Keep SIHA NAS work in sus-siha-bootstrap**
   Do instead: use `..\sus-siha-bootstrap` for SIHA NAS scripts, tests, docs, Samba, unit `S:`, and `SIHA_INFISICAL_*` / `SIHA_NAS_*`.
3. **[2026-06-23] Protect e-SUS PEC production**
   Do instead: treat `192.168.1.253` / `esus.presidenteepitacio.sp.gov.br` as read-only from this repo; only perform explicitly authorized production changes from `..\esus-pec-bootstrap`.
1. **[2026-06-09] Windows Proxmox Cloud-Init needs Cloudbase-Init before Sysprep**
   Do instead: install/configure Cloudbase-Init for ConfigDrive in the Windows template and run Sysprep with Cloudbase `Unattend.xml`; Proxmox `ciuser`/`cipassword` are not applied by QEMU Guest Agent or OpenSSH alone.
2. **[2026-05-22] Keep secrets out of tracked files**
   Do instead: store Proxmox credentials in ignored `config/*.pkrvars.hcl` files and track only `.example` files.
3. **[2026-05-23] Debian cloud images require Proxmox CLI access**
   Do instead: create Debian cloud-init templates by SSHing to the Proxmox node and running `qm` with `import-from`; the Packer ISO/API path is not the right mechanism for importing QCOW2 cloud images.
4. **[2026-05-23] Windows 11 Proxmox media and ACL requirements**
   Do instead: attach install/VirtIO ISOs as SATA, enable TPM 2.0, install NetKVM before WinRM, and grant `VM.GuestAgent.Audit` plus `VM.GuestAgent.Unrestricted` on the build VM.

## User Directives
1. **[2026-05-23] Commit before new work**
   Do instead: make a checkpoint commit before starting new analysis/build work, then use atomic follow-up commits for fixes and documentation.
2. **[2026-05-22] Prefer HCL2 Packer templates**
   Do instead: create Packer definitions as `.pkr.hcl` files and put variables in `variables.pkr.hcl`.
