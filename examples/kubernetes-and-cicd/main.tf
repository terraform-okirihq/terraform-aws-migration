# OpenShift / Rancher / kubeadm cluster -> EKS with Velero, images from Harbor and Docker Hub into ECR, and
# deploy roles for the CI systems that keep shipping the apps: GitHub Actions, GitLab, Jenkins on-prem.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.70.0, < 6.0.0" }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "corp_ca_pem" {
  description = "PEM of your internal CA (e.g. terraform apply -var corp_ca_pem=\"$(cat corp-ca.pem)\")"
  type        = string
}

module "migration" {
  source = "../../" # in your repo: source = "terraform-okirihq/migration/aws", version = "~> 0.2"

  name         = "acme"
  profile      = "production"
  alert_email  = "platform@acme.example"
  migrate      = ["images", "kubernetes"]
  target       = { platform_name = "acme-prod" } # EKS cluster from the platform module
  onprem_cidrs = ["10.20.0.0/16"]

  # Your internal CA: Velero on the on-prem cluster and Jenkins get short-lived AWS credentials from certificates.
  onprem_ca_certificate_pem = var.corp_ca_pem

  images = {
    copy = [
      { from = "harbor.acme.local/shop/web:3.2.0", to = "shop/web" },
      { from = "harbor.acme.local/shop/api:3.2.0", to = "shop/api" },
    ]
    pull_through = {
      docker-hub = { upstream = "docker-hub", secret_arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:ecr-pullthroughcache/dockerhub-AbCdEf" }
      k8s        = { upstream = "k8s" }
    }
  }

  kubernetes = {
    source_auth       = "roles-anywhere"
    namespaces        = ["shop", "payments"]
    storage_class_map = { "ocs-storagecluster-ceph-rbd" = "gp3", "thin" = "gp3" }
  }

  pipelines = {
    shop-web = { provider = "github", repository = "acme/shop-web", eks_clusters = ["acme-prod"], eks_namespaces = ["shop"] }
    payments = { provider = "gitlab", repository = "fin/payments", issuer_url = "https://gitlab.acme.internal", eks_clusters = ["acme-prod"], eks_namespaces = ["payments"] }
    legacy   = { provider = "jenkins", ecr_push = true, s3_buckets = ["acme-artifacts"] } # cert CN = "legacy"
  }
}

output "summary" {
  value = module.migration.summary
}
