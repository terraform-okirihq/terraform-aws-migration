# Linux shop: RHEL / Ubuntu / SUSE servers, MySQL + PostgreSQL, NFS exports into S3 and EFS.
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.70.0, < 6.0.0" }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "migration" {
  source = "../../"

  name         = "acme"
  profile      = "pilot"
  migrate      = ["databases", "files", "servers"]
  target       = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"] }
  onprem_cidrs = ["172.16.0.0/12"]

  databases = {
    shop = {
      source = { engine = "mysql", database_name = "shop", secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:onprem-shop-AbCdEf" }
      target = { engine = "aurora", secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:aurora-shop-AbCdEf" }
    }
    billing = {
      source  = { engine = "postgres", database_name = "billing", secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:onprem-billing-AbCdEf" }
      target  = { secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:rds-billing-AbCdEf" }
      include = [{ schema = "public" }, { schema = "invoices" }]
      exclude = [{ schema = "public", table = "audit_%" }]
    }
  }

  datasync_agents = { dc1 = { activation_key = "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE" } }

  file_shares = {
    media = {
      source      = { type = "nfs", agent = "dc1", host = "nas01.acme.local", path = "/exports/media", nfs_version = "NFS4_1" }
      destination = { type = "s3", s3_storage_class = "INTELLIGENT_TIERING" } # bucket created by the module
      excludes    = ["*.tmp", "/cache"]
    }
    home = {
      source      = { type = "nfs", agent = "dc1", host = "nas01.acme.local", path = "/exports/home" }
      destination = { type = "efs", efs_file_system_arn = "arn:aws:elasticfilesystem:us-east-1:111122223333:file-system/fs-0123456789abcdef0" }
    }
  }

  servers = {
    inventory = {
      web01   = { os = "ubuntu" }
      app01   = { os = "rhel", licensing = "byol" } # Red Hat Cloud Access
      app02   = { os = "rocky" }
      erp01   = { os = "suse", licensing = "aws" }
      batch01 = { os = "oracle-linux" }
    }
  }
}

output "summary" {
  value = module.migration.summary
}
