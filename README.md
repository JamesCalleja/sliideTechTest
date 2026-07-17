# Sliide Next-Generation Events Pipeline Infrastructure

This repository contains the Infrastructure-as-Code (IaC) configuration for Sliide's next-generation cloud-native events pipeline on AWS. It uses **Terragrunt** to manage environment states and **Terraform** to define modular infrastructure components. 

The design is optimized for cost, scalability (handling 50k to 500k events/sec), and strict network security.

---

## 🏗️ Architecture Design Overview

```
                                  [ 15M - 30M Mobile Clients ]
                                                │
                                     HTTPS POST (JSON, < 1KB)
                                                ▼
                                      [ Amazon API Gateway ]
                                                │
                             Direct Integration (No Lambda in-between)
                                                ▼
                                    [ Amazon Kinesis Stream ]
                                                │
                       ┌────────────────────────┴────────────────────────┐
                       ▼ (Sub-second / Real-time)                         ▼ (Near Real-time / Analytics)
             [ AWS Lambda Consumer ]                              [ Amazon Kinesis Firehose ]
                       │                                                 │
            Updates Personalization Engine                       Parquet + Snappy Partitioned
               (e.g., Redis Cache)                                       │
                                                                         ▼
                                                                  [ Amazon S3 ]
                                                                         │
                                                               Query via Amazon Athena
                                                               Aged out via S3 Lifecycle
```

### Key Technical Optimizations:
1. **Direct API Gateway Integration:** Avoids expensive proxy Lambda functions by mapping HTTP POST payloads directly to the downstream Kinesis stream inside API Gateway.
2. **Kinesis Auto-scaling:** Leverages Application Auto-Scaling policies to dynamically scale Kinesis shards (50 to 600 shards) to handle peak traffic (up to 500,000 events/sec) and control idle costs.
3. **Private Network Isolation:** All backend components (Kinesis, S3, KMS, Lambda, Firehose) are deployed within a private VPC and communicate securely using **VPC Endpoints (PrivateLink)**, avoiding the billing overhead of NAT Gateways.
4. **Analytics Storage (Snappy/Parquet):** Kinesis Firehose performs inline conversion of JSON events to Snappy-compressed Parquet format, saving up to 80% on storage costs and accelerating Amazon Athena analytical queries.
5. **Failover Resilience:** SQS Dead Letter Queues (DLQs) catch Lambda processing failures (poison pills), and Firehose utilizes backup S3 prefixes to capture processing/delivery errors.
6. **Alarms & Alerting:** Automated CloudWatch Alarms notify an SNS topic (subscribable via email or SMS) on stream throttles, execution errors, consumer processing lag (maximum iterator age), S3 delivery failure, or visibility of dead-letter messages.

---

## 📂 Repository Structure

The project conforms to the standard hierarchical Terragrunt environment layout:

```text
sliideTechTest/
├── scripts/
│   ├── bootstrap.sh                    # CloudShell bootstrapping script for vanilla AWS accounts (with scoped IAM policy)
│   └── teardown.sh                     # Teardown script to undo all bootstrap actions
├── README.md                           # This documentation file
├── modules/                            # Modularized, reusable Terraform components (using AWS curated modules)
│   ├── kms/                            # KMS Encryption keys for SSE-KMS
│   ├── vpc/                            # Private VPC & Endpoint definitions (terraform-aws-modules)
│   ├── s3/                             # S3 Events bucket with transition & deletion policies
│   ├── kinesis/                        # Kinesis Stream & auto-scaling policies
│   ├── api-gateway/                    # API Gateway with direct Kinesis proxy integration
│   ├── firehose/                       # Kinesis Data Firehose with Glue Catalog Schema conversion
│   ├── lambda/                         # Sub-second consumer Lambda function & SQS DLQ
│   └── monitoring/                     # CloudWatch Alarms & SNS alerting infrastructure
└── envs/
    ├── root.hcl                        # Global Terragrunt state backend and provider generation
    ├── proposition.hcl                 # Product line/proposition variables
    └── dev/
        ├── environment.hcl             # Environment (dev) configurations
        └── us-east-1/
            ├── region.hcl              # Region-specific CIDR, availability zones, and state bucket parameters
            ├── kms/terragrunt.hcl
            ├── vpc/terragrunt.hcl
            ├── s3/terragrunt.hcl
            ├── kinesis/terragrunt.hcl
            ├── api-gateway/terragrunt.hcl
            ├── firehose/terragrunt.hcl
            ├── lambda/terragrunt.hcl
            └── monitoring/terragrunt.hcl
```

---

## 🚀 Getting Started

