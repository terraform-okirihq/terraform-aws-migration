terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.70.0, < 6.0.0"
    }
    # DMS Schema Conversion (instance profiles, data providers, migration projects) exists only in AWSCC.
    awscc = {
      source  = "hashicorp/awscc"
      version = ">= 1.106.0, < 2.0.0"
    }
  }
}
