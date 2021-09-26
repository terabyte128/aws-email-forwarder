locals {
  email_lambda_name = "email-forwarder-lambda"
}

data "aws_caller_identity" "current" {}

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

resource "aws_ses_receipt_rule" "publish_to_sns" {
  name          = "publish-to-sns"
  rule_set_name = aws_ses_receipt_rule_set.potential_spam.rule_set_name
  enabled       = true

  sns_action {
    position  = 1
    encoding  = "Base64"
    topic_arn = aws_sns_topic.forward_to_lambda.arn
  }
}

data "aws_iam_policy_document" "ses_publish_to_sns" {
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.forward_to_lambda.arn]
    principals {
      type        = "Service"
      identifiers = ["ses.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic" "forward_to_lambda" {
  name = "forward-to-lambda"
}

resource "aws_sns_topic_policy" "forward_to_lambda" {
  arn    = aws_sns_topic.forward_to_lambda.arn
  policy = data.aws_iam_policy_document.ses_publish_to_sns.json
}

resource "aws_sns_topic_subscription" "forward_to_lambda" {
  topic_arn = aws_sns_topic.forward_to_lambda.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.email_lambda.arn
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
  environment {
    variables = {
      SOURCE_EMAIL = "${var.sender_username}@${var.source_domain}"
      TARGET_EMAIL = var.target_email
    }
  }
  depends_on = [
    aws_iam_role_policy_attachment.lambda_assume_role_attachment,
    aws_cloudwatch_log_group.email_lambda,
  ]
}

resource "aws_lambda_permission" "sns_call_lambda" {
  function_name = aws_lambda_function.email_lambda.function_name
  action        = "lambda:InvokeFunction"
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.forward_to_lambda.arn
}

resource "aws_cloudwatch_log_group" "email_lambda" {
  name              = "/aws/lambda/${local.email_lambda_name}"
  retention_in_days = 7
}

