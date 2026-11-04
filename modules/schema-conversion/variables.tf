variable "name" {
  description = "Short project name (same as the migration module)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,11}$", var.name))
    error_message = "name must be 2-12 chars: lowercase letters, digits, hyphens."
  }
}

variable "environment" {
  description = "Environment label"
  type        = string
  default     = "prod"
}

variable "network" {
  description = "Pass module.migration.schema_conversion_network: DMS subnet group, security group and KMS key."
  type = object({
    subnet_group_id   = string
    security_group_id = string
    kms_key_arn       = optional(string)
  })
}

variable "projects" {
  description = <<-EOT
    One migration project per source -> target pair. Data providers need the network address (host/port); the
    credentials stay in Secrets Manager (same secrets as the migration module).
    engine: mysql | mariadb | postgres | aurora | aurora-postgresql | oracle | sqlserver | db2 | sybase | mongodb | docdb | redshift
  EOT
  type = map(object({
    source = object({
      engine        = string
      host          = string
      port          = number
      database_name = optional(string)
      ssl_mode      = optional(string, "require")
      secret_arn    = string
    })
    target = object({
      engine        = string
      host          = string
      port          = number
      database_name = optional(string)
      ssl_mode      = optional(string, "require")
      secret_arn    = string
    })
  }))

  validation {
    condition     = length(var.projects) > 0 && alltrue([for k in keys(var.projects) : can(regex("^[a-z][a-z0-9-]{0,19}$", k))])
    error_message = "Define at least one project; keys are 1-20 lowercase letters, digits or hyphens."
  }

  validation {
    condition = alltrue(flatten([for p in values(var.projects) : [for e in [p.source.engine, p.target.engine] :
      contains(["mysql", "mariadb", "postgres", "aurora", "aurora-postgresql", "oracle", "sqlserver", "db2", "sybase", "mongodb", "docdb", "redshift"], e)
    ]]))
    error_message = "engine must be mysql, mariadb, postgres, aurora, aurora-postgresql, oracle, sqlserver, db2, sybase, mongodb, docdb or redshift."
  }

  validation {
    condition     = alltrue(flatten([for p in values(var.projects) : [can(regex("^arn:[^:]+:secretsmanager:", p.source.secret_arn)), can(regex("^arn:[^:]+:secretsmanager:", p.target.secret_arn))]]))
    error_message = "secret_arn values must be Secrets Manager ARNs."
  }
}

variable "tags" {
  description = "Extra tags"
  type        = map(string)
  default     = {}
}
