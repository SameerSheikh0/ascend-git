data "archive_file" "code_writer_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/code_writer"
  output_path = "${path.module}/lambda/code_writer.zip"
}

resource "aws_lambda_function" "code_writer" {
  function_name    = "${var.project_name}-code-writer"
  role             = aws_iam_role.code_writer_lambda.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 256
  filename         = data.archive_file.code_writer_zip.output_path
  source_code_hash = data.archive_file.code_writer_zip.output_base64sha256

  environment {
    variables = {
      CODE_WRITER_MODEL_ID = var.code_writer_model_id
      OUTPUT_BUCKET         = aws_s3_bucket.generated_code.bucket
    }
  }
}

output "generated_code_bucket" {
  value = aws_s3_bucket.generated_code.bucket
}

output "codebase_kb_bucket" {
  value = aws_s3_bucket.codebase_kb.bucket
}
