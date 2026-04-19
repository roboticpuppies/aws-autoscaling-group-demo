#!/bin/bash
set -euo pipefail

echo "=== Installing node_exporter ==="

# Fetch latest release version from GitHub API
LATEST_VERSION=$(curl -fsSL https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
echo "Latest node_exporter version: ${LATEST_VERSION}"

# Download and extract
cd /tmp
curl -fsSL "https://github.com/prometheus/node_exporter/releases/download/v${LATEST_VERSION}/node_exporter-${LATEST_VERSION}.linux-amd64.tar.gz" -o node_exporter.tar.gz
tar xzf node_exporter.tar.gz
mv "node_exporter-${LATEST_VERSION}.linux-amd64/node_exporter" /usr/local/bin/node_exporter
chmod +x /usr/local/bin/node_exporter

# Clean up
rm -rf /tmp/node_exporter*

# Create system user
useradd --no-create-home --shell /bin/false node_exporter

# Create systemd service
cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable node_exporter

echo "=== node_exporter installation complete ==="
node_exporter --version
