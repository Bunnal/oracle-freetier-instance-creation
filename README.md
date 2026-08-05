# Oracle Free Tier Instance Creation (GitHub Actions)

Automate Oracle Cloud Free Tier instance creation using GitHub Actions with a **self-hosted runner**. The script retries creating an ARM (2 OCPU, 12 GB RAM) or AMD Micro (1 OCPU, 1 GB RAM) instance every 60 seconds until capacity becomes available.

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│  GitHub Actions (cron every 15 min)                     │
│                                                         │
│  1. Checkout repo                                       │
│  2. Write secrets → oci_config, oci.env, PEM key        │
│  3. Run main.py for ~13 minutes                         │
│  4. Instance created? → Stop. Not yet? → Exit cleanly.  │
│  5. Upload logs as artifacts                            │
│  6. Cleanup sensitive files                             │
│                                                         │
│  Next cron trigger repeats the cycle.                   │
└─────────────────────────────────────────────────────────┘
```

## Prerequisites

- **Oracle Cloud account** with Free Tier eligibility
- **OCI API Key** — follow the [Oracle API Key Generation guide](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm) to create one
- **A server** (Linux/macOS) to run the self-hosted GitHub Actions runner
- **Existing subnet** — either from a running Micro instance or create one in the OCI console

## Setup

### 1. Fork / Clone This Repo

```bash
git clone https://github.com/Bunnal/oracle-freetier-instance-creation.git
cd oracle-freetier-instance-creation
```

### 2. Create GitHub Secrets

Go to your repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.

Create these **3 secrets**:

#### `OCI_CONFIG_CONTENT`

The full content of your OCI config file. **Set `key_file` to the relative path** `oci_api_private_key.pem`:

```ini
[DEFAULT]
user=ocid1.user.oc1..aaaaaaaXXXXXXXXX
fingerprint=xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx
tenancy=ocid1.tenancy.oc1..aaaaaaaXXXXXXXXX
region=us-ashburn-1
key_file=oci_api_private_key.pem
```

#### `OCI_API_PRIVATE_KEY`

The full content of your OCI API private key PEM file:

```
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBg...
...
-----END PRIVATE KEY-----
```

#### `OCI_ENV_CONTENT`

The full content of the `oci.env` configuration. Customize these values for your setup:

```bash
# OCI Configuration
OCI_CONFIG=oci_config
OCT_FREE_AD=AD-1
DISPLAY_NAME=my-free-instance
OCI_COMPUTE_SHAPE=VM.Standard.A1.Flex
SECOND_MICRO_INSTANCE=False
REQUEST_WAIT_TIME_SECS=60
SSH_AUTHORIZED_KEYS_FILE=id_rsa.pub

# Leave empty to auto-detect
OCI_SUBNET_ID=
OCI_IMAGE_ID=

# OS selection (ignored if OCI_IMAGE_ID is set)
OPERATING_SYSTEM=Canonical Ubuntu
OS_VERSION=22.04

# Network
ASSIGN_PUBLIC_IP=false
BOOT_VOLUME_SIZE=50

# Gmail notification (optional)
NOTIFY_EMAIL=False
EMAIL=
EMAIL_PASSWORD=

# Discord notification (optional)
DISCORD_WEBHOOK=
```

### 3. Create GitHub Variable

Go to **Settings** → **Secrets and variables** → **Actions** → **Variables** tab → **New repository variable**.

| Name | Value |
|---|---|
| `INSTANCE_CREATED` | `false` |

> Set this to `true` after your instance is created to stop the cron schedule.

### 4. Set Up Self-Hosted Runner

Go to **Settings** → **Actions** → **Runners** → **New self-hosted runner**.

On your server, run the commands GitHub provides:

```bash
# GitHub will show the exact download URL and token for your repo.
# Copy and run those commands on your server. Then:

# Install as a service so it runs on boot
sudo ./svc.sh install
sudo ./svc.sh start
```

> **Tip:** Use `--labels self-hosted` during configuration. The workflow targets the `self-hosted` label.

### 5. Trigger the Workflow

**Option A — Wait for cron:** The workflow runs automatically every 15 minutes.

**Option B — Manual trigger:** Go to **Actions** → **OCI Free Tier Instance Creation** → **Run workflow**.

## Monitoring

- **Live logs:** Actions tab → click on a running workflow → view step output
- **Artifacts:** Each run uploads logs (retained for 7 days)
- **Instance created?** Check for the `INSTANCE_CREATED` file in the workflow artifacts

## Stopping the Workflow

Once your instance is created:

1. Go to **Settings** → **Secrets and variables** → **Actions** → **Variables**
2. Edit `INSTANCE_CREATED` and set it to `true`
3. All future cron runs will be skipped automatically

## Environment Variables Reference

| Variable | Required | Default | Description |
|---|---|---|---|
| `OCI_CONFIG` | Yes | — | Path to OCI config file |
| `OCT_FREE_AD` | Yes | — | Availability Domain (e.g., `AD-1`). Comma-separated for multiple |
| `DISPLAY_NAME` | No | — | Instance display name |
| `OCI_COMPUTE_SHAPE` | No | `VM.Standard.A1.Flex` | `VM.Standard.A1.Flex` or `VM.Standard.E2.1.Micro` |
| `SECOND_MICRO_INSTANCE` | No | `False` | Set `True` for second Micro instance |
| `REQUEST_WAIT_TIME_SECS` | No | `60` | Seconds between retry attempts (default: 60) |
| `SSH_AUTHORIZED_KEYS_FILE` | No | — | Path to SSH public key (auto-generated if missing) |
| `OCI_SUBNET_ID` | No | — | Subnet OCID (auto-detected if empty) |
| `OCI_IMAGE_ID` | No | — | Image OCID (auto-detected from OS/version if empty) |
| `OPERATING_SYSTEM` | No | — | OS name (e.g., `Canonical Ubuntu`) |
| `OS_VERSION` | No | — | OS version (e.g., `22.04`) |
| `ASSIGN_PUBLIC_IP` | No | `false` | Auto-assign ephemeral public IP |
| `BOOT_VOLUME_SIZE` | No | `50` | Boot volume size in GB (minimum 50) |
| `NOTIFY_EMAIL` | No | `False` | Enable Gmail notifications |
| `EMAIL` | No | — | Gmail address (sender = recipient) |
| `EMAIL_PASSWORD` | No | — | Gmail app password |
| `DISCORD_WEBHOOK` | No | — | Discord webhook URL |
| `MAX_RUNTIME_SECS` | No | `780` (Actions) / `0` (Local) | Max script runtime in seconds (0 = unlimited) |

## Local Development

You can still run the script locally without GitHub Actions:

```bash
# Create and configure oci.env and oci_config files locally
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python main.py
```

When running locally, `MAX_RUNTIME_SECS` defaults to `0` (no time limit), so the script loops indefinitely until the instance is created.

## Credits

- [mohankumarpaluru](https://github.com/mohankumarpaluru/oracle-freetier-instance-creation) — Original project
- [Oracle Launch Instance API](https://docs.oracle.com/en-us/iaas/api/#/en/iaas/20160918/Instance/LaunchInstance)
- [LaunchInstanceDetails](https://docs.oracle.com/en-us/iaas/api/#/en/iaas/20160918/datatypes/LaunchInstanceDetails)

## License

[MIT](LICENSE)
