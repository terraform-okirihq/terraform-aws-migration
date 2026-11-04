# Windows shop: SQL Server databases, SMB file shares into FSx for Windows, Windows Server VMs.
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
  source = "../../" # in your repo: source = "terraform-aws-okirihq/migration/aws", version = "~> 0.1"

  name         = "contoso"
  profile      = "pilot"
  migrate      = ["databases", "files", "servers"]
  target       = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"] }
  onprem_cidrs = ["10.10.0.0/16"]

  databases = {
    erp = {
      source = { engine = "sqlserver", database_name = "ERP", secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:onprem-erp-AbCdEf" }
      target = { secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:rds-erp-AbCdEf" } # RDS for SQL Server
    }
  }

  datasync_agents = { hq = { activation_key = "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE" } }

  file_shares = {
    departments = {
      source      = { type = "smb", agent = "hq", host = "fs01.contoso.local", path = "/Departments", smb_domain = "CONTOSO", secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:smb-svc-AbCdEf" }
      destination = { type = "fsx-windows", fsx_windows_arn = "arn:aws:fsx:us-east-1:111122223333:file-system/fs-0123456789abcdef0", fsx_secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:fsx-svc-AbCdEf", fsx_domain = "CONTOSO" }
      schedule    = "cron(0 1 * * ? *)" # nightly re-sync until cutover
    }
  }

  servers = {
    inventory = {
      iis01 = { os = "windows", licensing = "aws" }  # license included
      iis02 = { os = "windows", licensing = "byol" } # bring your own (dedicated hosts / SA)
      app01 = { os = "windows" }
    }
  }
}

output "summary" {
  value = module.migration.summary
}
