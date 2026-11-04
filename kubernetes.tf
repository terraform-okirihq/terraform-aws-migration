# ============================================
# KUBERNETES -> EKS (Velero)
# ============================================
# Velero on the on-prem cluster backs up namespaces (manifests + volume data via file-system backup) to S3;
# Velero on EKS restores them. This module creates the bucket and the AWS identity for both sides.

locals {
  k8s_on         = local.has.kubernetes
  k8s_target     = local.k8s_on ? coalesce(var.kubernetes.target_cluster_name, local.use_platform ? local.platform : null, "unset") : null
  k8s_ready      = local.k8s_on && local.k8s_target != "unset" && (var.kubernetes.source_auth != "roles-anywhere" || var.onprem_ca_certificate_pem != null)
  velero_bucket  = "${local.prefix}-velero-${local.account_id}"
  velero_ns      = "velero"
  velero_sa      = "velero"
  velero_plugins = "velero/velero-plugin-for-aws:${var.kubernetes.velero_plugin_version}"
}

# --------------------------------------------
# Backup bucket
# --------------------------------------------
resource "aws_s3_bucket" "velero" {
  count         = local.k8s_ready ? 1 : 0
  bucket        = local.velero_bucket
  force_destroy = true # holds only migration backups, which expire anyway
  tags          = merge(local.tags, { Purpose = "Velero migration backups" })
}

