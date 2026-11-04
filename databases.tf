# ============================================
# DATABASES: AWS DMS
# ============================================
# Credentials are read by DMS from Secrets Manager at runtime; they never enter Terraform state.

locals {
  db_secret_arns = distinct(compact(flatten([for d in values(local.dbs) : [d.source.secret_arn, d.target.secret_arn]])))
  s3_targets     = { for k, d in local.dbs : k => d if d.target_engine == "s3" }
  db_targets     = { for k, d in local.dbs : k => d if d.target_engine != "s3" }
  db_ca_certs    = { for k, d in local.dbs : k => d.source.ca_certificate_pem if d.source.ca_certificate_pem != null }

  table_mappings = { for k, d in local.dbs : k => jsonencode({
    rules = concat(
      [for i, r in d.include : {
        "rule-type"      = "selection"
        "rule-id"        = tostring(i + 1)
        "rule-name"      = "include-${i + 1}"
        "object-locator" = { "schema-name" = r.schema, "table-name" = r.table }
        "rule-action"    = "include"
      }],
      [for i, r in d.exclude : {
        "rule-type"      = "selection"
        "rule-id"        = tostring(length(d.include) + i + 1)
        "rule-name"      = "exclude-${i + 1}"
        "object-locator" = { "schema-name" = r.schema, "table-name" = r.table }
        "rule-action"    = "exclude"
      }]
    )
  }) }

  replication_settings = { for k, d in local.dbs : k => jsonencode(merge(
    {
      Logging          = { EnableLogging = true }
      FullLoadSettings = { TargetTablePrepMode = d.table_prep }
    },
    # Row-level validation compares source and target; only meaningful for relational targets.
    local.s.dms_validation && contains(local.relational_targets, d.target_engine) ? {
      ValidationSettings = { EnableValidation = true, ValidationMode = "ROW_LEVEL", ThreadCount = 5 }
    } : {}
  )) }
}

# --------------------------------------------
# Network
# --------------------------------------------
resource "aws_security_group" "dms" {
  count       = local.has.databases ? 1 : 0
  name        = "${local.prefix}-dms"
  description = "DMS replication: out to on-prem sources, AWS targets and AWS APIs"
  vpc_id      = local.vpc_id
  tags        = merge(local.tags, { Name = "${local.prefix}-dms" })
}

resource "aws_vpc_security_group_egress_rule" "dms_onprem" {
  for_each = local.has.databases ? toset(var.onprem_cidrs) : toset([])

  security_group_id = aws_security_group.dms[0].id
  description       = "On-prem database sources"
  ip_protocol       = "tcp"
  from_port         = 1
  to_port           = 65535
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "dms_vpc" {
  count             = local.has.databases ? 1 : 0
  security_group_id = aws_security_group.dms[0].id
  description       = "AWS targets inside the VPC"
  ip_protocol       = "tcp"
  from_port         = 1
  to_port           = 65535
  cidr_ipv4         = local.vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "dms_https" {
  count             = local.has.databases ? 1 : 0
  security_group_id = aws_security_group.dms[0].id
  description       = "AWS APIs (Secrets Manager, S3, KMS) via NAT or VPC endpoints"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# --------------------------------------------
# IAM
# --------------------------------------------
# DMS looks these roles up by these exact names (account-wide).
resource "aws_iam_role" "dms_vpc" {
  count = local.has.databases && var.create_dms_service_roles ? 1 : 0
  name  = "dms-vpc-role"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "dms.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "dms_vpc" {
  count      = length(aws_iam_role.dms_vpc)
  role       = aws_iam_role.dms_vpc[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

resource "aws_iam_role" "dms_logs" {
  count = local.has.databases && var.create_dms_service_roles ? 1 : 0
  name  = "dms-cloudwatch-logs-role"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "dms.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "dms_logs" {
  count      = length(aws_iam_role.dms_logs)
  role       = aws_iam_role.dms_logs[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole"
}

# Reads exactly the secrets named in var.databases, nothing else.
resource "aws_iam_role" "dms_secrets" {
  count = local.has.databases ? 1 : 0
  name  = "${local.prefix}-dms-secrets"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "dms.${local.region}.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "dms_secrets" {
  count = length(aws_iam_role.dms_secrets)
  name  = "read-migration-secrets"
  role  = aws_iam_role.dms_secrets[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = local.db_secret_arns
      },
      {
        Effect    = "Allow"
        Action    = "kms:Decrypt"
        Resource  = "*"
        Condition = { StringEquals = { "kms:ViaService" = "secretsmanager.${local.region}.amazonaws.com" } }
      }
    ]
  })
}

resource "aws_iam_role" "dms_s3" {
  count = length(local.s3_targets) > 0 ? 1 : 0
  name  = "${local.prefix}-dms-s3"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "dms.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "dms_s3" {
  count = length(aws_iam_role.dms_s3)
  name  = "write-target-buckets"
  role  = aws_iam_role.dms_s3[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect   = "Allow"
          Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
          Resource = [for d in values(local.s3_targets) : "arn:${local.partition}:s3:::${d.target.s3_bucket}"]
        },
        {
          Effect   = "Allow"
          Action   = ["s3:PutObject", "s3:DeleteObject", "s3:PutObjectTagging"]
          Resource = [for d in values(local.s3_targets) : "arn:${local.partition}:s3:::${d.target.s3_bucket}/*"]
        }
      ],
      [for x in [{
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = local.kms_key_arn
      }] : x if local.kms_key_arn != null]
    )
  })
}

