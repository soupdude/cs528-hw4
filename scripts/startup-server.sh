#!/bin/bash
# Startup script for the Service 1 web server VM.
# Compute Engine runs this as root on every boot. It:
#   1. installs Python's venv tool
#   2. copies the server code from the bucket
#   3. installs the Python libraries into a venv
#   4. runs server.py on port 80 as a systemd service (restarts on crash, starts on reboot)
set -euo pipefail

CODE_SRC="gs://cs528-12kfiles-bucket-thomas/hw4-code/service1"
APP_DIR="/opt/hw4/service1"
VENV="/opt/hw4/venv"

echo "[startup] installing system packages"
# Other installers (e.g. the Ops Agent) may be using apt at boot.
# Wait up to 10 minutes for the package lock instead of failing.
APT="apt-get -o DPkg::Lock::Timeout=600"
$APT update -y
DEBIAN_FRONTEND=noninteractive $APT install -y python3-venv

echo "[startup] copying code from $CODE_SRC"
mkdir -p "$APP_DIR"
gcloud storage cp "$CODE_SRC/server.py" "$CODE_SRC/requirements.txt" "$APP_DIR/"

echo "[startup] installing Python libraries"
if [ ! -d "$VENV" ]; then
  python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet -r "$APP_DIR/requirements.txt"

echo "[startup] writing systemd service"
cat > /etc/systemd/system/hw4-server.service <<EOF
[Unit]
Description=CS528 HW4 Service 1 web server
After=network-online.target
Wants=network-online.target

[Service]
Environment=PORT=80
Environment=PYTHONUNBUFFERED=1
WorkingDirectory=$APP_DIR
ExecStart=$VENV/bin/python $APP_DIR/server.py
Restart=always
RestartSec=3
# Run as a throwaway unprivileged user, with only the right to bind port 80.
DynamicUser=yes
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hw4-server
systemctl restart hw4-server   # restart (not start) so a reboot picks up new code

echo "[startup] done"