### Prerequisites
Before deployment, make sure you have the following installed locally:
- [Terraform](https://developer.hashicorp.com/terraform/downloads) (>= 1.5.0)
- [Terragrunt](https://terragrunt.gruntwork.io/docs/getting-started/quick-start/) (>= 0.50.0)
- [AWS CLI](https://aws.amazon.com/cli/)

---

### Step 1: Bootstrapping a Vanilla AWS Account
If you are deploying to a brand-new or clean AWS Account, you must initialize the remote state bucket and provisioning runner. Since the repository is private, the most frictionless way to do this in **AWS CloudShell** is to paste the script directly:

1. Log in to the **AWS Console** as **root** (or an administrator user).
2. Open **AWS CloudShell** (the terminal icon in the top right header).
3. Create the file and paste the contents of [`scripts/bootstrap.sh`](file:///C:/code/sliideTechTest/scripts/bootstrap.sh):
   ```bash
   cat << 'EOF' > bootstrap.sh
   # (Paste the full contents of scripts/bootstrap.sh here)
   EOF
   ```
4. Run the script:
   ```bash
   bash bootstrap.sh
   ```
5. The script will output the credentials block. Copy the block for your local shell of choice:

   **For Windows PowerShell:**
   ```powershell
   $env:AWS_ACCESS_KEY_ID="AKIA47YBKWVXLNQWGJ2U"
   $env:AWS_SECRET_ACCESS_KEY="kvjc/lyCBFsXlBG2Og5egot3dPGE6deQlIBw/j2i"
   $env:AWS_DEFAULT_REGION="us-east-1"
   ```

   **For Bash (Git Bash / Linux / macOS):**
   ```bash
   export AWS_ACCESS_KEY_ID="AKIA47YBKWVXLNQWGJ2U"
   export AWS_SECRET_ACCESS_KEY="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"
   export AWS_DEFAULT_REGION="us-east-1"
   ```

---

### Step 2: Deploying the Pipeline
Set the environment variables you copied above in your local terminal, then run the deployment commands:

#### Option A: Using Windows PowerShell (Terragrunt < v0.60, e.g., v0.63.6)
1. Paste the `$env:AWS_*` credentials block into your PowerShell window.
2. Navigate to the region directory:
   ```powershell
   cd sliideTechTest
   cd envs/dev/us-east-1
   ```
3. Run a global plan to inspect changes:
   ```powershell
   terragrunt run-all plan
   ```
4. Deploy the entire stack:
   ```powershell
   terragrunt run-all apply
   ```

#### Option B: Using Bash (Git Bash / Linux / macOS) (Terragrunt >= v0.60)
1. Paste the `export AWS_*` credentials block into your Bash window.
2. Navigate to the region directory:
   ```bash
   cd sliideTechTest
   cd envs/dev/us-east-1
   ```
3. Run a global plan to inspect changes:
   ```bash
   terragrunt run -- run-all plan
   ```
4. Deploy the entire stack:
   ```bash
   terragrunt run -- run-all apply
   ```

---

## 📊 Verification and Ingesting Events

Once deployment completes, the `api-gateway` module outputs the `api_url`. You can test ingestion by sending a POST request containing mock JSON data.

### Using Bash (Linux/macOS/Git Bash):
```bash
curl -X POST https://<api-id>.execute-api.us-east-1.amazonaws.com/dev/events \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "user-12345",
    "eventType": "article_view",
    "timestamp": "2026-07-15T17:00:00Z",
    "payload": "{\"articleId\": \"sports-998\", \"durationSec\": 45}"
  }'
```

### Using Windows PowerShell:
In PowerShell, `curl` is aliased to `Invoke-WebRequest` which does not support standard curl flags. Use the native `curl.exe` or `Invoke-RestMethod`:

**Option 1 (Using native `curl.exe`):**
```powershell
curl.exe -X POST https://<api-id>.execute-api.us-east-1.amazonaws.com/dev/events `
  -H "Content-Type: application/json" `
  -d '{\"userId\": \"user-12345\", \"eventType\": \"article_view\", \"timestamp\": \"2026-07-15T17:00:00Z\", \"payload\": \"{\\\"articleId\\\": \\\"sports-998\\\", \\\"durationSec\\\": 45}\"}'
```

**Option 2 (Using native PowerShell `Invoke-RestMethod`):**
```powershell
$body = @{
    userId    = "user-12345"
    eventType = "article_view"
    timestamp = "2026-07-15T17:00:00Z"
    payload   = '{"articleId": "sports-998", "durationSec": 45}'
} | ConvertTo-Json

Invoke-RestMethod -Uri "https://<api-id>.execute-api.us-east-1.amazonaws.com/dev/events" -Method Post -Body $body -ContentType "application/json"
```

*Expected response:*
```json
{
  "status": "success",
  "requestId": "some-aws-request-id"
}
```
You can verify the sub-second path by viewing the CloudWatch logs for the Lambda function, and the analytics path by checking S3 under the partitioned `events/` folder after ~60 seconds.

---

## 🧹 Teardown and Cleanup

To clean up and destroy all resources created during this POC to avoid unwanted AWS charges, run the following commands:

### Step 1: Destroying Terragrunt Infrastructure

#### Option A: If using Windows PowerShell (Terragrunt < v0.60)
```powershell
cd envs/dev/us-east-1
terragrunt run-all destroy
```

#### Option B: If using Bash (Git Bash / Linux / macOS) (Terragrunt >= v0.60)
```bash
cd envs/dev/us-east-1
terragrunt run -- run-all destroy
```

### Step 2: Undoing the Bootstrapper
Once the main infrastructure has been destroyed, log in to the **AWS Console** as **root/admin**, open **AWS CloudShell**, and paste the teardown script:

1. Create the file and paste the contents of [`scripts/teardown.sh`](file:///C:/code/sliideTechTest/scripts/teardown.sh):
   ```bash
   cat << 'EOF' > teardown.sh
   # (Paste the full contents of scripts/teardown.sh here)
   EOF
   ```
2. Run the script:
   ```bash
   bash teardown.sh
   ```


