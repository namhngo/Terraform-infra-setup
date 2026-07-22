import json
import os
import time
import hashlib
import boto3
import logging
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ses = boto3.client("ses", region_name=os.environ.get("AWS_SES_REGION", "us-east-1"))
dynamodb = boto3.resource("dynamodb")
SENDER_EMAIL = os.environ["SENDER_EMAIL"]
IDEMPOTENCY_TABLE = os.environ.get("IDEMPOTENCY_TABLE")
IDEMPOTENCY_TTL_SECONDS = 86400  # 1 day
MAX_RETRIES = 3
RETRY_BACKOFF_SECONDS = [1, 3, 7]  # delay before each retry attempt

table = dynamodb.Table(IDEMPOTENCY_TABLE) if IDEMPOTENCY_TABLE else None


def lambda_handler(event, context):
    """Entry point — AWS invokes this when SQS delivers a message."""
    for record in event["Records"]:
        body = json.loads(record["body"])
        logger.info(f"Received event: {json.dumps(body, indent=2)}")
        process_notification(body)


def build_idempotency_key(msg):
    """Unique per event + recipient, so redelivered SQS messages don't double-send."""
    event_id = msg.get("eventId", "")
    recipient = msg.get("recipientEmail", "")
    raw = f"{event_id}:{recipient}"
    return hashlib.sha256(raw.encode()).hexdigest()


def already_sent(idempotency_key):
    """Check the DynamoDB table for a prior successful send with this key."""
    if not table:
        return False
    try:
        response = table.get_item(Key={"idempotency_key": idempotency_key})
        return "Item" in response
    except ClientError as e:
        logger.error(f"Idempotency check failed, proceeding anyway: {e}")
        return False


def mark_sent(idempotency_key):
    """Record this key so a future redelivery is skipped."""
    if not table:
        return
    try:
        table.put_item(
            Item={
                "idempotency_key": idempotency_key,
                "expires_at": int(time.time()) + IDEMPOTENCY_TTL_SECONDS,
            }
        )
    except ClientError as e:
        logger.error(f"Failed to record idempotency key (non-fatal): {e}")


def process_notification(msg):
    """Parse the SQS message and send an email via SES, with idempotency + retry."""
    event_type = msg.get("eventType", "UNKNOWN")
    originator = msg.get("originatorName", "System")
    recipient = msg.get("recipientEmail")
    contents = msg.get("contents", {})

    if not recipient:
        logger.error("No recipientEmail in message — skipping")
        return

    idempotency_key = build_idempotency_key(msg)

    if already_sent(idempotency_key):
        logger.info(f"Skipping duplicate delivery for key {idempotency_key}")
        return

    subject = build_subject(event_type, contents)
    body_text = build_body(event_type, originator, contents)
    body_html = build_html_body(event_type, originator, contents)

    send_with_retry(recipient, subject, body_text, body_html)

    mark_sent(idempotency_key)


def send_with_retry(recipient, subject, body_text, body_html):
    """Attempt delivery up to MAX_RETRIES times with a short backoff between attempts."""
    last_error = None

    for attempt in range(1, MAX_RETRIES + 1):
        try:
            logger.info(f"Sending email to {recipient} | subject: {subject} | attempt {attempt}")
            ses.send_email(
                Source=SENDER_EMAIL,
                Destination={"ToAddresses": [recipient]},
                Message={
                    "Subject": {"Data": subject, "Charset": "UTF-8"},
                    "Body": {
                        "Text": {"Data": body_text, "Charset": "UTF-8"},
                        "Html": {"Data": body_html, "Charset": "UTF-8"},
                    },
                },
            )
            logger.info(f"Email sent successfully to {recipient}")
            return

        except ClientError as e:
            last_error = e
            logger.error(f"Attempt {attempt} failed for {recipient}: {e}")
            if attempt < MAX_RETRIES:
                time.sleep(RETRY_BACKOFF_SECONDS[attempt - 1])

    # All retries exhausted — raise so SQS redelivers / eventually sends to DLQ
    logger.error(f"All {MAX_RETRIES} attempts failed for {recipient}, giving up")
    raise last_error


def build_subject(event_type, contents):
    if event_type == "OBS.STATUS_CHANGE":
        count = len(contents.get("records", []))
        return f"[Notify] {count} observation(s) updated"
    elif event_type == "OBS.NEW_ALERTS":
        count = len(contents.get("records", []))
        return f"[Notify] {count} new alert(s) detected"
    return f"[Notify] Notification — {event_type}"


def build_body(event_type, originator, contents):
    lines = [f"Notification type: {event_type}", f"Triggered by: {originator}", ""]

    records = contents.get("records", [])
    if records:
        lines.append(f"{len(records)} record(s):")
        for r in records[:10]:
            status = r.get("status", "N/A")
            obs_id = r.get("id", "?")
            lines.append(f"  - Observation {obs_id}: {status}")
        if len(records) > 10:
            lines.append(f"  ... and {len(records) - 10} more")

    comment = contents.get("comment")
    if comment:
        lines.append(f"\nComment: {comment}")

    return "\n".join(lines)


def build_html_body(event_type, originator, contents):
    records = contents.get("records", [])

    rows = ""
    for r in records[:20]:
        obs_id = r.get("id", "?")
        status = r.get("status", "N/A")
        rows += f"<tr><td style='padding:4px 8px;border:1px solid #ddd;'>{obs_id}</td><td style='padding:4px 8px;border:1px solid #ddd;'>{status}</td></tr>"

    return f"""
    <html>
    <body style="font-family: Arial, sans-serif; color: #333;">
        <h2 style="color: #2c5282;">{build_subject(event_type, contents)}</h2>
        <p>Triggered by: <strong>{originator}</strong></p>
        <table style="border-collapse: collapse; margin-top: 10px;">
            <tr style="background: #f7fafc;">
                <th style="padding:6px 8px;border:1px solid #ddd;text-align:left;">Observation ID</th>
                <th style="padding:6px 8px;border:1px solid #ddd;text-align:left;">Status</th>
            </tr>
            {rows}
        </table>
        <p style="margin-top:16px;color:#888;font-size:12px;">This is an automated notification from this system.</p>
    </body>
    </html>
    """
