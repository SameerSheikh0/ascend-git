import json
import os
import re
import uuid
import boto3

bedrock_runtime = boto3.client("bedrock-runtime")
s3 = boto3.client("s3")

MODEL_ID = os.environ["CODE_WRITER_MODEL_ID"]
OUTPUT_BUCKET = os.environ["OUTPUT_BUCKET"]


def _get_param(params, name, default=""):
    for p in params:
        if p.get("name") == name:
            return p.get("value")
    return default


def _extract_code_block(text: str) -> str:
    match = re.search(r"```(?:\w+\n)?(.*?)```", text, re.DOTALL)
    return match.group(1).strip() if match else text.strip()


def generate_code(prompt: str, language: str) -> str:
    system_prompt = (
        f"You are an expert {language or 'general-purpose'} developer. "
        "Return ONLY a fenced code block, no extra text."
    )
    response = bedrock_runtime.invoke_model(
        modelId=MODEL_ID,
        body=json.dumps(
            {
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": 2048,
                "system": system_prompt,
                "messages": [{"role": "user", "content": prompt}],
            }
        ),
    )
    payload = json.loads(response["body"].read())
    text = "".join(b.get("text", "") for b in payload.get("content", []))
    return _extract_code_block(text)


def lambda_handler(event, context):
    action_group = event.get("actionGroup")
    function = event.get("function")
    parameters = event.get("parameters", [])

    prompt = _get_param(parameters, "prompt")
    language = _get_param(parameters, "language")
    filename = _get_param(parameters, "filename") or f"generated/{uuid.uuid4()}.txt"

    code = generate_code(prompt, language)

    s3.put_object(Bucket=OUTPUT_BUCKET, Key=filename, Body=code.encode("utf-8"))

    return {
        "messageVersion": "1.0",
        "response": {
            "actionGroup": action_group,
            "function": function,
            "functionResponse": {
                "responseBody": {
                    "TEXT": {
                        "body": json.dumps(
                            {"s3_location": f"s3://{OUTPUT_BUCKET}/{filename}", "code": code}
                        )
                    }
                }
            },
        },
    }
