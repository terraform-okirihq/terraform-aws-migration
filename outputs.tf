# ============================================
# WHAT YOU GOT + HOW TO CUT OVER
# ============================================

locals {
  db_runbook = { for k, d in local.dbs : k => {
    route   = "${d.source.engine} -> ${d.target_engine} (${d.mode}, ${d.compute})"
    tls     = "source ${d.source.ssl_mode}, target ${d.target_engine == "s3" ? "https" : d.target.ssl_mode}"
    started = d.start
    commands = d.compute == "serverless" ? {
      start  = "aws dms start-replication --region ${local.region} --replication-config-arn ${aws_dms_replication_config.main[k].arn} --start-replication-type start-replication"
      status = "aws dms describe-replications --region ${local.region} --filters Name=replication-config-arn,Values=${aws_dms_replication_config.main[k].arn} --query 'Replications[0].{status:Status,stats:ReplicationStats}'"
      stop   = "aws dms stop-replication --region ${local.region} --replication-config-arn ${aws_dms_replication_config.main[k].arn}"
      } : {
      start  = "aws dms start-replication-task --region ${local.region} --replication-task-arn ${aws_dms_replication_task.main[k].replication_task_arn} --start-replication-task-type start-replication"
      status = "aws dms describe-replication-tasks --region ${local.region} --filters Name=replication-task-arn,Values=${aws_dms_replication_task.main[k].replication_task_arn} --query 'ReplicationTasks[0].{status:Status,stats:ReplicationTaskStats}'"
      stop   = "aws dms stop-replication-task --region ${local.region} --replication-task-arn ${aws_dms_replication_task.main[k].replication_task_arn}"
    }
  } }

  share_runbook = { for k, f in local.shares : k => {
    route    = "${f.source.type}://${coalesce(f.source.host, f.source.s3_bucket, f.source.azure_container_url, "hdfs")}${f.source.path} -> ${f.destination.type}${f.destination.type == "s3" ? "://${local.dest_bucket_name[k]}${f.destination.path}" : ""}"
    schedule = coalesce(f.schedule, "on demand")
    # For an s3 source in another account: the bucket owner adds this to the source bucket's policy.
    source_bucket_policy = f.source.type == "s3" ? jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid       = "AllowDataSyncMigrationRead"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.datasync_s3[0].arn }
        Action    = ["s3:GetBucketLocation", "s3:ListBucket", "s3:GetObject", "s3:GetObjectTagging", "s3:GetObjectVersion", "s3:GetObjectVersionTagging"]
        Resource  = ["arn:${local.partition}:s3:::${f.source.s3_bucket}", "arn:${local.partition}:s3:::${f.source.s3_bucket}/*"]
      }]
    }) : null
    commands = {
      run    = "aws datasync start-task-execution --region ${local.region} --task-arn ${aws_datasync_task.main[k].arn}"
      status = "aws datasync list-task-executions --region ${local.region} --task-arn ${aws_datasync_task.main[k].arn} --max-results 5"
    }
  } }

  setup_steps = compact([
    var.alert_email != "" ? "Confirm the SNS subscription email sent to ${var.alert_email}." : "Set alert_email to be told when a replication or transfer fails.",
    local.has.databases ? "Databases: run the 'start' command per database (or set start = true), watch 'status', and stop replication at cutover." : "",
    local.has.databases && length(local.platform_db_targets) == 0 ? "Databases: allow security group ${try(aws_security_group.dms[0].id, "")} on each target database's security group (port of that engine)." : "",
    local.has.files && length(local.agents_create) > 0 ? "Files: deploy the DataSync agent appliance on-prem (VMware, Hyper-V or KVM image from the DataSync console) before applying, so activation succeeds." : "",
    local.private_link ? "Files: DataSync uses PrivateLink. When generating an activation key on the agent console, choose 'VPC endpoint' and enter ${try(data.aws_network_interface.datasync_endpoint[0].private_ip, "")}." : "",
    local.has.files && length(local.dest_fsx) > 0 ? "Files: allow security group ${try(aws_security_group.datasync[0].id, "")} on your FSx for Windows security group (SMB 445)." : "",
    local.has.files && length(local.dest_efs) > length(local.dest_efs_plat) ? "Files: allow security group ${try(aws_security_group.datasync[0].id, "")} on your EFS mount-target security group (NFS 2049)." : "",
    local.has.servers ? "Servers: run setup.1 and setup.2 once, then on each server get credentials with setup.3 and run its install command." : "",
  ])
}

output "summary" {
  description = "What this module created, and the commands to run the migration and cut over."
  value = {
    name    = local.prefix
    profile = var.profile
    region  = local.region
    network = "VPC ${local.vpc_id} (${local.vpc_cidr}), ${length(local.subnet_ids)} private subnets, on-prem ${join(", ", var.onprem_cidrs)}"

    databases = local.db_runbook
    files     = local.share_runbook
    servers = local.has.servers ? {
      setup     = local.mgn_setup
      inventory = { for k, s in local.server_plan : k => { os = s.os, prerequisites = s.prereq, install = s.install, licensing = s.license_cmd } }
      cutover   = local.mgn_cutover
    } : null

    next_steps = local.setup_steps

    cost_notes = compact([
      local.has.databases ? "DMS: Serverless bills per capacity-unit-hour (${local.s.dms_min_capacity_units}-${local.s.dms_max_capacity_units} DCU); instance-based bills per instance-hour (${local.s.dms_instance_class}). Stop replications you are not using." : "",
      local.has.files ? "DataSync: billed per GB copied; agents are free. Keep schedules only as long as you need re-syncs." : "",
      local.has.servers ? "MGN: free for 90 days of replication per server, then hourly; replication servers (${var.servers.replication_instance_type}) and staging EBS are billed as EC2." : "",
      "Destroy this stack after cutover: it is tagged Lifecycle = temporary.",
    ])
  }
}

output "settings" {
  description = "Resolved profile settings (profile defaults + overrides)."
  value       = local.s
}

output "security_group_ids" {
  description = "Security groups to allow on target data stores (DMS, DataSync) and for MGN replication servers."
  value = {
    dms             = try(aws_security_group.dms[0].id, null)
    datasync        = try(aws_security_group.datasync[0].id, null)
    mgn_replication = try(aws_security_group.mgn_replication[0].id, null)
  }
}

output "dms" {
  description = "DMS replication ARNs per database."
  value = {
    serverless = { for k, r in aws_dms_replication_config.main : k => r.arn }
    tasks      = { for k, t in aws_dms_replication_task.main : k => t.replication_task_arn }
    instance   = try(aws_dms_replication_instance.main[0].replication_instance_arn, null)
  }
}

output "datasync" {
  description = "DataSync agent and task ARNs."
  value = {
    agents = local.agent_arn
    tasks  = { for k, t in aws_datasync_task.main : k => t.arn }
    s3     = local.dest_bucket_name
  }
}

output "mgn_installer_role_arn" {
  description = "Role to assume for short-lived MGN agent install credentials."
  value       = try(aws_iam_role.mgn_installer[0].arn, null)
}

output "alerts_topic_arn" {
  description = "SNS topic receiving DMS and DataSync state changes."
  value       = aws_sns_topic.alerts.arn
}

output "kms_key_arn" {
  description = "KMS key used for migration data (null = AWS-managed keys)."
  value       = local.kms_key_arn
}
