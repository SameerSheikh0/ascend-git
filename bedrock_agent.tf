resource "aws_bedrockagent_agent" "ascend_agent" {
  agent_name                  = "${var.project_name}-code-agent"
  agent_resource_role_arn     = aws_iam_role.bedrock_agent.arn
  foundation_model            = var.agent_model_id
  idle_session_ttl_in_seconds = 900

  instruction = <<-EOT
    You are the Ascend coding agent. You have access to a knowledge base
    containing the ascend-git repository, kept in sync via Terraform on
    every push. When asked to write, generate, or modify code, call the
    write_code function. Return the generated code and mention where it
    was saved in S3.
  EOT
}

resource "aws_bedrockagent_agent_knowledge_base_association" "ascend_kb_assoc" {
  agent_id             = aws_bedrockagent_agent.ascend_agent.agent_id
  knowledge_base_id    = aws_bedrockagent_knowledge_base.ascend_kb.id
  knowledge_base_state = "ENABLED"
  description          = "The ascend-git repo codebase"
}

resource "aws_bedrockagent_agent_action_group" "write_code" {
  agent_id                   = aws_bedrockagent_agent.ascend_agent.agent_id
  agent_version               = "DRAFT"
  action_group_name           = "write_code"
  action_group_state          = "ENABLED"
  skip_resource_in_use_check  = true

  action_group_executor {
    lambda = aws_lambda_function.code_writer.arn
  }

  function_schema {
    member_functions {
      functions {
        name        = "write_code"
        description = "Generate source code from a natural-language prompt and save it to S3"

        parameters {
          map_block_key = "prompt"
          type          = "string"
          description   = "What the code should do, described in plain English"
          required      = true
        }
        parameters {
          map_block_key = "language"
          type          = "string"
          description   = "Target programming language, e.g. python, javascript"
          required      = false
        }
        parameters {
          map_block_key = "filename"
          type          = "string"
          description   = "Suggested output filename for the generated code"
          required      = false
        }
      }
    }
  }
}

resource "aws_bedrockagent_agent_alias" "prod" {
  agent_id         = aws_bedrockagent_agent.ascend_agent.agent_id
  agent_alias_name = "prod"

  depends_on = [aws_bedrockagent_agent_action_group.write_code]
}

output "bedrock_agent_id" {
  value = aws_bedrockagent_agent.ascend_agent.agent_id
}

output "bedrock_agent_alias_id" {
  value = aws_bedrockagent_agent_alias.prod.agent_alias_id
}
