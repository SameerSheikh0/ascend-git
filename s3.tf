# ============================================================================
# Bucket the repo gets synced into. This is the Bedrock Knowledge Base's
# data source.
# ============================================================================
resource "aws_s3_bucket" "codebase_kb" {
  bucket = "${var.project_name}-codebase-kb-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "codebase_kb" {
  bucket = aws_s3_bucket.codebase_kb.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "codebase_kb" {
  bucket                  = aws_s3_bucket.codebase_kb.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Where the code-writer Lambda saves what the LLM generates.
resource "aws_s3_bucket" "generated_code" {
  bucket = "${var.project_name}-generated-code-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "generated_code" {
  bucket                  = aws_s3_bucket.generated_code.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================================
# THE ACTUAL "take the git directory and put it into S3" STEP.
#
# HCP Terraform checks out this repo into the run's working directory before
# every plan/apply. `path.root` here is the repo root (one level up from
# this infra/ folder, since the workspace's working directory is set to
# "infra" - see README). fileset() walks every file in the repo at apply
# time and uploads each one as its own S3 object, so every `terraform apply`
# - which HCP Terraform triggers automatically on every push - re-syncs
# whatever changed. No CodeBuild, no CodePipeline, no GitHub Actions: this
# *is* the pipeline.
# ============================================================================
locals {
  repo_root = abspath("${path.module}/config")

  # Walk every file in the repo except .git internals, this Terraform
  # code itself, and the Lambda source (we don't want to feed our own
  # infra code into the knowledge base).
  repo_files = {
    for f in fileset(local.repo_root, "**") :
    f => f
    if !startswith(f, ".git/")
      && !startswith(f, ".terraform")
      && !startswith(f, "lambda/")
      && !endswith(f, ".tf")
      && f != ".terraformrc"
  }
}

resource "aws_s3_object" "codebase" {
  for_each = local.repo_files

  bucket = aws_s3_bucket.codebase_kb.id
  key    = each.value
  source = "${local.repo_root}/${each.value}"
  etag   = filemd5("${local.repo_root}/${each.value}")
}
