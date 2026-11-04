# ============================================
# CI/CD PIPELINES -> AWS
# ============================================
# One least-privilege deploy role per pipeline, for any CI system. Cloud CI uses OIDC federation; on-prem CI
# (Jenkins, TeamCity, Bamboo, ...) uses IAM Roles Anywhere with a client certificate. No static keys.

locals {
  oidc_providers = ["github", "gitlab", "bitbucket", "circleci", "azure-devops"]

  # Resolved identity per pipeline (defaults filled in for GitHub and GitLab).
  pipe = { for k, p in var.pipelines : k => merge(p, {
    issuer = (
      p.provider == "github" ? "https://token.actions.githubusercontent.com" :
      p.provider == "gitlab" ? coalesce(p.issuer_url, "https://gitlab.com") :
      contains(local.oidc_providers, p.provider) ? p.issuer_url : null
    )
    aud = (
      p.provider == "github" ? "sts.amazonaws.com" :
      p.provider == "gitlab" ? coalesce(p.audience, p.issuer_url, "https://gitlab.com") :
      p.provider == "azure-devops" ? coalesce(p.audience, "api://AzureADTokenExchange") :
      p.audience
    )
    subs = length(p.subjects) > 0 ? p.subjects : (
      p.provider == "github" && p.repository != null ? ["repo:${p.repository}:ref:refs/heads/${p.branch}"] :
      p.provider == "gitlab" && p.repository != null ? ["project_path:${p.repository}:ref_type:branch:ref:${p.branch}"] :
      []
    )
  }) }

  # Only complete definitions become resources; guardrails.tf explains anything missing.
  pipelines_ok = { for k, p in local.pipe : k => p
    if(contains(local.oidc_providers, p.provider) && p.issuer != null && p.aud != null && length(p.subs) > 0)
    || (p.provider == "jenkins" && var.onprem_ca_certificate_pem != null)
    || (p.provider == "codebuild" && p.codebuild_repo_url != null)
  }
  oidc_pipelines = { for k, p in local.pipelines_ok : k => p if contains(local.oidc_providers, p.provider) }

  # One IAM OIDC provider per issuer, trusting every audience used with it.
  oidc_issuers = { for iss in distinct([for p in values(local.oidc_pipelines) : p.issuer]) : iss => distinct([for p in values(local.oidc_pipelines) : p.aud if p.issuer == iss]) }
}

# --------------------------------------------
# Shared on-prem trust: IAM Roles Anywhere trust anchor (your CA)
# --------------------------------------------
locals {
  need_trust_anchor = var.onprem_ca_certificate_pem != null && (
    (local.k8s_on && var.kubernetes.source_auth == "roles-anywhere") || anytrue([for p in values(var.pipelines) : p.provider == "jenkins"])
  )
}

resource "aws_rolesanywhere_trust_anchor" "onprem" {
  count   = local.need_trust_anchor ? 1 : 0
  name    = "${local.prefix}-onprem-ca"
  enabled = true

  source {
    source_type = "CERTIFICATE_BUNDLE"
    source_data {
      x509_certificate_data = var.onprem_ca_certificate_pem
    }
  }

  tags = local.tags
}

# --------------------------------------------
# OIDC identity providers
# --------------------------------------------
resource "aws_iam_openid_connect_provider" "ci" {
  for_each       = var.create_oidc_providers ? local.oidc_issuers : {}
  url            = each.key
  client_id_list = each.value
  tags           = merge(local.tags, { Lifecycle = "keep" })
}

data "aws_iam_openid_connect_provider" "ci" {
  for_each = var.create_oidc_providers ? {} : local.oidc_issuers
  url      = each.key
}

locals {
  oidc_provider_arn = merge(
    { for iss, p in aws_iam_openid_connect_provider.ci : iss => p.arn },
    { for iss, p in data.aws_iam_openid_connect_provider.ci : iss => p.arn },
  )
}

# --------------------------------------------
# Deploy roles
# --------------------------------------------
resource "aws_iam_role" "ci" {
  for_each             = local.pipelines_ok
  name                 = substr("${local.prefix}-ci-${each.key}", 0, 64)
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [for s in [{
        Effect    = "Allow"
        Principal = { Federated = lookup(local.oidc_provider_arn, coalesce(each.value.issuer, "-"), "") }
        Action    = ["sts:AssumeRoleWithWebIdentity"]
        Condition = {
          StringEquals = { "${trimprefix(coalesce(each.value.issuer, "-"), "https://")}:aud" = each.value.aud }
          StringLike   = { "${trimprefix(coalesce(each.value.issuer, "-"), "https://")}:sub" = each.value.subs }
        }
      }] : s if contains(local.oidc_providers, each.value.provider)],
      [for s in [{
        Effect    = "Allow"
        Principal = { Service = "rolesanywhere.amazonaws.com" }
        Action    = ["sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"]
        Condition = {
          ArnEquals    = { "aws:SourceArn" = try(aws_rolesanywhere_trust_anchor.onprem[0].arn, "") }
          StringEquals = { "aws:PrincipalTag/x509Subject/CN" = each.key }
        }
      }] : s if each.value.provider == "jenkins"],
      [for s in [{
        Effect    = "Allow"
        Principal = { Service = "codebuild.amazonaws.com" }
        Action    = ["sts:AssumeRole"]
        Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
      }] : s if each.value.provider == "codebuild"]
    )
  })

  tags = merge(local.tags, { Lifecycle = "keep", Pipeline = each.key })
}

