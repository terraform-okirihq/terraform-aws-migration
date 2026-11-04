# AWS Migration Module

[![Terraform CI](https://github.com/terraform-aws-okirihq/terraform-aws-migration/actions/workflows/terraform-ci.yml/badge.svg)](https://github.com/terraform-aws-okirihq/terraform-aws-migration/actions/workflows/terraform-ci.yml)
[![Terraform Registry](https://img.shields.io/badge/Terraform%20Registry-terraform--aws--okirihq%2Fmigration%2Faws-623CE4?logo=terraform)](https://registry.terraform.io/modules/terraform-aws-okirihq/migration/aws)
[![Terraform](https://img.shields.io/badge/Terraform-%E2%89%A51.5-623CE4?logo=terraform)](https://www.terraform.io/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Move databases, file shares and servers from your data centre to AWS with one module. Tell it **what** to
migrate and **where** it lands; it builds the AWS side of DMS, DataSync and Application Migration Service with
secure defaults, and prints a step-by-step cutover runbook for every workload.

Built to be temporary: when the cutover is done, `terraform destroy` removes all migration tooling and leaves
your target environment untouched.

```hcl
module "migration" {
  source  = "terraform-aws-okirihq/migration/aws"
  version = "~> 0.1"

  name         = "acme"
  migrate      = ["databases", "files", "servers"]
  target       = { vpc_id = "vpc-0123", subnet_ids = ["subnet-a", "subnet-b"] }
  onprem_cidrs = ["10.20.0.0/16"]

  databases = {
    shop = {
      source = { engine = "mysql", database_name = "shop", secret_arn = "arn:aws:secretsmanager:...:onprem-shop" }
      target = { secret_arn = "arn:aws:secretsmanager:...:rds-shop" }
    }
  }

  datasync_agents = { dc1 = { activation_key = "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE" } }
  file_shares = {
    media = { source = { type = "nfs", agent = "dc1", host = "nas01", path = "/exports/media" }, destination = { type = "s3" } }
  }

  servers = { inventory = { web01 = { os = "windows" }, app01 = { os = "rhel" } } }
}
```

---

## Contents

- [What it supports](#what-it-supports)
- [Quick start](#quick-start)
- [How a migration runs](#how-a-migration-runs)
- [Databases](#databases)
- [Files](#files)
- [Servers](#servers)
- [Profiles](#profiles)
- [Guardrails](#guardrails)
- [Outputs](#outputs)
- [Using it with the platform module](#using-it-with-the-platform-module)
- [Limitations](#limitations)
- [Testing and CI](#testing-and-ci)
- [Repository layout](#repository-layout)

---

## What it supports

| Workload | Sources | Lands on | AWS service |
|:---------|:--------|:---------|:------------|
| Databases | MySQL, MariaDB, PostgreSQL, Oracle, SQL Server, Db2, SAP ASE (Sybase), MongoDB | RDS / Aurora (MySQL, PostgreSQL), RDS for Oracle / SQL Server, DocumentDB, Redshift, S3 data lake | DMS (Serverless, or instance-based where Serverless doesn't apply) |
| Files | NFS (Linux/Unix), SMB (Windows), HDFS (Hadoop), S3-compatible object storage (MinIO, StorageGRID, ...) | S3 (any storage class), EFS, FSx for Windows File Server | DataSync |
| Servers | Windows Server, RHEL, CentOS, Rocky, AlmaLinux, Oracle Linux, Amazon Linux, Ubuntu, Debian, SUSE | EC2 | Application Migration Service (MGN) |

Mix any of them: a Windows estate, a Linux estate, or both at once. See [examples](examples).

| Example | Shows |
|:--------|:------|
| [windows-estate](examples/windows-estate/main.tf) | SQL Server, SMB shares into FSx for Windows, Windows Server with license-included and BYOL |
| [linux-estate](examples/linux-estate/main.tf) | MySQL to Aurora, PostgreSQL with table filters, NFS into S3 and EFS, RHEL / Ubuntu / SUSE / Oracle Linux |
| [mixed-estate](examples/mixed-estate/main.tf) | Production profile: Oracle to Aurora PostgreSQL, Sybase, MongoDB to DocumentDB, Db2 to S3, HDFS, MinIO |
| [with-platform](examples/with-platform/main.tf) | Migrating into a stack built with [`OkiriGabriel/platform/aws`](https://registry.terraform.io/modules/OkiriGabriel/platform/aws) |

---

## Quick start

**You need:**

1. **Network connectivity** from AWS to your data centre: Site-to-Site VPN, Direct Connect or Transit Gateway.
   Put those on-prem ranges in `onprem_cidrs`.
2. **A target VPC** with private subnets in at least two AZs, or a stack built with the platform module.
3. **Secrets in Secrets Manager**, one per database endpoint, as JSON in the format DMS reads natively:
   ```json
   { "username": "dms_user", "password": "...", "host": "10.20.0.15", "port": 5432 }
   ```
   For SMB, FSx or object storage: `{ "username": "...", "password": "..." }` or `{ "access_key": "...", "secret_key": "..." }`.
4. **For files:** the DataSync agent appliance (VMware, Hyper-V or KVM image from the DataSync console) running
   on-prem, plus its activation key.

Then:

```bash
terraform init
terraform apply
terraform output -json summary   # your per-workload runbook
```

---

## How a migration runs

```
 1. apply            2. sync                       3. cutover                  4. clean up
 ─────────────       ─────────────────────         ──────────────────────      ────────────────
 module creates      DMS: full load, then          stop writes on-prem,        terraform destroy
 replication,        continuous change capture     wait for lag ~ 0,           (stack is tagged
 tasks, roles,       DataSync: scheduled re-syncs  stop replication / final    Lifecycle = temporary)
 alerts              MGN: block-level replication  DataSync run / MGN cutover
```

Replications are **created stopped** by default (`start = false`), so you can check connectivity and settings
first. The `summary` output gives the exact `start`, `status` and `stop` command for every database, the
`run` / `status` commands for every share, and the full MGN sequence for servers.

Every DMS and DataSync state change in this stack is sent to an SNS topic. Set `alert_email` to receive them.

---

## Databases

```hcl
databases = {
  erp = {
    source = {
      engine        = "sqlserver"
      database_name = "ERP"
      secret_arn    = "arn:aws:secretsmanager:...:onprem-erp"
      ssl_mode      = "require"            # none | require | verify-ca | verify-full
    }
    target = {
      engine     = "sqlserver"             # default: same engine as the source (mongodb -> docdb)
      secret_arn = "arn:aws:secretsmanager:...:rds-erp"
    }
    mode               = "full-load-and-cdc" # full-load | cdc | full-load-and-cdc
    include            = [{ schema = "dbo" }]
    exclude            = [{ schema = "dbo", table = "audit_%" }]
    on_existing_tables = "keep"              # keep | truncate | drop
    start              = false
  }
}
```

| Behaviour | Detail |
|:----------|:-------|
| Credentials | Read by DMS from Secrets Manager at runtime; never in Terraform state. One IAM role can read exactly the listed secrets |
| Encryption in transit | `ssl_mode = "require"` by default. `none` is refused unless you set `allow_unencrypted = true` for that database |
| Certificates | `verify-ca` / `verify-full` (and Oracle SSL) take the CA in `ca_certificate_pem`; the module registers it with DMS |
| Compute | DMS Serverless by default (scales between the profile's capacity units). SAP ASE (Sybase) runs on an instance automatically; set `compute = "instance"` for any other |
| Existing data | `on_existing_tables = "keep"` never drops target tables. Choose `truncate` or `drop` for a clean reload |
| Heterogeneous moves | Oracle / SQL Server / Db2 / Sybase into PostgreSQL or MySQL: convert the schema first with AWS DMS Schema Conversion or AWS SCT, then replicate the data with this module |
| Validation | Production compares rows between source and target for relational targets |
| S3 data lake | `target = { engine = "s3", s3_bucket = "lake", s3_folder = "db2/sales" }` writes Parquet (or CSV), date-partitioned, encrypted |
| Network | DMS gets its own security group: out to `onprem_cidrs`, the VPC and AWS APIs only. Allow it on your target database's security group (automatic for the platform module's RDS) |

---

## Files

```hcl
datasync_agents = {
  dc1 = { activation_key = "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE" } # or ip_address = "...", or arn = "existing agent"
}

file_shares = {
  departments = {
    source      = { type = "smb", agent = "dc1", host = "fs01.corp.local", path = "/Departments", smb_domain = "CORP", secret_arn = "arn:aws:secretsmanager:...:smb" }
    destination = { type = "fsx-windows", fsx_windows_arn = "arn:aws:fsx:...", fsx_secret_arn = "arn:aws:secretsmanager:...:fsx" }
    schedule    = "cron(0 1 * * ? *)"   # nightly re-sync until cutover; null = on demand
  }
  media = {
    source         = { type = "nfs", agent = "dc1", host = "nas01", path = "/exports/media", nfs_version = "NFS4_1" }
    destination    = { type = "s3", s3_storage_class = "INTELLIGENT_TIERING" } # bucket created when s3_bucket is null
    bandwidth_mbps = 200
    excludes       = ["*.tmp", "/cache"]
  }
}
```

| Behaviour | Detail |
|:----------|:-------|
| Sources | `nfs`, `smb`, `hdfs` (simple auth), `object-storage` (S3-compatible, HTTPS) |
| Destinations | `s3` (existing bucket, or one created with versioning, encryption, TLS-only policy, ACLs off), `efs` (TLS in transit), `fsx-windows` |
| Transfers | Only changed data is copied; deleted files are preserved by default; verification defaults to `ONLY_FILES_TRANSFERRED` |
| Bandwidth | `bandwidth_mbps` caps each task so business traffic keeps its share of the link |
| Private connectivity | Production routes agents over a DataSync VPC endpoint (PrivateLink) instead of the internet |
| Logs | Per-task logs in CloudWatch (`/aws/datasync/<name>-<env>-mig`) |

---

## Servers

AWS Application Migration Service (MGN) replicates whole servers block by block and launches them as EC2
instances. **The AWS Terraform provider has no MGN resources**, so this module builds everything Terraform can
and generates the exact commands for the rest:

| Built by Terraform | Generated for you (in `summary.servers`) |
|:-------------------|:-----------------------------------------|
| Replication security group (TCP 1500 from `onprem_cidrs` only) | One-time `aws mgn initialize-service` |
| Staging subnet choice | Replication template command with your subnet, security group, private routing, bandwidth |
| Agent installer IAM role (short-lived credentials, no IAM user or static keys) | Credentials command (`aws sts assume-role` into that role) |
| | **Per-server install command for its OS** (PowerShell for Windows, shell for Linux) |
| | Kernel-header package hint per distro family (`yum`, `apt-get`, `zypper`) |
| | Licensing command for Windows / RHEL / SUSE (`aws` license-included or `byol`) |
| | Test, cutover, finalize and archive commands |

```hcl
servers = {
  use_private_ip = true          # replicate over VPN / Direct Connect (default)
  inventory = {
    web01 = { os = "windows", licensing = "byol" }
    app01 = { os = "rhel" }
    api01 = { os = "ubuntu" }
  }
}
```

Supported `os` values: `windows`, `rhel`, `centos`, `rocky`, `alma`, `oracle-linux`, `amazon-linux`, `ubuntu`,
`debian`, `suse`.

---

## Profiles

| Setting | `pilot` (default) | `production` |
|:--------|:------------------|:-------------|
| DMS Serverless capacity | 1-4 DCU | 2-16 DCU |
| DMS Multi-AZ | no | yes |
| DMS instance class (instance-based engines) | dms.t3.medium | dms.r6i.large |
| Row validation | no | yes (relational targets) |
| Customer-managed KMS key | no (AWS-managed keys) | yes, unless you pass `kms_key_arn` |
| DataSync agents over PrivateLink | no | yes |
| Log retention | 14 days | 90 days |
| `alert_email` | optional | required |

Override any of these with `overrides = { dms_max_capacity_units = 32 }`; the `settings` output lists every key.

---

## Guardrails

The plan stops with a clear message instead of failing halfway through an apply:

| Refused | Fix |
|:--------|:----|
| Credentials that are not Secrets Manager ARNs | Store them in Secrets Manager |
| `ssl_mode = "none"` | Use TLS, or `allow_unencrypted = true` for that database |
| `verify-ca` / `verify-full` without a CA certificate | Set `ca_certificate_pem` |
| Db2 / Sybase without a target engine | Set `target.engine` |
| MongoDB into a relational database, or relational into DocumentDB | Use `docdb` / `s3`, or a relational target |
| Databases with fewer than two subnets | DMS needs subnets in two AZs |
| A share pointing at an unknown agent, or an agent with zero / several activation methods | Fix `datasync_agents` |
| SMB / object storage / FSx without a credentials secret | Set `secret_arn` / `fsx_secret_arn` |
| Both, or neither, of `target.platform_name` and `target.vpc_id` | Choose one |
| `production` without `alert_email` | Set it |
| Unknown OS, engine, share type or mode | Use a supported value |

---

## Outputs

| Output | Contents |
|:-------|:---------|
| `summary` | Network, per-database route + TLS + start/status/stop commands, per-share route + schedule + run/status commands, full server runbook, next steps, cost notes |
| `settings` | Resolved profile settings |
| `security_group_ids` | DMS, DataSync and MGN replication security groups (allow these on your targets) |
| `dms` | Serverless replication ARNs, task ARNs, replication instance |
| `datasync` | Agent ARNs, task ARNs, destination bucket names |
| `mgn_installer_role_arn` | Role for short-lived agent install credentials |
| `alerts_topic_arn` | SNS topic with every DMS / DataSync state change |
| `kms_key_arn` | Key used for migration data |

---

## Using it with the platform module

```hcl
module "migration" {
  source  = "terraform-aws-okirihq/migration/aws"
  version = "~> 0.1"

  name         = "acme"
  environment  = "prod"
  migrate      = ["databases", "files"]
  target       = { platform_name = "acme-prod" }   # name-env of the platform stack
  onprem_cidrs = ["10.20.0.0/16"]

  databases = {
    app = {
      source = { engine = "postgres", database_name = "app", secret_arn = "..." }
      target = { platform_database = true, secret_arn = "..." }  # opens the platform RDS to DMS automatically
    }
  }
  # destination = { type = "efs" } with no ARN uses the platform's shared EFS
}
```

It discovers the platform's VPC, private subnets, RDS security group and shared EFS by name, and adds the
security-group rules DMS and DataSync need. Those rules are removed when you destroy the migration stack.
Keep the migration in **its own folder and state**, so destroying it never touches the platform.

The platform module already provides the network path (`vpn`, `client-vpn`, `transit-gateway` in its `stack`).

---

## Limitations

- **MGN is not in the Terraform AWS provider.** Server replication settings and agent installs are run from the
  generated commands, not by `terraform apply`.
- **DataSync credentials in state.** DataSync requires SMB, FSx and object-storage credentials as resource
  arguments, so those values (marked sensitive) are in Terraform state. Keep state encrypted and access-controlled.
  Database credentials are not in state.
- **Schema conversion is separate.** For heterogeneous moves (for example Oracle to PostgreSQL), convert the schema
  first with AWS DMS Schema Conversion or SCT.
- **HDFS** supports simple authentication; Kerberos is not configured by this module.
- **DataSync agents** are appliances you deploy on-prem (or on EC2); the module activates and uses them.
- **Account-level DMS roles** (`dms-vpc-role`, `dms-cloudwatch-logs-role`) are created by default. Set
  `create_dms_service_roles = false` if your account already has them.
- **One region per module instance.**

---

## Testing and CI

```bash
terraform init -backend=false
terraform test
```

The suite runs a mixed estate (seven database engines, four share types, five operating systems), a production
deployment on the platform module, and every guardrail against a mocked AWS provider: no credentials, nothing
created. CI runs on every push and pull request: format, TFLint, validate (module and all examples), tests,
Gitleaks and Checkov.

---

## Repository layout

```
.
├── main.tf            # KMS, alerts topic, platform security-group rules
├── variables.tf       # Inputs
├── locals.tf          # Profiles, target network discovery, engine rules
├── guardrails.tf      # Plan-time refusals
├── databases.tf       # DMS: roles, endpoints, serverless + instance replication, alerts
├── files.tf           # DataSync: agents, PrivateLink, locations, buckets, tasks, logs, alerts
├── servers.tf         # MGN: replication security group, installer role, per-OS commands
├── outputs.tf         # summary runbook and building-block outputs
├── versions.tf
├── examples/          # windows-estate, linux-estate, mixed-estate, with-platform
└── tests/             # terraform test suite (mocked provider)
```

## License

MIT. See [LICENSE](LICENSE).
