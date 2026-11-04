# ============================================
# CONTAINER IMAGES -> ECR
# ============================================
# Repositories are destinations: they keep your images after cutover. ECR refuses to delete a repository that
# still holds images, so destroying this stack fails safely until you move them out of this state
# (terraform state rm 'module.migration.aws_ecr_repository.image["shop/web"]') or empty them.

locals {
  images_on = local.has.images
  ecr_host  = "${local.account_id}.dkr.ecr.${local.region}.amazonaws.com"
  immutable = coalesce(var.images.immutable_tags, var.profile == "production")

  upstream_url = {
    docker-hub = "registry-1.docker.io"
    quay       = "quay.io"
    ghcr       = "ghcr.io"
    gitlab     = "registry.gitlab.com"
    k8s        = "registry.k8s.io"
    ecr-public = "public.ecr.aws"
    azure      = null
  }
  upstream_needs_secret = ["docker-hub", "ghcr", "gitlab", "azure"]

  # "harbor.corp.local/shop/web:1.4.2" -> registry "harbor.corp.local", tag "1.4.2" (default "latest")
  image_copies = local.images_on ? [for c in var.images.copy : {
    from     = c.from
    to       = c.to
    registry = split("/", c.from)[0]
    tag      = length(regexall(":[^/:]+$", c.from)) > 0 ? regex(":([^/:]+)$", c.from)[0] : "latest"
  }] : []

  ecr_repositories = local.images_on ? toset(concat(var.images.repositories, [for c in local.image_copies : c.to])) : toset([])

  pull_through = local.images_on ? {
    for prefix, p in var.images.pull_through : prefix => merge(p, { url = coalesce(p.registry_url, local.upstream_url[p.upstream], "unset") })
    if(p.upstream != "azure" || p.registry_url != null) && (!contains(local.upstream_needs_secret, p.upstream) || p.secret_arn != null)
  } : {}

  ecr_lifecycle = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 14 days"
        selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 14 }
        action       = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the ${var.images.keep_images} most recent images"
        selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = var.images.keep_images }
        action       = { type = "expire" }
      }
    ]
  })
}

resource "aws_ecr_repository" "image" {
  for_each             = local.ecr_repositories
  name                 = each.value
  image_tag_mutability = local.immutable ? "IMMUTABLE" : "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = local.kms_key_arn != null ? "KMS" : "AES256"
    kms_key         = local.kms_key_arn
  }

  tags = merge(local.tags, { Lifecycle = "keep" }) # a destination, not migration tooling
}

resource "aws_ecr_lifecycle_policy" "image" {
  for_each   = aws_ecr_repository.image
  repository = each.value.name
  policy     = local.ecr_lifecycle
}

# --------------------------------------------
# Pull-through cache: public registries mirrored into ECR on first pull
# --------------------------------------------
resource "aws_ecr_pull_through_cache_rule" "upstream" {
  for_each              = local.pull_through
  ecr_repository_prefix = each.key
  upstream_registry_url = each.value.url
  credential_arn        = each.value.secret_arn
}

# Repositories created by the cache get the same scanning, encryption and lifecycle as the rest.
resource "aws_iam_role" "ecr_templates" {
  count = length(local.pull_through) > 0 && local.kms_key_arn != null ? 1 : 0
  name  = "${local.prefix}-ecr-templates"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ecr.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "ecr_templates" {
  count = length(aws_iam_role.ecr_templates)
  name  = "create-encrypted-repositories"
  role  = aws_iam_role.ecr_templates[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ecr:CreateRepository", "ecr:TagResource", "ecr:PutLifecyclePolicy"], Resource = "*" },
      { Effect = "Allow", Action = ["kms:CreateGrant", "kms:DescribeKey", "kms:RetireGrant"], Resource = local.kms_key_arn },
    ]
  })
}

resource "aws_ecr_repository_creation_template" "pull_through" {
  for_each             = local.pull_through
  prefix               = each.key
  applied_for          = ["PULL_THROUGH_CACHE"]
  description          = "Repositories mirrored from ${each.value.url}"
  image_tag_mutability = "MUTABLE" # caches must be able to refresh tags
  lifecycle_policy     = local.ecr_lifecycle
  custom_role_arn      = try(aws_iam_role.ecr_templates[0].arn, null)
  resource_tags        = local.tags

  encryption_configuration {
    encryption_type = local.kms_key_arn != null ? "KMS" : "AES256"
    kms_key         = local.kms_key_arn
  }

  depends_on = [aws_iam_role_policy.ecr_templates]
}

locals {
  images_summary = local.images_on ? {
    registry     = local.ecr_host
    repositories = { for k, r in aws_ecr_repository.image : k => r.repository_url }
    pull_through = { for k, p in local.pull_through : k => "${local.ecr_host}/${k}/<image>:<tag>  mirrors  ${p.url}/<image>:<tag>" }
    copy_commands = length(local.image_copies) == 0 ? [] : concat(
      ["aws ecr get-login-password --region ${local.region} | skopeo login --username AWS --password-stdin ${local.ecr_host}"],
      [for r in distinct([for c in local.image_copies : c.registry]) : "skopeo login ${r}"],
      [for c in local.image_copies : "skopeo copy --all docker://${c.from} docker://${local.ecr_host}/${c.to}:${c.tag}"],
    )
  } : null
}
