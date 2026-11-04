# ============================================
# CORE
# ============================================

variable "name" {
  description = "Short project name used to prefix every resource (lowercase letters, digits, hyphens; max 12 chars)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,11}$", var.name))
    error_message = "name must be 2-12 chars: lowercase letters, digits, hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment label (e.g. dev, prod). Max 8 chars."
  type        = string
  default     = "prod"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,7}$", var.environment))
    error_message = "environment must be 2-8 lowercase letters/digits, starting with a letter."
  }
}

variable "profile" {
  description = <<-EOT
    pilot      - prove the approach on a few workloads: single-AZ DMS, small capacity, 14-day logs
    production - Multi-AZ DMS, data validation, customer-managed KMS, DataSync over PrivateLink,
                 90-day logs, alert_email required
  EOT
  type        = string
  default     = "pilot"

  validation {
    condition     = contains(["pilot", "production"], var.profile)
    error_message = "profile must be pilot or production."
  }
}

variable "migrate" {
  description = "What to migrate: databases (DMS), files (DataSync), servers (MGN), images (container registries -> ECR), kubernetes (clusters -> EKS with Velero)."
  type        = set(string)

  validation {
    condition     = length(var.migrate) > 0 && alltrue([for m in var.migrate : contains(["databases", "files", "servers", "images", "kubernetes"], m)])
    error_message = "migrate must contain one or more of: databases, files, servers, images, kubernetes."
  }
}

variable "target" {
  description = <<-EOT
    Where migrated workloads land. Either:
      { platform_name = "acme-prod" }                         -> discover the VPC/subnets created by OkiriGabriel/platform/aws
      { vpc_id = "vpc-...", subnet_ids = ["subnet-...", ...] } -> any existing VPC (private subnets, 2+ AZs for Multi-AZ)
  EOT
  type = object({
    platform_name = optional(string)
    vpc_id        = optional(string)
    subnet_ids    = optional(list(string), [])
  })
}

variable "onprem_cidrs" {
  description = "On-premises network ranges reachable over VPN / Direct Connect / Transit Gateway (sources live here)."
  type        = list(string)

  validation {
    condition     = length(var.onprem_cidrs) > 0 && alltrue([for c in var.onprem_cidrs : can(cidrhost(c, 0))])
    error_message = "onprem_cidrs must list at least one valid CIDR, e.g. [\"10.20.0.0/16\"]."
  }

  validation {
    condition     = !contains(var.onprem_cidrs, "0.0.0.0/0")
    error_message = "onprem_cidrs must be your private on-prem ranges, not 0.0.0.0/0."
  }
}

variable "alert_email" {
  description = "Email for replication / transfer failures. Required for the production profile."
  type        = string
  default     = ""
}

variable "kms_key_arn" {
  description = "Existing KMS key for DMS, logs, EBS staging disks and SNS. Null = create one (production) or use AWS-managed keys (pilot)."
  type        = string
  default     = null
}

variable "overrides" {
  description = "Override any resolved profile setting by key (see the `settings` output)."
  type        = any
  default     = {}
}

variable "tags" {
  description = "Extra tags on every resource."
  type        = map(string)
  default     = {}
}

# ============================================
# DATABASES (DMS)
# ============================================

