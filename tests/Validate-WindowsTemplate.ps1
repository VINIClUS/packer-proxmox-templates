Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$templateRoot = Join-Path $root "windows/win11-24h2"
$requiredFiles = @(
    "windows/win11-24h2/windows-11.pkr.hcl",
    "windows/win11-24h2/variables.pkr.hcl",
    "windows/win11-24h2/http/Autounattend.xml.pkrtpl",
    "windows/win11-24h2/http/scripts/Configure-WinRM.ps1",
    "windows/win11-24h2/http/scripts/Install-QemuGuestAgent.ps1",
    "windows/win11-24h2/scripts/Install-VirtIO.ps1",
    "windows/win11-24h2/scripts/Optimize-Template.ps1",
    "windows/win11-24h2/scripts/Sysprep-Template.ps1",
    "config/Proxmox.pkrvars.hcl.example",
    "windows/win11-24h2/windows-11.pkrvars.hcl.example",
    "docs/credentials/windows-template-credentials.html"
)

foreach ($relativePath in $requiredFiles) {
    $path = Join-Path $root $relativePath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing required file: $relativePath"
    }
}

$varsExample = Get-Content -LiteralPath (Join-Path $root "config/Proxmox.pkrvars.hcl.example") -Raw
if ($varsExample -notmatch 'proxmox_url\s*=\s*"https://192\.168\.1\.149:8006/api2/json"') {
    throw "Proxmox example must default to https://192.168.1.149:8006/api2/json"
}
if ($varsExample -notmatch 'proxmox_api_token_secret') {
    throw "Proxmox example must include proxmox_api_token_secret"
}
if ($varsExample -notmatch 'winrm_password') {
    throw "Proxmox example must include winrm_password"
}
if ($varsExample -notmatch 'windows_product_key') {
    throw "Proxmox example must include windows_product_key"
}

$packerFile = Get-Content -LiteralPath (Join-Path $templateRoot "windows-11.pkr.hcl") -Raw
if ($packerFile -notmatch 'source\s+"proxmox-iso"\s+"windows_11"') {
    throw "Packer file must define source proxmox-iso windows_11"
}
if ($packerFile -notmatch 'additional_iso_files') {
    throw "Packer file must attach local answer/scripts ISO"
}
if ($packerFile -notmatch 'http_directory\s*=\s*abspath\("\$\{path\.root\}/http"\)') {
    throw "Packer file must serve the local http directory"
}
if ($packerFile -match 'http_directory\s*=\s*"http"') {
    throw "Packer file must use abspath for http_directory when building from the repository root"
}
if ($packerFile -notmatch 'communicator\s*=\s*"winrm"') {
    throw "Packer file must use WinRM communicator"
}
if ($packerFile -notmatch 'Install-QemuGuestAgent\.ps1') {
    throw "Packer file must include Install-QemuGuestAgent.ps1 on the generated answer ISO"
}
if ($packerFile -notmatch 'scsi_controller\s*=\s*"virtio-scsi-single"') {
    throw "Packer file must use virtio-scsi-single"
}
if ($packerFile -notmatch '(?s)tpm_config\s+\{\s*tpm_storage_pool\s*=\s*var\.proxmox_vm_storage_pool\s*tpm_version\s*=\s*"v2\.0"\s*\}') {
    throw "Packer file must attach a TPM 2.0 device for Windows 11 setup"
}
if ($packerFile -notmatch 'boot\s*=\s*"order=sata0;ide0;scsi0"') {
    throw "Packer file must boot from the Windows ISO before the empty system disk"
}
if ($packerFile -notmatch '<spacebar><wait1s><spacebar>') {
    throw "Packer file must repeat boot keypresses to catch the Windows ISO boot prompt"
}
if ($packerFile -notmatch '(?s)boot_iso\s+\{\s*type\s*=\s*"sata".*?iso_file\s*=\s*var\.windows_iso_file') {
    throw "Packer file must attach Windows install media as SATA so WinPE can read it before VirtIO drivers load"
}
if ($packerFile -notmatch '(?s)additional_iso_files\s+\{\s*type\s*=\s*"sata".*?iso_file\s*=\s*var\.virtio_iso_file') {
    throw "Packer file must attach VirtIO driver media as SATA so Windows Setup can load storage drivers"
}
if ($packerFile -match 'vlan_tag\s*=\s*var\.proxmox_vlan_tag') {
    throw "Packer file must not emit vlan_tag=0 for untagged networks; omit vlan_tag unless tagged networks are explicitly modeled"
}
if ($packerFile -match '=\s*"\$\{path\.root\}/' -or $packerFile -match '\[\s*"\$\{path\.root\}/') {
    throw "Packer file must wrap local path.root references with abspath() for reliable validation/builds"
}

