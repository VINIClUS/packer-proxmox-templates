$root = Resolve-Path (Join-Path $PSScriptRoot "..")
& (Join-Path $root "tests/Test-CloudInitTemplateScripts.ps1")
