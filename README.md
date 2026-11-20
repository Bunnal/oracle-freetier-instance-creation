# Oracle Free Tier Instance Creation (GitHub Actions)

Automate Oracle Cloud Free Tier instance creation using GitHub Actions with a **self-hosted runner**. The OCI CLI script retries creating an ARM instance (1 OCPU, 6 GB RAM) until capacity becomes available.

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│  GitHub Actions (cron every 20 min)                     │
│                                                         │
│  1. Checkout repo                                       │
│  2. Write OCI API config and PEM key to ~/.oci          │
│  3. Run launch-oci.sh for up to ~12 minutes            │
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

Create these secrets:

| Secret | Description |
|---|---|
| `OCI_TENANCY` | Tenancy OCID |
| `OCI_USER` | OCI API user OCID |
| `OCI_FINGERPRINT` | OCI API key fingerprint |
| `OCI_PRIVATE_KEY` | Full OCI API private key PEM |
| `COMPARTMENT_ID` | Compartment OCID |
| `SUBNET_ID` | Target subnet OCID |
| `IMAGE_ID` | Ubuntu image OCID |
| `SSH_KEY` | SSH public key |

Example private key secret:
```
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBg...
...
-----END PRIVATE KEY-----
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

**Option B — Manual trigger:** Go to **Actions** → **OCI Always Free Provisioning** → **Run workflow**.

## Monitoring

- **Live logs:** Actions tab → click on a running workflow → view step output
- **Artifacts:** Successful runs upload `INSTANCE_CREATED` (retained for 7 days)
- **Instance created?** Check for the `INSTANCE_CREATED` file in the workflow artifacts

## Stopping the Workflow

Once your instance is created:

1. Go to **Settings** → **Secrets and variables** → **Actions** → **Variables**
2. Edit `INSTANCE_CREATED` and set it to `true`
3. All future cron runs will be skipped automatically

## Script Configuration

The shell script requires `COMPARTMENT_ID`, `IMAGE_ID`, `SUBNET_ID`, and `SSH_KEY`.

Optional environment variables control retry and resource settings:

| Variable | Default | Description |
|---|---|---|
| `OCPUS` | `1` | Flexible ARM OCPU count |
| `MEMORY_GB` | `6` | Flexible ARM memory in GB |
| `BOOT_VOLUME_GB` | `100` | Boot volume size in GB |
| `AVAILABILITY_DOMAIN` | Auto-discovered | Optional repository variable with the exact OCI availability-domain name |
| `SLEEP_SECONDS` | `30` | Seconds between retries |
| `MAX_ATTEMPTS` | `8` | Maximum attempts per run |
| `REQUEST_TIMEOUT_SECONDS` | `45` | Maximum seconds for one OCI launch request |

## Local Development

You can still run the script locally without GitHub Actions:

```bash
# Configure ~/.oci/config and install OCI CLI
python3 -m pip install --user oci-cli

export COMPARTMENT_ID="ocid1.compartment..."
export IMAGE_ID="ocid1.image..."
export SUBNET_ID="ocid1.subnet..."
export SSH_KEY="$(cat ~/.ssh/id_rsa.pub)"

chmod +x launch-oci.sh
./launch-oci.sh
```

## Credits

- [mohankumarpaluru](https://github.com/mohankumarpaluru/oracle-freetier-instance-creation) — Original project
- [Oracle Launch Instance API](https://docs.oracle.com/en-us/iaas/api/#/en/iaas/20160918/Instance/LaunchInstance)
- [LaunchInstanceDetails](https://docs.oracle.com/en-us/iaas/api/#/en/iaas/20160918/datatypes/LaunchInstanceDetails)

## License

[MIT](LICENSE)
