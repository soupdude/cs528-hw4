#!/bin/bash
# Startup script for the Service 2 (forbidden-request reporter) VM.
# Compute Engine runs this as root on every boot. It:
#   1. installs Python's venv tool
#   2. reads main.py and requirements.txt from this VM's metadata
#      (attached by the deploy script, so this VM needs no bucket or GitHub access)
#   3. installs the Python libraries into a venv
#   4. runs main.py as a systemd service (restarts on crash, starts on reboot)
set -euo pipefail

APP_DIR="/opt/hw4/service2"
VENV="/opt/hw4/venv"
MD="http://metadata.google.internal/computeMetadata/v1/instance/attributes"

echo "[startup] installing system packages"
# Other installers (e.g. the Ops Agent) may be using apt at boot.
# Wait up to 10 minutes for the package lock instead of failing.
APT="apt-get -o DPkg::Lock::Timeout=600"
$APT update -y
DEBIAN_FRONTEND=noninteractive $APT install -y python3-venv

echo "[startup] reading code from instance metadata"
mkdir -p "$APP_DIR"
curl -sf -H "Metadata-Flavor: Google" "$MD/service2-code"         -o "$APP_DIR/main.py"
curl -sf -H "Metadata-Flavor: Google" "$MD/service2-requirements" -o "$APP_DIR/requirements.txt"

echo "[startup] installing Python libraries"
if [ ! -d "$VENV" ]; then
  python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet -r "$APP_DIR/requirements.txt"

echo "[startup] writing systemd service"
cat > /etc/systemd/system/hw4-service2.service <<EOF
[Unit]
Description=CS528 HW4 Service 2 forbidden-request reporter
After=network-online.target
Wants=network-online.target

[Service]
Environment=PYTHONUNBUFFERED=1
WorkingDirectory=$APP_DIR
ExecStart=$VENV/bin/python $APP_DIR/main.py
Restart=always
RestartSec=3
# Run as a throwaway unprivileged user; it only needs outbound network access.
DynamicUser=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hw4-service2
systemctl restart hw4-service2   # restart (not start) so a reboot picks up new code

echo "[startup] done"
