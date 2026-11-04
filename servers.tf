# ============================================
# SERVERS: AWS Application Migration Service (MGN)
# ============================================
# The AWS provider has no MGN resources, so this module builds everything Terraform can (staging network,
# replication security group, a short-lived installer role) and generates the exact commands for the rest:
# service initialization, the replication template, and the agent install for each server's OS.

locals {
  servers_on     = local.has.servers
  staging_subnet = coalesce(var.servers.staging_subnet_id, local.first_subnet_id, "unset")

  os_family = {
    windows        = "windows"
    rhel           = "rhel"
    centos         = "rhel"
    rocky          = "rhel"
    alma           = "rhel"
    "oracle-linux" = "rhel"
    "amazon-linux" = "rhel"
    ubuntu         = "debian"
    debian         = "debian"
    suse           = "suse"
  }

  installer_base = "https://aws-application-migration-service-${local.region}.s3.${local.region}.amazonaws.com/latest"

  install_cmd = {
    windows = join("\n", [
      "# PowerShell as Administrator. Needs outbound TCP 443 (MGN API, S3) and 1500 (replication servers).",
      "Invoke-WebRequest -Uri ${local.installer_base}/windows/AwsReplicationWindowsInstaller.exe -OutFile AwsReplicationWindowsInstaller.exe",
      ".\\AwsReplicationWindowsInstaller.exe --region ${local.region} --aws-access-key-id $env:AWS_ACCESS_KEY_ID --aws-secret-access-key $env:AWS_SECRET_ACCESS_KEY --aws-session-token $env:AWS_SESSION_TOKEN --no-prompt",
    ])
    linux = join("\n", [
      "# As root / sudo. Needs outbound TCP 443 (MGN API, S3) and 1500 (replication servers).",
      "curl -fsSL -o aws-replication-installer-init ${local.installer_base}/linux/aws-replication-installer-init",
      "chmod +x aws-replication-installer-init",
      "sudo ./aws-replication-installer-init --region ${local.region} --aws-access-key-id \"$AWS_ACCESS_KEY_ID\" --aws-secret-access-key \"$AWS_SECRET_ACCESS_KEY\" --aws-session-token \"$AWS_SESSION_TOKEN\" --no-prompt",
    ])
  }

  # If the Linux installer reports missing kernel headers, install the package for the running kernel.
  kernel_headers = {
    rhel   = "sudo yum install -y kernel-devel-$(uname -r)"
    debian = "sudo apt-get install -y linux-headers-$(uname -r)"
    suse   = "sudo zypper install -y kernel-default-devel"
  }

  server_plan = local.servers_on ? {
    for k, s in var.servers.inventory : k => {
      os        = s.os
      family    = local.os_family[s.os]
      licensing = coalesce(s.licensing, "aws")
      install   = local.os_family[s.os] == "windows" ? local.install_cmd.windows : local.install_cmd.linux
      prereq    = local.os_family[s.os] == "windows" ? ".NET Framework 4.5+ and Administrator rights" : "Python 3, curl, and kernel headers if prompted: ${lookup(local.kernel_headers, local.os_family[s.os], "")}"
      license_cmd = contains(["windows", "rhel", "suse"], s.os) ? (
        "aws mgn update-launch-configuration --region ${local.region} --source-server-id <id-of-${k}> --licensing osByol=${coalesce(s.licensing, "aws") == "byol" ? "true" : "false"}"
      ) : null
    }
  } : {}
}

# --------------------------------------------
# Replication servers' security group (agents push data on TCP 1500)
# --------------------------------------------
resource "aws_security_group" "mgn_replication" {
  count       = local.servers_on ? 1 : 0
  name        = "${local.prefix}-mgn-replication"
  description = "MGN replication servers: TCP 1500 from on-prem agents, HTTPS out to AWS APIs"
  vpc_id      = local.vpc_id
  tags        = merge(local.tags, { Name = "${local.prefix}-mgn-replication" })
}

