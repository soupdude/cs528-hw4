#!/bin/bash
# Creates both HW4 VMs and starts their programs, in one command.
#   - web server VM: e2-micro, static IP, runs as the server service account,
#     startup script copies service1/ from the bucket and runs it on port 80
#   - Service 2 VM:  e2-micro, runs as the Service 2 service account,
#     its code travels in the VM's metadata (no bucket access needed)
#
# Usage (from anywhere):  ./scripts/deploy.sh
# Override any setting with an environment variable, e.g.
#   PROJECT=my-project BUCKET=my-bucket ZONE=us-central1-a ./scripts/deploy.sh
# Run ./scripts/setup.sh once first.
set -euo pipefail
cd "$(dirname "$0")/.."   # run from the repository root so relative paths work

PROJECT="${PROJECT:-project-f131ec20-0df6-4cfa-bf0}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-b}"
BUCKET="${BUCKET:-cs528-12kfiles-bucket-thomas}"
SERVER_SA="${SERVER_SA:-hw4-sa@${PROJECT}.iam.gserviceaccount.com}"
SERVICE2_SA="${SERVICE2_SA:-hw4-sa2@${PROJECT}.iam.gserviceaccount.com}"
SERVER_VM="${SERVER_VM:-web-server-hw4}"
SERVICE2_VM="${SERVICE2_VM:-hw4-service2}"
IP_NAME="${IP_NAME:-hw4-server-ip}"
MACHINE="${MACHINE:-e2-micro}"
TAG="${TAG:-http-server}"
IMAGE=(--image-family=debian-12 --image-project=debian-cloud)

g() { gcloud --project="$PROJECT" --quiet "$@"; }
vm_exists() { g compute instances describe "$1" --zone="$ZONE" >/dev/null 2>&1; }

echo "== 1/4 Uploading Service 1 code to gs://$BUCKET/hw4-code/service1/"
g storage cp service1/server.py service1/requirements.txt "gs://$BUCKET/hw4-code/service1/"

echo "== 2/4 Static IP '$IP_NAME'"
if ! g compute addresses describe "$IP_NAME" --region="$REGION" >/dev/null 2>&1; then
  g compute addresses create "$IP_NAME" --region="$REGION"
fi
IP=$(g compute addresses describe "$IP_NAME" --region="$REGION" --format='value(address)')
echo "   $IP"

echo "== 3/4 Web server VM '$SERVER_VM'"
if vm_exists "$SERVER_VM"; then
  echo "   already exists, skipping (delete it first to recreate)"
else
  g compute instances create "$SERVER_VM" \
    --zone="$ZONE" --machine-type="$MACHINE" "${IMAGE[@]}" \
    --service-account="$SERVER_SA" --scopes=cloud-platform \
    --tags="$TAG" --address="$IP" \
    --metadata-from-file=startup-script=scripts/startup-server.sh
fi

echo "== 4/4 Service 2 VM '$SERVICE2_VM'"
if vm_exists "$SERVICE2_VM"; then
  echo "   already exists, skipping (delete it first to recreate)"
else
  g compute instances create "$SERVICE2_VM" \
    --zone="$ZONE" --machine-type="$MACHINE" "${IMAGE[@]}" \
    --service-account="$SERVICE2_SA" --scopes=cloud-platform \
    --metadata-from-file=startup-script=scripts/startup-service2.sh,service2-code=service2/main.py,service2-requirements=service2/requirements.txt
fi

cat <<EOF

Done. Both programs start automatically; allow 2-3 minutes for the first boot.

  Web server:  http://$IP/12k-files/5.html
  Server logs: gcloud compute ssh $SERVER_VM --zone=$ZONE --command='sudo journalctl -u hw4-server -n 20'
  Service 2:   gcloud compute ssh $SERVICE2_VM --zone=$ZONE --command='sudo journalctl -u hw4-service2 -f'
EOF
