# Windows 11 24H2 Proxmox Template Runbook

## Scope

This runbook covers analysis, testing, validation, building, and documentation for `windows/win11-24h2`.

## Analysis

The template builds a Windows 11 24H2 Proxmox template from a local Proxmox ISO path. It uses:

- `windows/win11-24h2/windows-11.pkr.hcl` for the Proxmox ISO builder.
- `windows/win11-24h2/http/Autounattend.xml.pkrtpl` for unattended setup.
- `windows/win11-24h2/http/scripts/Configure-WinRM.ps1` for WinRM bootstrap.
- `windows/win11-24h2/scripts/*.ps1` for VirtIO tools, Cloudbase-Init, cleanup, and Sysprep.
- `config/Proxmox.pkrvars.hcl` for real local secrets.
- `config/Proxmox.pkrvars.hcl.example` for tracked example values.

## Cloudbase-Init

Windows clones created from this template depend on Cloudbase-Init to consume
the Proxmox Cloud-Init drive. The Packer build installs
`CloudbaseInitSetup_Stable_x64.msi`, configures the service to run as
LocalSystem, restricts metadata discovery to ConfigDrive, and enables the
plugins for hostname, user creation, network config, SSH public keys, volume
extension, user data, password injection, and local scripts.

The Sysprep step uses
`C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\Unattend.xml` when it
exists so the generalized image boots with Cloudbase-Init integration intact.

On 2026-06-09, VMID `7001` on Proxmox `192.168.1.149` had `ciuser=cpd`, a
cloud-init drive on `ide2`, and guest networking on `192.168.1.98`, but QEMU
Guest Agent inspection showed no `cloudbase-init` service and `net user cpd`
returned that the user did not exist. That means the Proxmox Cloud-Init values
were generated on the host but no Windows guest agent was present to apply them.

## Testing

Run the local structural and script syntax check:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests\Validate-WindowsTemplate.ps1
```

Expected result:

```text
Windows template structure validated.
```

## Validation

Format and validate the Packer template before any build:

```powershell
rtk packer fmt -check -diff windows\win11-24h2
rtk packer init windows\win11-24h2
rtk packer validate -var-file="config\Proxmox.pkrvars.hcl" windows\win11-24h2
```

Expected validation result:

```text
The configuration is valid.
```

Run the Proxmox preflight:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-ProxmoxPreflight.ps1
```

This checks API access without printing secrets and verifies that the configured Windows and VirtIO ISOs exist in Proxmox ISO storage.

The local machine also needs one supported ISO authoring command for Packer's generated answer/scripts ISO: `oscdimg`, `xorriso`, `mkisofs`, or `hdiutil`. On Windows, `oscdimg` can be installed with:

```powershell
rtk winget install --id Microsoft.OSCDIMG --accept-package-agreements --accept-source-agreements --silent
```

If the current shell does not see the new alias, prepend the installed package directory to `PATH` for the build session.

## Build

Only run the build after the preflight passes.

```powershell
rtk packer build -var-file="config\Proxmox.pkrvars.hcl" windows\win11-24h2
```

The configured example expects these Proxmox ISO paths:

- `local:iso/Win11_24H2_English_x64.iso`
- `local:iso/virtio-win.iso`

Upload both ISO files to the configured `proxmox_iso_storage_pool` before building.

The Proxmox API token must be able to upload the generated answer ISO to the configured ISO storage. The observed missing privilege is:

```text
Datastore.AllocateTemplate on /storage/local
```

For untagged networking on Proxmox 9, omit `vlan_tag`; do not set `tag=0`. The current template creates an untagged VirtIO NIC on the configured bridge.

VM creation also requires disk allocation on the VM storage pool:

```text
Datastore.AllocateSpace on /storage/local-lvm
```

Failed-build cleanup of generated `packer*.iso` files in ISO storage requires:

```text
Datastore.Allocate on /storage/local
```

VM creation/configuration currently also requires:

```text
VM.Config.Options on /vms/9101
```

If the build VM ID changes, grant the equivalent permission on that VM path or on a parent scope that covers the Packer build VM IDs.

Console access was granted during the 2026-05-22 retry. The next observed Proxmox 9 SDN requirement for the configured bridge is:

```text
SDN.Use on /sdn/zones/localnetwork/vmbr0
```

If `proxmox_network_bridge` changes, grant the equivalent `SDN.Use` permission for that bridge path.

## Documentation

Credential requirements are documented in `docs/credentials/windows-template-credentials.html`. Update that HTML file whenever a variable or secret requirement changes. Do not commit `config/Proxmox.pkrvars.hcl`.