variable "databases" {
  description = <<-EOT
    One entry per database to replicate. Credentials always come from Secrets Manager: each secret is JSON with
    username, password, host and port (the format DMS reads natively).

    source.engine: mysql | mariadb | postgres | oracle | sqlserver | db2 | sybase | mongodb
    target.engine: mysql | mariadb | postgres | aurora | aurora-postgresql | oracle | sqlserver | docdb | redshift | s3
                   (default: same engine as the source; mongodb -> docdb)
  EOT
  type = map(object({
    source = object({
      engine                      = string
      secret_arn                  = string
      database_name               = optional(string)
      ssl_mode                    = optional(string, "require") # none | require | verify-ca | verify-full
      ca_certificate_pem          = optional(string)            # needed for verify-ca / verify-full and Oracle SSL
      extra_connection_attributes = optional(string)
    })
    target = optional(object({
      engine            = optional(string)
      secret_arn        = optional(string) # required unless engine = s3
      database_name     = optional(string)
      ssl_mode          = optional(string, "require")
      platform_database = optional(bool, false) # open the platform module's RDS security group to DMS
      s3_bucket         = optional(string)      # engine = s3: existing bucket name
      s3_folder         = optional(string, "")
      s3_format         = optional(string, "parquet") # parquet | csv
    }), {})
    mode               = optional(string, "full-load-and-cdc") # full-load | cdc | full-load-and-cdc
    compute            = optional(string)                      # serverless | instance (default: serverless; sybase -> instance)
    include            = optional(list(object({ schema = string, table = optional(string, "%") })), [{ schema = "%", table = "%" }])
    exclude            = optional(list(object({ schema = string, table = optional(string, "%") })), [])
    on_existing_tables = optional(string, "keep") # keep | truncate | drop
    start              = optional(bool, false)    # start replicating on apply (default: start from the CLI after checks)
    allow_unencrypted  = optional(bool, false)    # permit ssl_mode = none for legacy sources
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.databases) : can(regex("^[a-z][a-z0-9-]{0,19}$", k))])
    error_message = "Database keys must be 1-20 lowercase letters, digits or hyphens."
  }

  validation {
    condition     = alltrue([for d in values(var.databases) : contains(["mysql", "mariadb", "postgres", "oracle", "sqlserver", "db2", "sybase", "mongodb"], d.source.engine)])
    error_message = "databases.*.source.engine must be one of: mysql, mariadb, postgres, oracle, sqlserver, db2, sybase, mongodb."
  }

  validation {
    condition     = alltrue([for d in values(var.databases) : d.target.engine == null || contains(["mysql", "mariadb", "postgres", "aurora", "aurora-postgresql", "oracle", "sqlserver", "docdb", "redshift", "s3"], d.target.engine)])
    error_message = "databases.*.target.engine must be one of: mysql, mariadb, postgres, aurora, aurora-postgresql, oracle, sqlserver, docdb, redshift, s3."
  }

  validation {
    condition     = alltrue([for d in values(var.databases) : contains(["full-load", "cdc", "full-load-and-cdc"], d.mode)])
    error_message = "databases.*.mode must be full-load, cdc or full-load-and-cdc."
  }

  validation {
    condition     = alltrue([for d in values(var.databases) : d.compute == null || contains(["serverless", "instance"], d.compute)])
    error_message = "databases.*.compute must be serverless or instance."
  }

  validation {
    condition     = alltrue([for d in values(var.databases) : contains(["keep", "truncate", "drop"], d.on_existing_tables)])
    error_message = "databases.*.on_existing_tables must be keep, truncate or drop."
  }

  validation {
    condition = alltrue(flatten([for d in values(var.databases) : [
      contains(["none", "require", "verify-ca", "verify-full"], d.source.ssl_mode),
      contains(["none", "require", "verify-ca", "verify-full"], d.target.ssl_mode),
    ]]))
    error_message = "ssl_mode must be none, require, verify-ca or verify-full."
  }

  validation {
    condition = alltrue(flatten([for d in values(var.databases) : [
      can(regex("^arn:[^:]+:secretsmanager:", d.source.secret_arn)),
      d.target.secret_arn == null || can(regex("^arn:[^:]+:secretsmanager:", d.target.secret_arn)),
    ]]))
    error_message = "secret_arn values must be Secrets Manager ARNs (credentials are never accepted in plain text)."
  }
}

# ============================================
# FILES (DataSync)
# ============================================

variable "datasync_agents" {
  description = <<-EOT
    DataSync agents (VMware / Hyper-V / KVM / EC2 appliance) that read your on-prem shares. Per agent, give ONE of:
      activation_key - from the agent's local console (recommended)
      ip_address     - Terraform fetches the key itself (needs HTTP to the agent from where you run Terraform)
      arn            - an agent you already activated
  EOT
  type = map(object({
    activation_key = optional(string)
    ip_address     = optional(string)
    arn            = optional(string)
  }))
  default = {}
}

