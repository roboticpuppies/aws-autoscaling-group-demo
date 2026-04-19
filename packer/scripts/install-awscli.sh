#!/bin/bash
set -euo pipefail

echo "=== Installing AWS CLI v2 ==="

apt-get install -y unzip curl

curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install

# Clean up
rm -rf /tmp/awscliv2.zip /tmp/aws

echo "=== AWS CLI installation complete ==="
aws --version
