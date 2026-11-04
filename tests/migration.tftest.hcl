# Runs the module against a mocked AWS provider: no credentials, nothing created.
#   terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:root", user_id = "AIDA" }
  }
  mock_data "aws_region" {
    defaults = { name = "us-east-1" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_vpc" {
    defaults = { id = "vpc-0123456789abcdef0", cidr_block = "10.0.0.0/16" }
  }
  mock_data "aws_subnets" {
    defaults = { ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"] }
  }
  mock_data "aws_security_group" {
    defaults = { id = "sg-0platform000000000", arn = "arn:aws:ec2:us-east-1:123456789012:security-group/sg-0platform000000000" }
  }
  mock_data "aws_efs_file_system" {
    defaults = { id = "fs-0123456789", arn = "arn:aws:elasticfilesystem:us-east-1:123456789012:file-system/fs-0123456789" }
  }
  mock_data "aws_secretsmanager_secret_version" {
    defaults = { secret_string = "{\"username\":\"svc\",\"password\":\"x\",\"access_key\":\"AKIAMOCKMOCK\",\"secret_key\":\"mocksecretmocksecret\"}" }
  }
  mock_data "aws_network_interface" {
    defaults = { private_ip = "10.0.1.10" }
  }

  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000" }
  }
  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:us-east-1:123456789012:mig-alerts" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }
  mock_resource "aws_security_group" {
    defaults = { id = "sg-0mock000000000000", arn = "arn:aws:ec2:us-east-1:123456789012:security-group/sg-0mock000000000000" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/datasync/mock" }
  }
  mock_resource "aws_cloudwatch_event_rule" {
    defaults = { arn = "arn:aws:events:us-east-1:123456789012:rule/mock" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::mock-bucket", bucket = "mock-bucket" }
  }
  mock_resource "aws_dms_certificate" {
    defaults = { certificate_arn = "arn:aws:dms:us-east-1:123456789012:cert:MOCK" }
  }
  mock_resource "aws_dms_replication_subnet_group" {
    defaults = { id = "mock-subnet-group" }
  }
  mock_resource "aws_dms_endpoint" {
    defaults = { endpoint_arn = "arn:aws:dms:us-east-1:123456789012:endpoint:MOCK" }
  }
  mock_resource "aws_dms_s3_endpoint" {
    defaults = { endpoint_arn = "arn:aws:dms:us-east-1:123456789012:endpoint:MOCKS3" }
  }
  mock_resource "aws_dms_replication_config" {
    defaults = { arn = "arn:aws:dms:us-east-1:123456789012:replication-config:MOCK" }
  }
  mock_resource "aws_dms_replication_instance" {
    defaults = { replication_instance_arn = "arn:aws:dms:us-east-1:123456789012:rep:MOCK" }
  }
  mock_resource "aws_dms_replication_task" {
    defaults = { replication_task_arn = "arn:aws:dms:us-east-1:123456789012:task:MOCK" }
  }
  mock_resource "aws_vpc_endpoint" {
    defaults = { id = "vpce-0mock", network_interface_ids = ["eni-0mock"] }
  }
  mock_resource "aws_datasync_agent" {
    defaults = { arn = "arn:aws:datasync:us-east-1:123456789012:agent/agent-0mock" }
  }
  mock_resource "aws_datasync_location_nfs" {
    defaults = { arn = "arn:aws:datasync:us-east-1:123456789012:location/loc-0nfs" }
  }
  mock_resource "aws_datasync_location_smb" {
    defaults = { arn = "arn:aws:datasync:us-east-1:123456789012:location/loc-0smb" }
  }
  mock_resource "aws_datasync_location_hdfs" {
    defaults = { arn = "arn:aws:datasync:us-east-1:123456789012:location/loc-0hdfs" }
  }
  mock_resource "aws_datasync_location_object_storage" {
    defaults = { arn = "arn:aws:datasync:us-east-1:123456789012:location/loc-0obj" }
  }
  mock_resource "aws_datasync_location_s3" {
    defaults = { arn = "arn:aws:datasync:us-east-1:123456789012:location/loc-0s3" }
  }
  mock_resource "aws_datasync_location_efs" {
    defaults = { arn = "arn:aws:datasync:us-east-1:123456789012:location/loc-0efs" }
  }
  mock_resource "aws_datasync_location_fsx_windows_file_system" {
    defaults = { arn = "arn:aws:datasync:us-east-1:123456789012:location/loc-0fsx" }
  }
  mock_resource "aws_datasync_task" {
    defaults = { arn = "arn:aws:datasync:us-east-1:123456789012:task/task-0mock" }
  }
}

variables {
  name         = "acme"
  onprem_cidrs = ["10.20.0.0/16", "192.168.10.0/24"]
}

# ---------------------------------------------------------------- happy paths

run "mixed_estate_every_engine_share_and_os" {
  command = apply

  variables {
    migrate = ["databases", "files", "servers"]
    target  = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"] }

    databases = {
      shop = { source = { engine = "mysql", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:shop-src-AbCdEf", database_name = "shop" }, target = { secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:shop-tgt-AbCdEf" } }
      crm  = { source = { engine = "postgres", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:crm-AbCdEf", database_name = "crm" }, target = { engine = "aurora-postgresql", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:crm-tgt-AbCdEf" } }
      erp  = { source = { engine = "sqlserver", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:erp-AbCdEf", database_name = "ERP" }, target = { secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:erp-tgt-AbCdEf" } }
      hr   = { source = { engine = "oracle", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:hr-AbCdEf", database_name = "ORCL", ssl_mode = "verify-ca", ca_certificate_pem = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----" }, target = { engine = "postgres", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:hr-tgt-AbCdEf" } }
      ase  = { source = { engine = "sybase", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:ase-AbCdEf", database_name = "legacy" }, target = { engine = "postgres", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:ase-tgt-AbCdEf" } }
      docs = { source = { engine = "mongodb", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:docs-AbCdEf", database_name = "docs" }, target = { secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:docs-tgt-AbCdEf" } }
      lake = { source = { engine = "db2", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:lake-AbCdEf", database_name = "SALES" }, target = { engine = "s3", s3_bucket = "acme-datalake" }, mode = "full-load" }
    }

    datasync_agents = {
      dc1 = { activation_key = "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE" }
      dc2 = { arn = "arn:aws:datasync:us-east-1:123456789012:agent/agent-0existing" }
    }

    file_shares = {
      exports  = { source = { type = "nfs", agent = "dc1", host = "nas01.corp.local", path = "/exports/data" }, destination = { type = "s3" }, schedule = "cron(0 2 * * ? *)" }
      profiles = { source = { type = "smb", agent = "dc1", host = "fs01.corp.local", path = "/profiles", smb_domain = "CORP", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:smb-AbCdEf" }, destination = { type = "fsx-windows", fsx_windows_arn = "arn:aws:fsx:us-east-1:123456789012:file-system/fs-0win", fsx_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:fsx-AbCdEf" } }
      minio    = { source = { type = "object-storage", agent = "dc2", host = "minio.corp.local", path = "media", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:minio-AbCdEf" }, destination = { type = "s3", s3_bucket = "acme-media" }, bandwidth_mbps = 200 }
      hadoop   = { source = { type = "hdfs", agent = "dc2", path = "/warehouse", hdfs_name_nodes = [{ host = "nn01.corp.local" }], hdfs_simple_user = "hdfs" }, destination = { type = "s3" } }
    }

    servers = {
      inventory = {
        web01   = { os = "windows", licensing = "byol" }
        app01   = { os = "rhel" }
        batch01 = { os = "rocky" }
        api01   = { os = "ubuntu" }
        sap01   = { os = "suse", licensing = "aws" }
      }
    }
  }

  assert {
    condition     = length(aws_dms_endpoint.source) == 7 && length(aws_dms_endpoint.target) == 6 && length(aws_dms_s3_endpoint.target) == 1
    error_message = "every database needs a source endpoint; db2 -> s3 uses the S3 endpoint"
  }
  assert {
    condition     = length(aws_dms_replication_config.main) == 6 && length(aws_dms_replication_task.main) == 1 && length(aws_dms_replication_instance.main) == 1
    error_message = "sybase must run instance-based; everything else serverless"
  }
  assert {
    condition     = aws_dms_endpoint.target["docs"].engine_name == "docdb" && aws_dms_endpoint.target["shop"].engine_name == "mysql"
    error_message = "default target engines: mongodb -> docdb, mysql -> mysql"
  }
  assert {
    condition     = length(aws_dms_certificate.source_ca) == 1 && aws_dms_endpoint.source["hr"].ssl_mode == "verify-ca"
    error_message = "verify-ca source should register its CA certificate"
  }
  assert {
    condition     = jsondecode(aws_dms_replication_config.main["shop"].replication_settings).FullLoadSettings.TargetTablePrepMode == "DO_NOTHING"
    error_message = "existing target tables must be kept by default"
  }
  assert {
    condition     = length(aws_datasync_task.main) == 4 && length(aws_datasync_agent.main) == 1 && length(aws_s3_bucket.dest) == 2
    error_message = "4 shares, 1 new agent (dc2 existing), 2 module-created buckets (nfs, hdfs)"
  }
  assert {
    condition     = aws_datasync_task.main["minio"].options[0].bytes_per_second == 25000000 && aws_datasync_task.main["profiles"].options[0].posix_permissions == "NONE"
    error_message = "bandwidth limit and SMB POSIX handling"
  }
  assert {
    condition     = strcontains(output.summary.servers.inventory.web01.install, "AwsReplicationWindowsInstaller.exe") && strcontains(output.summary.servers.inventory.app01.install, "aws-replication-installer-init")
    error_message = "Windows and Linux servers need their own installer"
  }
  assert {
    condition     = strcontains(output.summary.servers.inventory.web01.licensing, "osByol=true") && output.summary.servers.inventory.api01.licensing == null
    error_message = "licensing only for windows/rhel/suse"
  }
  assert {
    condition     = strcontains(output.summary.servers.inventory.batch01.prerequisites, "yum") && strcontains(output.summary.servers.inventory.api01.prerequisites, "apt-get") && strcontains(output.summary.servers.inventory.sap01.prerequisites, "zypper")
    error_message = "per-distro kernel header hints"
  }
  assert {
    condition     = length(aws_kms_key.migration) == 0 && length(aws_vpc_endpoint.datasync) == 0
    error_message = "pilot uses AWS-managed keys and no PrivateLink"
  }
}

run "production_on_platform_module" {
  command = apply

  variables {
    profile     = "production"
    migrate     = ["databases", "files"]
    target      = { platform_name = "acme-prod" }
    alert_email = "migration@example.com"

    databases = {
      orders = {
        source = { engine = "postgres", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:orders-AbCdEf", database_name = "orders" }
        target = { secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:orders-tgt-AbCdEf", platform_database = true }
      }
    }

    datasync_agents = { dc1 = { activation_key = "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE" } }
    file_shares = {
      uploads = { source = { type = "nfs", agent = "dc1", host = "nas01.corp.local", path = "/uploads" }, destination = { type = "efs" } }
    }
  }

  assert {
    condition     = length(aws_kms_key.migration) == 1 && output.kms_key_arn != null
    error_message = "production creates a customer-managed key"
  }
  assert {
    condition     = aws_dms_replication_config.main["orders"].compute_config[0].multi_az == true
    error_message = "production DMS is Multi-AZ"
  }
  assert {
    condition     = jsondecode(aws_dms_replication_config.main["orders"].replication_settings).ValidationSettings.EnableValidation == true
    error_message = "production validates rows for relational targets"
  }
  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.platform_rds_from_dms) == 1 && aws_vpc_security_group_ingress_rule.platform_rds_from_dms["orders"].from_port == 5432
    error_message = "platform RDS must be opened to DMS on 5432"
  }
  assert {
    condition     = length(aws_vpc_endpoint.datasync) == 1 && length(aws_vpc_security_group_ingress_rule.platform_efs_from_datasync) == 1
    error_message = "production uses DataSync PrivateLink and opens the platform EFS"
  }
  assert {
    condition     = length(aws_sns_topic_subscription.email) == 1
    error_message = "alert email should be subscribed"
  }
}

# ---------------------------------------------------------------- guardrails refuse bad input

run "refuses_unencrypted_database" {
  command = plan
  variables {
    migrate   = ["databases"]
    target    = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"] }
    databases = { legacy = { source = { engine = "mysql", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:l-AbCdEf", ssl_mode = "none" }, target = { secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:t-AbCdEf" } } }
  }
  expect_failures = [terraform_data.guardrails]
}

run "databases_need_two_subnets" {
  command = plan
  variables {
    migrate   = ["databases"]
    target    = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"] }
    databases = { x = { source = { engine = "mysql", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:x-AbCdEf" }, target = { secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:t-AbCdEf" } } }
  }
  expect_failures = [terraform_data.guardrails]
}

run "refuses_plaintext_credentials" {
  command = plan
  variables {
    migrate   = ["databases"]
    target    = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"] }
    databases = { x = { source = { engine = "mysql", secret_arn = "user:password@host" } } }
  }
  expect_failures = [var.databases]
}

run "db2_needs_explicit_target" {
  command = plan
  variables {
    migrate   = ["databases"]
    target    = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"] }
    databases = { x = { source = { engine = "db2", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:x-AbCdEf" }, target = { secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:t-AbCdEf" } } }
  }
  expect_failures = [terraform_data.guardrails]
}

run "mongodb_cannot_target_relational" {
  command = plan
  variables {
    migrate   = ["databases"]
    target    = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"] }
    databases = { x = { source = { engine = "mongodb", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:x-AbCdEf" }, target = { engine = "postgres", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:t-AbCdEf" } } }
  }
  expect_failures = [terraform_data.guardrails]
}

run "production_requires_alert_email" {
  command = plan
  variables {
    profile = "production"
    migrate = ["servers"]
    target  = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"] }
    servers = { inventory = { web01 = { os = "windows" } } }
  }
  expect_failures = [terraform_data.guardrails]
}

run "smb_share_needs_secret" {
  command = plan
  variables {
    migrate         = ["files"]
    target          = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"] }
    datasync_agents = { dc1 = { activation_key = "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE" } }
    file_shares     = { p = { source = { type = "smb", agent = "dc1", host = "fs01" }, destination = { type = "s3" } } }
  }
  expect_failures = [terraform_data.guardrails]
}

run "unknown_agent_refused" {
  command = plan
  variables {
    migrate         = ["files"]
    target          = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"] }
    datasync_agents = { dc1 = { activation_key = "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE" } }
    file_shares     = { p = { source = { type = "nfs", agent = "dc9", host = "nas01" }, destination = { type = "s3" } } }
  }
  expect_failures = [terraform_data.guardrails]
}

run "target_must_be_one_style" {
  command = plan
  variables {
    migrate = ["servers"]
    target  = { platform_name = "acme-prod", vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"] }
    servers = { inventory = { web01 = { os = "rhel" } } }
  }
  expect_failures = [terraform_data.guardrails]
}

run "unknown_os_refused" {
  command = plan
  variables {
    migrate = ["servers"]
    target  = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"] }
    servers = { inventory = { old01 = { os = "solaris" } } }
  }
  expect_failures = [var.servers]
}
