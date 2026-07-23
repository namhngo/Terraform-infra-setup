import json
import os
import time
import uuid
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
NOTIFICATION_LOG_TABLE = os.environ.get("NOTIFICATION_LOG_TABLE")
BATCH_BUFFER_TABLE = os.environ.get("BATCH_BUFFER_TABLE")
IDEMPOTENCY_TTL_SECONDS = 86400  # 1 day
LOG_TTL_SECONDS = 2592000  # 30 days
BUFFER_TTL_SECONDS = 3600  # safety net in case a flush is ever missed
MAX_RETRIES = 3
RETRY_BACKOFF_SECONDS = [1, 3, 7]  # delay before each retry attempt

idempotency_table = dynamodb.Table(IDEMPOTENCY_TABLE) if IDEMPOTENCY_TABLE else None
log_table = dynamodb.Table(NOTIFICATION_LOG_TABLE) if NOTIFICATION_LOG_TABLE else None
buffer_table = dynamodb.Table(BATCH_BUFFER_TABLE) if BATCH_BUFFER_TABLE else None


def lambda_handler(event, context):
    """Entry point — invoked either by SQS (new events to buffer) or by the
    CloudWatch schedule in digest.tf (time to flush the buffer as emails)."""
    if event.get("source") == "digest.schedule":
        flush_digest()
        return

    for record in event.get("Records", []):
        body = json.loads(record["body"])
        logger.info(f"Received event: {json.dumps(body, indent=2)}")
        buffer_notification(body)


def build_idempotency_key(msg):
    """Unique per event + recipient, so redelivered SQS messages don't double-send."""
    event_id = msg.get("eventId", "")
    recipient = msg.get("recipientEmail", "")
    raw = f"{event_id}:{recipient}"
    return hashlib.sha256(raw.encode()).hexdigest()


def already_sent(idempotency_key):
    """Check the DynamoDB table for a prior successful send with this key."""
    if not idempotency_table:
        return False
    try:
        response = idempotency_table.get_item(Key={"idempotency_key": idempotency_key})
        return "Item" in response
    except ClientError as e:
        logger.error(f"Idempotency check failed, proceeding anyway: {e}")
        return False


def mark_sent(idempotency_key):
    """Record this key so a future redelivery is skipped."""
    if not idempotency_table:
        return
    try:
        idempotency_table.put_item(
            Item={
                "idempotency_key": idempotency_key,
                "expires_at": int(time.time()) + IDEMPOTENCY_TTL_SECONDS,
            }
        )
    except ClientError as e:
        logger.error(f"Failed to record idempotency key (non-fatal): {e}")


def log_delivery_attempt(event_id, recipient, channel, status, attempt_number, error_message=None):
    """Record a delivery attempt in the notification log table (best-effort, never raises)."""
    if not log_table:
        return
    try:
        item = {
            "log_id": str(uuid.uuid4()),
            "event_id": event_id or "unknown",
            "recipient": recipient,
            "channel": channel,
            "status": status,
            "attempt_number": attempt_number,
            "sent_at": int(time.time()),
            "expires_at": int(time.time()) + LOG_TTL_SECONDS,
        }
        if error_message:
            item["error_message"] = str(error_message)[:1000]
        log_table.put_item(Item=item)
    except ClientError as e:
        logger.error(f"Failed to write notification log (non-fatal): {e}")


def buffer_notification(msg):
    """Parse the SQS message and stash it in the batch buffer instead of
    sending right away. The scheduled digest flush (see flush_digest)
    picks it up and sends it grouped with any other events for the
    same recipient.
    """
    event_id = msg.get("eventId")
    recipient = msg.get("recipientEmail")

    if not recipient:
        logger.error("No recipientEmail in message — skipping")
        return

    idempotency_key = build_idempotency_key(msg)

    if already_sent(idempotency_key):
        logger.info(f"Skipping duplicate buffering for key {idempotency_key}")
        return

    if not buffer_table:
        logger.error("BATCH_BUFFER_TABLE not configured — cannot buffer event")
        return

    buffer_table.put_item(
        Item={
            "buffer_id": str(uuid.uuid4()),
            "recipient": recipient,
            "event_id": event_id or "unknown",
            "event_type": msg.get("eventType", "UNKNOWN"),
            "originator_name": msg.get("originatorName", "System"),
            "contents": json.dumps(msg.get("contents", {})),
            "created_at": int(time.time()),
            "expires_at": int(time.time()) + BUFFER_TTL_SECONDS,
        }
    )

    # Mark as processed now — once it's in the buffer it's guaranteed to be
    # picked up by the next flush, so a redelivered SQS message shouldn't
    # buffer it a second time.
    mark_sent(idempotency_key)
    logger.info(f"Buffered notification for {recipient} (event {event_id})")


def send_with_retry(event_id, recipient, subject, body_text, body_html):
    """Attempt email delivery up to MAX_RETRIES times with a short backoff between attempts.

    Returns True if delivered, False if all attempts failed (never raises —
    the caller decides whether to fall back to another channel).
    """
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
            log_delivery_attempt(event_id, recipient, "EMAIL", "SENT", attempt)
            return True

        except ClientError as e:
            logger.error(f"Attempt {attempt} failed for {recipient}: {e}")
            log_delivery_attempt(event_id, recipient, "EMAIL", "FAILED", attempt, error_message=e)
            if attempt < MAX_RETRIES:
                time.sleep(RETRY_BACKOFF_SECONDS[attempt - 1])

    logger.error(f"All {MAX_RETRIES} email attempts failed for {recipient}, falling back")
    return False


