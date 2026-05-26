# e-SUS PEC Test VM 102 Implementation

Date: 2026-05-25
Target: `102 test-esus-pec-5437`
Constraint: VM `101 ESUS-TESTE` was not modified. CT `100 Netbird` was not
modified.

## Implemented Change

Created an isolated Debian 13 test VM from template `9200`:

```text
VMID: 102
Name: test-esus-pec-5437
Source template: 9200 tpl-debian-13-cloudinit
CPU: 2 cores
Memory: 4096 MB
Disk: 40G on local-lvm
Network: vmbr0 DHCP, firewall=1
IPv4: 192.168.1.202
User: debian via SSH public key
```

The VM description marks it as temporary and warns not to store secrets there.

## Local Installer Staging

The Linux installer was downloaded locally into ignored path `.downloads/`:

```text
Path: .downloads/esus-pec/eSUS-AB-PEC-5.4.37-Linux64.jar
Size: 892232957 bytes
SHA-256: 9975a55184a6dd1f66d8a837bbc533376e0400069485e8acb45100c23a535bfb
Source: https://sisaps.saude.gov.br/sistemas/esusaps/blog/versao-5-4-37/
```

The installer was copied to the test VM:

```text
/opt/esus-pec-staging/eSUS-AB-PEC-5.4.37-Linux64.jar
```

VM-side validation matched the same SHA-256 and identified the file as a Java
archive.

## VM Preflight

Installed on VM `102` only:

```text
default-jre-headless
postgresql-client
qemu-guest-agent
file
unzip
procps
```

Validated versions:

```text
Java: OpenJDK 21.0.11
psql: PostgreSQL 17.10
pg_restore: PostgreSQL 17.10
file: 5.46
qemu-guest-agent: active
```

Filesystem and memory:

```text
Root filesystem: ext4, 40G, about 37G available after package installation
Memory: 3.8 GiB total, about 3.5 GiB available
Swap: none
```

## Installer Smoke Test

Manifest:

```text
Main-Class: br.gov.saude.esus.installers.installer.Main
Build-Jdk: 17.0.16
```

Smoke command:

```bash
timeout 45s java -jar eSUS-AB-PEC-5.4.37-Linux64.jar -console </dev/null
```

Result:

```text
The installer started in console/headless path and checked the effective user.
It stopped because it was executed as non-root:
"Esta ferramenta necessita executar com privilégios de administrador."
```

This validates that the `-console` path is available and avoids the previous
DISPLAY/X11 failure mode. The installer was not allowed to proceed with
administrative privileges, so PEC was not installed in this step.

## Secret Handling

No real secrets were created, read, printed, or committed. Required future
secret names are documented in:

- `config/esus-pec.infisical.env.example`
- `docs/credentials/esus-pec-infisical-secrets.html`

## Next Small Step

After confirming whether the test VM may perform a full installer run, execute
the installer as root in VM `102` only, with all generated credentials captured
directly into Infisical and not into repository files.