locals {
  ci_ecr_arns = { for k, p in local.pipelines_ok : k => (concat(
    p.ecr_push ? [for r in aws_ecr_repository.image : r.arn] : [],
    [for n in p.ecr_repositories : "arn:${local.partition}:ecr:${local.region}:${local.account_id}:repository/${n}"],
  )) }

  ci_statements = { for k, p in local.pipelines_ok : k => concat(
    (p.ecr_push && length(local.ecr_repositories) > 0) || length(p.ecr_repositories) > 0 ? [
      { Sid = "EcrLogin", Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = ["*"] },
      {
        Sid    = "EcrPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:CompleteLayerUpload", "ecr:DescribeImages",
          "ecr:GetDownloadUrlForLayer", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart",
        ]
        Resource = local.ci_ecr_arns[k]
      },
    ] : [],
    length(p.ecs_clusters) > 0 ? [
      { Sid = "EcsTaskDefinitions", Effect = "Allow", Action = ["ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition"], Resource = ["*"] },
      {
        Sid      = "EcsDeploy"
        Effect   = "Allow"
        Action   = ["ecs:UpdateService", "ecs:DescribeServices"]
        Resource = [for c in p.ecs_clusters : "arn:${local.partition}:ecs:${local.region}:${local.account_id}:service/${c}/*"]
      },
    ] : [],
    length(p.ecs_pass_roles) > 0 ? [{
      Sid       = "PassTaskRoles"
      Effect    = "Allow"
      Action    = ["iam:PassRole"]
      Resource  = p.ecs_pass_roles
      Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } }
    }] : [],
    length(p.eks_clusters) > 0 ? [{
      Sid      = "EksDescribe"
      Effect   = "Allow"
      Action   = ["eks:DescribeCluster"]
      Resource = [for c in p.eks_clusters : "arn:${local.partition}:eks:${local.region}:${local.account_id}:cluster/${c}"]
    }] : [],
    length(p.s3_buckets) > 0 ? [
      { Sid = "S3List", Effect = "Allow", Action = ["s3:ListBucket", "s3:GetBucketLocation"], Resource = [for b in p.s3_buckets : "arn:${local.partition}:s3:::${b}"] },
      { Sid = "S3Sync", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = [for b in p.s3_buckets : "arn:${local.partition}:s3:::${b}/*"] },
    ] : [],
    p.provider == "codebuild" ? [
      {
        Sid      = "BuildLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/codebuild/${local.prefix}-${k}*"]
      },
      {
        Sid      = "UseConnection"
        Effect   = "Allow"
        Action   = ["codeconnections:UseConnection", "codeconnections:GetConnectionToken", "codestar-connections:UseConnection", "codestar-connections:GetConnectionToken"]
        Resource = [aws_codeconnections_connection.ci[k].arn]
      },
    ] : [],
  ) }
}

locals {
  # Decided from inputs (known at plan time), not from resource ARNs.
  ci_has_policy = { for k, p in local.pipelines_ok : k => (
    (p.ecr_push && length(local.ecr_repositories) > 0) || length(p.ecr_repositories) > 0 || length(p.ecs_clusters) > 0 ||
    length(p.ecs_pass_roles) > 0 || length(p.eks_clusters) > 0 || length(p.s3_buckets) > 0 || p.provider == "codebuild"
  ) }
}

resource "aws_iam_role_policy" "ci" {
  for_each = { for k, s in local.ci_statements : k => s if local.ci_has_policy[k] }
  name     = "deploy"
  role     = aws_iam_role.ci[each.key].id
  policy   = jsonencode({ Version = "2012-10-17", Statement = each.value })
}

resource "aws_iam_role_policy_attachment" "ci_extra" {
  for_each   = { for pair in flatten([for k, p in local.pipelines_ok : [for a in p.policy_arns : { k = k, arn = a }]]) : "${pair.k}|${pair.arn}" => pair }
  role       = aws_iam_role.ci[each.value.k].name
  policy_arn = each.value.arn
}

# EKS: namespace-scoped edit (or cluster-wide edit when no namespaces), never cluster-admin.
locals {
  ci_eks = { for pair in flatten([for k, p in local.pipelines_ok : [for c in p.eks_clusters : { k = k, cluster = c, namespaces = p.eks_namespaces }]]) : "${pair.k}|${pair.cluster}" => pair }
}