# --------------------------------------------
# Subnets, certificates, endpoints
# --------------------------------------------
resource "aws_dms_replication_subnet_group" "main" {
  count                                = length(local.dbs) > 0 ? 1 : 0
  replication_subnet_group_id          = local.prefix
  replication_subnet_group_description = "${local.prefix} DMS replication subnets"
  subnet_ids                           = local.subnet_ids
  tags                                 = local.tags

  depends_on = [aws_iam_role_policy_attachment.dms_vpc]
}

resource "aws_dms_certificate" "source_ca" {
  for_each        = local.db_ca_certs
  certificate_id  = "${local.prefix}-${each.key}-ca"
  certificate_pem = each.value
  tags            = local.tags
}

resource "aws_dms_endpoint" "source" {
  for_each = local.dbs

  endpoint_id                     = "${local.prefix}-${each.key}-src"
  endpoint_type                   = "source"
  engine_name                     = each.value.source.engine
  database_name                   = each.value.source.database_name
  ssl_mode                        = each.value.source.ssl_mode
  certificate_arn                 = try(aws_dms_certificate.source_ca[each.key].certificate_arn, null)
  secrets_manager_arn             = each.value.source.secret_arn
  secrets_manager_access_role_arn = aws_iam_role.dms_secrets[0].arn
  extra_connection_attributes     = each.value.source.extra_connection_attributes
  kms_key_arn                     = local.kms_key_arn

  dynamic "mongodb_settings" {
    for_each = each.value.source.engine == "mongodb" ? [1] : []
    content {
      auth_type      = "password"
      auth_source    = "admin"
      auth_mechanism = "default"
    }
  }

  tags = merge(local.tags, { Database = each.key })

  depends_on = [aws_iam_role_policy.dms_secrets]
}

resource "aws_dms_endpoint" "target" {
  for_each = local.db_targets

  endpoint_id                     = "${local.prefix}-${each.key}-tgt"
  endpoint_type                   = "target"
  engine_name                     = each.value.target_engine
  database_name                   = coalesce(each.value.target.database_name, each.value.source.database_name, "migrated")
  ssl_mode                        = each.value.target.ssl_mode
  secrets_manager_arn             = each.value.target.secret_arn
  secrets_manager_access_role_arn = aws_iam_role.dms_secrets[0].arn
  kms_key_arn                     = local.kms_key_arn

  tags = merge(local.tags, { Database = each.key })

  depends_on = [aws_iam_role_policy.dms_secrets]
}

