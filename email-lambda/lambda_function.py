import json
import email
import base64
import boto3
import re
import os


def lambda_handler(event, context):
    source_email = os.environ.get("SOURCE_EMAIL")
    target_email = os.environ.get("TARGET_EMAIL")

    if any(i is None for i in [source_email, target_email]):
        raise ValueError("SOURCE_EMAIL and TARGET_EMAIL are required")

    msg = json.loads(event["Records"][0]["Sns"]["Message"])
    content = base64.b64decode(msg["content"])

    letter = email.message_from_bytes(content)
    client = boto3.client("ses")

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

    client.send_raw_email(
        Destinations=[target_email],
        RawMessage={"Data": bytes(letter)},
    )
