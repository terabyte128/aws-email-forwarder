locals {
  email_lambda_name     = "email-forwarder-lambda"
  ses_receipt_rule_name = "send-to-s3"
  ses_receipt_rule_arn  = "arn:aws:ses:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:receipt-rule-set/${aws_ses_receipt_rule_set.potential_spam.rule_set_name}:receipt-rule/${local.ses_receipt_rule_name}"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_ses_domain_identity" "source_domain" {
  domain = var.source_domain
}

resource "aws_ses_email_identity" "forwarded_emails" {
  email = var.target_email
}

resource "aws_ses_receipt_rule_set" "potential_spam" {
  rule_set_name = "potential-spam-receipt"
}

resource "aws_ses_active_receipt_rule_set" "potential_spam" {
  rule_set_name = aws_ses_receipt_rule_set.potential_spam.rule_set_name
}

data "aws_iam_policy_document" "ses_write_to_s3" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.email_bucket.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["ses.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [local.ses_receipt_rule_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "ses_write_to_s3" {
  bucket = var.s3_bucket_name
  policy = data.aws_iam_policy_document.ses_write_to_s3.json
}

resource "aws_s3_bucket" "email_bucket" {
  bucket = var.s3_bucket_name
  acl    = "private"
}

resource "aws_s3_bucket_public_access_block" "email_bucket" {
  bucket                  = var.s3_bucket_name
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_ses_receipt_rule" "send_to_s3" {
  name          = local.ses_receipt_rule_name
  rule_set_name = aws_ses_receipt_rule_set.potential_spam.rule_set_name
  enabled       = true

  s3_action {
    position    = 1
    bucket_name = var.s3_bucket_name
  }

  lambda_action {
    position     = 2
    function_arn = aws_lambda_function.email_lambda.arn
  }

  depends_on = [
    aws_s3_bucket_policy.ses_write_to_s3,
    aws_lambda_permission.ses_call_lambda
  ]
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_assume_role" {
  name               = "email-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_resource_access" {
  statement {
    actions   = ["ses:SendRawEmail"]
    resources = ["arn:aws:ses:*:${data.aws_caller_identity.current.account_id}:identity/*"]
  }

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:*"]
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:DeleteObject"
    ]
    resources = ["${aws_s3_bucket.email_bucket.arn}/*"]
  }
}

resource "aws_iam_policy" "lambda_resource_access" {
  name   = "email-lambda-resource-access"
  policy = data.aws_iam_policy_document.lambda_resource_access.json
}

resource "aws_iam_role_policy_attachment" "lambda_assume_role_attachment" {
  role       = aws_iam_role.lambda_assume_role.name
  policy_arn = aws_iam_policy.lambda_resource_access.arn
}

resource "aws_lambda_function" "email_lambda" {
  function_name = local.email_lambda_name
  role          = aws_iam_role.lambda_assume_role.arn
  runtime       = "python3.9"
  handler       = "lambda_function.lambda_handler"
  filename      = "email-lambda.zip"
  timeout       = 10

  environment {
    variables = {
      SOURCE_EMAIL   = "${var.sender_username}@${var.source_domain}"
      TARGET_EMAIL   = var.target_email
      S3_BUCKET_NAME = var.s3_bucket_name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_assume_role_attachment,
    aws_cloudwatch_log_group.email_lambda,
  ]
}

resource "aws_lambda_permission" "ses_call_lambda" {
  function_name  = aws_lambda_function.email_lambda.function_name
  action         = "lambda:InvokeFunction"
  principal      = "ses.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
  source_arn     = local.ses_receipt_rule_arn
}

resource "aws_cloudwatch_log_group" "email_lambda" {
  name              = "/aws/lambda/${local.email_lambda_name}"
  retention_in_days = 7
}

