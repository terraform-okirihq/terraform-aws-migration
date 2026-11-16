# Changelog

## 0.3.0

**Upgrade notes**

- Production with `servers` now requires `servers.installer_principal_arns` (the IAM users or roles allowed to
  assume the agent installer role). The plan stops with a message until it is set.
- DMS security groups now open only each engine's default port. If a database listens elsewhere, set
  `databases.<name>.source.port` / `target.port`, or DMS cannot connect.

**Changes**

- MGN staging disks use the customer-managed key when the module has one. The key policy lets MGN's
  service-linked roles use it through EC2/EBS only, so replication can create encrypted staging disks.
- Log buckets no longer write access logs into themselves (an endless log loop AWS advises against); the data
  buckets still log to them.
- DMS security groups allow only each engine's port (or `source.port` / `target.port`). HTTPS to the internet remains only when this module is not creating interface endpoints; DataSync egress is NFS 2049 or SMB 445.
- Production requires `servers.installer_principal_arns` so the agent installer role is not assumable by every principal in the account.
- The KMS key policy and the schema-conversion role require the caller's account. The schema-conversion bucket denies non-TLS access and enforces bucket-owner ownership.
- File and Velero buckets write server access logs and publish object deletions to the alerts topic. The schema-conversion bucket logs to its own log bucket and sends events to EventBridge.
- The on-prem Velero user receives its policy through an IAM group. The ECR pull-through role can create repositories only under its cache prefixes. CodeBuild privileged mode is off unless `pipelines.codebuild_privileged` is set.
- `network.availability_zones` pins the Availability Zones for a VPC this module creates. GitHub Actions checkout runs on Node 24.

## 0.2.0

- **Landing network:** `network.create` builds a VPC (2-4 AZs, NAT none / single / per AZ, gateway and optional
  interface endpoints, flow logs, locked default SG); `vpn` adds a Site-to-Site VPN on a VGW or Transit Gateway
  (new or existing) with strong IKEv2 ciphers, tunnel logs, static or BGP routing and a tunnel-down alarm; `dns`
  adds Route 53 Resolver forwarding to on-prem DNS and an inbound endpoint. Works with existing VPCs and the
  platform module too.

- **Files:** Kerberos for HDFS (principal, keytab, krb5.conf, QOP); `s3` source for buckets in another account or
  region (agentless, with the bucket policy to hand the source owner); `azure-blob` source.
- **Servers:** `servers.automate = true` applies the MGN setup during apply (service init, replication and launch
  templates, per-server licensing by hostname); `mgn_setup_script` output.
- **Container images:** ECR repositories, pull-through caches (Docker Hub, Quay, GHCR, GitLab, registry.k8s.io,
  ECR Public, Azure) with creation templates, and skopeo copy commands for private registries.
- **Kubernetes to EKS:** Velero bucket and policy, EKS access via Pod Identity or IRSA, on-prem access via IAM
  Roles Anywhere or a keyless-in-state IAM user, install / backup / restore commands, StorageClass mapping.
- **CI/CD:** deploy roles for GitHub Actions, GitLab, Bitbucket, CircleCI, Azure DevOps, Jenkins / on-prem CI
  (Roles Anywhere) and AWS CodeBuild, with opt-in ECR, ECS, namespace-scoped EKS and S3 permissions.
- **Schema conversion:** new `modules/schema-conversion` submodule for DMS Schema Conversion (AWSCC provider).

## 0.1.0

First release.

- **Databases (DMS):** MySQL, MariaDB, PostgreSQL, Oracle, SQL Server, Db2, SAP ASE (Sybase) and MongoDB sources;
  RDS / Aurora, Oracle, SQL Server, DocumentDB, Redshift and S3 targets. Serverless by default, instance-based for
  Sybase or on request. Credentials from Secrets Manager only, TLS required by default, row validation in production.
- **Files (DataSync):** NFS, SMB, HDFS and S3-compatible sources into S3, EFS or FSx for Windows; agent activation,
  optional PrivateLink, schedules, bandwidth limits, verification, logs.
- **Servers (MGN):** replication security group, short-lived installer role, and generated per-OS install,
  replication-template, licensing and cutover commands for Windows and nine Linux distributions.
- `pilot` and `production` profiles, `overrides`, plan-time guardrails, a `summary` runbook output, SNS alerts on
  every DMS / DataSync state change.
- Works standalone or with `OkiriGabriel/platform/aws` (`target = { platform_name = "..." }`).