$autounattend = Get-Content -LiteralPath (Join-Path $templateRoot "http/Autounattend.xml.pkrtpl") -Raw
foreach ($needle in @("NonInteractive", "Configure-WinRM.ps1", "Install-QemuGuestAgent.ps1", "AdministratorPassword", "ProductKey")) {
    if ($autounattend -notmatch [regex]::Escape($needle)) {
        throw "Autounattend.xml must contain $needle"
    }
}
$renderedAutounattend = $autounattend
foreach ($placeholder in @(
    "winrm_username",
    "winrm_password",
    "local_admin_full_name",
    "local_admin_description",
    "windows_edition",
    "windows_product_key",
    "timezone",
    "system_locale",
    "input_locale",
    "user_locale",
    "computer_name"
)) {
    $renderedAutounattend = $renderedAutounattend.Replace("`${$placeholder}", "example")
}
[xml]$null = $renderedAutounattend

$powershellFiles = @(
    "windows/win11-24h2/http/scripts/Configure-WinRM.ps1",
    "windows/win11-24h2/http/scripts/Install-QemuGuestAgent.ps1",
    "windows/win11-24h2/scripts/Install-VirtIO.ps1",
    "windows/win11-24h2/scripts/Optimize-Template.ps1",
    "windows/win11-24h2/scripts/Sysprep-Template.ps1"
)
foreach ($relativePath in $powershellFiles) {
    $path = Join-Path $root $relativePath
    $errors = $null
    [System.Management.Automation.PSParser]::Tokenize((Get-Content -LiteralPath $path -Raw), [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        $messages = ($errors | ForEach-Object { $_.Message }) -join "; "
        throw "$relativePath has PowerShell syntax errors: $messages"
    }
}

$winrmScript = Get-Content -LiteralPath (Join-Path $templateRoot "http/scripts/Configure-WinRM.ps1") -Raw
if ($winrmScript -match 'Restart-Service\s+-Name\s+WinRM') {
    throw "Configure-WinRM.ps1 must not restart WinRM during specialize; it can hang setup"
}
if ($winrmScript -match 'Get-NetConnectionProfile|Set-NetConnectionProfile') {
    throw "Configure-WinRM.ps1 must not call network profile cmdlets during specialize; they can hang setup"
}
foreach ($needle in @("NetKVM\w11\amd64\netkvm.inf", "pnputil.exe", "ipconfig.exe /renew")) {
    if ($winrmScript -notmatch [regex]::Escape($needle)) {
        throw "Configure-WinRM.ps1 must install the VirtIO network driver before WinRM: $needle"
    }
}
if ($winrmScript -match 'qemu-ga-x86_64\.msi|msiexec\.exe') {
    throw "Configure-WinRM.ps1 must not install QEMU Guest Agent during specialize; MSI install can hang setup"
}

$qemuScript = Get-Content -LiteralPath (Join-Path $templateRoot "http/scripts/Install-QemuGuestAgent.ps1") -Raw
foreach ($needle in @("Set-NetConnectionProfile", "Enable-PSRemoting", "SkipNetworkProfileCheck", "LocalAccountTokenFilterPolicy", "AllowUnencrypted", "vioserial\w11\amd64\vioser.inf", "pnputil.exe", "guest-agent\qemu-ga-x86_64.msi", "msiexec.exe", "QEMU-GA")) {
    if ($qemuScript -notmatch [regex]::Escape($needle)) {
        throw "Install-QemuGuestAgent.ps1 must install VirtIO serial and start QEMU Guest Agent: $needle"
    }
}

$credentialDoc = Get-Content -LiteralPath (Join-Path $root "docs/credentials/windows-template-credentials.html") -Raw
foreach ($needle in @("Proxmox API token", "WinRM Administrator password", "Windows setup product key", "QEMU Guest Agent", "VM.GuestAgent.Audit", "VM.GuestAgent.Unrestricted", "192.168.1.149:8006")) {
    if ($credentialDoc -notmatch [regex]::Escape($needle)) {
        throw "Credential documentation must mention $needle"
    }
}

Write-Host "Windows template structure validated."
