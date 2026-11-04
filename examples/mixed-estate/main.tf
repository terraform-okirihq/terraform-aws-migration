# Everything at once, production profile: Oracle -> PostgreSQL, SAP ASE (Sybase) -> PostgreSQL, MongoDB ->
# DocumentDB, Db2 -> S3 data lake, Hadoop + S3-compatible storage -> S3, Windows and Linux servers.
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

  name         = "globex"
  profile      = "production"
  migrate      = ["databases", "files", "servers"]
  target       = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb", "subnet-0cccccccccccccccc"] }
  onprem_cidrs = ["10.0.0.0/8"]
  alert_email  = "migration@globex.example"

  databases = {
    hr = {
      source = { engine = "oracle", database_name = "HRPROD", ssl_mode = "verify-ca", ca_certificate_pem = "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----", secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:oracle-hr-AbCdEf" }
      target = { engine = "aurora-postgresql", secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:aurora-hr-AbCdEf" }
      # Convert the schema first (AWS DMS Schema Conversion / SCT), then replicate data:
      on_existing_tables = "keep"
    }
    legacy = {
      source = { engine = "sybase", database_name = "legacy", secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:ase-legacy-AbCdEf" }
      target = { engine = "postgres", secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:pg-legacy-AbCdEf" } # runs instance-based automatically
    }
    catalog = {
      source = { engine = "mongodb", database_name = "catalog", secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:mongo-catalog-AbCdEf" }
      target = { secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:docdb-catalog-AbCdEf" } # -> DocumentDB
    }
    sales-history = {
      source = { engine = "db2", database_name = "SALES", secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:db2-sales-AbCdEf" }
      target = { engine = "s3", s3_bucket = "globex-datalake", s3_folder = "db2/sales" }
      mode   = "full-load"
    }
  }

  datasync_agents = {
    dc1 = { activation_key = "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE" }
    dc2 = { arn = "arn:aws:datasync:us-east-1:111122223333:agent/agent-0123456789abcdef0" }
  }

  file_shares = {
    warehouse = {
      source      = { type = "hdfs", agent = "dc1", path = "/warehouse", hdfs_name_nodes = [{ host = "nn01.globex.local" }, { host = "nn02.globex.local" }], hdfs_simple_user = "hdfs" }
      destination = { type = "s3", s3_bucket = "globex-datalake", path = "/hdfs/warehouse" }
    }
    assets = {
      source         = { type = "object-storage", agent = "dc2", host = "minio.globex.local", path = "assets", secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:minio-AbCdEf" }
      destination    = { type = "s3" }
      bandwidth_mbps = 500
      verify         = "POINT_IN_TIME_CONSISTENT"
    }
  }

  servers = {
    inventory = {
      dc01  = { os = "windows", licensing = "byol" }
      web01 = { os = "rhel" }
      web02 = { os = "alma" }
      ops01 = { os = "debian" }
      tool1 = { os = "amazon-linux" }
    }
  }
}

output "summary" {
  value = module.migration.summary
}
