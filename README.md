# Ascend, as originally specified — Terraform-native version

This reproduces exactly what you first asked for:

```
git push to ascend-git (main branch)
        │
        ▼
HCP Terraform workspace, connected to this GitHub repo via VCS integration
  → automatically starts a `terraform plan` + `apply` on every push
        │
        ▼
terraform apply:
  • uploads every file in the repo to S3 (aws_s3_object, one per file —
    this IS the "pipeline puts the codebase into S3" step, no CodeBuild
    or GitHub Actions needed)
  • re-triggers a Bedrock Knowledge Base ingestion job so retrieval stays
    current with whatever just got pushed
        │
        ▼
S3 bucket ──▶ Bedrock Knowledge Base (S3 Vectors — cheap, no monthly
              minimum, unlike OpenSearch Serverless)
                      │
                      ▼
              Bedrock Agent (Claude Haiku 4.5)
                • answers questions grounded in the KB
                • action group "write_code" → Lambda → calls the LLM
                  → saves generated code to a separate S3 bucket
```

Compared to the earlier version of this project, this drops CodeCommit,
CodePipeline, CodeBuild, and OpenSearch Serverless entirely — Terraform
itself, triggered by HCP Terraform's VCS integration, *is* the pipeline.

## One thing Terraform can't do for itself

Terraform can't create the thing that watches git and runs Terraform — that
has to exist first. This is a five-minute manual setup:

1. Go to https://app.terraform.io and sign up (free for personal/small use).
2. Create an organization if you don't have one.
3. **New workspace** → **Version control workflow** → connect your GitHub
   account → select the `ascend-git` repository.
4. **Terraform working directory**: set this to `infra` (since this
   Terraform code lives in an `infra/` subfolder of your repo, not the
   repo root — that's what lets `fileset()` in `s3.tf` walk the rest of the
   repo as "the codebase" without trying to upload itself).
5. Name the workspace `ascend-infra` (must match `main.tf`'s `cloud` block
   — or edit that block to match whatever you name it).
6. Under the workspace's **Variables**, add your AWS credentials as
   **environment variables** (not Terraform variables), marked sensitive:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
7. Set **auto-apply** on (Settings → General → Auto Apply), so pushes don't
   sit waiting for a manual approval click — this is what makes it "push
   and it just runs."

From here on: every push to `main` in `ascend-git` triggers a run in this
workspace automatically. HCP Terraform checks out the repo, runs
`terraform apply` inside `infra/`, which re-uploads any changed files to S3
and re-triggers a KB ingestion job.

## Repo layout this expects

```
ascend-git/
├── infra/              ← this Terraform code lives here
│   ├── main.tf
│   ├── variables.tf
│   ├── s3.tf
│   ├── iam.tf
│   ├── bedrock_kb.tf
│   ├── bedrock_agent.tf
│   ├── lambda.tf
│   └── lambda/code_writer/index.py
├── README.md            ← your actual project files
├── src/                 ← whatever code your project has
└── ...
```

Everything outside `infra/` (and outside `.git/`) is what gets synced to S3
and indexed into the knowledge base.

## First run

The very first `terraform apply` needs Bedrock model access to exist in
your account/region (Claude Haiku 4.5 and Titan Text Embeddings V2 —  both
auto-enable on first invocation per current AWS behavior, no manual
"Model access" step needed).

Push a commit, then watch the run in the HCP Terraform UI — it streams
plan/apply output live. First run takes a few minutes (S3 Vectors index +
Knowledge Base creation); subsequent runs are fast unless the file set
changed a lot.

## Testing the agent

```bash
aws bedrock-agent-runtime invoke-agent \
  --agent-id <bedrock_agent_id output> \
  --agent-alias-id <bedrock_agent_alias_id output> \
  --session-id test-1 \
  --input-text "Write a Python function that reverses a string" \
  out.json
```

## Cost

- S3 storage: pennies for a small repo.
- S3 Vectors: pay-per-use, no monthly minimum.
- Lambda: free tier covers casual use.
- Bedrock invocations (Haiku 4.5): fractions of a cent per call.
- HCP Terraform: free tier covers a single personal workspace.

No component here has a standing monthly charge the way OpenSearch
Serverless or CodePipeline would have.
