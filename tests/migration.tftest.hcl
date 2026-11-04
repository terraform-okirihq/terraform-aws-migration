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
    defaults = { secret_string = "{\"username\":\"svc\",\"password\":\"x\",\"access_key\":\"AKIAMOCKMOCK\",\"secret_key\":\"mocksecretmocksecret\",\"sas_token\":\"sv=2024&sig=mock\",\"keytab_base64\":\"BQIAAA==\",\"krb5_conf\":\"[libdefaults]\\n default_realm = CORP.LOCAL\"}" }
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
  mock_resource "aws_datasync_location_azure_blob" {
    defaults = { arn = "arn:aws:datasync:us-east-1:123456789012:location/loc-0azure" }
  }
  mock_data "aws_eks_cluster" {
    defaults = { identity = [{ oidc = [{ issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/MOCK" }] }] }
  }
  mock_data "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/MOCK" }
  }
  mock_resource "aws_ecr_repository" {
    defaults = { arn = "arn:aws:ecr:us-east-1:123456789012:repository/mock", repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/mock" }
  }
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::123456789012:policy/mock" }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/mock" }
  }
  mock_resource "aws_rolesanywhere_trust_anchor" {
    defaults = { arn = "arn:aws:rolesanywhere:us-east-1:123456789012:trust-anchor/mock" }
  }
  mock_resource "aws_rolesanywhere_profile" {
    defaults = { arn = "arn:aws:rolesanywhere:us-east-1:123456789012:profile/mock" }
  }
  mock_resource "aws_codeconnections_connection" {
    defaults = { arn = "arn:aws:codeconnections:us-east-1:123456789012:connection/mock" }
  }
  mock_resource "aws_codebuild_project" {
    defaults = { arn = "arn:aws:codebuild:us-east-1:123456789012:project/mock" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
  }
  mock_data "aws_route_tables" {
    defaults = { ids = ["rtb-0aaaaaaaaaaaaaaaa", "rtb-0bbbbbbbbbbbbbbbb"] }
  }
  mock_resource "aws_ec2_transit_gateway" {
    defaults = { id = "tgw-0mock0000000000", association_default_route_table_id = "tgw-rtb-0mock000000000" }
  }
  mock_resource "aws_flow_log" {
    defaults = { arn = "arn:aws:ec2:us-east-1:123456789012:vpc-flow-log/fl-0mock" }
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

run "kerberos_hdfs_s3_and_azure_sources" {
  command = apply

  variables {
    migrate         = ["files"]
    target          = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"] }
    datasync_agents = { dc1 = { activation_key = "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE" } }
    file_shares = {
      warehouse = {
        source      = { type = "hdfs", agent = "dc1", path = "/warehouse", hdfs_name_nodes = [{ host = "nn01.corp.local" }], hdfs_auth = "kerberos", kerberos_principal = "hdfs/nn01.corp.local@CORP.LOCAL", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:kerb-AbCdEf" }
        destination = { type = "s3" }
      }
      oldaccount = {
        source      = { type = "s3", s3_bucket = "legacy-account-bucket", path = "/" }
        destination = { type = "s3", s3_bucket = "new-account-bucket" }
      }
      azure = {
        source      = { type = "azure-blob", agent = "dc1", azure_container_url = "https://acme.blob.core.windows.net/media", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:sas-AbCdEf" }
        destination = { type = "s3" }
      }
    }
  }

  assert {
    condition     = aws_datasync_location_hdfs.source["warehouse"].authentication_type == "KERBEROS" && aws_datasync_location_hdfs.source["warehouse"].qop_configuration[0].rpc_protection == "PRIVACY"
    error_message = "Kerberos HDFS with privacy protection"
  }
  assert {
    condition     = length(aws_datasync_location_s3.source) == 1 && length(aws_datasync_location_azure_blob.source) == 1 && length(aws_datasync_task.main) == 3
    error_message = "s3 and azure-blob sources should get locations and tasks"
  }
  assert {
    condition     = strcontains(output.summary.files.oldaccount.source_bucket_policy, "legacy-account-bucket") && output.summary.files.azure.source_bucket_policy == null
    error_message = "cross-account S3 sources get a ready-made bucket policy"
  }
}

run "kerberos_needs_principal" {
  command = plan
  variables {
    migrate         = ["files"]
    target          = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"] }
    datasync_agents = { dc1 = { activation_key = "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE" } }
    file_shares     = { w = { source = { type = "hdfs", agent = "dc1", hdfs_name_nodes = [{ host = "nn01" }], hdfs_auth = "kerberos", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:k-AbCdEf" }, destination = { type = "s3" } } }
  }
  expect_failures = [terraform_data.guardrails]
}

run "servers_automation_script" {
  command = plan

  # Plan only: the script is rendered and checked, never executed.
  override_resource {
    target          = aws_security_group.mgn_replication[0]
    override_during = plan
    values          = { id = "sg-0mgnreplication000" }
  }

  variables {
    migrate = ["servers"]
    target  = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"] }
    servers = {
      automate  = true
      inventory = { web01 = { os = "windows", licensing = "byol" }, app01 = { os = "rhel" }, api01 = { os = "ubuntu" } }
    }
  }

  assert {
    condition     = length(terraform_data.mgn_setup) == 1
    error_message = "automate = true should schedule the MGN setup"
  }
  assert {
    condition     = strcontains(output.mgn_setup_script, "sg-0mgnreplication000") && strcontains(output.mgn_setup_script, "hostname=='web01'") && strcontains(output.mgn_setup_script, "osByol=true") && !strcontains(output.mgn_setup_script, "hostname=='api01'")
    error_message = "script must use the replication SG and set licensing only for windows/rhel/suse servers"
  }
}

run "images_kubernetes_and_every_ci_system" {
  command = apply

  variables {
    migrate                   = ["images", "kubernetes"]
    target                    = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"] }
    onprem_ca_certificate_pem = "-----BEGIN CERTIFICATE-----\nMIIBmock\n-----END CERTIFICATE-----"

    images = {
      repositories = ["shop/web"]
      copy         = [{ from = "harbor.corp.local/shop/api:2.1", to = "shop/api" }]
      pull_through = {
        docker-hub = { upstream = "docker-hub", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:ecr-pullthroughcache/dockerhub-AbCdEf" }
        k8s        = { upstream = "k8s" }
      }
    }

    kubernetes = {
      target_cluster_name = "prod-eks"
      target_auth         = "irsa"
      source_auth         = "roles-anywhere"
      namespaces          = ["shop", "payments"]
      storage_class_map   = { "vsphere-csi" = "gp3" }
    }

    pipelines = {
      gh      = { provider = "github", repository = "acme/shop", eks_clusters = ["prod-eks"], eks_namespaces = ["shop"] }
      gl      = { provider = "gitlab", repository = "platform/api", issuer_url = "https://gitlab.acme.internal", ecs_clusters = ["acme-prod"], ecs_pass_roles = ["arn:aws:iam::123456789012:role/acme-prod-api-task"] }
      bb      = { provider = "bitbucket", issuer_url = "https://api.bitbucket.org/2.0/workspaces/acme/pipelines-config/identity/oidc", audience = "ari:cloud:bitbucket::workspace/1234", subjects = ["{repo-uuid}:*"] }
      circle  = { provider = "circleci", issuer_url = "https://oidc.circleci.com/org/abc", audience = "abc", subjects = ["org/abc/project/def/user/*"] }
      ado     = { provider = "azure-devops", issuer_url = "https://vstoken.dev.azure.com/0000", subjects = ["sc://acme/shop/aws-prod"] }
      jenkins = { provider = "jenkins", s3_buckets = ["acme-artifacts"] }
      cb      = { provider = "codebuild", codebuild_repo_url = "https://github.com/acme/shop" }
    }
  }

  assert {
    condition     = length(aws_ecr_repository.image) == 2 && length(aws_ecr_pull_through_cache_rule.upstream) == 2 && length(aws_ecr_repository_creation_template.pull_through) == 2
    error_message = "two repositories (one from copy) and two pull-through caches"
  }
  assert {
    condition     = contains(output.summary.images.copy_commands, "skopeo copy --all docker://harbor.corp.local/shop/api:2.1 docker://123456789012.dkr.ecr.us-east-1.amazonaws.com/shop/api:2.1")
    error_message = "copy command must keep the tag"
  }
  assert {
    condition     = aws_ecr_pull_through_cache_rule.upstream["k8s"].upstream_registry_url == "registry.k8s.io"
    error_message = "k8s upstream URL"
  }
  assert {
    condition     = length(aws_s3_bucket.velero) == 1 && strcontains(aws_iam_role.velero_target[0].assume_role_policy, "AssumeRoleWithWebIdentity") && length(aws_eks_pod_identity_association.velero) == 0
    error_message = "IRSA target role for Velero"
  }
  assert {
    condition     = length(aws_rolesanywhere_trust_anchor.onprem) == 1 && length(aws_rolesanywhere_profile.velero) == 1 && length(aws_iam_user.velero_source) == 0
    error_message = "on-prem Velero via Roles Anywhere, no IAM user"
  }
  assert {
    condition     = strcontains(output.summary.kubernetes.storage_class_configmap, "vsphere-csi: gp3") && anytrue([for c in output.summary.kubernetes.source_cluster : strcontains(c, "--include-namespaces shop,payments")])
    error_message = "storage-class mapping and namespace filter"
  }
  assert {
    condition     = length(aws_iam_role.ci) == 7 && length(aws_iam_openid_connect_provider.ci) == 5
    error_message = "seven pipelines, five distinct OIDC issuers"
  }
  assert {
    condition     = strcontains(aws_iam_role.ci["gh"].assume_role_policy, "repo:acme/shop:ref:refs/heads/main") && strcontains(aws_iam_role.ci["gl"].assume_role_policy, "project_path:platform/api:ref_type:branch:ref:main")
    error_message = "default subjects pin the main branch"
  }
  assert {
    condition     = length(aws_eks_access_entry.ci) == 1 && aws_eks_access_policy_association.ci["gh|prod-eks"].access_scope[0].type == "namespace"
    error_message = "EKS deploy is namespace-scoped"
  }
  assert {
    condition     = length(aws_codebuild_project.ci) == 1 && length(aws_rolesanywhere_profile.ci) == 1 && strcontains(output.summary.pipelines.gh.setup, "configure-aws-credentials")
    error_message = "codebuild project, jenkins via Roles Anywhere, usage hints"
  }
}

run "wildcard_ci_subject_refused" {
  command = plan
  variables {
    migrate   = ["images"]
    target    = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"] }
    images    = { repositories = ["app"] }
    pipelines = { any = { provider = "github", subjects = ["*"] } }
  }
  expect_failures = [terraform_data.guardrails]
}

run "jenkins_needs_ca" {
  command = plan
  variables {
    migrate   = ["images"]
    target    = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"] }
    images    = { repositories = ["app"] }
    pipelines = { build = { provider = "jenkins" } }
  }
  expect_failures = [terraform_data.guardrails]
}

run "docker_hub_cache_needs_prefixed_secret" {
  command = plan
  variables {
    migrate = ["images"]
    target  = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"] }
    images  = { pull_through = { hub = { upstream = "docker-hub", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:dockerhub-AbCdEf" } } }
  }
  expect_failures = [terraform_data.guardrails]
}

run "kubernetes_needs_target_cluster" {
  command = plan
  variables {
    migrate = ["kubernetes"]
    target  = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"] }
  }
  expect_failures = [terraform_data.guardrails]
}

run "full_landing_zone_from_scratch" {
  command = apply

  variables {
    profile     = "production"
    alert_email = "migration@example.com"
    migrate     = ["databases", "files", "servers"]
    network     = { create = true, cidr = "10.50.0.0/16", az_count = 3, nat = "per_az" }
    vpn         = { customer_gateway_ip = "198.51.100.10" }
    dns         = { forward_domains = ["corp.local", "ad.corp.local"], onprem_dns_servers = ["10.20.0.2", "10.20.0.3"] }

    databases       = { erp = { source = { engine = "sqlserver", database_name = "ERP", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:erp-AbCdEf" }, target = { secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:erp-tgt-AbCdEf" } } }
    datasync_agents = { dc1 = { activation_key = "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE" } }
    file_shares     = { data = { source = { type = "nfs", agent = "dc1", host = "nas01.corp.local", path = "/data" }, destination = { type = "s3" } } }
    servers         = { inventory = { web01 = { os = "windows" } } }
  }

  assert {
    condition     = length(aws_vpc.this) == 1 && length(aws_subnet.private) == 3 && length(aws_subnet.public) == 3 && length(aws_nat_gateway.this) == 3
    error_message = "3-AZ VPC with a NAT per AZ"
  }
  assert {
    condition     = length(aws_vpc_endpoint.interface) == 12 && length(aws_vpc_endpoint.gateway) == 2 && length(aws_flow_log.this) == 1
    error_message = "production adds private endpoints; gateway endpoints and flow logs always"
  }
  assert {
    condition     = length(aws_vpn_gateway.this) == 1 && length(aws_vpn_gateway_route_propagation.private) == 3 && length(aws_vpn_connection_route.onprem) == 2
    error_message = "VPN on a VGW, propagated to every private route table, static routes per on-prem CIDR"
  }
  assert {
    condition     = contains(aws_vpn_connection.onprem[0].tunnel1_ike_versions, "ikev2") && !contains(aws_vpn_connection.onprem[0].tunnel1_phase1_encryption_algorithms, "AES128") && length(aws_cloudwatch_metric_alarm.vpn_down) == 1
    error_message = "strong ciphers only, tunnel-down alarm"
  }
  assert {
    condition     = length(aws_route53_resolver_rule.forward) == 2 && length(aws_route53_resolver_endpoint.inbound) == 1 && length(aws_route53_resolver_rule_association.forward) == 2
    error_message = "hybrid DNS forwards both domains and offers an inbound endpoint"
  }
  assert {
    condition     = length(aws_dms_replication_subnet_group.main[0].subnet_ids) == 3 && output.summary.network.created == true
    error_message = "DMS runs in the module-built private subnets"
  }
}

run "vpn_on_new_transit_gateway_with_bgp" {
  command = apply

  variables {
    migrate = ["servers"]
    target  = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"], route_table_ids = ["rtb-0aaaaaaaaaaaaaaaa", "rtb-0bbbbbbbbbbbbbbbb"] }
    vpn     = { customer_gateway_ip = "203.0.113.7", attach = "tgw", routing = "bgp", bgp_asn = 65010 }
    servers = { inventory = { app01 = { os = "rhel" } } }
  }

  assert {
    condition     = length(aws_ec2_transit_gateway.this) == 1 && length(aws_ec2_transit_gateway_vpc_attachment.this) == 1 && length(aws_vpn_gateway.this) == 0
    error_message = "TGW created and attached; no VGW"
  }
  assert {
    condition     = length(aws_route.to_onprem_via_tgw) == 4 && length(aws_ec2_transit_gateway_route.onprem) == 0 && aws_vpn_connection.onprem[0].static_routes_only == false
    error_message = "VPC routes to on-prem via TGW; BGP means no static TGW routes"
  }
}

run "landing_network_must_be_one_choice" {
  command = plan
  variables {
    migrate = ["servers"]
    target  = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"] }
    network = { create = true }
    servers = { inventory = { web01 = { os = "rhel" } } }
  }
  expect_failures = [terraform_data.guardrails]
}

run "vpn_on_existing_vpc_needs_route_tables" {
  command = plan
  variables {
    migrate = ["servers"]
    target  = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"] }
    vpn     = { customer_gateway_ip = "198.51.100.10" }
    servers = { inventory = { web01 = { os = "rhel" } } }
  }
  expect_failures = [terraform_data.guardrails]
}

run "no_nat_needs_endpoints" {
  command = plan
  variables {
    migrate = ["servers"]
    network = { create = true, nat = "none" }
    servers = { inventory = { web01 = { os = "rhel" } } }
  }
  expect_failures = [terraform_data.guardrails]
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
