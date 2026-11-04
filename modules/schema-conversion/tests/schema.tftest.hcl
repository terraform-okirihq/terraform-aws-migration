mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_region" {
    defaults = { name = "us-east-1" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::acme-prod-sc-123456789012", bucket = "acme-prod-sc-123456789012" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/acme-prod-sc-access" }
  }
}

mock_provider "awscc" {
  mock_resource "awscc_dms_instance_profile" {
    defaults = { instance_profile_arn = "arn:aws:dms:us-east-1:123456789012:instance-profile:MOCK" }
  }
  mock_resource "awscc_dms_data_provider" {
    defaults = { data_provider_arn = "arn:aws:dms:us-east-1:123456789012:data-provider:MOCK" }
  }
  mock_resource "awscc_dms_migration_project" {
    defaults = { migration_project_arn = "arn:aws:dms:us-east-1:123456789012:migration-project:MOCK" }
  }
}

variables {
  name    = "acme"
  network = { subnet_group_id = "acme-prod-mig", security_group_id = "sg-0dms" }
}

run "oracle_and_sqlserver_to_postgres" {
  command = apply

  variables {
    projects = {
      hr = {
        source = { engine = "oracle", host = "ora01.corp.local", port = 1521, database_name = "HRPROD", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:ora-AbCdEf" }
        target = { engine = "aurora-postgresql", host = "hr.cluster-x.us-east-1.rds.amazonaws.com", port = 5432, database_name = "hr", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:pg-AbCdEf" }
      }
      erp = {
        source = { engine = "sqlserver", host = "sql01.corp.local", port = 1433, database_name = "ERP", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:sql-AbCdEf" }
        target = { engine = "postgres", host = "erp.x.us-east-1.rds.amazonaws.com", port = 5432, database_name = "erp", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:pg2-AbCdEf" }
      }
    }
  }

  assert {
    condition     = length(awscc_dms_data_provider.this) == 4 && length(awscc_dms_migration_project.this) == 2
    error_message = "two projects, four data providers"
  }
  assert {
    condition     = awscc_dms_data_provider.this["hr-tgt"].engine == "aurora_postgresql" && awscc_dms_data_provider.this["hr-src"].settings.oracle_settings.server_name == "ora01.corp.local"
    error_message = "engine names and settings blocks map correctly"
  }
  assert {
    condition     = awscc_dms_data_provider.this["erp-src"].settings.microsoft_sql_server_settings.port == 1433 && awscc_dms_data_provider.this["erp-src"].engine == "sqlserver"
    error_message = "SQL Server source uses the SQL Server settings block"
  }
  assert {
    condition     = awscc_dms_instance_profile.this.publicly_accessible == false
    error_message = "instance profile must be private"
  }
}

run "refuses_plaintext_credentials" {
  command = plan
  variables {
    projects = { x = {
      source = { engine = "oracle", host = "h", port = 1521, secret_arn = "user/pass" }
      target = { engine = "postgres", host = "h", port = 5432, secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:x" }
    } }
  }
  expect_failures = [var.projects]
}