resource "aws_dms_s3_endpoint" "target" {
  for_each = local.s3_targets

  endpoint_id                       = "${local.prefix}-${each.key}-tgt"
  endpoint_type                     = "target"
  bucket_name                       = each.value.target.s3_bucket
  bucket_folder                     = each.value.target.s3_folder
  service_access_role_arn           = aws_iam_role.dms_s3[0].arn
  data_format                       = each.value.target.s3_format
  parquet_version                   = each.value.target.s3_format == "parquet" ? "parquet-2-0" : null
  compression_type                  = "GZIP"
  date_partition_enabled            = true
  # Data is encrypted with SSE-KMS via server_side_encryption_kms_key_id (kms_key_arn is deprecated in provider v6).
  encryption_mode                   = local.kms_key_arn != null ? "SSE_KMS" : "SSE_S3"
  server_side_encryption_kms_key_id = local.kms_key_arn

  tags = merge(local.tags, { Database = each.key })

  depends_on = [aws_iam_role_policy.dms_s3]
}

locals {
  target_endpoint_arn = merge(
    { for k, e in aws_dms_endpoint.target : k => e.endpoint_arn },
    { for k, e in aws_dms_s3_endpoint.target : k => e.endpoint_arn },
  )
}

# --------------------------------------------
# Replication: serverless (default) ...
# --------------------------------------------
resource "aws_dms_replication_config" "main" {
  for_each = local.serverless_dbs

  replication_config_identifier = "${local.prefix}-${each.key}"
  resource_identifier           = "${local.prefix}-${each.key}"
  replication_type              = each.value.mode
  source_endpoint_arn           = aws_dms_endpoint.source[each.key].endpoint_arn
  target_endpoint_arn           = local.target_endpoint_arn[each.key]
  table_mappings                = local.table_mappings[each.key]
  replication_settings          = local.replication_settings[each.key]
  start_replication             = each.value.start

  compute_config {
    replication_subnet_group_id  = aws_dms_replication_subnet_group.main[0].id
    vpc_security_group_ids       = [aws_security_group.dms[0].id]
    min_capacity_units           = local.s.dms_min_capacity_units
    max_capacity_units           = local.s.dms_max_capacity_units
    multi_az                     = local.s.dms_multi_az
    kms_key_id                   = local.kms_key_arn
    preferred_maintenance_window = "sun:05:00-sun:06:00"
  }

  tags = merge(local.tags, { Database = each.key })
}

# --------------------------------------------
# ... or instance-based (engines Serverless does not support, or compute = "instance")
# --------------------------------------------
resource "aws_dms_replication_instance" "main" {
  count = length(local.instance_dbs) > 0 ? 1 : 0

  replication_instance_id     = local.prefix
  replication_instance_class  = local.s.dms_instance_class
  allocated_storage           = local.s.dms_instance_storage
  multi_az                    = local.s.dms_multi_az
  publicly_accessible         = false
  kms_key_arn                 = local.kms_key_arn
  replication_subnet_group_id = aws_dms_replication_subnet_group.main[0].id
  vpc_security_group_ids      = [aws_security_group.dms[0].id]
  auto_minor_version_upgrade  = true
  apply_immediately           = false

  tags = local.tags
}

resource "aws_dms_replication_task" "main" {
  for_each = local.instance_dbs

  replication_task_id       = "${local.prefix}-${each.key}"
  migration_type            = each.value.mode
  replication_instance_arn  = aws_dms_replication_instance.main[0].replication_instance_arn
  source_endpoint_arn       = aws_dms_endpoint.source[each.key].endpoint_arn
  target_endpoint_arn       = local.target_endpoint_arn[each.key]
  table_mappings            = local.table_mappings[each.key]
  replication_task_settings = local.replication_settings[each.key]
  start_replication_task    = each.value.start

  tags = merge(local.tags, { Database = each.key })
}

# --------------------------------------------
# Alerts: every state change of this stack's replications
# --------------------------------------------
locals {
  dms_resource_arns = concat(
    [for r in aws_dms_replication_config.main : r.arn],
    [for t in aws_dms_replication_task.main : t.replication_task_arn],
  )
}

resource "aws_cloudwatch_event_rule" "dms" {
  count       = local.has.databases ? 1 : 0
  name        = "${local.prefix}-dms-events"
  description = "DMS replication state changes and failures for ${local.prefix}"

  event_pattern = jsonencode({
    source    = ["aws.dms"]
    resources = local.dms_resource_arns
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "dms" {
  count = length(aws_cloudwatch_event_rule.dms)
  rule  = aws_cloudwatch_event_rule.dms[0].name
  arn   = aws_sns_topic.alerts.arn
}
