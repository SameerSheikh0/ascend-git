# ============================================================================
# S3 Vectors: the cheap, no-monthly-minimum vector store (vs. OpenSearch
# Serverless, which bills ~$170+/mo even idle). Native Terraform support
# since aws provider v6.27.0.
# ============================================================================
resource "aws_s3vectors_vector_bucket" "kb" {
  vector_bucket_name = "${var.project_name}-kb-vectors"
}

resource "aws_s3vectors_index" "kb" {
  vector_bucket_name = aws_s3vectors_vector_bucket.kb.vector_bucket_name
  index_name         = "${var.project_name}-kb-index"
  data_type          = "float32"
  dimension          = 1024 # matches Titan Text Embeddings V2 output size
  distance_metric    = "cosine"
}

resource "aws_bedrockagent_knowledge_base" "ascend_kb" {
  name     = "${var.project_name}-knowledge-base"
  role_arn = aws_iam_role.bedrock_kb.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"
    }
  }

  storage_configuration {
    type = "S3_VECTORS"
    s3vectors_configuration {
      vector_bucket_arn = aws_s3vectors_vector_bucket.kb.arn
      index_arn         = aws_s3vectors_index.kb.arn
    }
  }
}

resource "aws_bedrockagent_data_source" "codebase" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.ascend_kb.id
  name               = "${var.project_name}-codebase-source"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = aws_s3_bucket.codebase_kb.arn
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"
      fixed_size_chunking_configuration {
        max_tokens         = 300
        overlap_percentage = 20
      }
    }
  }
}

# Re-trigger ingestion whenever the set of synced files changes, so every
# `terraform apply` (i.e. every git push) both updates S3 *and* refreshes
# what the agent can retrieve - no manual "Sync" click needed.
resource "terraform_data" "trigger_ingestion" {
  triggers_replace = [
    sha256(jsonencode([for f in aws_s3_object.codebase : f.etag]))
  ]

  provisioner "local-exec" {
    command = <<-EOT
      aws bedrock-agent start-ingestion-job \
        --knowledge-base-id ${aws_bedrockagent_knowledge_base.ascend_kb.id} \
        --data-source-id ${aws_bedrockagent_data_source.codebase.data_source_id} \
        --region ${var.aws_region}
    EOT
  }

  depends_on = [aws_s3_object.codebase, aws_bedrockagent_data_source.codebase]
}

output "knowledge_base_id" {
  value = aws_bedrockagent_knowledge_base.ascend_kb.id
}
