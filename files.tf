# ============================================
# FILES: AWS DataSync
# ============================================
# Note: DataSync locations require SMB / FSx / object-storage credentials as arguments, so those values are
# read from Secrets Manager and end up (marked sensitive) in Terraform state. Keep state encrypted.

locals {
  # Only shares that pass the guardrails become resources, so mistakes surface as guardrail messages.
  shares = local.has.files ? {
    for k, f in var.file_shares : k => f
    if contains(keys(local.agents_valid), f.source.agent)
    && (!contains(["smb", "object-storage"], f.source.type) || f.source.secret_arn != null)
    && (f.source.type == "hdfs" ? length(f.source.hdfs_name_nodes) > 0 : f.source.host != null)
    && (f.destination.type != "efs" || f.destination.efs_file_system_arn != null || local.use_platform)
    && (f.destination.type != "fsx-windows" || (f.destination.fsx_windows_arn != null && f.destination.fsx_secret_arn != null))
  } : {}

  agents_valid = { for k, a in var.datasync_agents : k => a if length(compact([a.activation_key, a.ip_address, a.arn])) == 1 }

  shares_by_type = {
    nfs    = { for k, f in local.shares : k => f if f.source.type == "nfs" }
    smb    = { for k, f in local.shares : k => f if f.source.type == "smb" }
    hdfs   = { for k, f in local.shares : k => f if f.source.type == "hdfs" }
    object = { for k, f in local.shares : k => f if f.source.type == "object-storage" }
  }

  dest_s3         = { for k, f in local.shares : k => f if f.destination.type == "s3" }
  dest_s3_create  = { for k, f in local.dest_s3 : k => f if f.destination.s3_bucket == null }
  dest_efs        = { for k, f in local.shares : k => f if f.destination.type == "efs" }
  dest_efs_plat   = { for k, f in local.dest_efs : k => f if f.destination.efs_file_system_arn == null }
  dest_fsx        = { for k, f in local.shares : k => f if f.destination.type == "fsx-windows" }
  share_secrets   = { for k, f in local.shares : k => f.source.secret_arn if f.source.secret_arn != null }
  fsx_secrets     = { for k, f in local.dest_fsx : k => f.destination.fsx_secret_arn }
  agents_create   = local.has.files ? { for k, a in local.agents_valid : k => a if a.arn == null } : {}
  private_link    = local.has.files && local.s.datasync_private_link
  first_subnet_id = try(local.subnet_ids[0], null)
}

# --------------------------------------------
# Network
# --------------------------------------------
resource "aws_security_group" "datasync" {
  count       = local.has.files ? 1 : 0
  name        = "${local.prefix}-datasync"
  description = "DataSync access to EFS / FSx and the agent PrivateLink endpoint"
  vpc_id      = local.vpc_id
  tags        = merge(local.tags, { Name = "${local.prefix}-datasync" })
}

resource "aws_vpc_security_group_egress_rule" "datasync_vpc" {
  count             = local.has.files ? 1 : 0
  security_group_id = aws_security_group.datasync[0].id
  description       = "EFS / FSx inside the VPC"
  ip_protocol       = "-1"
  cidr_ipv4         = local.vpc_cidr
}

# Agents talk to DataSync over 443 and 1024-1064 when using PrivateLink.
resource "aws_vpc_security_group_ingress_rule" "datasync_agents" {
  for_each = local.private_link ? { for pair in setproduct(var.onprem_cidrs, ["443", "1024-1064"]) : "${pair[0]}|${pair[1]}" => pair } : {}

  security_group_id = aws_security_group.datasync[0].id
  description       = "DataSync agents (PrivateLink) from on-prem"
  ip_protocol       = "tcp"
  from_port         = tonumber(split("-", each.value[1])[0])
  to_port           = tonumber(element(split("-", each.value[1]), length(split("-", each.value[1])) - 1))
  cidr_ipv4         = each.value[0]
}

resource "aws_vpc_endpoint" "datasync" {
  count               = local.private_link ? 1 : 0
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${local.region}.datasync"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [local.first_subnet_id]
  security_group_ids  = [aws_security_group.datasync[0].id]
  private_dns_enabled = false
  tags                = merge(local.tags, { Name = "${local.prefix}-datasync" })
}

