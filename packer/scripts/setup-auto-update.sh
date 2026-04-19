#!/bin/bash
set -euo pipefail

echo "=== Configuring automatic OS updates at midnight UTC+7 (17:00 UTC) ==="

apt-get install -y unattended-upgrades

# Enable automatic updates
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

# Override apt-daily.timer to run package list update at 16:50 UTC
mkdir -p /etc/systemd/system/apt-daily.timer.d
cat > /etc/systemd/system/apt-daily.timer.d/override.conf << 'EOF'
[Timer]
OnCalendar=
OnCalendar=*-*-* 16:50:00
RandomizedDelaySec=0
EOF

# Override apt-daily-upgrade.timer to run upgrades at 17:00 UTC (midnight UTC+7)
mkdir -p /etc/systemd/system/apt-daily-upgrade.timer.d
cat > /etc/systemd/system/apt-daily-upgrade.timer.d/override.conf << 'EOF'
[Timer]
OnCalendar=
OnCalendar=*-*-* 17:00:00
RandomizedDelaySec=0
EOF

systemctl daemon-reload

echo "=== Automatic OS update configuration complete ==="
