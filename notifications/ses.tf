# Verify the sender email address in SES
# After terraform apply, AWS sends a verification email — you must click the link
resource "aws_ses_email_identity" "sender" {
  email = var.sender_email
}

# Verify the test recipient email (required in SES sandbox mode)
# New AWS accounts start in "sandbox" — you can only send to verified emails
resource "aws_ses_email_identity" "recipient" {
  email = var.test_recipient_email
}