def send_in_app_fallback(event_id, recipient, subject, body_text):
    """Last-resort channel — this project has no in-app UI, so it just logs the
    notification in a structured way (a real UI could poll the log table for these).
    This channel is not expected to fail.
    """
    logger.info(f"[IN_APP] To: {recipient} | {subject}\n{body_text}")
    log_delivery_attempt(event_id, recipient, "IN_APP", "SENT", 1)


def flush_digest():
    """Scheduled entry point (triggered by digest.tf) — reads everything
    currently sitting in the batch buffer, groups it by recipient, and
    sends one digest email per person instead of one email per event.
    """
    if not buffer_table:
        logger.error("BATCH_BUFFER_TABLE not configured — nothing to flush")
        return

    items = scan_buffer()

    if not items:
        logger.info("Digest flush: buffer is empty, nothing to send")
        return

    grouped = {}
    for item in items:
        grouped.setdefault(item["recipient"], []).append(item)

    logger.info(f"Digest flush: {len(items)} buffered event(s) for {len(grouped)} recipient(s)")

    for recipient, events in grouped.items():
        deliver_digest(recipient, events)


def scan_buffer():
    """Read every item currently sitting in the buffer table (paginated)."""
    items = []
    response = buffer_table.scan()
    items.extend(response.get("Items", []))

    while "LastEvaluatedKey" in response:
        response = buffer_table.scan(ExclusiveStartKey=response["LastEvaluatedKey"])
        items.extend(response.get("Items", []))

    return items


def deliver_digest(recipient, events):
    """Build and send a single digest covering all buffered events for one
    recipient, then clear those events from the buffer.
    """
    subject = build_digest_subject(events)
    body_text = build_digest_body(events)
    body_html = build_digest_html(events)

    # Use the first event's id as a representative id for logging —
    # a digest covers multiple events, not just one.
    event_id = events[0].get("event_id")

    delivered = send_with_retry(event_id, recipient, subject, body_text, body_html)

    if not delivered:
        send_in_app_fallback(event_id, recipient, subject, body_text)

    clear_buffer_items(events)


def clear_buffer_items(events):
    """Remove buffered items once they've been delivered (or handed off to the
    in-app fallback) so the next flush doesn't resend them.
    """
    for item in events:
        try:
            buffer_table.delete_item(Key={"buffer_id": item["buffer_id"]})
        except ClientError as e:
            logger.error(f"Failed to delete buffered item {item.get('buffer_id')}: {e}")


def build_digest_subject(events):
    if len(events) == 1:
        contents = json.loads(events[0].get("contents", "{}"))
        return build_subject(events[0].get("event_type", "UNKNOWN"), contents)
    return f"[Notify] {len(events)} notification(s)"


def build_digest_body(events):
    if len(events) == 1:
        contents = json.loads(events[0].get("contents", "{}"))
        return build_body(
            events[0].get("event_type", "UNKNOWN"),
            events[0].get("originator_name", "System"),
            contents,
        )

    lines = [f"You have {len(events)} notification(s):", ""]
    for e in events:
        contents = json.loads(e.get("contents", "{}"))
        lines.append(f"— {e.get('event_type', 'UNKNOWN')} (from {e.get('originator_name', 'System')})")
        lines.append(build_body(e.get("event_type", "UNKNOWN"), e.get("originator_name", "System"), contents))
        lines.append("")
    return "\n".join(lines)


def build_digest_html(events):
    if len(events) == 1:
        contents = json.loads(events[0].get("contents", "{}"))
        return build_html_body(
            events[0].get("event_type", "UNKNOWN"),
            events[0].get("originator_name", "System"),
            contents,
        )

    fragments = "".join(
        build_html_fragment(
            e.get("event_type", "UNKNOWN"),
            e.get("originator_name", "System"),
            json.loads(e.get("contents", "{}")),
        )
        for e in events
    )
    return wrap_html_document(fragments)


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
    return wrap_html_document(build_html_fragment(event_type, originator, contents))


def build_html_fragment(event_type, originator, contents):
    """Renders just the content block for one event — no <html>/<body> wrapper,
    so multiple fragments can be combined into a single digest document.
    """
    records = contents.get("records", [])

    rows = ""
    for r in records[:20]:
        obs_id = r.get("id", "?")
        status = r.get("status", "N/A")
        rows += f"<tr><td style='padding:4px 8px;border:1px solid #ddd;'>{obs_id}</td><td style='padding:4px 8px;border:1px solid #ddd;'>{status}</td></tr>"

    return f"""
    <div style="margin-bottom: 24px;">
        <h2 style="color: #2c5282;">{build_subject(event_type, contents)}</h2>
        <p>Triggered by: <strong>{originator}</strong></p>
        <table style="border-collapse: collapse; margin-top: 10px;">
            <tr style="background: #f7fafc;">
                <th style="padding:6px 8px;border:1px solid #ddd;text-align:left;">Observation ID</th>
                <th style="padding:6px 8px;border:1px solid #ddd;text-align:left;">Status</th>
            </tr>
            {rows}
        </table>
    </div>
    """


def wrap_html_document(inner_html):
    return f"""
    <html>
    <body style="font-family: Arial, sans-serif; color: #333;">
        {inner_html}
        <p style="margin-top:16px;color:#888;font-size:12px;">This is an automated notification from this system.</p>
    </body>
    </html>
    """