data "aws_network_interface" "datasync_endpoint" {
  count = local.private_link ? 1 : 0
  id    = tolist(aws_vpc_endpoint.datasync[0].network_interface_ids)[0]
}

# --------------------------------------------
# Agents
# --------------------------------------------
resource "aws_datasync_agent" "main" {
  for_each = local.agents_create

  name           = "${local.prefix}-${each.key}"
  activation_key = each.value.activation_key
  ip_address     = each.value.ip_address

  vpc_endpoint_id = local.private_link ? aws_vpc_endpoint.datasync[0].id : null
  # With an activation key the endpoint is chosen on the agent console (baked into the key);
  # with ip_address Terraform requests the key over PrivateLink itself.
  private_link_endpoint = local.private_link && each.value.activation_key == null ? data.aws_network_interface.datasync_endpoint[0].private_ip : null
  subnet_arns           = local.private_link ? ["arn:${local.partition}:ec2:${local.region}:${local.account_id}:subnet/${local.first_subnet_id}"] : null
  security_group_arns   = local.private_link ? [aws_security_group.datasync[0].arn] : null

  tags = merge(local.tags, { Name = "${local.prefix}-${each.key}" })
}

locals {
  agent_arn = merge(
    { for k, a in local.agents_valid : k => a.arn if a.arn != null },
    { for k, a in aws_datasync_agent.main : k => a.arn },
  )
}

# --------------------------------------------
# Credentials (Secrets Manager -> DataSync)
# --------------------------------------------
data "aws_secretsmanager_secret_version" "share" {
  for_each  = local.share_secrets
  secret_id = each.value
}

data "aws_secretsmanager_secret_version" "fsx" {
  for_each  = local.fsx_secrets
  secret_id = each.value
}

locals {
  share_cred = { for k, v in data.aws_secretsmanager_secret_version.share : k => jsondecode(v.secret_string) }
  fsx_cred   = { for k, v in data.aws_secretsmanager_secret_version.fsx : k => jsondecode(v.secret_string) }
}

# --------------------------------------------
# Source locations
# --------------------------------------------
resource "aws_datasync_location_nfs" "source" {
  for_each        = local.shares_by_type.nfs
  server_hostname = each.value.source.host
  subdirectory    = each.value.source.path

  on_prem_config {
    agent_arns = [local.agent_arn[each.value.source.agent]]
  }

  mount_options {
    version = each.value.source.nfs_version
  }

  tags = merge(local.tags, { Share = each.key })
}

resource "aws_datasync_location_smb" "source" {
  for_each        = local.shares_by_type.smb
  server_hostname = each.value.source.host
  subdirectory    = each.value.source.path
  domain          = each.value.source.smb_domain
  user            = local.share_cred[each.key].username
  password        = local.share_cred[each.key].password
  agent_arns      = [local.agent_arn[each.value.source.agent]]

  mount_options {
    version = each.value.source.smb_version
  }

  tags = merge(local.tags, { Share = each.key })
}

resource "aws_datasync_location_hdfs" "source" {
  for_each            = local.shares_by_type.hdfs
  agent_arns          = [local.agent_arn[each.value.source.agent]]
  subdirectory        = each.value.source.path
  authentication_type = "SIMPLE"
  simple_user         = each.value.source.hdfs_simple_user

  dynamic "name_node" {
    for_each = each.value.source.hdfs_name_nodes
    content {
      hostname = name_node.value.host
      port     = name_node.value.port
    }
  }

  tags = merge(local.tags, { Share = each.key })
}

resource "aws_datasync_location_object_storage" "source" {
  for_each        = local.shares_by_type.object
  agent_arns      = [local.agent_arn[each.value.source.agent]]
  server_hostname = each.value.source.host
  bucket_name     = trimprefix(each.value.source.path, "/")
  server_port     = each.value.source.object_port
  server_protocol = each.value.source.object_protocol
  access_key      = local.share_cred[each.key].access_key
  secret_key      = local.share_cred[each.key].secret_key

  tags = merge(local.tags, { Share = each.key })
}

