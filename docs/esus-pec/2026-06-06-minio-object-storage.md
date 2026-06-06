# e-SUS PEC MinIO Object Storage

## Scope

Implemented a dedicated MinIO object-storage LXC for e-SUS PEC backups. The container was created on Proxmox `192.168.1.149`, storage `rpool`, without changing VM `101` or CT `100`.

## Container

```text
ctid=134
hostname=esus-pec-minio
ip=192.168.1.210/24
gateway=192.168.1.1
bridge=vmbr0
storage=rpool
rootfs=rpool:64G
memory=2048M
cores=2
swap=512M
template=debian-13-standard_13.1-2_amd64.tar.zst
onboot=1
unprivileged=1
```

The ZFS dataset is `rpool/subvol-134-disk-0`. After upload, observed usage was about `1.84G`.

## MinIO Configuration

MinIO runs as `minio-user` through systemd and stores data under `/var/lib/minio/data`.

```text
api_url=https://192.168.1.210:9000
console_url=https://192.168.1.210:9001
bucket=esus-pec-backups
tls=MinIO native self-signed certificate
object_lock=enabled at bucket creation
versioning=enabled
```

Installed binaries:

```text
minio version RELEASE.2025-09-07T16-13-09Z
mc version RELEASE.2025-08-13T08-35-41Z
```

## Infisical Variables

Secrets and metadata were stored in project `esus-pec`, environment `dev`, path `/test`, using the prefix `ESUS_PEC_OBJECT_STORAGE_*`. The attempted `/test/ObjectStorage` folder is empty and unused because the active token policy did not allow secret creation in that subpath.

Credential variables:

- `ESUS_PEC_OBJECT_STORAGE_ROOT_USER`
- `ESUS_PEC_OBJECT_STORAGE_ROOT_PASSWORD`
- `ESUS_PEC_OBJECT_STORAGE_BACKUP_ACCESS_KEY`
- `ESUS_PEC_OBJECT_STORAGE_BACKUP_SECRET_KEY`
- `ESUS_PEC_OBJECT_STORAGE_TLS_PRIVATE_KEY_PEM`

Metadata variables include endpoint URLs, bucket name, TLS certificate metadata, MinIO/mc versions, backup object key, backup SHA-256, size, and upload timestamp. No secret values are stored in Git or documentation.

## Backup Migration

Source file:

```text
20260519192557-esus-postgres.backup
size_bytes=1529766316
sha256=A388D0769B5B0907652E3DC325E5FEFD7782A4D8206B070AA8CFF31E5DF3918C
```

Object destination:

```text
bucket=esus-pec-backups
object_key=postgres/2026/05/20260519192557-esus-postgres.backup
```

The object was uploaded through the S3 API with the backup access key, read back through `mc cat`, and verified against the local SHA-256. After checksum and size validation passed, the local workspace copy was removed.

## Validation Evidence

```text
minio_service=active
https_health=https://192.168.1.210:9000/minio/health/ready -> HTTP 200
plain_http_health=http://192.168.1.210:9000/minio/health/ready -> HTTP 400
bucket_version_listing=object present with version id
local_backup_present=false
object_sha256_matches_source=true
object_size_matches_source=true
object_storage_secret_count=26
```

## Runbooks

Provision or repair the container:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/esus-pec/Provision-EsusPecMinioObjectStorage.ps1
```

Upload and move a verified backup:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/esus-pec/Upload-EsusPecBackupToMinio.ps1 -BackupFile .\20260519192557-esus-postgres.backup -RemoveLocalAfterValidation
```

Quick health check:

```powershell
rtk curl.exe -k -sS -o NUL -w "minio_api=%{http_code}`n" https://192.168.1.210:9000/minio/health/ready
```

## Notes

This is a single-node single-disk MinIO deployment suitable for local backup staging and S3-compatible automation. It is not a high-availability object-storage cluster. For production, add remote replication, external monitoring, and a CA-issued certificate or trusted internal CA.
