# Changelog

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
