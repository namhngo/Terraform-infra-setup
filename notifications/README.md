# Notification System — Terraform Infrastructure

Terraform configuration for an asynchronous notification system built on SQS + Lambda + SES.

---

## Architecture

```
                           ┌───────────────────────────────────────────────────────────────────────────────────┐
                           │                                      AWS                                         │
                           │                                                                                   │
  ┌───────────────┐ publish│   ┌──────────┐   trigger   ┌────────────┐   send email   ┌───────────┐          │
  │               │────────┼──▶│          │────────────▶│            │───────────────▶│           │          │
  │ Backend Server│  event  │   │   SQS    │             │   Lambda   │               │    SES    │          │
  │               │         │   │  Queue   │             │  (Python)  │               │           │          │
  └───────────────┘         │   │          │             │            │               └───────────┘          │
                            │   └────┬─────┘             └──▲──────┬──┘                                       │
                            │        │                      │      │ buffer event                            │
                            │   ┌────▼─────┐   ┌─────────────┘      ▼                                         │
                            │   │   DLQ    │   │ every N min   ┌─────────────┐                                │
                            │   │ (failed) │   │ CloudWatch    │ Batch Buffer│                                │
                            │   └──────────┘   │ Schedule      │  (DynamoDB) │                                │
                            │                  └───────────────└─────────────┘                                │
                            │                                  │                                              │
                            │                          ┌───────▼───────┐                                      │
                            │                          │  CloudWatch   │                                      │
                            │                          │    Logs       │                                      │
                            │                          └───────────────┘                                      │
                            └───────────────────────────────────────────────────────────────────────────────────┘
```

**Flow:**
1. Backend server publishes a lightweight notification event to SQS and returns immediately
2. SQS triggers the Lambda function
3. Lambda checks a DynamoDB table to skip events it has already processed (idempotency), then writes the event into a batch buffer table instead of sending immediately *(in a full setup, it would also query a database for subscriber preferences — this basic version just buffers directly)*
4. Every `batch_window_minutes` (default 5), a CloudWatch scheduled trigger invokes the same Lambda in "flush" mode
5. The flush reads everything in the buffer, groups it by recipient, and sends **one digest email per recipient** via SES (with retries on failure)
6. If email fails after all retries, Lambda falls back to an "in-app" channel — since this project has no real frontend, that just means logging a structured notification instead of losing it
7. Every delivery attempt (success, failure, or fallback) is recorded in a DynamoDB log table, and buffered items are cleared once handled
8. If the Lambda itself crashes (not a normal email failure), SQS redelivers the message; after exhausting `sqs_max_receive_count` it lands in the Dead Letter Queue (DLQ)
9. CloudWatch alarms watch the DLQ, Lambda error rate, and queue processing lag — and notify via SNS/email
10. All execution logs stream to CloudWatch

### Six-Layer Design

