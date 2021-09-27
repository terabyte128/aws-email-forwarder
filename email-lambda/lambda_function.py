import json
import email
import base64
import boto3
import re
import os


def lambda_handler(event, context):
    source_email = os.environ.get("SOURCE_EMAIL")
    target_email = os.environ.get("TARGET_EMAIL")
    s3_bucket_name = os.environ.get("S3_BUCKET_NAME")

    if any(i is None for i in [source_email, target_email, s3_bucket_name]):
        raise ValueError("SOURCE_EMAIL and TARGET_EMAIL are required")

    message_id = event["Records"][0]["ses"]["mail"]["messageId"]

    s3_client = boto3.client("s3")

    email_obj = s3_client.get_object(
        Bucket=s3_bucket_name,
        Key=message_id,
    )

    content = email_obj["Body"].read()

    letter = email.message_from_bytes(content)
    ses_client = boto3.client("ses")

    orig_from = letter["From"]

    matched = re.match(r"(.*)\s<(.*)>", orig_from)

    if matched:
        new_from = f"{matched.group(1)} <{source_email}>"
    else:
        new_from = source_email

    for header in letter.keys():
        if header not in ["Subject", "To", "Content-Type", "From"]:
            del letter[header]

    letter["Reply-To"] = orig_from

    letter.replace_header("From", new_from)

    ses_client.send_raw_email(
        Destinations=[target_email],
        RawMessage={"Data": bytes(letter)},
    )

    s3_client.delete_object(
        Bucket=s3_bucket_name,
        Key=message_id,
    )
