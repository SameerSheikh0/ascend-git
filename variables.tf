variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "ascendtf"
}

variable "agent_model_id" {
  description = "Bedrock inference profile ID for the agent's foundation model"
  type        = string
  default     = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
}

variable "code_writer_model_id" {
  description = "Bedrock inference profile ID used by the code-writer Lambda"
  type        = string
  default     = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
}
