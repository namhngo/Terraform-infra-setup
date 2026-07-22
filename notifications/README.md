# Notification System — Terraform Infrastructure

Terraform configuration for an asynchronous notification system built on SQS + Lambda + SES.

---

## Architecture

```
                           ┌─────────────────────────────────────────────────────────────────────────┐
                           │                              AWS                                         │
                           │                                                                         │
  ┌───────────────┐ publish│   ┌──────────┐   trigger   ┌────────────┐   send email   ┌───────────┐  │
  │               │────────┼──▶│          │────────────▶│            │───────────────▶│           │  │
  │ Backend Server│  event  │   │   SQS    │             │   Lambda   │               │    SES    │  │
  │               │         │   │  Queue   │             │  (Python)  │               │           │  │
  └───────────────┘         │   │          │             │            │               └───────────┘  │
                            │   └────┬─────┘             └─────┬──────┘                              │
                            │        │                         │                                     │
                            │   ┌────▼─────┐                   │                                     │
                            │   │   DLQ    │                   │                                     │
                            │   │ (failed) │                   │                                     │
                            │   └──────────┘                   │                                     │
                            │                                  │                                     │
                            │                          ┌───────▼───────┐                             │
                            │                          │  CloudWatch   │                             │
                            │                          │    Logs       │                             │
                            │                          └───────────────┘                             │
                            └─────────────────────────────────────────────────────────────────────────┘
```

**Flow:**
1. Backend server publishes a lightweight notification event to SQS and returns immediately
2. SQS triggers the Lambda function
3. Lambda picks up the event and sends email via SES *(in a full setup, it would also query a database for subscriber preferences and log delivery results — this basic version sends directly)*
4. Failed messages (after max retries by SQS) go to the Dead Letter Queue (DLQ)
5. All execution logs stream to CloudWatch

### Six-Layer Design

| Layer | Purpose | Terraform |
|---|---|---|
| 1. Event Producers | Backend publishes events to SQS | — (app code) |
| 2. Event Capture | SQS receives and buffers events | `sqs.tf` |
| 3. Async Processing | Lambda processes events | `lambda.tf` |
| 4. Delivery | SES sends emails | `ses.tf` |
| 5. Failure Handling | DLQ + retries | `sqs.tf`, `lambda.tf` |
| 6. Tracking & Audit | CloudWatch logs | (built-in) |

---

## Project Structure

```
notifications/
├── main.tf              # Terraform provider & backend config
├── variables.tf          # Input variables
├── outputs.tf            # Output values (queue URLs, Lambda ARN)
├── sqs.tf                # SQS main queue + Dead Letter Queue
├── lambda.tf             # IAM role, Lambda function, SQS trigger
├── ses.tf                # SES email identities (sender + recipient)
├── lambda/
│   └── handler.py        # Lambda function code (Python 3.11)
├── scripts/
│   └── send_test_event.py # CLI tool to send test events to SQS
└── README.md
```

---

## Prerequisites

- AWS account with credentials configured
- Terraform >= 1.5.0
- Python 3.11+ (for Lambda code)
- SES sandbox or production access (verified sender + recipient emails)

---

## Setup

### 1. Configure Variables

Create a `terraform.tfvars` file (or export env vars):

```hcl
sender_email          = "alerts@yourdomain.com"
test_recipient_email  = "you@yourdomain.com"
```

See [`variables.tf`](./variables.tf) for all options.

### 2. Deploy

```bash
cd notifications
terraform init
terraform plan
terraform apply
```

### 3. Verify SES

After apply, check your inbox for AWS SES verification emails and click the confirmation links.

### 4. Test

Send a test event:

```bash
python scripts/send_test_event.py
```

Paste the queue URL from `terraform output sqs_queue_url` when prompted.

---

## Provisioned Resources

| Resource | Name | Config |
|---|---|---|
| SQS Queue (main) | `<project>-queue` | 1-day retention |
| SQS Queue (DLQ) | `<project>-dlq` | 14-day retention, max 3 receives |
| Lambda Function | `<project>-processor` | Python 3.11, 60s timeout, 256MB |
| IAM Role | `<project>-lambda-role` | SQS + SES + CloudWatch Logs |
| SES Identity (sender) | `var.sender_email` | Requires verification click |
| SES Identity (recipient) | `var.test_recipient_email` | Required in SES sandbox |

---

## Implementation Checklist

### Phase 1 — Event Capture + Async Delivery

- [x] SQS main notification queue
- [x] SQS Dead Letter Queue
- [x] Lambda function with IAM role
- [x] SQS → Lambda event source mapping (trigger)
- [x] SES email identities (sender + test recipient)
- [x] Lambda handler: parses SQS events, sends email via SES
- [x] Test script to publish events to SQS
- [ ] Backend server: publish events to SQS queue
- [ ] CloudWatch alarms (DLQ depth, Lambda errors, processing lag)

### Phase 2 — Retry + Fallback + Tracking

- [ ] Per-channel retry with exponential backoff in Lambda
- [ ] Channel fallback: EMAIL → SMS → IN_APP
- [ ] Delivery tracking (log every attempt with status + timestamps)
- [ ] Idempotency key deduplication

### Phase 3 — Aggregation + Batching

- [ ] Digest/batching for status-change events (CloudWatch scheduled trigger)
- [ ] In-app notification as guaranteed last resort

### Phase 4 — User Preferences + New Types

- [ ] Notification preferences model + API
- [ ] Notification preferences UI
- [ ] Targeted routing: @mention, alert assignment
- [ ] Role-based routing

---

## Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `aws_region` | string | `us-east-1` | AWS region |
| `project_name` | string | `notifications` | Resource name prefix |
| `sender_email` | string | *required* | SES verified sender address |
| `test_recipient_email` | string | *required* | SES verified recipient (sandbox) |
| `lambda_timeout` | number | `60` | Lambda timeout (seconds) |
| `lambda_memory` | number | `256` | Lambda memory (MB) |
| `sqs_max_receive_count` | number | `3` | Retries before moving to DLQ |

## Outputs

| Output | Description |
|---|---|
| `sqs_queue_url` | Main SQS queue URL |
| `sqs_dlq_url` | Dead Letter Queue URL |
| `lambda_function_name` | Lambda function name |
| `lambda_function_arn` | Lambda function ARN |
| `sender_email` | Verified SES sender email |

---

## Future Improvements

- **Remote state (S3 backend)** — move `terraform.tfstate` to an S3 bucket so it's not stored only on your laptop. No DynamoDB needed for a solo project (locking is only relevant when multiple people run terraform on the same infra).