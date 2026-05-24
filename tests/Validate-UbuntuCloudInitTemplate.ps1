$root = Resolve-Path (Join-Path $PSScriptRoot "..")
& (Join-Path $root "tests/Validate-ProxmoxCloudInitTemplate.ps1") `
  -TargetVarsFile (Join-Path $root "linux/ubuntu-26.04-cloudinit/ubuntu-26.04-cloudinit.pkrvars.hcl.example")