locals {
  source_location_arn = merge(
    { for k, l in aws_datasync_location_nfs.source : k => l.arn },
    { for k, l in aws_datasync_location_smb.source : k => l.arn },
    { for k, l in aws_datasync_location_hdfs.source : k => l.arn },
    { for k, l in aws_datasync_location_object_storage.source : k => l.arn },
  )
}

# --------------------------------------------
# Destinations: S3 (existing or created here)
# --------------------------------------------
resource "aws_s3_bucket" "dest" {
  for_each = local.dest_s3_create
  bucket   = "${local.prefix}-${each.key}-${local.account_id}"
  tags     = merge(local.tags, { Share = each.key })
}

resource "aws_s3_bucket_public_access_block" "dest" {
  for_each                = aws_s3_bucket.dest
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "dest" {
  for_each = aws_s3_bucket.dest
  bucket   = each.value.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "dest" {
  for_each = aws_s3_bucket.dest
  bucket   = each.value.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dest" {
  for_each = aws_s3_bucket.dest
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = local.kms_key_arn
    }
    bucket_key_enabled = local.kms_key_arn != null
  }
}

resource "aws_s3_bucket_policy" "dest" {
  for_each = aws_s3_bucket.dest
  bucket   = each.value.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [each.value.arn, "${each.value.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.dest]
}

locals {
  dest_bucket_name = merge(
    { for k, f in local.dest_s3 : k => f.destination.s3_bucket if f.destination.s3_bucket != null },
    { for k, b in aws_s3_bucket.dest : k => b.bucket },
  )
}

resource "aws_iam_role" "datasync_s3" {
  count = length(local.dest_s3) > 0 ? 1 : 0
  name  = "${local.prefix}-datasync-s3"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "datasync.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "datasync_s3" {
  count = length(aws_iam_role.datasync_s3)
  name  = "write-destination-buckets"
  role  = aws_iam_role.datasync_s3[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect   = "Allow"
          Action   = ["s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"]
          Resource = [for b in values(local.dest_bucket_name) : "arn:${local.partition}:s3:::${b}"]
        },
        {
          Effect = "Allow"
          Action = [
            "s3:AbortMultipartUpload", "s3:DeleteObject", "s3:GetObject", "s3:ListMultipartUploadParts",
            "s3:PutObject", "s3:GetObjectTagging", "s3:PutObjectTagging",
          ]
          Resource = [for b in values(local.dest_bucket_name) : "arn:${local.partition}:s3:::${b}/*"]
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

resource "aws_datasync_location_s3" "dest" {
  for_each         = local.dest_s3
  s3_bucket_arn    = "arn:${local.partition}:s3:::${local.dest_bucket_name[each.key]}"
  subdirectory     = each.value.destination.path
  s3_storage_class = each.value.destination.s3_storage_class

  s3_config {
    bucket_access_role_arn = aws_iam_role.datasync_s3[0].arn
  }

  tags = merge(local.tags, { Share = each.key })

  depends_on = [aws_iam_role_policy.datasync_s3, aws_s3_bucket_policy.dest]
}

# --------------------------------------------
# Destinations: EFS (explicit, or the platform module's shared EFS)
# --------------------------------------------
data "aws_efs_file_system" "platform" {
  count = length(local.dest_efs_plat) > 0 ? 1 : 0
  tags  = { Name = "${local.platform}-shared" }
}

data "aws_security_group" "platform_efs" {
  count  = length(local.dest_efs_plat) > 0 ? 1 : 0
  name   = "${local.platform}-efs"
  vpc_id = local.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "platform_efs_from_datasync" {
  count                        = length(local.dest_efs_plat) > 0 ? 1 : 0
  security_group_id            = data.aws_security_group.platform_efs[0].id
  description                  = "DataSync migration; removed when the migration stack is destroyed"
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049
  referenced_security_group_id = aws_security_group.datasync[0].id
  tags                         = local.tags
}

resource "aws_datasync_location_efs" "dest" {
  for_each              = local.dest_efs
  efs_file_system_arn   = coalesce(each.value.destination.efs_file_system_arn, try(data.aws_efs_file_system.platform[0].arn, null))
  subdirectory          = each.value.destination.path
  in_transit_encryption = "TLS1_2"

  ec2_config {
    subnet_arn          = "arn:${local.partition}:ec2:${local.region}:${local.account_id}:subnet/${local.first_subnet_id}"
    security_group_arns = [aws_security_group.datasync[0].arn]
  }

  tags = merge(local.tags, { Share = each.key })

  depends_on = [aws_vpc_security_group_ingress_rule.platform_efs_from_datasync]
}

# --------------------------------------------
# Destinations: FSx for Windows File Server
# --------------------------------------------
resource "aws_datasync_location_fsx_windows_file_system" "dest" {
  for_each            = local.dest_fsx
  fsx_filesystem_arn  = each.value.destination.fsx_windows_arn
  subdirectory        = each.value.destination.path
  domain              = each.value.destination.fsx_domain
  user                = local.fsx_cred[each.key].username
  password            = local.fsx_cred[each.key].password
  security_group_arns = [aws_security_group.datasync[0].arn]

  tags = merge(local.tags, { Share = each.key })
}

locals {
  dest_location_arn = merge(
    { for k, l in aws_datasync_location_s3.dest : k => l.arn },
    { for k, l in aws_datasync_location_efs.dest : k => l.arn },
    { for k, l in aws_datasync_location_fsx_windows_file_system.dest : k => l.arn },
  )
}

# --------------------------------------------
# Tasks + logs + alerts
# --------------------------------------------
resource "aws_cloudwatch_log_group" "datasync" {
  count             = local.has.files ? 1 : 0
  name              = "/aws/datasync/${local.prefix}"
  retention_in_days = local.s.log_retention
  kms_key_id        = local.kms_key_arn
  tags              = local.tags
}

resource "aws_cloudwatch_log_resource_policy" "datasync" {
  count       = local.has.files ? 1 : 0
  policy_name = "${local.prefix}-datasync"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "datasync.amazonaws.com" }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = "${aws_cloudwatch_log_group.datasync[0].arn}:*"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
}

resource "aws_datasync_task" "main" {
  for_each = local.shares

  name                     = "${local.prefix}-${each.key}"
  source_location_arn      = local.source_location_arn[each.key]
  destination_location_arn = local.dest_location_arn[each.key]
  cloudwatch_log_group_arn = aws_cloudwatch_log_group.datasync[0].arn

  options {
    bytes_per_second       = each.value.bandwidth_mbps == null ? -1 : each.value.bandwidth_mbps * 125000
    verify_mode            = each.value.verify
    preserve_deleted_files = each.value.preserve_deleted ? "PRESERVE" : "REMOVE"
    transfer_mode          = "CHANGED"
    log_level              = var.profile == "production" ? "TRANSFER" : "BASIC"
    # SMB and object storage carry no POSIX metadata.
    posix_permissions = contains(["smb", "object-storage"], each.value.source.type) ? "NONE" : null
    uid               = contains(["smb", "object-storage"], each.value.source.type) ? "NONE" : null
    gid               = contains(["smb", "object-storage"], each.value.source.type) ? "NONE" : null
  }

  dynamic "excludes" {
    for_each = length(each.value.excludes) > 0 ? [1] : []
    content {
      filter_type = "SIMPLE_PATTERN"
      value       = join("|", each.value.excludes)
    }
  }

  dynamic "schedule" {
    for_each = each.value.schedule != null ? [1] : []
    content {
      schedule_expression = each.value.schedule
    }
  }

  tags = merge(local.tags, { Share = each.key })

  depends_on = [aws_cloudwatch_log_resource_policy.datasync]
}

resource "aws_cloudwatch_event_rule" "datasync" {
  count       = local.has.files ? 1 : 0
  name        = "${local.prefix}-datasync-events"
  description = "DataSync task execution state changes for ${local.prefix}"

  event_pattern = jsonencode({
    source    = ["aws.datasync"]
    resources = [for t in aws_datasync_task.main : { prefix = t.arn }]
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "datasync" {
  count = length(aws_cloudwatch_event_rule.datasync)
  rule  = aws_cloudwatch_event_rule.datasync[0].name
  arn   = aws_sns_topic.alerts.arn
}
