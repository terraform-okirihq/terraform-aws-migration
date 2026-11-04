# ============================================
# PLAN-TIME GUARDRAILS
# ============================================
# Refuse unsafe or incomplete configurations before anything is created; each message says what to change.

locals {
  share_needs_secret = { for k, f in var.file_shares : k => contains(["smb", "object-storage"], f.source.type) }
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
      condition     = alltrue([for f in values(var.file_shares) : contains(keys(var.datasync_agents), f.source.agent)])
      error_message = "Every file_shares.*.source.agent must name an entry in datasync_agents."
    }

    precondition {
      condition = alltrue([for a in values(var.datasync_agents) :
        length(compact([a.activation_key, a.ip_address, a.arn])) == 1
      ])
      error_message = "Each datasync_agents entry needs exactly one of activation_key, ip_address or arn."
    }

    precondition {
      condition     = alltrue([for k, f in var.file_shares : !local.share_needs_secret[k] || f.source.secret_arn != null])
      error_message = "SMB and object-storage sources need source.secret_arn (Secrets Manager JSON with the credentials)."
    }

    precondition {
      condition     = alltrue([for f in values(var.file_shares) : f.source.type == "hdfs" ? length(f.source.hdfs_name_nodes) > 0 : f.source.host != null])
      error_message = "nfs / smb / object-storage sources need source.host; hdfs sources need source.hdfs_name_nodes."
    }

    precondition {
      condition     = alltrue([for f in values(var.file_shares) : f.destination.type != "efs" || f.destination.efs_file_system_arn != null || local.use_platform])
      error_message = "EFS destinations need destination.efs_file_system_arn, or target.platform_name to use the platform's shared EFS."
    }

    precondition {
      condition     = alltrue([for f in values(var.file_shares) : f.destination.type != "fsx-windows" || (f.destination.fsx_windows_arn != null && f.destination.fsx_secret_arn != null)])
      error_message = "fsx-windows destinations need destination.fsx_windows_arn and destination.fsx_secret_arn."
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
