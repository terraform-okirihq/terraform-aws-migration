# Migrate into a stack built with OkiriGabriel/platform/aws. Keep this in its own folder and state so that
# "terraform destroy" after cutover removes only the migration tooling, never the platform.
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
  environment  = "prod"
  profile      = "production"
  migrate      = ["databases", "files"]
  target       = { platform_name = "acme-prod" } # finds the platform's VPC, private subnets, RDS and EFS
  onprem_cidrs = ["10.20.0.0/16"]
  alert_email  = "migration@acme.example"

  databases = {
    app = {
      source = { engine = "postgres", database_name = "app", secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:onprem-app-AbCdEf" }
      # A dedicated DMS user on the platform database (host/port/username/password in the secret):
      target = { platform_database = true, secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:platform-dms-AbCdEf" }
    }
  }

  datasync_agents = { dc1 = { activation_key = "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE" } }

  file_shares = {
    uploads = {
      source      = { type = "nfs", agent = "dc1", host = "nas01.acme.local", path = "/exports/uploads" }
      destination = { type = "efs", path = "/app/uploads" } # the platform's shared EFS
    }
  }
}

output "summary" {
  value = module.migration.summary
}
