# Changelog

## 0.2.0

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
