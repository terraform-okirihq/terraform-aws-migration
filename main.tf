# ============================================
# SHARED: ENCRYPTION, ALERTS, NETWORK ACCESS
# ============================================

# --------------------------------------------
# KMS (production, unless kms_key_arn is given)
# --------------------------------------------
resource "aws_kms_key" "migration" {
  count                   = var.kms_key_arn == null && local.s.create_kms_key ? 1 : 0
  description             = "${local.prefix} migration data (DMS, DataSync logs, MGN staging disks, SNS)"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:${local.partition}:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "CloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${local.region}.amazonaws.com" }
        Action    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource  = "*"
        Condition = {
          ArnLike = { "kms:EncryptionContext:aws:logs:arn" = "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:*" }
        }
      },
      {
        Sid       = "EventsPublishToEncryptedSNS"
        Effect    = "Allow"
        Principal = { Service = ["events.amazonaws.com", "cloudwatch.amazonaws.com"] }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
      }
    ]
  })

  tags = merge(local.tags, { Name = "${local.prefix}-key" })
}

resource "aws_kms_alias" "migration" {
  count         = length(aws_kms_key.migration)
  name          = "alias/${local.prefix}"
  target_key_id = aws_kms_key.migration[0].key_id
}

# --------------------------------------------
# Alerts: every DMS and DataSync state change for this stack goes here
# --------------------------------------------
resource "aws_sns_topic" "alerts" {
  name              = "${local.prefix}-alerts"
  kms_master_key_id = local.kms_key_arn
  tags              = local.tags
}

resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridge"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.alerts.arn
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# --------------------------------------------
# Platform security groups: let migration tooling reach the platform's data stores
# --------------------------------------------
locals {
  platform_db_targets = { for k, d in local.dbs : k => d if d.target.platform_database }
}

data "aws_security_group" "platform_rds" {
  count  = length(local.platform_db_targets) > 0 ? 1 : 0
  name   = "${local.platform}-rds"
  vpc_id = local.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "platform_rds_from_dms" {
  for_each = local.platform_db_targets

  security_group_id            = data.aws_security_group.platform_rds[0].id
  description                  = "DMS migration (${each.key}); removed when the migration stack is destroyed"
  ip_protocol                  = "tcp"
  from_port                    = local.engine_port[each.value.target_engine]
  to_port                      = local.engine_port[each.value.target_engine]
  referenced_security_group_id = aws_security_group.dms[0].id

  tags = local.tags
}