variable "file_shares" {
  description = <<-EOT
    One entry per share to copy.
      source.type:      nfs (Linux/Unix) | smb (Windows) | hdfs | object-storage (S3-compatible: MinIO, NetApp StorageGRID,
                        Google Cloud Storage interop, ...) | s3 (another account or region, no agent) | azure-blob
      destination.type: s3 | efs | fsx-windows
    Credentials come from Secrets Manager JSON:
      SMB / FSx: { "username": "...", "password": "..." }      Object storage: { "access_key": "...", "secret_key": "..." }
      Azure Blob: { "sas_token": "..." }                        HDFS Kerberos: { "keytab_base64": "...", "krb5_conf": "..." }
  EOT
  type = map(object({
    source = object({
      type                = string
      agent               = optional(string) # key in datasync_agents (not needed for s3)
      host                = optional(string)
      path                = optional(string, "/") # export / share path, or bucket name for object-storage
      nfs_version         = optional(string, "AUTOMATIC")
      smb_domain          = optional(string)
      smb_version         = optional(string, "AUTOMATIC")
      secret_arn          = optional(string)
      object_port         = optional(number, 443)
      object_protocol     = optional(string, "HTTPS")
      hdfs_name_nodes     = optional(list(object({ host = string, port = optional(number, 8020) })), [])
      hdfs_simple_user    = optional(string)
      hdfs_auth           = optional(string, "simple")  # simple | kerberos
      kerberos_principal  = optional(string)            # e.g. hdfs/nn01.corp.local@CORP.LOCAL
      hdfs_protection     = optional(string, "PRIVACY") # Kerberos QOP: AUTHENTICATION | INTEGRITY | PRIVACY
      s3_bucket           = optional(string)            # s3 source: bucket name (cross-account: see summary for the bucket policy)
      azure_container_url = optional(string)            # azure-blob: https://<account>.blob.core.windows.net/<container>
    })
    destination = object({
      type                = string
      s3_bucket           = optional(string) # existing bucket; null = the module creates one
      s3_storage_class    = optional(string, "STANDARD")
      efs_file_system_arn = optional(string) # null + platform target = the platform's shared EFS
      fsx_windows_arn     = optional(string)
      fsx_secret_arn      = optional(string)
      fsx_domain          = optional(string)
      path                = optional(string, "/")
    })
    schedule         = optional(string)                           # e.g. "cron(0 2 * * ? *)" or "rate(12 hours)"; null = run on demand
    bandwidth_mbps   = optional(number)                           # null = unlimited
    verify           = optional(string, "ONLY_FILES_TRANSFERRED") # POINT_IN_TIME_CONSISTENT | ONLY_FILES_TRANSFERRED | NONE
    preserve_deleted = optional(bool, true)
    excludes         = optional(list(string), []) # e.g. ["*.tmp", "/cache"]
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.file_shares) : can(regex("^[a-z][a-z0-9-]{0,19}$", k))])
    error_message = "File share keys must be 1-20 lowercase letters, digits or hyphens."
  }

  validation {
    condition     = alltrue([for f in values(var.file_shares) : contains(["nfs", "smb", "hdfs", "object-storage", "s3", "azure-blob"], f.source.type)])
    error_message = "file_shares.*.source.type must be nfs, smb, hdfs, object-storage, s3 or azure-blob."
  }

  validation {
    condition     = alltrue([for f in values(var.file_shares) : contains(["simple", "kerberos"], f.source.hdfs_auth) && contains(["AUTHENTICATION", "INTEGRITY", "PRIVACY"], f.source.hdfs_protection)])
    error_message = "hdfs_auth must be simple or kerberos; hdfs_protection must be AUTHENTICATION, INTEGRITY or PRIVACY."
  }

  validation {
    condition     = alltrue([for f in values(var.file_shares) : contains(["s3", "efs", "fsx-windows"], f.destination.type)])
    error_message = "file_shares.*.destination.type must be s3, efs or fsx-windows."
  }

  validation {
    condition     = alltrue([for f in values(var.file_shares) : contains(["POINT_IN_TIME_CONSISTENT", "ONLY_FILES_TRANSFERRED", "NONE"], f.verify)])
    error_message = "file_shares.*.verify must be POINT_IN_TIME_CONSISTENT, ONLY_FILES_TRANSFERRED or NONE."
  }
}

# ============================================
# SERVERS (Application Migration Service)
# ============================================

