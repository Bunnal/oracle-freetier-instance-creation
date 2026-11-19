#!/usr/bin/env bash
set -uo pipefail

REQUIRED_VARS=("COMPARTMENT_ID" "IMAGE_ID" "SUBNET_ID" "SSH_KEY")
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "ERROR: Environment variable '$var' is empty or not set."
    exit 1
  fi
done

DISPLAY_NAME="ubuntu-always-free-instance2"

EXISTING_ID=$(oci compute instance list \
  --compartment-id "$COMPARTMENT_ID" \
  --display-name "$DISPLAY_NAME" \
  --query "data[?\"lifecycle-state\"=='RUNNING' || \"lifecycle-state\"=='PROVISIONING'].id | [0]" \
  --raw-output 2>/dev/null)

if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "null" ]; then
  echo "INFO: Instance '$DISPLAY_NAME' already exists ($EXISTING_ID). Skipping creation."
  printf 'Instance ID: %s\nDisplay Name: %s\n' "$EXISTING_ID" "$DISPLAY_NAME" > INSTANCE_CREATED
  exit 0
fi

OCPUS=${OCPUS:-1}
MEMORY_GB=${MEMORY_GB:-6}
BOOT_VOLUME_GB=${BOOT_VOLUME_GB:-100}
SLEEP_SECONDS=${SLEEP_SECONDS:-60}
MAX_ATTEMPTS=${MAX_ATTEMPTS:-12}

SHAPE_CONFIG=$(python3 -c 'import json, os; print(json.dumps({"ocpus": int(os.environ["OCPUS"]), "memory_in_gbs": int(os.environ["MEMORY_GB"])}))')
METADATA=$(python3 -c 'import json, os; print(json.dumps({"ssh_authorized_keys": os.environ["SSH_KEY"]}))')

echo "Starting server provisioning loop via OCI CLI (${OCPUS} OCPU / ${MEMORY_GB} GB RAM / ${BOOT_VOLUME_GB} GB Storage)..."

for ((attempt=1; attempt<=MAX_ATTEMPTS; attempt++)); do
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Attempt $attempt/$MAX_ATTEMPTS: Sending instance creation request..."

  OUTPUT=$(oci compute instance launch \
    --compartment-id "$COMPARTMENT_ID" \
    --availability-domain "PMOM:AP-SINGAPORE-2-AD-1" \
    --shape "VM.Standard.A1.Flex" \
    --shape-config "$SHAPE_CONFIG" \
    --boot-volume-size-in-gbs "$BOOT_VOLUME_GB" \
    --display-name "$DISPLAY_NAME" \
    --image-id "$IMAGE_ID" \
    --subnet-id "$SUBNET_ID" \
    --metadata "$METADATA" \
    --assign-public-ip true 2>&1)

  EXIT_CODE=$?

  if [ $EXIT_CODE -eq 0 ] && echo "$OUTPUT" | grep -q '"lifecycle-state": "PROVISIONING"'; then
    INSTANCE_ID=$(printf '%s' "$OUTPUT" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("id", ""))')
    echo "----------------------------------------------------"
    echo "SUCCESS! Instance is provisioning."
    echo "----------------------------------------------------"
    echo "$OUTPUT"
    {
      printf 'Instance ID: %s\n' "$INSTANCE_ID"
      printf 'Display Name: %s\n' "$DISPLAY_NAME"
      printf 'Shape: VM.Standard.A1.Flex\n'
      printf 'State: PROVISIONING\n'
    } > INSTANCE_CREATED
    exit 0
  fi

  ERROR_CODE=$(echo "$OUTPUT" | grep -o '"code": *"[^"]*"' | head -n 1)
  ERROR_MSG=$(echo "$OUTPUT" | grep -o '"message": *"[^"]*"' | head -n 1)

  if [ -n "$ERROR_CODE" ] || [ -n "$ERROR_MSG" ]; then
    echo "OCI Response: ${ERROR_CODE:-UnknownCode} | ${ERROR_MSG:-NoMessage}"
  else
    echo "OCI Raw Response: $OUTPUT"
  fi

  if echo "$OUTPUT" | grep -qE "NotAuthorizedOrNotFound|InvalidParameter|LimitExceeded"; then
    echo "CRITICAL: Stopping script due to permission, parameter, or quota error."
    exit 1
  fi

  if [ $attempt -lt $MAX_ATTEMPTS ]; then
    echo "Retrying in ${SLEEP_SECONDS} seconds..."
    echo "----------------------------------------------------"
    sleep "$SLEEP_SECONDS"
  fi
done

echo "INFO: Completed $MAX_ATTEMPTS attempts without available capacity. Waiting for next scheduled run."
exit 0
