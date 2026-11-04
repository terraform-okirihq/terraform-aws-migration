# ============================================
# DMS SCHEMA CONVERSION
# ============================================
# Converts schemas and code (tables, views, procedures, functions) between engines, e.g. Oracle or SQL Server
# to PostgreSQL. Run the conversion in the DMS console (Migration projects), apply it to the target, then
# replicate the data with the migration module.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  prefix    = "${var.name}-${var.environment}-sc"
  region    = data.aws_region.current.name
  partition = data.aws_partition.current.partition
  tags      = merge({ Project = var.name, Environment = var.environment, ManagedBy = "terraform", Module = "aws-migration/schema-conversion", Lifecycle = "temporary" }, var.tags)
  tag_set   = [for k, v in local.tags : { key = k, value = v }]

  # Our engine names -> DMS data provider engine names and settings blocks.
  provider_engine = {
    mysql  = "mysql", mariadb = "mariadb", postgres = "postgres", aurora = "aurora", "aurora-postgresql" = "aurora_postgresql",
    oracle = "oracle", sqlserver = "sqlserver", db2 = "db2", sybase = "sybase", mongodb = "mongodb", docdb = "docdb", redshift = "redshift"
  }

  endpoints = merge(
    { for k, p in var.projects : "${k}-src" => merge(p.source, { project = k }) },
    { for k, p in var.projects : "${k}-tgt" => merge(p.target, { project = k }) },
  )
}

# --------------------------------------------
# Artifacts bucket (assessment reports, converted code)
# --------------------------------------------
resource "aws_s3_bucket" "artifacts" {
  bucket        = "${local.prefix}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = local.tags
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.network.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.network.kms_key_arn
    }
  }
}

# --------------------------------------------
# Role for Schema Conversion: read the listed secrets, write artifacts
# --------------------------------------------
resource "aws_iam_role" "sc" {
  name = "${local.prefix}-access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = ["dms.amazonaws.com", "dms.${local.region}.amazonaws.com"] }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "sc" {
  name = "schema-conversion"
  role = aws_iam_role.sc.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
          Resource = distinct([for e in values(local.endpoints) : e.secret_arn])
        },
        {
          Effect   = "Allow"
          Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketVersioning"]
          Resource = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
        },
      ],
      [for x in [{
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = var.network.kms_key_arn
      }] : x if var.network.kms_key_arn != null]
    )
  })
}

# --------------------------------------------
# Instance profile (private, in the migration module's DMS subnets)
# --------------------------------------------
resource "awscc_dms_instance_profile" "this" {
  instance_profile_name   = local.prefix
  description             = "Schema conversion for ${var.name} ${var.environment}"
  subnet_group_identifier = var.network.subnet_group_id
  vpc_security_groups     = [var.network.security_group_id]
  publicly_accessible     = false
  kms_key_arn             = var.network.kms_key_arn
  network_type            = "IPV4"
  tags                    = local.tag_set
}

# --------------------------------------------
# Data providers (one per source / target)
# --------------------------------------------
resource "awscc_dms_data_provider" "this" {
  for_each           = local.endpoints
  data_provider_name = "${local.prefix}-${each.key}"
  engine             = local.provider_engine[each.value.engine]

  settings = {
    my_sql_settings               = contains(["mysql", "aurora"], each.value.engine) ? { server_name = each.value.host, port = each.value.port, ssl_mode = each.value.ssl_mode } : null
    maria_db_settings             = each.value.engine == "mariadb" ? { server_name = each.value.host, port = each.value.port, ssl_mode = each.value.ssl_mode } : null
    postgre_sql_settings          = contains(["postgres", "aurora-postgresql"], each.value.engine) ? { server_name = each.value.host, port = each.value.port, database_name = each.value.database_name, ssl_mode = each.value.ssl_mode } : null
    oracle_settings               = each.value.engine == "oracle" ? { server_name = each.value.host, port = each.value.port, database_name = each.value.database_name, ssl_mode = each.value.ssl_mode } : null
    microsoft_sql_server_settings = each.value.engine == "sqlserver" ? { server_name = each.value.host, port = each.value.port, database_name = each.value.database_name, ssl_mode = each.value.ssl_mode } : null
    ibm_db_2_luw_settings         = each.value.engine == "db2" ? { server_name = each.value.host, port = each.value.port, database_name = each.value.database_name, ssl_mode = each.value.ssl_mode } : null
    sybase_ase_settings           = each.value.engine == "sybase" ? { server_name = each.value.host, port = each.value.port, database_name = each.value.database_name, ssl_mode = each.value.ssl_mode } : null
    mongo_db_settings             = each.value.engine == "mongodb" ? { server_name = each.value.host, port = each.value.port, database_name = each.value.database_name, ssl_mode = each.value.ssl_mode, auth_type = "password", auth_source = "admin" } : null
    doc_db_settings               = each.value.engine == "docdb" ? { server_name = each.value.host, port = each.value.port, database_name = each.value.database_name, ssl_mode = each.value.ssl_mode } : null
    redshift_settings             = each.value.engine == "redshift" ? { server_name = each.value.host, port = each.value.port, database_name = each.value.database_name } : null
  }

  tags = local.tag_set
}

# --------------------------------------------
# Migration projects
# --------------------------------------------
resource "awscc_dms_migration_project" "this" {
  for_each                    = var.projects
  migration_project_name      = "${local.prefix}-${each.key}"
  description                 = "${each.value.source.engine} -> ${each.value.target.engine}"
  instance_profile_identifier = awscc_dms_instance_profile.this.instance_profile_arn

  source_data_provider_descriptors = [{
    data_provider_arn               = awscc_dms_data_provider.this["${each.key}-src"].data_provider_arn
    secrets_manager_secret_id       = each.value.source.secret_arn
    secrets_manager_access_role_arn = aws_iam_role.sc.arn
  }]

  target_data_provider_descriptors = [{
    data_provider_arn               = awscc_dms_data_provider.this["${each.key}-tgt"].data_provider_arn
    secrets_manager_secret_id       = each.value.target.secret_arn
    secrets_manager_access_role_arn = aws_iam_role.sc.arn
  }]

  schema_conversion_application_attributes = {
    s3_bucket_path     = "s3://${aws_s3_bucket.artifacts.bucket}"
    s3_bucket_role_arn = aws_iam_role.sc.arn
  }

  tags = local.tag_set

  depends_on = [aws_iam_role_policy.sc]
}
