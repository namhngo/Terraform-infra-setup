import json
import os
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ses = boto3.client("ses", region_name=os.environ.get("AWS_SES_REGION", "us-east-1"))
SENDER_EMAIL = os.environ["SENDER_EMAIL"]


def lambda_handler(event, context):
    """Entry point — AWS invokes this when SQS delivers a message."""
    for record in event["Records"]:
        body = json.loads(record["body"])
        logger.info(f"Received event: {json.dumps(body, indent=2)}")
        process_notification(body)


def process_notification(msg):
    """Parse the SQS message and send an email via SES."""
    event_type = msg.get("eventType", "UNKNOWN")
    originator = msg.get("originatorName", "System")
    recipient = msg.get("recipientEmail")
    contents = msg.get("contents", {})

    if not recipient:
        logger.error("No recipientEmail in message — skipping")
        return

    subject = build_subject(event_type, contents)
    body_text = build_body(event_type, originator, contents)

    logger.info(f"Sending email to {recipient} | subject: {subject}")

    ses.send_email(
        Source=SENDER_EMAIL,
        Destination={"ToAddresses": [recipient]},
        Message={
            "Subject": {"Data": subject, "Charset": "UTF-8"},
            "Body": {
                "Text": {"Data": body_text, "Charset": "UTF-8"},
                "Html": {"Data": build_html_body(event_type, originator, contents), "Charset": "UTF-8"},
            },
        },
    )

    logger.info(f"Email sent successfully to {recipient}")


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