variable "servers" {
  description = <<-EOT
    Lift-and-shift servers with AWS Application Migration Service (MGN).
    inventory: name => { os = windows | rhel | centos | rocky | alma | oracle-linux | ubuntu | debian | suse | amazon-linux }
    The module creates the AWS side (staging network, security group, encryption, installer role) and generates
    the exact install command for each server's OS.
  EOT
  type = object({
    inventory = optional(map(object({
      os        = string
      licensing = optional(string) # windows / rhel / suse: byol | aws (license included). Default aws.
    })), {})
    staging_subnet_id         = optional(string) # default: first target private subnet
    replication_instance_type = optional(string, "t3.small")
    use_private_ip            = optional(bool, true)        # replicate over VPN / Direct Connect, not the internet
    bandwidth_mbps            = optional(number, 0)         # 0 = no throttling
    automate                  = optional(bool, false)       # run the MGN setup with the AWS CLI during apply (needs bash + aws CLI)
    launch_disposition        = optional(string, "STOPPED") # STOPPED | STARTED: state of test/cutover instances at launch
    right_sizing              = optional(string, "BASIC")   # BASIC | NONE: pick the EC2 type from source CPU/RAM
  })
  default = {}

  validation {
    condition = alltrue([for s in values(var.servers.inventory) : contains(
      ["windows", "rhel", "centos", "rocky", "alma", "oracle-linux", "ubuntu", "debian", "suse", "amazon-linux"], s.os
    )])
    error_message = "servers.inventory.*.os must be one of: windows, rhel, centos, rocky, alma, oracle-linux, ubuntu, debian, suse, amazon-linux."
  }

  validation {
    condition     = contains(["STOPPED", "STARTED"], var.servers.launch_disposition) && contains(["BASIC", "NONE"], var.servers.right_sizing)
    error_message = "servers.launch_disposition must be STOPPED or STARTED; servers.right_sizing must be BASIC or NONE."
  }

  validation {
    condition     = alltrue([for s in values(var.servers.inventory) : s.licensing == null || contains(["byol", "aws"], s.licensing)])
    error_message = "servers.inventory.*.licensing must be byol or aws."
  }
}

variable "create_dms_service_roles" {
  description = "Create the account-level roles DMS requires (dms-vpc-role, dms-cloudwatch-logs-role). Set false if they already exist."
  type        = bool
  default     = true
}

# ============================================
# SHARED: on-prem identity without static keys
# ============================================

variable "onprem_ca_certificate_pem" {
  description = <<-EOT
    PEM of the certificate authority that issues certificates to on-prem systems (Velero on your cluster, Jenkins, ...).
    Enables IAM Roles Anywhere: those systems exchange a certificate for short-lived AWS credentials instead of
    using access keys. Used by kubernetes.source_auth = "roles-anywhere" and pipelines with provider = "jenkins".
  EOT
  type        = string
  default     = null
}

# ============================================
# CONTAINER IMAGES -> ECR
# ============================================

variable "images" {
  description = <<-EOT
    Bring container images into ECR (migrate must include "images").
      repositories: ECR repositories to create, e.g. ["shop/web", "shop/api"]
      pull_through: prefix => upstream. Public registries are mirrored on first pull:
                    docker-hub | quay | ghcr | gitlab | k8s | ecr-public | azure (needs registry_url).
                    Docker Hub, GHCR, GitLab and Azure need secret_arn (name must start with "ecr-pullthroughcache/").
      copy:         images from private registries (Harbor, Nexus, Artifactory, Docker registry) to copy, e.g.
                    { from = "harbor.corp.local/shop/web:1.4.2", to = "shop/web" }. Target repositories are created
                    and summary.images.copy_commands lists ready-to-run skopeo commands.
  EOT
  type = object({
    repositories = optional(list(string), [])
    pull_through = optional(map(object({
      upstream     = string
      registry_url = optional(string) # required for azure (myregistry.azurecr.io), optional override otherwise
      secret_arn   = optional(string)
    })), {})
    copy           = optional(list(object({ from = string, to = string })), [])
    immutable_tags = optional(bool) # default: true in production
    keep_images    = optional(number, 50)
  })
  default = {}

  validation {
    condition     = alltrue([for p in values(var.images.pull_through) : contains(["docker-hub", "quay", "ghcr", "gitlab", "k8s", "ecr-public", "azure"], p.upstream)])
    error_message = "images.pull_through.*.upstream must be docker-hub, quay, ghcr, gitlab, k8s, ecr-public or azure."
  }

  validation {
    condition     = alltrue([for r in concat(var.images.repositories, [for c in var.images.copy : c.to]) : can(regex("^[a-z0-9]+(?:[._-][a-z0-9]+)*(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)*$", r))])
    error_message = "Repository names must be lowercase, e.g. shop/web."
  }
}

# ============================================
# KUBERNETES -> EKS (Velero)
# ============================================

