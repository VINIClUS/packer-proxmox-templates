#!/usr/bin/env bash
set -euo pipefail

installer_path="${1:-/opt/esus-pec-staging/eSUS-AB-PEC-5.4.37-Linux64.jar}"
install_log="${2:-/root/esus-pec-install-console.log}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root inside the target LXC container." >&2
  exit 1
fi

if [[ ! -f "$installer_path" ]]; then
  echo "Installer not found: $installer_path" >&2
  exit 1
fi

# The installer help exposes -console -continue for non-interactive execution.
# Force pt_BR.UTF-8 so the bundled PostgreSQL cluster initializes correctly.
cd "$(dirname "$installer_path")"
env LANG=pt_BR.UTF-8 LC_ALL=pt_BR.UTF-8 \
  java -jar "$(basename "$installer_path")" -console -continue > "$install_log" 2>&1
