# e-SUS PEC 5.4.37 LXC CT 133 Installation

## Scope

Validated e-SUS PEC 5.4.37 in a new Proxmox LXC container without modifying VM `101 ESUS-TESTE` or CT `100 Netbird`.

- Proxmox: `pve-manager/9.1.1/42db4a6cf33dac83`, kernel `6.17.2-1-pve`
- Final CTID: `133`
- Hostname: `esus-pec-lxc-5437`
- IP: `192.168.1.209/24`
- Template: `local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst`
- LXC mode: unprivileged, `nesting=1,keyctl=1`
- Resources: `2` cores, `6144 MB` RAM, `1024 MB` swap, `40G` rootfs

## Implementation

Create the CT from the Debian 13 standard template:

```bash
pct create 133 local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst \
  --hostname esus-pec-lxc-5437 \
  --rootfs local-lvm:40 \
  --cores 2 --memory 6144 --swap 1024 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.1.209/24,gw=192.168.1.1,firewall=1 \
  --unprivileged 1 --features nesting=1,keyctl=1 --ostype debian --onboot 0
```

Bootstrap was run with `scripts/esus-pec/bootstrap-lxc.sh`. It installs only `default-jre-headless` and `locales`, generates `pt_BR.UTF-8` and `en_US.UTF-8`, and writes:

```ini
[Login]
RemoveIPC=no
```

to `/etc/systemd/logind.conf.d/99-esus-pec-postgresql.conf`.

The installer was copied to `/opt/esus-pec-staging/eSUS-AB-PEC-5.4.37-Linux64.jar` and validated with SHA-256:

```text
9975a55184a6dd1f66d8a837bbc533376e0400069485e8acb45100c23a535bfb
```

Installation was run with:

```bash
/root/esus-pec-install-lxc.sh
```

The script executes `java -jar eSUS-AB-PEC-5.4.37-Linux64.jar -console -continue` with `LANG=pt_BR.UTF-8`.

## Root Cause Found

The first LXC probes failed at database migration with:

```text
FATAL: semctl(46, 3, SETVAL, 0) failed: Argumento invalido
Falha ao migrar o Banco de Dados.
```

The installer creates `postgres` as UID `1000`, not a system user. With systemd-logind default `RemoveIPC=yes`, PostgreSQL 9.6 SysV semaphores can be removed during installer session transitions. Setting `RemoveIPC=no` before the first run fixed the migration in an unprivileged CT.

Reference: PostgreSQL documents the `RemoveIPC` risk for SysV semaphore cleanup under systemd and recommends `RemoveIPC=no` for PostgreSQL hosts: <https://wiki.postgresql.org/wiki/Systemd#RemoveIPC>.

## Validation Evidence

- `e-SUS-AB-PostgreSQL.service`: `active`
- `e-SUS-PEC.service`: `active`
- Bundled PostgreSQL: `127.0.0.1:5433`
- PEC HTTP: `0.0.0.0:8080`
- External HTTP check: `http://192.168.1.209:8080/ -> HTTP 200`
- Credential file: `/opt/e-SUS/webserver/config/credenciais.txt`
- Credential file owner/mode: `root:root`, `Mode: 600`
- No external PostgreSQL client/server package was installed; `/usr/bin/psql` and `/usr/bin/pg_restore` were absent before installation.

## Security And Credentials

Do not print or commit `credenciais.txt`. Read it only directly on CT `133` for Infisical entry under `/esus-pec/test-lxc`.

Required source path:

```text
/opt/e-SUS/webserver/config/credenciais.txt
```

## Cleanup And Rollback

Failed probe CTs `130`, `131`, and `132` were destroyed after evidence collection. To remove the validated LXC test container:

```bash
pct stop 133
pct destroy 133 --purge
```

Keep VM `101 ESUS-TESTE` read-only unless a future instruction explicitly changes that constraint.
