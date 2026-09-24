terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      # S3 Vectors support for Bedrock Knowledge Bases landed in v6.27.0
      version = ">= 6.27.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    terraform = {
      source  = "hashicorp/terraform"
      version = "~> 1.0"
    }
  }

  # This block makes the workspace an HCP Terraform (Terraform Cloud) remote
  # workspace instead of local state. Create the workspace in the HCP
  # Terraform UI first (see README), then fill in your org name below.
  cloud {
    organization = "sameer-ascend"
    workspaces {
      name = "ascend-infra"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
