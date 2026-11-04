output "migration_projects" {
  description = "Migration project ARN per pair, and where to run the conversion."
  value = { for k, p in awscc_dms_migration_project.this : k => {
    arn     = p.migration_project_arn
    route   = "${var.projects[k].source.engine} -> ${var.projects[k].target.engine}"
    console = "https://${local.region}.console.aws.amazon.com/dms/v2/home?region=${local.region}#migrationProjects"
  } }
}

output "next_steps" {
  description = "How to convert, then hand over to data replication."
  value = [
    "DMS console > Migration projects > <project> > Schema conversion > Launch schema conversion.",
    "Run the assessment report (saved to s3://${aws_s3_bucket.artifacts.bucket}) and review what needs manual changes.",
    "Convert the schema, review the converted code, then 'Apply changes' to the target database.",
    "Replicate the data with the migration module (databases.<name>, on_existing_tables = \"keep\").",
  ]
}

output "artifacts_bucket" {
  description = "S3 bucket with assessment reports and converted code."
  value       = aws_s3_bucket.artifacts.bucket
}
