# SIO Notifications — Terraform Infrastructure

Terraform configuration for the [SIO Vigilance](https://github.com/satelytics/sio-vigilance) asynchronous notification system.  
Design doc: [`sio-vigilance/plans/notifications/notification-system-design.md`](https://github.com/satelytics/sio-vigilance/blob/doc/notification-system/plans/notifications/notification-system-design.md)

---

## Architecture

```
                           ┌─────────────────────────────────────────────────────────────────────────┐
                           │                              AWS                                         │
                           │                                                                         │
  ┌──────────┐   publish   │   ┌──────────┐   trigger   ┌────────────┐   send email   ┌───────────┐  │
  │          │─────────────┼──▶│          │────────────▶│            │───────────────▶│           │  │
  │  sio-api │   event     │   │   SQS    │             │   Lambda   │               │    SES    │  │
  │          │             │   │  Queue   │             │ (Python)   │               │           │  │
  └──────────┘             │   │          │             │            │               └───────────┘  │
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
1. `sio-api` publishes a lightweight notification event to SQS and returns immediately
2. SQS triggers the Lambda function
3. Lambda processes the event: resolves recipients, builds payloads, sends email via SES
4. Failed messages (after retries) go to the Dead Letter Queue (DLQ)
5. All execution logs stream to CloudWatch

### Six-Layer Design

The full system design (see [design doc](https://github.com/satelytics/sio-vigilance/blob/doc/notification-system/plans/notifications/notification-system-design.md)) defines six layers:

| Layer | Purpose | Terraform |
|---|---|---|
| 1. Event Producers | sio-api publishes events to SQS | — (app code) |
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
- [ ] Terraform remote state backend (S3 + DynamoDB lock)
- [ ] `NOTIFICATION_USE_QUEUE = True` in sio-api settings
- [ ] `NotificationEvent` model in sio-api
- [ ] `NotificationLog` model in sio-api
- [ ] Refactor `sendNotification` to write event + publish to SQS
- [ ] Lambda VPC attachment (for RDS database access)
- [ ] NAT Gateway (Lambda internet access from VPC)
- [ ] Secrets Manager (DB credentials for Lambda)
- [ ] Port subscriber lookup + filtering logic from sio-api to Lambda
- [ ] Port delivery logic (Email/SMS/In-app) from sio-api to Lambda

### Phase 2 — Retry + Fallback + Tracking

- [ ] Per-channel retry with exponential backoff in Lambda
- [ ] Channel fallback: EMAIL → SMS → IN_APP
- [ ] `NotificationLog` entries for every delivery attempt
- [ ] Idempotency key deduplication
- [ ] CloudWatch alarm: DLQ depth > 0
- [ ] CloudWatch alarm: Lambda error rate > 5%
- [ ] CloudWatch alarm: processing lag > 15min

### Phase 3 — Aggregation + Batching

- [ ] Digest/batching for `OBS.STATUS_CHANGE` (CloudWatch scheduled trigger)
- [ ] In-app notification as guaranteed last resort

### Phase 4 — User Preferences + New Types

- [ ] `NotificationPreference` model + API
- [ ] Notification preferences UI in Vigilance
- [ ] Targeted routing: @mention, alert assignment
- [ ] Role-based routing: professional services

---

## Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `aws_region` | string | `us-east-1` | AWS region |
| `project_name` | string | `sio-notifications` | Resource name prefix |
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

## Related Repos

- **sio-api** — API producer (publishes events to SQS)
- **sio-vigilance** — Frontend (notification preferences UI — future)