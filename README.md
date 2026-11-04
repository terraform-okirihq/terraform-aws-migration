# AWS Migration Module

[![Terraform CI](https://github.com/terraform-okirihq/terraform-aws-migration/actions/workflows/terraform-ci.yml/badge.svg)](https://github.com/terraform-okirihq/terraform-aws-migration/actions/workflows/terraform-ci.yml)
[![Terraform Registry](https://img.shields.io/badge/Terraform%20Registry-terraform--okirihq%2Fmigration%2Faws-623CE4?logo=terraform)](https://registry.terraform.io/modules/terraform-okirihq/migration/aws)
[![Terraform](https://img.shields.io/badge/Terraform-%E2%89%A51.5-623CE4?logo=terraform)](https://www.terraform.io/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Move databases, file shares, servers, container images and Kubernetes workloads from your data centre to AWS
with one module, and set up the CI/CD that keeps shipping them. Tell it **what** to migrate and **where** it
lands; it builds the AWS side of DMS, DataSync, Application Migration Service, ECR and Velero with secure
defaults, creates keyless deploy roles for any CI system, and prints a step-by-step cutover runbook.

**Starting from nothing?** It also builds the landing network: VPC, Site-to-Site VPN to your data centre and
hybrid DNS. Already have a VPC or the [platform module](https://registry.terraform.io/modules/OkiriGabriel/platform/aws)?
Point it there instead. You spin up only the parts you need.

Built to be temporary: when the cutover is done, `terraform destroy` removes all migration tooling and leaves
your target environment untouched.

```hcl
module "migration" {
  source  = "terraform-okirihq/migration/aws"
  version = "~> 0.2"

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
- [Landing network: VPC, VPN, DNS](#landing-network-vpc-vpn-dns)
- [Databases](#databases)
- [Files](#files)
- [Servers](#servers)
- [Container images](#container-images)
- [Kubernetes to EKS](#kubernetes-to-eks)
- [CI/CD pipelines](#cicd-pipelines)
- [Schema conversion](#schema-conversion)
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
| Network | Your data centre (any IPsec router / firewall), your DNS servers | A VPC built here, an existing VPC, or the platform module | VPC, Site-to-Site VPN (VGW or Transit Gateway), Route 53 Resolver |
| Databases | MySQL, MariaDB, PostgreSQL, Oracle, SQL Server, Db2, SAP ASE (Sybase), MongoDB | RDS / Aurora (MySQL, PostgreSQL), RDS for Oracle / SQL Server, DocumentDB, Redshift, S3 data lake | DMS (Serverless, or instance-based where Serverless doesn't apply) |
| Schemas and code | Oracle, SQL Server, Db2, Sybase, MySQL, PostgreSQL, ... | PostgreSQL / Aurora, MySQL, ... | DMS Schema Conversion ([submodule](modules/schema-conversion)) |
| Files | NFS (Linux/Unix), SMB (Windows), HDFS (Hadoop, simple or Kerberos), S3-compatible storage (MinIO, StorageGRID, GCS interop), S3 in another account or region, Azure Blob | S3 (any storage class), EFS, FSx for Windows File Server | DataSync |
| Servers | Windows Server, RHEL, CentOS, Rocky, AlmaLinux, Oracle Linux, Amazon Linux, Ubuntu, Debian, SUSE | EC2 | Application Migration Service (MGN) |
| Container images | Harbor, Nexus, Artifactory, any Docker registry; Docker Hub, Quay, GHCR, GitLab, registry.k8s.io, ECR Public, Azure (cached) | ECR | ECR + pull-through cache |
| Kubernetes | OpenShift, Rancher, Tanzu, kubeadm, k3s, any conformant cluster | EKS | Velero (S3 + Pod Identity / IRSA) |
| CI/CD | GitHub Actions, GitLab (SaaS or self-managed), Bitbucket, CircleCI, Azure DevOps, Jenkins / on-prem CI | Deploy roles for ECR, ECS, EKS, S3 | IAM OIDC, IAM Roles Anywhere, CodeBuild |

Mix any of them: a Windows estate, a Linux estate, or both at once. See [examples](examples).

| Example | Shows |
|:--------|:------|
| [from-scratch](examples/from-scratch/main.tf) | Empty account: VPC + VPN + hybrid DNS, then SQL Server, SMB shares, Windows / RHEL / Ubuntu servers (automated MGN) |
| [windows-estate](examples/windows-estate/main.tf) | SQL Server, SMB shares into FSx for Windows, Windows Server with license-included and BYOL |
| [linux-estate](examples/linux-estate/main.tf) | MySQL to Aurora, PostgreSQL with table filters, NFS into S3 and EFS, RHEL / Ubuntu / SUSE / Oracle Linux |
| [mixed-estate](examples/mixed-estate/main.tf) | Production profile: Oracle to Aurora PostgreSQL, Sybase, MongoDB to DocumentDB, Db2 to S3, HDFS, MinIO |
| [kubernetes-and-cicd](examples/kubernetes-and-cicd/main.tf) | OpenShift to EKS with Velero, Harbor + Docker Hub images into ECR, GitHub / GitLab / Jenkins deploy roles |
| [schema-conversion](examples/schema-conversion/main.tf) | Oracle to Aurora PostgreSQL: convert the schema, then replicate the data |
| [with-platform](examples/with-platform/main.tf) | Migrating into a stack built with [`OkiriGabriel/platform/aws`](https://registry.terraform.io/modules/OkiriGabriel/platform/aws) |

---

## Quick start

**You need:**

1. **Your on-prem ranges** in `onprem_cidrs`. No VPN yet? Set `vpn` and the module builds it (or bring your own
   VPN, Direct Connect or Transit Gateway).
2. **A landing network:** `network = { create = true }` builds one; or use an existing VPC (private subnets in two
   AZs) or a stack from the platform module.
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

## Landing network: VPC, VPN, DNS

Choose exactly one landing network:

| Option | Input | Use when |
|:-------|:------|:---------|
| Build it here | `network = { create = true, cidr = "10.100.0.0/16", az_count = 3, nat = "per_az" }` | No AWS network yet |
| Existing VPC | `target = { vpc_id = "...", subnet_ids = [...], route_table_ids = [...] }` | You already have one |
| Platform module | `target = { platform_name = "acme-prod" }` | You built it with `OkiriGabriel/platform/aws` |

`network.create` builds public and private subnets in each AZ, NAT (`none`, `single` or `per_az`), free S3 and
DynamoDB gateway endpoints, VPC flow logs and a locked default security group. With `interface_endpoints`
(default in production) it adds private endpoints for DMS, MGN, Secrets Manager, KMS, CloudWatch Logs, STS, SSM,
EC2 and ECR, reachable from on-prem too, so migration traffic to AWS APIs never needs the internet.

```hcl
vpn = {
  customer_gateway_ip = "198.51.100.10"  # your firewall's public IP
  bgp_asn             = 65000
  routing             = "static"         # static (routes = onprem_cidrs) | bgp
  attach              = "vgw"            # vgw | tgw (transit_gateway_id, or one is created)
}

dns = {
  forward_domains    = ["corp.local"]              # AWS resolves these via your DNS servers
  onprem_dns_servers = ["10.20.0.2", "10.20.0.3"]
  inbound            = true                        # your DNS can resolve AWS names via the inbound IPs
}
```

| Behaviour | Detail |
|:----------|:-------|
| VPN security | IKEv2 only, AES-256 / AES-256-GCM, SHA-2, DH groups 14+, both tunnels logged to CloudWatch |
| Routing | Static routes for every `onprem_cidrs` entry (on the VGW or the TGW route table), or BGP; private route tables reach on-prem through the VGW (propagation) or TGW |
| Router setup | `summary.network.vpn.router_config` gives the commands that download a ready-made config for your firewall model (Cisco, Fortinet, Palo Alto, pfSense, Juniper, ...) |
| Monitoring | Alarm `<name>-<env>-mig-vpn-down` when both tunnels are down, to the alerts topic |
| Hybrid DNS | Outbound resolver endpoint + forwarding rules per domain; inbound endpoint IPs in `summary.network.dns.inbound_ips` for your conditional forwarders |

The VPC, subnets and gateways carry `Lifecycle = keep`: they are the foundation your migrated workloads run on,
so move them to a long-lived stack (`terraform state mv` / `state rm`) before destroying the migration tooling.

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
| Sources | `nfs`, `smb`, `hdfs` (simple or Kerberos: principal, keytab and krb5.conf from Secrets Manager, QOP `PRIVACY` by default), `object-storage` (S3-compatible, HTTPS), `s3` (another account or region, no agent; `summary.files.<share>.source_bucket_policy` is the policy the source owner adds), `azure-blob` (SAS token) |
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

Set `servers.automate = true` and the module also **applies the MGN setup itself** during `terraform apply`
(AWS CLI, idempotent): initializes the service, creates or updates the replication and launch templates
(`launch_disposition`, `right_sizing`), and, once agents have connected, sets each server's licensing by
hostname. Re-apply after installing agents. Needs `bash` and the AWS CLI where Terraform runs; the script is
also in the `mgn_setup_script` output if you prefer to run it yourself or in CI.

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

## Container images

```hcl
migrate = ["images"]
images = {
  repositories = ["shop/worker"]
  copy = [{ from = "harbor.corp.local/shop/web:3.2.0", to = "shop/web" }]   # Harbor / Nexus / Artifactory
  pull_through = {
    docker-hub = { upstream = "docker-hub", secret_arn = "arn:aws:secretsmanager:...:secret:ecr-pullthroughcache/dockerhub" }
    k8s        = { upstream = "k8s" }       # registry.k8s.io, no credentials
  }
}
```

| Behaviour | Detail |
|:----------|:-------|
| Repositories | Scan on push, encryption (KMS in production), lifecycle (untagged after 14 days, keep the newest 50), immutable tags in production |
| Pull-through cache | `<registry>/docker-hub/library/nginx:1.27` pulls through to Docker Hub once and serves from ECR afterwards; cached repositories get the same scanning, encryption and lifecycle |
| Private registries | `summary.images.copy_commands` lists the `skopeo login` and `skopeo copy --all` commands (multi-arch safe), tags preserved |
| Keeping them | Repositories are destinations (`Lifecycle = keep`); ECR refuses to delete one with images, so destroying the migration stack never loses them silently |

---

## Kubernetes to EKS

```hcl
migrate = ["kubernetes"]
kubernetes = {
  target_cluster_name = "prod-eks"          # default with target.platform_name: the platform's cluster
  target_auth         = "pod-identity"      # pod-identity | irsa
  source_auth         = "roles-anywhere"    # roles-anywhere (with onprem_ca_certificate_pem) | iam-user
  namespaces          = ["shop", "payments"]
  storage_class_map   = { "vsphere-csi" = "gp3", "ocs-storagecluster-ceph-rbd" = "gp3" }
}
```

The module creates an encrypted, TLS-only backup bucket with expiry, a least-privilege Velero policy, and AWS
access for both clusters without keys in Terraform state:

- **EKS:** Pod Identity association (needs the `eks-pod-identity-agent` add-on) or an IRSA role bound to `velero/velero`.
- **On-prem cluster:** IAM Roles Anywhere with a certificate from your CA, or an IAM user whose access key you
  create from the printed command (the key never enters state; the user is removed with the stack).

`summary.kubernetes` lists the exact `velero install`, `backup create`, `restore create` commands for each cluster,
sets the EKS side read-only on the bucket, and gives the StorageClass-mapping ConfigMap for your storage classes.

---

## CI/CD pipelines

One least-privilege deploy role per pipeline, for whichever CI system you run. No static access keys anywhere.

```hcl
pipelines = {
  web      = { provider = "github", repository = "acme/web", eks_clusters = ["prod-eks"], eks_namespaces = ["shop"] }
  payments = { provider = "gitlab", repository = "fin/payments", issuer_url = "https://gitlab.acme.internal", ecs_clusters = ["acme-prod"] }
  mobile   = { provider = "bitbucket", issuer_url = "https://api.bitbucket.org/2.0/workspaces/acme/pipelines-config/identity/oidc", audience = "ari:cloud:bitbucket::workspace/<uuid>", subjects = ["{<repo-uuid>}:*"] }
  data     = { provider = "circleci", issuer_url = "https://oidc.circleci.com/org/<org-id>", audience = "<org-id>", subjects = ["org/<org-id>/project/<project-id>/user/*"] }
  erp      = { provider = "azure-devops", issuer_url = "https://vstoken.dev.azure.com/<org-id>", subjects = ["sc://acme/erp/aws-prod"] }
  legacy   = { provider = "jenkins", s3_buckets = ["acme-artifacts"] }          # on-prem CI, certificate CN = "legacy"
  build    = { provider = "codebuild", codebuild_repo_url = "https://github.com/acme/web" }
}
```

| Provider | How it authenticates | Default trust |
|:---------|:---------------------|:--------------|
| `github` | OIDC (`token.actions.githubusercontent.com`) | `repo:<owner/repo>:ref:refs/heads/<branch>` |
| `gitlab` | OIDC (gitlab.com or your self-managed URL) | `project_path:<group/project>:ref_type:branch:ref:<branch>` |
| `bitbucket`, `circleci`, `azure-devops` | OIDC with your workspace / org issuer | the `subjects` you give |
| `jenkins` (TeamCity, Bamboo, any on-prem CI) | IAM Roles Anywhere: client certificate from your CA | certificate CN = pipeline key |
| `codebuild` | AWS CodeBuild project on a CodeConnections link to GitHub / GitLab / Bitbucket | the project itself |

Permissions are opt-in per pipeline: `ecr_push` (this module's repositories, plus `ecr_repositories`),
`ecs_clusters` + `ecs_pass_roles`, `eks_clusters` (EKS access entry with the **edit** policy, scoped to
`eks_namespaces`, never cluster-admin), `s3_buckets`, and `policy_arns` for anything else.
`summary.pipelines.<name>.setup` shows how to use the role from that CI system. Subjects starting with `*` are refused.

Set `create_oidc_providers = false` if the OIDC providers already exist in the account (for example GitHub's,
created by the platform module); they are looked up instead.

---

## Schema conversion

Moving between engines (Oracle or SQL Server to PostgreSQL, Db2 to Aurora, ...) needs the schema and code
converted before data is copied. The [schema-conversion submodule](modules/schema-conversion) sets up
**DMS Schema Conversion** in the same private network, with the same secrets:

```hcl
module "schema_conversion" {
  source  = "terraform-okirihq/migration/aws//modules/schema-conversion"
  version = "~> 0.2"

  name    = "acme"
  network = module.migration.schema_conversion_network

  projects = {
    hr = {
      source = { engine = "oracle", host = "ora01.corp.local", port = 1521, database_name = "HRPROD", secret_arn = "..." }
      target = { engine = "aurora-postgresql", host = "hr.cluster-x.rds.amazonaws.com", port = 5432, database_name = "hr", secret_arn = "..." }
    }
  }
}
```

It creates a private instance profile, a data provider per endpoint, a migration project per pair, and an
encrypted bucket for assessment reports and converted code. Then: open the project in the DMS console, run the
assessment, convert, apply to the target, and replicate the data with the main module (`on_existing_tables = "keep"`).
It uses the AWSCC provider (the only provider with these resources), so it is a separate submodule: the main
module stays AWS-provider-only.

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
| More or fewer than one landing network (`network.create`, `target.vpc_id`, `target.platform_name`) | Choose one |
| VPN on an existing VPC without `route_table_ids`; static routing without `onprem_cidrs` | Set them |
| `dns` without domains / servers, or with fewer than two subnets | Fix `dns` |
| `network.nat = "none"` without interface endpoints | Enable endpoints or keep a NAT |
| `production` without `alert_email` | Set it |
| Kerberos HDFS without a principal or secret | Set `kerberos_principal` and `secret_arn` |
| `images` with nothing to create; Azure cache without `registry_url`; Docker Hub / GHCR / GitLab / Azure cache without an `ecr-pullthroughcache/` secret | Fix `images` |
| `kubernetes` without a target cluster; `roles-anywhere` without `onprem_ca_certificate_pem` | Set them |
| Pipelines without a repository / issuer / subjects, Jenkins without a CA, CodeBuild without a repo URL, a subject starting with `*` | Fix `pipelines` |
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
| `ecr_repositories` | Repository URL per migrated image |
| `velero_bucket` | Velero backup bucket |
| `pipeline_role_arns` | Deploy role per pipeline |
| `mgn_setup_script` | The idempotent MGN setup script (`servers.automate`) |
| `schema_conversion_network` | Input for the schema-conversion submodule |
| `vpc` | VPC, private subnets and route tables (built here or discovered) |
| `vpn` | VPN connection, tunnel IPs, router-config commands |

---

## Using it with the platform module

```hcl
module "migration" {
  source  = "terraform-okirihq/migration/aws"
  version = "~> 0.2"

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

- **Agent installs are on the servers.** MGN agents (and DataSync agent appliances) run on your machines; the
  module generates the per-OS install commands and, with `servers.automate`, applies all MGN settings for you.
- **Schema conversion runs in the console.** The submodule builds the project; the conversion itself (assess,
  convert, review, apply) is interactive in DMS Schema Conversion.
- **Secrets that end up in state:** DataSync SMB / FSx / object-storage / Azure / Kerberos credentials (provider
  arguments, marked sensitive). Database, MGN, Velero and CI credentials are not in state.
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

The suite runs a from-scratch landing zone (VPC + VPN + DNS), a VPN on a Transit Gateway with BGP, a mixed estate (seven database engines, four share types, five operating systems), Kerberos /
S3 / Azure sources, MGN automation, images + Kubernetes + all seven CI systems, a production deployment on the
platform module, and every guardrail, against mocked providers: no credentials, nothing created. The
schema-conversion submodule has its own suite (`cd modules/schema-conversion && terraform test`). CI runs on every push and pull request: format, TFLint, validate (module and all examples), tests,
Gitleaks and Checkov.

---

## Repository layout

```
.
├── main.tf            # KMS, alerts topic, platform security-group rules
├── network.tf         # VPC, NAT, endpoints, flow logs, Site-to-Site VPN, Transit Gateway, Route 53 Resolver
├── variables.tf       # Inputs
├── locals.tf          # Profiles, target network discovery, engine rules
├── guardrails.tf      # Plan-time refusals
├── databases.tf       # DMS: roles, endpoints, serverless + instance replication, alerts
├── files.tf           # DataSync: agents, PrivateLink, locations, buckets, tasks, logs, alerts
├── servers.tf         # MGN: replication security group, installer role, per-OS commands, optional CLI automation
├── images.tf          # ECR repositories, pull-through caches, copy commands
├── kubernetes.tf      # Velero bucket, EKS + on-prem access, runbook
├── cicd.tf            # Deploy roles for GitHub, GitLab, Bitbucket, CircleCI, Azure DevOps, Jenkins, CodeBuild
├── outputs.tf         # summary runbook and building-block outputs
├── versions.tf
├── modules/
│   └── schema-conversion/   # DMS Schema Conversion (AWSCC provider)
├── examples/          # from-scratch, windows-estate, linux-estate, mixed-estate, kubernetes-and-cicd, schema-conversion, with-platform
└── tests/             # terraform test suite (mocked provider)
```

## License

MIT. See [LICENSE](LICENSE).
