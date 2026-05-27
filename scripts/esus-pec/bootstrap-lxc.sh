#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Keep the base container minimal: Java for the installer and locales for
# PostgreSQL/e-SUS runtime validation.
apt-get update
apt-get install -y --no-install-recommends default-jre-headless locales

for locale_name in pt_BR.UTF-8 en_US.UTF-8; do
  if ! grep -q "^${locale_name} UTF-8" /etc/locale.gen; then
    if grep -q "^# *${locale_name} UTF-8" /etc/locale.gen; then
      sed -i "s/^# *${locale_name} UTF-8/${locale_name} UTF-8/" /etc/locale.gen
    else
      echo "${locale_name} UTF-8" >> /etc/locale.gen
    fi
  fi
done

locale-gen pt_BR.UTF-8 en_US.UTF-8
update-locale LANG=pt_BR.UTF-8

# The PEC installer creates a postgres user with UID 1000. Keep systemd-logind
# from removing PostgreSQL SysV IPC semaphores during installer user-session
# transitions.
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/99-esus-pec-postgresql.conf <<'CONF'
[Login]
RemoveIPC=no
CONF
systemctl restart systemd-logind.service 2>/dev/null || true

java -version
locale -a | grep -Ei '^(pt_BR|en_US)\.utf8$'
