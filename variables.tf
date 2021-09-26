variable "source_domain" {
  description = "Domain source for sending email"
  type        = string
}

variable "sender_username" {
  description = "Username of sender, i.e., {sender_username}@{source_domain}"
  type        = string
}

variable "target_email" {
  description = "Target email address for forwarded messages"
  type        = string
}