resource "aws_eks_access_entry" "ci" {
  for_each      = local.ci_eks
  cluster_name  = each.value.cluster
  principal_arn = aws_iam_role.ci[each.value.k].arn
  type          = "STANDARD"
  tags          = local.tags
}

resource "aws_eks_access_policy_association" "ci" {
  for_each      = local.ci_eks
  cluster_name  = each.value.cluster
  principal_arn = aws_iam_role.ci[each.value.k].arn
  policy_arn    = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = length(each.value.namespaces) > 0 ? "namespace" : "cluster"
    namespaces = length(each.value.namespaces) > 0 ? each.value.namespaces : null
  }

  depends_on = [aws_eks_access_entry.ci]
}

# --------------------------------------------
# AWS CodeBuild (provider = "codebuild")
# --------------------------------------------
locals {
  codebuild_pipelines = { for k, p in local.pipelines_ok : k => p if p.provider == "codebuild" }
  connection_provider = { GITHUB = "GitHub", GITLAB = "GitLab", BITBUCKET = "Bitbucket" }
}

resource "aws_codeconnections_connection" "ci" {
  for_each      = local.codebuild_pipelines
  name          = substr("${var.name}-${each.key}", 0, 32)
  provider_type = local.connection_provider[each.value.codebuild_source]
  tags          = local.tags
}

resource "aws_codebuild_project" "ci" {
  for_each      = local.codebuild_pipelines
  name          = "${local.prefix}-${each.key}"
  description   = "Build and deploy ${each.value.codebuild_repo_url}"
  service_role  = aws_iam_role.ci[each.key].arn
  build_timeout = 60

  source {
    type     = each.value.codebuild_source
    location = each.value.codebuild_repo_url
    auth {
      type     = "CODECONNECTIONS"
      resource = aws_codeconnections_connection.ci[each.key].arn
    }
    # buildspec.yml from the repository root
  }

  source_version = each.value.branch

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true # docker build
  }

  logs_config {
    cloudwatch_logs {
      group_name = "/aws/codebuild/${local.prefix}-${each.key}"
    }
  }

  encryption_key = local.kms_key_arn
  tags           = merge(local.tags, { Lifecycle = "keep" })

  depends_on = [aws_iam_role_policy.ci]
}

# --------------------------------------------
# How to use each role from its CI system
# --------------------------------------------
locals {
  ci_usage = { for k, p in local.pipelines_ok : k => {
    provider = p.provider
    role_arn = aws_iam_role.ci[k].arn
    setup = (
      p.provider == "github" ? "uses: aws-actions/configure-aws-credentials@v4 with role-to-assume: ${aws_iam_role.ci[k].arn}, aws-region: ${local.region} (job needs permissions: id-token: write)" :
      p.provider == "gitlab" ? "id_tokens: { AWS_TOKEN: { aud: ${p.aud} } } then: aws sts assume-role-with-web-identity --role-arn ${aws_iam_role.ci[k].arn} --role-session-name gitlab-$CI_JOB_ID --web-identity-token $AWS_TOKEN" :
      p.provider == "bitbucket" ? "step: oidc: true; env AWS_ROLE_ARN=${aws_iam_role.ci[k].arn}, AWS_WEB_IDENTITY_TOKEN_FILE=$(pwd)/web-identity-token (echo $BITBUCKET_STEP_OIDC_TOKEN > web-identity-token)" :
      p.provider == "circleci" ? "circleci/aws-cli orb: aws-cli/setup with role_arn: ${aws_iam_role.ci[k].arn} (uses $CIRCLE_OIDC_TOKEN)" :
      p.provider == "azure-devops" ? "AWS Toolkit for Azure DevOps service connection with 'Use OIDC' and role ${aws_iam_role.ci[k].arn}" :
      p.provider == "jenkins" ? "Client certificate with CN=${k}; ~/.aws/config: credential_process = aws_signing_helper credential-process --certificate ci.crt --private-key ci.key --trust-anchor-arn ${aws_rolesanywhere_trust_anchor.onprem[0].arn} --profile-arn ${aws_rolesanywhere_profile.ci[k].arn} --role-arn ${aws_iam_role.ci[k].arn}" :
      "Approve the pending connection in the AWS console (Developer Tools > Settings > Connections > ${aws_codeconnections_connection.ci[k].name}), then add a buildspec.yml and start builds or add a webhook trigger."
    )
  } }
}

resource "aws_rolesanywhere_profile" "ci" {
  for_each         = { for k, p in local.pipelines_ok : k => p if p.provider == "jenkins" }
  name             = "${local.prefix}-ci-${each.key}"
  role_arns        = [aws_iam_role.ci[each.key].arn]
  duration_seconds = 3600
  enabled          = true
  tags             = local.tags
}
