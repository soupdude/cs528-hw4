#!/bin/bash
# One-time project setup for CS528 HW4. Safe to run more than once.
# Creates (if missing) the APIs, service accounts, least-privilege role grants,
# Pub/Sub topic/subscription and the port-80 firewall rule that deploy.sh relies on.
#
# Usage:  PROJECT=<your-project-id> BUCKET=<your-bucket> ./scripts/setup.sh
# Run it as a user who can manage IAM in the project (e.g. the project Owner).
set -euo pipefail

PROJECT="${PROJECT:-project-f131ec20-0df6-4cfa-bf0}"
BUCKET="${BUCKET:-cs528-12kfiles-bucket-thomas}"
TOPIC="${TOPIC:-forbidden-requests}"
SUBSCRIPTION="${SUBSCRIPTION:-forbidden-sub}"
SERVER_SA_NAME="${SERVER_SA_NAME:-hw4-sa}"
SERVICE2_SA_NAME="${SERVICE2_SA_NAME:-hw4-sa2}"
TAG="${TAG:-http-server}"

SERVER_SA="${SERVER_SA_NAME}@${PROJECT}.iam.gserviceaccount.com"
SERVICE2_SA="${SERVICE2_SA_NAME}@${PROJECT}.iam.gserviceaccount.com"

g() { gcloud --project="$PROJECT" --quiet "$@"; }

echo "== Enabling APIs"
g services enable compute.googleapis.com pubsub.googleapis.com logging.googleapis.com \
  monitoring.googleapis.com storage.googleapis.com iam.googleapis.com

echo "== Service accounts"
created=0
for name in "$SERVER_SA_NAME" "$SERVICE2_SA_NAME"; do
  if g iam service-accounts describe "${name}@${PROJECT}.iam.gserviceaccount.com" >/dev/null 2>&1; then
    echo "   $name exists"
  else
    g iam service-accounts create "$name" --display-name="CS528 HW4 $name"
    created=1
  fi
done
# New service accounts take a few seconds before they can be granted roles.
if [ "$created" = 1 ]; then sleep 15; fi

echo "== Pub/Sub topic and subscription"
g pubsub topics describe "$TOPIC" >/dev/null 2>&1 || g pubsub topics create "$TOPIC"
g pubsub subscriptions describe "$SUBSCRIPTION" >/dev/null 2>&1 \
  || g pubsub subscriptions create "$SUBSCRIPTION" --topic="$TOPIC"

echo "== Roles for the web server account ($SERVER_SA)"
# Read-only access to objects in this one bucket.
g storage buckets add-iam-policy-binding "gs://$BUCKET" \
  --member="serviceAccount:$SERVER_SA" --role=roles/storage.objectViewer >/dev/null
# Publish to this one topic only.
g pubsub topics add-iam-policy-binding "$TOPIC" \
  --member="serviceAccount:$SERVER_SA" --role=roles/pubsub.publisher >/dev/null
# Write logs and metrics (Cloud Logging client and Ops Agent). These roles are project-level.
for role in roles/logging.logWriter roles/monitoring.metricWriter; do
  g projects add-iam-policy-binding "$PROJECT" --condition=None \
    --member="serviceAccount:$SERVER_SA" --role="$role" >/dev/null
done

echo "== Roles for the Service 2 account ($SERVICE2_SA)"
# Pull messages from this one subscription only. Nothing else.
g pubsub subscriptions add-iam-policy-binding "$SUBSCRIPTION" \
  --member="serviceAccount:$SERVICE2_SA" --role=roles/pubsub.subscriber >/dev/null

echo "== Firewall: allow HTTP (port 80) to VMs tagged '$TAG'"
g compute firewall-rules describe hw4-allow-http >/dev/null 2>&1 \
  || g compute firewall-rules create hw4-allow-http --network=default \
       --direction=INGRESS --allow=tcp:80 --source-ranges=0.0.0.0/0 --target-tags="$TAG"

echo "== Setup complete. Next: ./scripts/deploy.sh"
