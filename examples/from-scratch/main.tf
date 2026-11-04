# Empty AWS account -> full migration landing zone in one module call: VPC, VPN to the data centre, hybrid DNS,
# then databases, file shares and servers. Pick only the parts you need.

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
  source = "../../" # in your repo: source = "terraform-okirihq/migration/aws", version = "~> 0.2"

  name         = "acme"
  profile      = "production"
  alert_email  = "migration@acme.example"
  onprem_cidrs = ["10.20.0.0/16"]

  # 1. Network: VPC across 3 AZs, NAT per AZ, private AWS endpoints (production), flow logs.
  network = { create = true, cidr = "10.100.0.0/16", az_count = 3, nat = "per_az" }

  # 2. Connectivity: IPsec VPN to the data-centre firewall (static routes to onprem_cidrs).
  vpn = { customer_gateway_ip = "198.51.100.10", bgp_asn = 65000 }

  # 3. Hybrid DNS: AWS resolves corp.local via your DNS servers; they can resolve AWS via the inbound IPs.
  dns = { forward_domains = ["corp.local"], onprem_dns_servers = ["10.20.0.2", "10.20.0.3"] }

  # 4. What to move.
  migrate = ["databases", "files", "servers"]

  databases = {
    erp = {
      source = { engine = "sqlserver", database_name = "ERP", secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:onprem-erp-AbCdEf" }
      target = { secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:rds-erp-AbCdEf" }
    }
  }

  datasync_agents = { dc1 = { activation_key = "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE" } }
  file_shares = {
    shared = { source = { type = "smb", agent = "dc1", host = "fs01.corp.local", path = "/Shared", smb_domain = "CORP", secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:smb-AbCdEf" }, destination = { type = "s3" } }
  }

  servers = {
    automate  = true
    inventory = { web01 = { os = "windows" }, app01 = { os = "rhel" }, api01 = { os = "ubuntu" } }
  }
}

output "summary" {
  value = module.migration.summary
}
