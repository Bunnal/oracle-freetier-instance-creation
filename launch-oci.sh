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

echo "INFO: Checking OCI launch resources..."

COMPARTMENT_EXISTS=$(oci iam compartment get \
  --compartment-id "$COMPARTMENT_ID" \
  --query "data.id" \
  --raw-output 2>/dev/null)

if [ -z "$COMPARTMENT_EXISTS" ] || [ "$COMPARTMENT_EXISTS" = "null" ]; then
  echo "ERROR: COMPARTMENT_ID is missing, inaccessible, or does not belong to this OCI tenancy."
  exit 1
fi

SUBNET_EXISTS=$(oci network subnet get \
  --subnet-id "$SUBNET_ID" \
  --query "data.id" \
  --raw-output 2>/dev/null)

if [ -z "$SUBNET_EXISTS" ] || [ "$SUBNET_EXISTS" = "null" ]; then
  echo "ERROR: SUBNET_ID is missing, inaccessible, or not available in ap-singapore-2."
  exit 1
fi

IMAGE_EXISTS=$(oci compute image get \
  --image-id "$IMAGE_ID" \
  --query "data.id" \
  --raw-output 2>/dev/null)

if [ -z "$IMAGE_EXISTS" ] || [ "$IMAGE_EXISTS" = "null" ]; then
  echo "ERROR: IMAGE_ID is missing, inaccessible, or not available in ap-singapore-2."
  exit 1
fi

echo "INFO: Compartment, subnet, and image resources are accessible."

OCPUS=${OCPUS:-1}
MEMORY_GB=${MEMORY_GB:-6}
BOOT_VOLUME_GB=${BOOT_VOLUME_GB:-100}
SLEEP_SECONDS=${SLEEP_SECONDS:-30}
MAX_ATTEMPTS=${MAX_ATTEMPTS:-8}
REQUEST_TIMEOUT_SECONDS=${REQUEST_TIMEOUT_SECONDS:-45}

if [ -n "${AVAILABILITY_DOMAIN:-}" ]; then
  AVAILABILITY_DOMAIN="$AVAILABILITY_DOMAIN"
else
  AVAILABILITY_DOMAIN=$(oci iam availability-domain list \
    --compartment-id "$COMPARTMENT_ID" \
    --query "data[0].name" \
    --raw-output 2>/dev/null)
  AD_EXIT_CODE=$?

  if [ $AD_EXIT_CODE -ne 0 ] || [ -z "$AVAILABILITY_DOMAIN" ] || [ "$AVAILABILITY_DOMAIN" = "null" ]; then
    echo "ERROR: Could not discover an availability domain in the OCI region."
    echo "OCI Response: $AVAILABILITY_DOMAIN"
    exit 1
  fi
fi

echo "INFO: Using availability domain '$AVAILABILITY_DOMAIN'."

SHAPE_CONFIG=$(python3 -c 'import json, os; print(json.dumps({"ocpus": int(os.environ["OCPUS"]), "memory_in_gbs": int(os.environ["MEMORY_GB"])}))')

SSH_KEY_FILE=$(mktemp)
trap 'rm -f "$SSH_KEY_FILE"' EXIT
printf '%s' "$SSH_KEY" | sed 's/\\n/\n/g' > "$SSH_KEY_FILE"

if ! grep -Eq '^(ssh-(rsa|ed25519)|ecdsa-[a-z0-9-]+) ' "$SSH_KEY_FILE"; then
  echo "ERROR: SSH_KEY must contain an SSH public key, not a private key or plain text."
  exit 1
fi

echo "Starting server provisioning loop via OCI CLI (${OCPUS} OCPU / ${MEMORY_GB} GB RAM / ${BOOT_VOLUME_GB} GB Storage)..."

for ((attempt=1; attempt<=MAX_ATTEMPTS; attempt++)); do
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Attempt $attempt/$MAX_ATTEMPTS: Sending instance creation request..."

  OUTPUT=$(timeout --foreground "${REQUEST_TIMEOUT_SECONDS}s" oci compute instance launch \
    --compartment-id "$COMPARTMENT_ID" \
    --availability-domain "$AVAILABILITY_DOMAIN" \
    --shape "VM.Standard.A1.Flex" \
    --shape-config "$SHAPE_CONFIG" \
    --boot-volume-size-in-gbs "$BOOT_VOLUME_GB" \
    --display-name "$DISPLAY_NAME" \
    --image-id "$IMAGE_ID" \
    --subnet-id "$SUBNET_ID" \
    --ssh-authorized-keys-file "$SSH_KEY_FILE" \
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

  if [ $EXIT_CODE -eq 124 ]; then
    echo "OCI Request timed out after ${REQUEST_TIMEOUT_SECONDS} seconds."
  else
    ERROR_CODE=$(echo "$OUTPUT" | grep -o '"code": *"[^"]*"' | head -n 1)
    ERROR_MSG=$(echo "$OUTPUT" | grep -o '"message": *"[^"]*"' | head -n 1)

    if [ -n "$ERROR_CODE" ] || [ -n "$ERROR_MSG" ]; then
      echo "OCI Response: ${ERROR_CODE:-UnknownCode} | ${ERROR_MSG:-NoMessage}"
      if echo "$OUTPUT" | grep -q '"code": *"CannotParseRequest"'; then
        echo "OCI Raw Response: $OUTPUT"
      fi
    else
      echo "OCI Raw Response: $OUTPUT"
    fi
  fi

  if echo "$OUTPUT" | grep -qE "NotAuthorizedOrNotFound|CannotParseRequest|InvalidParameter|LimitExceeded"; then
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
