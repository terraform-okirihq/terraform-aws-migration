# ============================================
# PROFILES -> SETTINGS
# ============================================

locals {
  profiles = {
    pilot = {
      dms_min_capacity_units = 1
      dms_max_capacity_units = 4
      dms_multi_az           = false
      dms_instance_class     = "dms.t3.medium"
      dms_instance_storage   = 50
      dms_validation         = false
      log_retention          = 14
      create_kms_key         = false
      datasync_private_link  = false
      require_alert_email    = false
    }
    production = {
      dms_min_capacity_units = 2
      dms_max_capacity_units = 16
      dms_multi_az           = true
      dms_instance_class     = "dms.r6i.large"
      dms_instance_storage   = 100
      dms_validation         = true
      log_retention          = 90
      create_kms_key         = true
      datasync_private_link  = true
      require_alert_email    = true
    }
  }

  s = merge(local.profiles[var.profile], var.overrides)

  prefix     = "${var.name}-${var.environment}-mig"
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  partition  = data.aws_partition.current.partition

  tags = merge({
    Project     = var.name
    Environment = var.environment
    Profile     = var.profile
    ManagedBy   = "terraform"
    Module      = "aws-migration"
    Lifecycle   = "temporary" # destroy this stack after cutover
  }, var.tags)

  has = {
    databases = contains(var.migrate, "databases")
    files     = contains(var.migrate, "files")
    servers   = contains(var.migrate, "servers")
  }

  # Customer-managed key: bring your own, create one (production), or use AWS-managed keys (pilot).
  kms_key_arn = var.kms_key_arn != null ? var.kms_key_arn : (local.s.create_kms_key ? aws_kms_key.migration[0].arn : null)
}

# ============================================
# TARGET NETWORK
# ============================================

locals {
  use_platform = try(var.target.platform_name, null) != null
  platform     = local.use_platform ? var.target.platform_name : ""

  vpc_id     = local.use_platform ? data.aws_vpc.platform[0].id : var.target.vpc_id
  vpc_cidr   = try(data.aws_vpc.target[0].cidr_block, "")
  subnet_ids = local.use_platform ? sort(data.aws_subnets.platform_private[0].ids) : var.target.subnet_ids
}

data "aws_vpc" "platform" {
  count = local.use_platform ? 1 : 0
  tags  = { Name = "${local.platform}-vpc" }
}

data "aws_subnets" "platform_private" {
  count = local.use_platform ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.platform[0].id]
  }

  tags = { Tier = "private" }
}

# Only looked up once a VPC is known; with no target the guardrails explain what is missing instead.
data "aws_vpc" "target" {
  count = local.vpc_id != null ? 1 : 0
  id    = local.vpc_id
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# ============================================
# ENGINE KNOWLEDGE
# ============================================

locals {
  # Default target engine for each source (homogeneous migration). db2 / sybase need an explicit target.
  default_target_engine = {
    mysql     = "mysql"
    mariadb   = "mariadb"
    postgres  = "postgres"
    oracle    = "oracle"
    sqlserver = "sqlserver"
    mongodb   = "docdb"
  }

  # DMS Serverless does not support every engine; these default to an instance-based replication.
  instance_only_engines = ["sybase"]

  relational_targets = ["mysql", "mariadb", "postgres", "aurora", "aurora-postgresql", "oracle", "sqlserver"]
  document_engines   = ["mongodb", "docdb"]

  engine_port = {
    mysql               = 3306
    mariadb             = 3306
    aurora              = 3306
    postgres            = 5432
    "aurora-postgresql" = 5432
    sqlserver           = 1433
    oracle              = 1521
    docdb               = 27017
    redshift            = 5439
  }

  table_prep = {
    keep     = "DO_NOTHING"
    truncate = "TRUNCATE_BEFORE_LOAD"
    drop     = "DROP_AND_CREATE"
  }

  # Every database definition, fully resolved (checked by guardrails.tf).
  dbs_all = local.has.databases ? {
    for k, d in var.databases : k => {
      source        = d.source
      target        = d.target
      target_engine = coalesce(d.target.engine, lookup(local.default_target_engine, d.source.engine, "unset"))
      compute       = coalesce(d.compute, contains(local.instance_only_engines, d.source.engine) ? "instance" : "serverless")
      mode          = d.mode
      include       = d.include
      exclude       = d.exclude
      table_prep    = local.table_prep[d.on_existing_tables]
      start         = d.start
      allow_unenc   = d.allow_unencrypted
    }
  } : {}

  # Resources are built only from definitions that pass the guardrails (and once the network is valid), so a
  # bad entry always surfaces as the guardrail's message rather than an AWS validation error.
  dbs = length(local.subnet_ids) >= 2 ? {
    for k, d in local.dbs_all : k => d
    if d.target_engine != "unset" && (d.source.engine == "mongodb" ? contains(["docdb", "s3"], d.target_engine) : d.target_engine != "docdb")
  } : {}

  serverless_dbs = { for k, d in local.dbs : k => d if d.compute == "serverless" }
  instance_dbs   = { for k, d in local.dbs : k => d if d.compute == "instance" }
}
