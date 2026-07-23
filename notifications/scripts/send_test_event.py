"""
Send a test notification event to SQS.

Usage:
    python scripts/send_test_event.py

Prerequisites:
    - pip install boto3
    - AWS credentials configured (aws configure)
    - Terraform applied (so the queue exists)
"""

import json
import boto3
import uuid
from datetime import datetime

QUEUE_URL = input("Paste your SQS queue URL (from terraform output): ").strip()
RECIPIENT_EMAIL = input("Recipient email (must be verified in SES): ").strip()
SEND_IMMEDIATELY = input("Send immediately instead of waiting for the digest? (y/N): ").strip().lower() == "y"

sqs = boto3.client("sqs", region_name="us-east-1")

event = {
    "eventId": str(uuid.uuid4()),
    "eventType": "OBS.STATUS_CHANGE",
    "environment": "DEMO",
    "accountId": str(uuid.uuid4()),
    "originatorName": "Nam Ngo",
    "originatorEmail": "nam@example.com",
    "timestamp": datetime.now().isoformat(),
    "targetMemberId": None,
    "recipientEmail": RECIPIENT_EMAIL,
    "sendImmediately": SEND_IMMEDIATELY,
    "contents": {
        "comment": "Status updated for demo test",
        "records": [
            {"id": 101, "status": "Confirmed", "project_id": 1, "product_id": 2},
            {"id": 102, "status": "Dismissed", "project_id": 1, "product_id": 3},
            {"id": 103, "status": "Under Review", "project_id": 2, "product_id": 1},
        ],
    },
}

print(f"\nSending event to SQS...")
print(json.dumps(event, indent=2))

response = sqs.send_message(
    QueueUrl=QUEUE_URL,
    MessageBody=json.dumps(event),
)

print(f"\nMessage sent! MessageId: {response['MessageId']}")
if SEND_IMMEDIATELY:
    print("sendImmediately=true — check your inbox in a few seconds.")
else:
    print("Buffered for the next digest flush — check your inbox in a few minutes.")
print("Check CloudWatch logs for the Lambda function either way.")
