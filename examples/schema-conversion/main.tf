# Heterogeneous move: Oracle -> Aurora PostgreSQL. Step 1 converts the schema and code (DMS Schema Conversion),
# step 2 replicates the data (DMS). Both reuse the same secrets and the same private network.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws   = { source = "hashicorp/aws", version = ">= 5.70.0, < 6.0.0" }
    awscc = { source = "hashicorp/awscc", version = ">= 1.106.0, < 2.0.0" }
  }
}

provider "aws" {
  region = "us-east-1"
}

provider "awscc" {
  region = "us-east-1"
}

module "migration" {
  source = "../../" # in your repo: source = "terraform-okirihq/migration/aws", version = "~> 0.2"

  name         = "acme"
  migrate      = ["databases"]
  target       = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"] }
  onprem_cidrs = ["10.20.0.0/16"]

  databases = {
    hr = {
      source             = { engine = "oracle", database_name = "HRPROD", secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:oracle-hr-AbCdEf" }
      target             = { engine = "aurora-postgresql", secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:aurora-hr-AbCdEf" }
      on_existing_tables = "keep" # tables come from the schema conversion
    }
  }
}

module "schema_conversion" {
  source = "../../modules/schema-conversion" # in your repo: "terraform-okirihq/migration/aws//modules/schema-conversion"

  name    = "acme"
  network = module.migration.schema_conversion_network

  projects = {
    hr = {
      source = { engine = "oracle", host = "ora01.corp.local", port = 1521, database_name = "HRPROD", secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:oracle-hr-AbCdEf" }
      target = { engine = "aurora-postgresql", host = "hr.cluster-abc.us-east-1.rds.amazonaws.com", port = 5432, database_name = "hr", secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:aurora-hr-AbCdEf" }
    }
  }
}

output "schema_conversion" {
  value = { projects = module.schema_conversion.migration_projects, next = module.schema_conversion.next_steps }
}

output "data_replication" {
  value = module.migration.summary.databases
}