| Layer | Purpose | Terraform |
|---|---|---|
| 1. Event Producers | Backend publishes events to SQS | — (app code) |
| 2. Event Capture | SQS receives and buffers events | `sqs.tf` |
| 3. Async Processing | Lambda processes events | `lambda.tf` |
| 4. Delivery | SES sends emails | `ses.tf` |
| 5. Failure Handling | DLQ + retries + idempotency + fallback + alarms | `sqs.tf`, `lambda.tf`, `dynamodb.tf`, `cloudwatch.tf` |
| 6. Tracking & Audit | Delivery log (DynamoDB) + CloudWatch logs/alarms | `dynamodb.tf`, `cloudwatch.tf` |
| 7. Aggregation | Batch buffer + scheduled digest flush | `dynamodb.tf`, `digest.tf` |

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
├── dynamodb.tf           # Idempotency + delivery log + batch buffer tables
├── cloudwatch.tf         # SNS alarm topic + CloudWatch alarms
├── digest.tf             # Scheduled trigger that flushes the batch buffer
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
alarm_email           = "you@yourdomain.com"
```

See [`variables.tf`](./variables.tf) for all options.

### 2. Deploy

```bash
cd notifications
terraform init
terraform plan
terraform apply
```

### 3. Verify SES + Confirm SNS Subscription

After apply, check your inbox for two emails:
- AWS SES verification — click the confirmation link
- AWS SNS subscription confirmation (for alarm notifications) — click "Confirm subscription"

### 4. Test

Send a test event:

```bash
python scripts/send_test_event.py
```

Paste the queue URL from `terraform output sqs_queue_url` when prompted.

The event is buffered immediately, but the actual email isn't sent until the
next scheduled flush (every `batch_window_minutes`, default 5). Check
CloudWatch Logs for the Lambda function to watch both the buffering and the
flush happen.

---

## Provisioned Resources

| Resource | Name | Config |
|---|---|---|
| SQS Queue (main) | `<project>-queue` | 1-day retention |
| SQS Queue (DLQ) | `<project>-dlq` | 14-day retention, max 3 receives |
| Lambda Function | `<project>-processor` | Python 3.11, 60s timeout, 256MB |
| IAM Role | `<project>-lambda-role` | SQS + SES + DynamoDB + CloudWatch Logs |
| SES Identity (sender) | `var.sender_email` | Requires verification click |
| SES Identity (recipient) | `var.test_recipient_email` | Required in SES sandbox |
| DynamoDB Table | `<project>-idempotency` | Pay-per-request, TTL enabled (1 day) |
| DynamoDB Table | `<project>-notification-log` | Pay-per-request, TTL enabled (30 days) — one row per delivery attempt |
| DynamoDB Table | `<project>-batch-buffer` | Pay-per-request, TTL enabled (1 hour safety net) — holds events until the next digest flush |
| SNS Topic | `<project>-alarms` | Email subscription for alarm notifications |
| CloudWatch Alarm | `<project>-dlq-depth` | Fires when a message lands in the DLQ |
| CloudWatch Alarm | `<project>-lambda-errors` | Fires on any Lambda error in a 5-min window |
| CloudWatch Alarm | `<project>-processing-lag` | Fires when oldest queued message > 15 min |
| CloudWatch Event Rule | `<project>-digest-schedule` | Fires every `var.batch_window_minutes` to flush the buffer |

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
- [x] CloudWatch alarms (DLQ depth, Lambda errors, processing lag)
- [ ] Backend server: publish events to SQS queue

### Phase 2 — Retry + Fallback + Tracking

- [x] Retry with backoff on email delivery in Lambda
- [x] Idempotency key deduplication (DynamoDB)
- [x] Channel fallback: EMAIL → IN_APP *(logged, since this project has no real UI to display in-app notifications)*
- [x] Delivery tracking (every attempt logged to DynamoDB with status + timestamp)

### Phase 3 — Aggregation + Batching

- [x] Batch buffer table — events are stored, not sent, on arrival
- [x] Scheduled CloudWatch trigger flushes the buffer every `batch_window_minutes`
- [x] Digest grouping — multiple events per recipient become a single email

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
| `alarm_email` | string | *required* | Email address to receive CloudWatch alarm notifications |
| `batch_window_minutes` | number | `5` | How often buffered notifications are flushed as a digest |

## Outputs

| Output | Description |
|---|---|
| `sqs_queue_url` | Main SQS queue URL |
| `sqs_dlq_url` | Dead Letter Queue URL |
| `lambda_function_name` | Lambda function name |
| `lambda_function_arn` | Lambda function ARN |
| `sender_email` | Verified SES sender email |
| `alarms_topic_arn` | ARN of the SNS topic used for alarm notifications |
| `notification_log_table_name` | Name of the DynamoDB table tracking delivery attempts |

---

## Future Improvements

- **Remote state (S3 backend)** — move `terraform.tfstate` to an S3 bucket so it's not stored only on your laptop. No DynamoDB needed for a solo project (locking is only relevant when multiple people run terraform on the same infra).
- **SMS channel** — skipped for now since it requires SNS phone number verification/cost. Current fallback chain is EMAIL → IN_APP only.
- **Real in-app UI** — currently "in-app" just means a structured log line. A future frontend could poll `notification_log` (or a dedicated table) to actually display these.
- **Per-type routing** — right now every event is batched and waits for the next flush. A more complete system would send time-sensitive events (like @mentions) immediately and only batch high-volume types (like status changes).