variable "kubernetes" {
  description = <<-EOT
    Move workloads from on-prem Kubernetes (OpenShift, Rancher, Tanzu, kubeadm, k3s, ...) to EKS with Velero
    (migrate must include "kubernetes"). The module creates the backup bucket and AWS access for both clusters,
    and prints the Velero install, backup and restore commands.
      target_cluster_name:  EKS cluster to restore into (default with target.platform_name: the platform's cluster)
      target_auth:          pod-identity (needs the eks-pod-identity-agent add-on) | irsa
      source_auth:          iam-user (access key created by you, never in state) | roles-anywhere (needs onprem_ca_certificate_pem)
      namespaces:           namespaces to migrate ([] = all)
      storage_class_map:    on-prem StorageClass => EKS StorageClass, e.g. { "vsphere-csi" = "gp3" }
  EOT
  type = object({
    target_cluster_name   = optional(string)
    target_auth           = optional(string, "pod-identity")
    source_auth           = optional(string, "iam-user")
    namespaces            = optional(list(string), [])
    storage_class_map     = optional(map(string), {})
    backup_retention_days = optional(number, 30)
    velero_plugin_version = optional(string, "v1.10.0") # velero/velero-plugin-for-aws tag matching your Velero version
  })
  default = {}

  validation {
    condition     = contains(["pod-identity", "irsa"], var.kubernetes.target_auth) && contains(["iam-user", "roles-anywhere"], var.kubernetes.source_auth)
    error_message = "kubernetes.target_auth must be pod-identity or irsa; kubernetes.source_auth must be iam-user or roles-anywhere."
  }
}

# ============================================
# CI/CD PIPELINES -> AWS
# ============================================

variable "pipelines" {
  description = <<-EOT
    Deploy roles for the CI/CD systems that will ship migrated apps. One entry per pipeline; no static keys anywhere.
      provider: github | gitlab | bitbucket | circleci | azure-devops | jenkins | codebuild
        github        repository = "owner/repo"                     (GitHub Actions OIDC)
        gitlab        repository = "group/project", issuer_url for self-managed GitLab (default https://gitlab.com)
        bitbucket     issuer_url, audience, subjects from Repository settings > OpenID Connect
        circleci      issuer_url = "https://oidc.circleci.com/org/<org-id>", audience = "<org-id>", subjects
        azure-devops  issuer_url = "https://vstoken.dev.azure.com/<org-id>", subjects = ["sc://<org>/<project>/<service-connection>"]
        jenkins       on-prem / any CI with a client certificate: IAM Roles Anywhere (needs onprem_ca_certificate_pem);
                      the certificate CN must equal the pipeline key
        codebuild     AWS CodeBuild project building `repository` (GitHub / GitLab / Bitbucket via a CodeConnections connection)
    Permissions are opt-in per pipeline: ECR push, ECS deploy, EKS deploy (namespace-scoped), S3 sync, extra policies.
  EOT
  type = map(object({
    provider   = string
    repository = optional(string)
    branch     = optional(string, "main")
    issuer_url = optional(string)
    audience   = optional(string)
    subjects   = optional(list(string), [])

    ecr_push           = optional(bool, true)       # this module's ECR repositories (+ ecr_repositories)
    ecr_repositories   = optional(list(string), []) # extra repository names in this account
    ecs_clusters       = optional(list(string), []) # cluster names it may deploy to
    ecs_pass_roles     = optional(list(string), []) # task / execution role ARNs it may pass
    eks_clusters       = optional(list(string), []) # cluster names it may deploy to
    eks_namespaces     = optional(list(string), []) # [] = whole cluster (edit, not admin)
    s3_buckets         = optional(list(string), []) # buckets it may sync to
    policy_arns        = optional(list(string), []) # anything else
    codebuild_repo_url = optional(string)           # codebuild: https://github.com/owner/repo (or GitLab / Bitbucket)
    codebuild_source   = optional(string, "GITHUB") # codebuild: GITHUB | GITLAB | BITBUCKET
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.pipelines) : can(regex("^[a-z][a-z0-9-]{0,24}$", k))])
    error_message = "Pipeline keys must be 1-25 lowercase letters, digits or hyphens."
  }

  validation {
    condition     = alltrue([for p in values(var.pipelines) : contains(["github", "gitlab", "bitbucket", "circleci", "azure-devops", "jenkins", "codebuild"], p.provider)])
    error_message = "pipelines.*.provider must be github, gitlab, bitbucket, circleci, azure-devops, jenkins or codebuild."
  }

  validation {
    condition     = alltrue([for p in values(var.pipelines) : contains(["GITHUB", "GITLAB", "BITBUCKET"], p.codebuild_source)])
    error_message = "pipelines.*.codebuild_source must be GITHUB, GITLAB or BITBUCKET."
  }
}

variable "create_oidc_providers" {
  description = "Create the IAM OIDC identity providers the pipelines need. Set false if they already exist in the account (they are looked up instead)."
  type        = bool
  default     = true
}