resource "aws_s3_bucket_public_access_block" "velero" {
  count                   = length(aws_s3_bucket.velero)
  bucket                  = aws_s3_bucket.velero[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "velero" {
  count  = length(aws_s3_bucket.velero)
  bucket = aws_s3_bucket.velero[0].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "velero" {
  count  = length(aws_s3_bucket.velero)
  bucket = aws_s3_bucket.velero[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = local.kms_key_arn
    }
    bucket_key_enabled = local.kms_key_arn != null
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "velero" {
  count  = length(aws_s3_bucket.velero)
  bucket = aws_s3_bucket.velero[0].id

  rule {
    id     = "expire-backups"
    status = "Enabled"
    filter {}
    expiration {
      days = var.kubernetes.backup_retention_days
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "velero" {
  count  = length(aws_s3_bucket.velero)
  bucket = aws_s3_bucket.velero[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.velero[0].arn, "${aws_s3_bucket.velero[0].arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.velero]
}

# --------------------------------------------
# Velero permissions (same for both clusters)
# --------------------------------------------
resource "aws_iam_policy" "velero" {
  count = local.k8s_ready ? 1 : 0
  name  = "${local.prefix}-velero"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid      = "Snapshots"
          Effect   = "Allow"
          Action   = ["ec2:DescribeVolumes", "ec2:DescribeSnapshots", "ec2:CreateTags", "ec2:CreateVolume", "ec2:CreateSnapshot", "ec2:DeleteSnapshot"]
          Resource = "*"
        },
        {
          Sid      = "BackupObjects"
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:DeleteObject", "s3:PutObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
          Resource = "${aws_s3_bucket.velero[0].arn}/*"
        },
        {
          Sid      = "BackupBucket"
          Effect   = "Allow"
          Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
          Resource = aws_s3_bucket.velero[0].arn
        }
      ],
      [for x in [{
        Sid      = "BackupKey"
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = local.kms_key_arn
      }] : x if local.kms_key_arn != null]
    )
  })

  tags = local.tags
}

# --------------------------------------------
# Target (EKS): Pod Identity or IRSA, no keys
# --------------------------------------------
data "aws_eks_cluster" "target" {
  count = local.k8s_ready && var.kubernetes.target_auth == "irsa" ? 1 : 0
  name  = local.k8s_target
}

data "aws_iam_openid_connect_provider" "target" {
  count = length(data.aws_eks_cluster.target)
  url   = data.aws_eks_cluster.target[0].identity[0].oidc[0].issuer
}

locals {
  k8s_issuer = try(trimprefix(data.aws_eks_cluster.target[0].identity[0].oidc[0].issuer, "https://"), "")
}

resource "aws_iam_role" "velero_target" {
  count = local.k8s_ready ? 1 : 0
  name  = "${local.prefix}-velero-eks"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [for s in [{
        Effect    = "Allow"
        Principal = { Service = "pods.eks.amazonaws.com" }
        Action    = ["sts:AssumeRole", "sts:TagSession"]
      }] : s if var.kubernetes.target_auth == "pod-identity"],
      [for s in [{
        Effect    = "Allow"
        Principal = { Federated = try(data.aws_iam_openid_connect_provider.target[0].arn, "") }
        Action    = ["sts:AssumeRoleWithWebIdentity"]
        Condition = {
          StringEquals = {
            "${local.k8s_issuer}:sub" = "system:serviceaccount:${local.velero_ns}:${local.velero_sa}"
            "${local.k8s_issuer}:aud" = "sts.amazonaws.com"
          }
        }
      }] : s if var.kubernetes.target_auth == "irsa"]
    )
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "velero_target" {
  count      = length(aws_iam_role.velero_target)
  role       = aws_iam_role.velero_target[0].name
  policy_arn = aws_iam_policy.velero[0].arn
}

resource "aws_eks_pod_identity_association" "velero" {
  count           = local.k8s_ready && var.kubernetes.target_auth == "pod-identity" ? 1 : 0
  cluster_name    = local.k8s_target
  namespace       = local.velero_ns
  service_account = local.velero_sa
  role_arn        = aws_iam_role.velero_target[0].arn
  tags            = local.tags
}

# --------------------------------------------
# Source (on-prem cluster): IAM user (you create the key; never in state) or Roles Anywhere
# --------------------------------------------
resource "aws_iam_user" "velero_source" {
  count         = local.k8s_ready && var.kubernetes.source_auth == "iam-user" ? 1 : 0
  name          = "${local.prefix}-velero-onprem"
  force_destroy = true # deletes the access key you created when this stack is destroyed
  tags          = merge(local.tags, { Purpose = "Velero on the source cluster; delete after cutover" })
}

resource "aws_iam_user_policy_attachment" "velero_source" {
  count      = length(aws_iam_user.velero_source)
  user       = aws_iam_user.velero_source[0].name
  policy_arn = aws_iam_policy.velero[0].arn
}

resource "aws_iam_role" "velero_source" {
  count = local.k8s_ready && var.kubernetes.source_auth == "roles-anywhere" ? 1 : 0
  name  = "${local.prefix}-velero-onprem"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "rolesanywhere.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"]
      Condition = {
        ArnEquals    = { "aws:SourceArn" = aws_rolesanywhere_trust_anchor.onprem[0].arn }
        StringEquals = { "aws:PrincipalTag/x509Subject/CN" = "velero" }
      }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "velero_source" {
  count      = length(aws_iam_role.velero_source)
  role       = aws_iam_role.velero_source[0].name
  policy_arn = aws_iam_policy.velero[0].arn
}

resource "aws_rolesanywhere_profile" "velero" {
  count            = length(aws_iam_role.velero_source)
  name             = "${local.prefix}-velero"
  role_arns        = [aws_iam_role.velero_source[0].arn]
  duration_seconds = 3600
  enabled          = true
  tags             = local.tags
}

# --------------------------------------------
# Runbook
# --------------------------------------------
locals {
  velero_common    = "--provider aws --plugins ${local.velero_plugins} --bucket ${local.velero_bucket} --backup-location-config region=${local.region} --snapshot-location-config region=${local.region} --use-node-agent"
  velero_ns_flag   = length(var.kubernetes.namespaces) > 0 ? "--include-namespaces ${join(",", var.kubernetes.namespaces)}" : ""
  velero_irsa_flag = var.kubernetes.target_auth == "irsa" ? " --sa-annotations eks.amazonaws.com/role-arn=${try(aws_iam_role.velero_target[0].arn, "")}" : ""

  storage_class_configmap = length(var.kubernetes.storage_class_map) == 0 ? null : join("\n", concat([
    "apiVersion: v1",
    "kind: ConfigMap",
    "metadata:",
    "  name: change-storage-class-config",
    "  namespace: velero",
    "  labels:",
    "    velero.io/plugin-config: \"\"",
    "    velero.io/change-storage-class: RestoreItemAction",
    "data:",
  ], [for from, to in var.kubernetes.storage_class_map : "  ${from}: ${to}"]))

  kubernetes_summary = local.k8s_ready ? {
    bucket = local.velero_bucket
    source_cluster = compact([
      var.kubernetes.source_auth == "iam-user" ? "aws iam create-access-key --user-name ${aws_iam_user.velero_source[0].name} --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text | awk '{print \"[default]\\naws_access_key_id=\"$1\"\\naws_secret_access_key=\"$2}' > credentials-velero   # key is never in Terraform state; delete it after cutover" : "",
      var.kubernetes.source_auth == "roles-anywhere" ? "Issue a client certificate with CN=velero from your CA, and give Velero this AWS config (aws_signing_helper must be available in the Velero pod):\n[default]\ncredential_process = aws_signing_helper credential-process --certificate /credentials/velero.crt --private-key /credentials/velero.key --trust-anchor-arn ${aws_rolesanywhere_trust_anchor.onprem[0].arn} --profile-arn ${aws_rolesanywhere_profile.velero[0].arn} --role-arn ${aws_iam_role.velero_source[0].arn}" : "",
      "velero install ${local.velero_common} --default-volumes-to-fs-backup --secret-file ./credentials-velero",
      "velero backup create migrate-1 ${local.velero_ns_flag} --default-volumes-to-fs-backup --wait",
      "velero backup describe migrate-1 --details",
    ])
    target_cluster = compact([
      "aws eks update-kubeconfig --region ${local.region} --name ${local.k8s_target}",
      "velero install ${local.velero_common} --no-secret --service-account-name ${local.velero_sa}${local.velero_irsa_flag}",
      "velero backup-location set default --access-mode ReadOnly   # never write to the source's backups from EKS",
      local.storage_class_configmap != null ? "kubectl apply -f change-storage-class.yaml   # see storage_class_configmap" : "",
      "velero restore create --from-backup migrate-1 --wait",
      "velero restore describe --details",
    ])
    storage_class_configmap = local.storage_class_configmap
    notes = compact([
      var.kubernetes.target_auth == "pod-identity" ? "EKS needs the eks-pod-identity-agent add-on for Velero's credentials." : "",
      "Re-run backup + restore as often as needed; at cutover stop writes on-prem, take a final backup and restore it.",
      "Images: point workloads at ECR (migrate \"images\") before restoring if the cluster cannot reach your on-prem registry.",
    ])
  } : null
}