resource "aws_vpc_security_group_ingress_rule" "mgn_agents" {
  for_each          = local.servers_on ? toset(var.onprem_cidrs) : toset([])
  security_group_id = aws_security_group.mgn_replication[0].id
  description       = "Replication data from on-prem agents"
  ip_protocol       = "tcp"
  from_port         = 1500
  to_port           = 1500
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "mgn_https" {
  count             = local.servers_on ? 1 : 0
  security_group_id = aws_security_group.mgn_replication[0].id
  description       = "MGN, EC2, S3 APIs"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# --------------------------------------------
# Agent installer role: short-lived credentials instead of an IAM user with static keys
# --------------------------------------------
resource "aws_iam_role" "mgn_installer" {
  count                = local.servers_on ? 1 : 0
  name                 = "${local.prefix}-mgn-agent-installer"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:${local.partition}:iam::${local.account_id}:root" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "mgn_installer" {
  count      = length(aws_iam_role.mgn_installer)
  role       = aws_iam_role.mgn_installer[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AWSApplicationMigrationAgentInstallationPolicy"
}

locals {
  mgn_setup = local.servers_on ? {
    "1_initialize_once_per_region" = "aws mgn initialize-service --region ${local.region}"
    "2_replication_template" = join(" ", [
      "aws mgn create-replication-configuration-template --region ${local.region}",
      "--staging-area-subnet-id ${local.staging_subnet}",
      "--replication-servers-security-groups-ids ${aws_security_group.mgn_replication[0].id}",
      "--replication-server-instance-type ${var.servers.replication_instance_type}",
      "--use-dedicated-replication-server false --associate-default-security-group false",
      "--default-large-staging-disk-type GP3 --ebs-encryption DEFAULT",
      "--bandwidth-throttling ${var.servers.bandwidth_mbps}",
      var.servers.use_private_ip ? "--data-plane-routing PRIVATE_IP --create-public-ip false" : "--data-plane-routing PUBLIC_IP --create-public-ip true",
      "--staging-area-tags Project=${var.name},Environment=${var.environment},ManagedBy=terraform",
    ])
    "3_installer_credentials" = "eval $(aws sts assume-role --role-arn ${aws_iam_role.mgn_installer[0].arn} --role-session-name mgn-install --duration-seconds 3600 --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text | awk '{print \"export AWS_ACCESS_KEY_ID=\"$1\" AWS_SECRET_ACCESS_KEY=\"$2\" AWS_SESSION_TOKEN=\"$3}')"
  } : {}

  mgn_cutover = local.servers_on ? [
    "aws mgn describe-source-servers --region ${local.region} --query 'items[].{id:sourceServerID,host:sourceProperties.identificationHints.hostname,state:dataReplicationInfo.dataReplicationState}'",
    "aws mgn start-test --region ${local.region} --source-server-ids <id> ...          # launch test instances",
    "aws mgn start-cutover --region ${local.region} --source-server-ids <id> ...       # launch final instances",
    "aws mgn finalize-cutover --region ${local.region} --source-server-id <id>         # stop replication, mark migrated",
    "aws mgn mark-as-archived --region ${local.region} --source-server-id <id>         # after the source is retired",
  ] : []
}

# --------------------------------------------
# Optional: apply the MGN setup with the AWS CLI during terraform apply (servers.automate = true)
# --------------------------------------------
# Terraform has no MGN resources, so this runs the same commands as summary.servers.setup, idempotently:
# initialize the service, create-or-update the replication and launch templates and, once agents have
# connected, apply each server's licensing by matching its hostname. Re-apply after installing agents.
# Requires bash and the AWS CLI v2 where Terraform runs, with permission to call MGN.

locals {
  mgn_automate = local.servers_on && var.servers.automate

  mgn_licensing = { for k, s in local.server_plan : k => s.licensing == "byol" if contains(["windows", "rhel", "suse"], s.os) }

  mgn_script = local.mgn_automate ? join("\n", concat([
    "set -euo pipefail",
    "R=${local.region}",
    "aws mgn initialize-service --region $R >/dev/null 2>&1 || true",
    "COMMON='--staging-area-subnet-id ${local.staging_subnet} --replication-servers-security-groups-ids ${aws_security_group.mgn_replication[0].id} --replication-server-instance-type ${var.servers.replication_instance_type} --use-dedicated-replication-server false --associate-default-security-group false --default-large-staging-disk-type GP3 --ebs-encryption DEFAULT --bandwidth-throttling ${var.servers.bandwidth_mbps} ${var.servers.use_private_ip ? "--data-plane-routing PRIVATE_IP --create-public-ip false" : "--data-plane-routing PUBLIC_IP --create-public-ip true"} --staging-area-tags Project=${var.name},Environment=${var.environment},ManagedBy=terraform'",
    "RT=$(aws mgn describe-replication-configuration-templates --region $R --query 'items[0].replicationConfigurationTemplateID' --output text)",
    "if [ \"$RT\" = \"None\" ] || [ -z \"$RT\" ]; then aws mgn create-replication-configuration-template --region $R $COMMON >/dev/null; else aws mgn update-replication-configuration-template --region $R --replication-configuration-template-id \"$RT\" $COMMON >/dev/null; fi",
    "LAUNCH='--copy-private-ip false --copy-tags true --launch-disposition ${var.servers.launch_disposition} --target-instance-type-right-sizing-method ${var.servers.right_sizing}'",
    "LT=$(aws mgn list-launch-configuration-templates --region $R --query 'items[0].launchConfigurationTemplateID' --output text 2>/dev/null || echo None)",
    "if [ \"$LT\" = \"None\" ] || [ -z \"$LT\" ]; then aws mgn create-launch-configuration-template --region $R $LAUNCH >/dev/null; else aws mgn update-launch-configuration-template --region $R --launch-configuration-template-id \"$LT\" $LAUNCH >/dev/null; fi",
    ], [for host, byol in local.mgn_licensing : join(" ", [
      "ID=$(aws mgn describe-source-servers --region $R --query \"items[?sourceProperties.identificationHints.hostname=='${host}'] | [0].sourceServerID\" --output text);",
      "if [ \"$ID\" != \"None\" ] && [ -n \"$ID\" ]; then aws mgn update-launch-configuration --region $R --source-server-id \"$ID\" --licensing osByol=${byol} >/dev/null && echo 'licensing set for ${host}'; else echo '${host}: agent not connected yet, re-apply after installing it'; fi",
  ])])) : ""
}

resource "terraform_data" "mgn_setup" {
  count = local.mgn_automate ? 1 : 0

  # Re-run when any setting or the server inventory changes.
  triggers_replace = [sha256(local.mgn_script)]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = local.mgn_script
  }
}
