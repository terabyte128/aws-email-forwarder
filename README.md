# AWS Email Forwarder

This is some simple terraform code (and a Python lambda script) that deploys AWS resources so that you, armed with a domain, can give out infinite disposable email addresses to services that you're worried might spam you.

For instance, if you have the domain example.com, you can put in your email as `{anything}@example.com`, and emails sent there will be auto-forwarded to your real address.

## How-To:

You'll need an AWS account, a user with API access, and [`terraform`](https://www.terraform.io) installed and configured for your AWS user.

Create a `variables.tfvars` file with the following:

```
sender_username = "{desired_sender_username}"
source_domain = "{domain_you_own}"
target_email = "{email_to_receive_forwards}"
s3_bucket_name = "{name_of_s3_bucket_for_email_storage}"
```

NB: emails are immediately deleted from the S3 bucket after the lambda is finished, so they shouldn't incur large costs.

then run `terraform apply --var-file variables.tfvars`.

You'll need to manually go into AWS and verify your domain in SES by setting the correct DNS records, as well as [set your MX records](https://docs.aws.amazon.com/ses/latest/DeveloperGuide/receiving-email-mx-record.html) so that SES receives emails sent to your domain.

## Caveats

You'll need to get your account out of the SES sandbox if you don't want to be subject to their [quota limits](https://docs.aws.amazon.com/ses/latest/dg/request-production-access.html). That being said, for this type of service, it's unlikely you'll exceed them.

