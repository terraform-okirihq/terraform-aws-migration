# ============================================
# PLAN-TIME GUARDRAILS
# ============================================
# Refuse unsafe or incomplete configurations before anything is created; each message says what to change.

locals {
  share_needs_secret = { for k, f in var.file_shares : k => contains(["smb", "object-storage", "azure-blob"], f.source.type) || (f.source.type == "hdfs" && f.source.hdfs_auth == "kerberos") }
  share_needs_agent  = { for k, f in var.file_shares : k => f.source.type != "s3" }
}

resource "terraform_data" "guardrails" {
  input = var.profile

  lifecycle {
    # ---------------------------------------------------------- target
    precondition {
      condition     = (try(var.target.platform_name, null) != null) != (try(var.target.vpc_id, null) != null)
      error_message = "Set exactly one of target.platform_name (to reuse the platform module's VPC) or target.vpc_id + target.subnet_ids."
    }

    precondition {
      condition     = try(var.target.platform_name, null) != null || length(var.target.subnet_ids) >= 1
      error_message = "target.vpc_id needs target.subnet_ids (private subnets; 2+ in different AZs for Multi-AZ)."
    }

    precondition {
      condition     = !local.has.databases || length(local.subnet_ids) >= 2
      error_message = "DMS needs at least two private subnets in different Availability Zones (an AWS requirement for replication subnet groups). Add a second subnet to target.subnet_ids."
    }

    # ---------------------------------------------------------- what to migrate
    precondition {
      condition     = !local.has.databases || length(var.databases) > 0
      error_message = "migrate includes \"databases\" but databases is empty."
    }

    precondition {
      condition     = !local.has.files || length(var.file_shares) > 0
      error_message = "migrate includes \"files\" but file_shares is empty."
    }

    precondition {
      condition     = !(length(var.databases) > 0 && !local.has.databases) && !(length(var.file_shares) > 0 && !local.has.files)
      error_message = "databases / file_shares are set but not listed in migrate. Add \"databases\" / \"files\" to migrate (or remove them)."
    }

    # ---------------------------------------------------------- profile
    precondition {
      condition     = !local.s.require_alert_email || var.alert_email != ""
      error_message = "Profile 'production' requires alert_email so failed replications and transfers reach a human."
    }

    # ---------------------------------------------------------- databases
    precondition {
      condition     = alltrue([for d in values(local.dbs_all) : d.target_engine != "unset"])
      error_message = "db2 and sybase sources need an explicit target.engine (for example postgres or aurora-postgresql)."
    }

    precondition {
      condition     = alltrue([for d in values(local.dbs_all) : d.target_engine == "s3" ? d.target.s3_bucket != null : d.target.secret_arn != null])
      error_message = "Each database target needs target.secret_arn (JSON: username, password, host, port), or target.s3_bucket when target.engine = s3."
    }

    precondition {
      condition     = alltrue([for d in values(local.dbs_all) : d.allow_unenc || (d.source.ssl_mode != "none" && (d.target_engine == "s3" || d.target.ssl_mode != "none"))])
      error_message = "ssl_mode = none sends database traffic unencrypted. Use require/verify-*, or set allow_unencrypted = true for that database if the source cannot do TLS."
    }

    precondition {
      condition     = alltrue([for d in values(local.dbs_all) : !contains(["verify-ca", "verify-full"], d.source.ssl_mode) || d.source.ca_certificate_pem != null])
      error_message = "source.ssl_mode verify-ca / verify-full needs source.ca_certificate_pem (the CA that signed the source database's certificate)."
    }

    precondition {
      condition = alltrue([for d in values(local.dbs_all) :
        d.source.engine == "mongodb" ? contains(["docdb", "s3"], d.target_engine) : d.target_engine != "docdb"
      ])
      error_message = "MongoDB sources must go to docdb or s3, and relational sources cannot target docdb."
    }

    precondition {
      condition     = alltrue([for d in values(local.dbs_all) : !d.target.platform_database || local.use_platform])
      error_message = "target.platform_database = true needs target.platform_name."
    }

    # ---------------------------------------------------------- files
    precondition {
      condition     = alltrue([for k, f in var.file_shares : !local.share_needs_agent[k] || contains(keys(var.datasync_agents), coalesce(f.source.agent, "-"))])
      error_message = "Every file_shares.*.source.agent must name an entry in datasync_agents (all source types except s3 need an agent)."
    }

    precondition {
      condition = alltrue([for a in values(var.datasync_agents) :
        length(compact([a.activation_key, a.ip_address, a.arn])) == 1
      ])
      error_message = "Each datasync_agents entry needs exactly one of activation_key, ip_address or arn."
    }

    precondition {
      condition     = alltrue([for k, f in var.file_shares : !local.share_needs_secret[k] || f.source.secret_arn != null])
      error_message = "SMB, object-storage, azure-blob and Kerberos HDFS sources need source.secret_arn (Secrets Manager JSON with the credentials)."
    }

    precondition {
      condition = alltrue([for f in values(var.file_shares) :
        f.source.type == "hdfs" ? length(f.source.hdfs_name_nodes) > 0 && (f.source.hdfs_auth == "simple" || f.source.kerberos_principal != null) :
        f.source.type == "s3" ? f.source.s3_bucket != null :
        f.source.type == "azure-blob" ? f.source.azure_container_url != null :
        f.source.host != null
      ])
      error_message = "nfs / smb / object-storage need source.host; hdfs needs hdfs_name_nodes (and kerberos_principal for Kerberos); s3 needs source.s3_bucket; azure-blob needs source.azure_container_url."
    }

    precondition {
      condition     = alltrue([for f in values(var.file_shares) : f.destination.type != "efs" || f.destination.efs_file_system_arn != null || local.use_platform])
      error_message = "EFS destinations need destination.efs_file_system_arn, or target.platform_name to use the platform's shared EFS."
    }

    precondition {
      condition     = alltrue([for f in values(var.file_shares) : f.destination.type != "fsx-windows" || (f.destination.fsx_windows_arn != null && f.destination.fsx_secret_arn != null)])
      error_message = "fsx-windows destinations need destination.fsx_windows_arn and destination.fsx_secret_arn."
    }

    # ---------------------------------------------------------- images
    precondition {
      condition     = !local.has.images || length(var.images.repositories) + length(var.images.copy) + length(var.images.pull_through) > 0
      error_message = "migrate includes \"images\" but images has no repositories, copy or pull_through entries."
    }

    precondition {
      condition     = alltrue([for p in values(var.images.pull_through) : p.upstream != "azure" || p.registry_url != null])
      error_message = "images.pull_through with upstream = azure needs registry_url (e.g. myregistry.azurecr.io)."
    }

    precondition {
      condition = alltrue([for p in values(var.images.pull_through) :
        !contains(["docker-hub", "ghcr", "gitlab", "azure"], p.upstream) || can(regex(":secret:ecr-pullthroughcache/", coalesce(p.secret_arn, "-")))
      ])
      error_message = "Docker Hub, GHCR, GitLab and Azure pull-through caches need secret_arn for a Secrets Manager secret whose name starts with ecr-pullthroughcache/ (an ECR requirement)."
    }

    # ---------------------------------------------------------- kubernetes
    precondition {
      condition     = !local.has.kubernetes || try(var.kubernetes.target_cluster_name, null) != null || local.use_platform
      error_message = "kubernetes needs target_cluster_name (the EKS cluster to restore into), or target.platform_name to use the platform's cluster."
    }

    precondition {
      condition     = !local.has.kubernetes || var.kubernetes.source_auth != "roles-anywhere" || var.onprem_ca_certificate_pem != null
      error_message = "kubernetes.source_auth = roles-anywhere needs onprem_ca_certificate_pem (the CA that issues the on-prem cluster's certificate)."
    }

    # ---------------------------------------------------------- pipelines
    precondition {
      condition = alltrue([for p in values(local.pipe) :
        !contains(["github", "gitlab"], p.provider) || p.repository != null || length(p.subjects) > 0
      ])
      error_message = "github / gitlab pipelines need repository (\"owner/repo\" or \"group/project\") or explicit subjects."
    }

    precondition {
      condition = alltrue([for p in values(local.pipe) :
        !contains(["bitbucket", "circleci", "azure-devops"], p.provider) || (p.issuer_url != null && p.aud != null && length(p.subjects) > 0)
      ])
      error_message = "bitbucket / circleci / azure-devops pipelines need issuer_url, audience (azure-devops defaults to api://AzureADTokenExchange) and subjects."
    }

    precondition {
      condition     = alltrue([for p in values(var.pipelines) : p.provider != "jenkins" || var.onprem_ca_certificate_pem != null])
      error_message = "jenkins (on-prem CI) pipelines authenticate with a client certificate: set onprem_ca_certificate_pem."
    }

    precondition {
      condition     = alltrue([for p in values(var.pipelines) : p.provider != "codebuild" || p.codebuild_repo_url != null])
      error_message = "codebuild pipelines need codebuild_repo_url (e.g. https://github.com/owner/repo)."
    }

    precondition {
      condition     = alltrue(flatten([for p in values(local.pipe) : [for s in p.subs : s != "*" && !startswith(s, "*")]]))
      error_message = "A pipeline subject cannot start with *; that would let any repository assume the role."
    }

    # ---------------------------------------------------------- servers
    precondition {
      condition     = !local.has.servers || length(var.servers.inventory) > 0
      error_message = "migrate includes \"servers\" but servers.inventory is empty. List each server and its os, e.g. { web01 = { os = \"rhel\" } }."
    }

    precondition {
      condition     = alltrue([for s in values(var.servers.inventory) : s.licensing == null || contains(["windows", "rhel", "suse"], s.os)])
      error_message = "licensing applies only to windows, rhel and suse servers."
    }
  }
}
