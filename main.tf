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
        Principal = { Service = ["events.amazonaws.com", "cloudwatch.amazonaws.com", "s3.amazonaws.com"] }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
      },
      {
        # MGN encrypts replication staging disks with this key (--ebs-encryption CUSTOM). Its service-linked
        # roles may use the key only through EC2/EBS. Matched by condition, not principal, so the policy is
        # valid before MGN is initialized and its roles exist.
        Sid       = "MgnStagingDisksViaEbs"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey", "kms:CreateGrant"]
        Resource  = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = local.account_id
            "kms:ViaService"    = "ec2.${local.region}.amazonaws.com"
          }
          ArnLike = { "aws:PrincipalArn" = "arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/mgn.amazonaws.com/*" }
        }
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
    Statement = [
      {
        Sid       = "AllowEventBridge"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.alerts.arn
        Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
      },
      {
        Sid       = "AllowS3ObjectRemoved"
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.alerts.arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account_id }
          ArnLike      = { "aws:SourceArn" = "arn:${local.partition}:s3:::${local.prefix}-*" }
        }
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# --------------------------------------------
# Access logs for buckets this module creates (DataSync destinations and Velero)
# --------------------------------------------
locals {
  s3_access_logs = length(local.dest_s3_create) > 0 || local.k8s_ready
}

resource "aws_s3_bucket" "access_logs" {
  # checkov:skip=CKV_AWS_145: S3 server access log delivery does not support SSE-KMS
  # checkov:skip=CKV_AWS_18: This is the log destination. Logging it into itself creates an endless log loop (AWS advises against it).
  count         = local.s3_access_logs ? 1 : 0
  bucket        = "${local.prefix}-s3-logs-${local.account_id}"
  force_destroy = true # access logs only; the data buckets themselves are kept
  tags          = merge(local.tags, { Purpose = "S3 server access logs" })
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  count                   = length(aws_s3_bucket.access_logs)
  bucket                  = aws_s3_bucket.access_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "access_logs" {
  count  = length(aws_s3_bucket.access_logs)
  bucket = aws_s3_bucket.access_logs[0].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "access_logs" {
  count  = length(aws_s3_bucket.access_logs)
  bucket = aws_s3_bucket.access_logs[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server access log delivery supports SSE-S3 only. A customer-managed key on this bucket drops the logs.
resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  count  = length(aws_s3_bucket.access_logs)
  bucket = aws_s3_bucket.access_logs[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  count  = length(aws_s3_bucket.access_logs)
  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = local.s.log_retention
    }
    noncurrent_version_expiration {
      noncurrent_days = local.s.log_retention
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "access_logs" {
  count  = length(aws_s3_bucket.access_logs)
  bucket = aws_s3_bucket.access_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.access_logs[0].arn, "${aws_s3_bucket.access_logs[0].arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "ServerAccessLogDelivery"
        Effect    = "Allow"
        Principal = { Service = "logging.s3.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.access_logs[0].arn}/*"
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account_id }
          ArnLike = {
            "aws:SourceArn" = concat(
              [for b in aws_s3_bucket.dest : b.arn],
              [for b in aws_s3_bucket.velero : b.arn],
            )
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.access_logs, aws_s3_bucket_ownership_controls.access_logs]
}

resource "aws_s3_bucket_notification" "access_logs" {
  count  = length(aws_s3_bucket.access_logs)
  bucket = aws_s3_bucket.access_logs[0].id

  topic {
    topic_arn = aws_sns_topic.alerts.arn
    events    = ["s3:ObjectRemoved:*"]
  }

  depends_on = [aws_sns_topic_policy.alerts, aws_s3_bucket_policy.access_logs]
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
