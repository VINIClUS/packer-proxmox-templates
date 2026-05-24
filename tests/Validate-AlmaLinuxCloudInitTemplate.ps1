$root = Resolve-Path (Join-Path $PSScriptRoot "..")
& (Join-Path $root "tests/Validate-ProxmoxCloudInitTemplate.ps1") `
  -TargetVarsFile (Join-Path $root "linux/almalinux-10-cloudinit/almalinux-10-cloudinit.pkrvars.hcl.example")
