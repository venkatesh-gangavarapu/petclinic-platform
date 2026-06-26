# Petclinic Platform — Infrastructure Setup Guide

**Last Updated:** 2026-06-26 (E-3 EKS added)
**Audience:** DevOps beginners and students learning cloud infrastructure

## Purpose

This guide explains every infrastructure decision made in the petclinic-platform repository — from AI-assisted tooling (E-0) to Terraform remote state (E-1). It answers not just *what* was built, but *why* each decision was made, how it maps to real production environments, and what would break if you skipped it.

---

## Table of Contents

1. [What Is This Platform?](#1-what-is-this-platform)
2. [Repository Structure](#2-repository-structure)
3. [E-0: Claude Code Setup](#3-e-0-claude-code-setup)
   - [MCP Servers — AI Tools for Infrastructure Work](#31-mcp-servers)
   - [Safety Hooks — Guardrails That Prevent Disasters](#32-safety-hooks)
   - [The Three-Tier Hook Model](#33-the-three-tier-hook-model)
   - [Rules — Context-Aware File Conventions](#34-rules)
   - [Agents — Specialized AI Reviewers](#35-agents)
   - [Skills — Slash Commands for Common Operations](#36-skills)
4. [E-1: Foundation & Remote State](#4-e-1-foundation--remote-state)
   - [Why Infrastructure as Code?](#41-why-infrastructure-as-code)
   - [Why Terraform Specifically?](#42-why-terraform-specifically)
   - [Why Remote State?](#43-why-remote-state)
   - [S3 + DynamoDB: How the State Backend Works](#44-s3--dynamodb-how-the-state-backend-works)
   - [Directory Structure: Environments vs Modules](#45-directory-structure-environments-vs-modules)
   - [Provider Configuration](#46-provider-configuration)
   - [Version Constraints](#47-version-constraints)
   - [Variables and Outputs](#48-variables-and-outputs)
   - [The Bootstrap Process](#49-the-bootstrap-process)
   - [Backend Configuration](#410-backend-configuration)
5. [E-2: Networking (VPC)](#5-e-2-networking-vpc)
   - [Why a Custom VPC?](#51-why-a-custom-vpc)
   - [All-Public Subnet Design (ADR-0001)](#52-all-public-subnet-design-adr-0001)
   - [What the VPC Module Creates](#53-what-the-vpc-module-creates)
   - [Security Groups: The Real Perimeter](#54-security-groups-the-real-perimeter)
   - [Kubernetes Tags on Subnets](#55-kubernetes-tags-on-subnets)
   - [Dev Environment Apply: What Was Created](#56-dev-environment-apply-what-was-created)
   - [Known Gotcha: Non-ASCII Characters in SG Descriptions](#57-known-gotcha-non-ascii-characters-in-sg-descriptions)
6. [E-3: EKS Cluster](#6-e-3-eks-cluster)
   - [Why EKS?](#61-why-eks)
   - [Cluster Configuration Decisions](#62-cluster-configuration-decisions)
   - [IAM Roles: Cluster vs Nodes](#63-iam-roles-cluster-vs-nodes)
   - [OIDC Provider and IRSA](#64-oidc-provider-and-irsa)
   - [Managed Node Group: ARM/Graviton](#65-managed-node-group-armgriviton)
   - [EKS Managed Add-ons](#66-eks-managed-add-ons)
   - [kubectl Access: How It Works](#67-kubectl-access-how-it-works)
   - [Dev Environment Apply: What Was Created](#68-dev-environment-apply-what-was-created)
7. [The Full Setup Workflow](#7-the-full-setup-workflow)
8. [Security Practices Explained](#8-security-practices-explained)
9. [Cost Considerations](#9-cost-considerations)
10. [Common Mistakes and How to Avoid Them](#10-common-mistakes-and-how-to-avoid-them)
11. [Glossary](#11-glossary)

---

## 1. What Is This Platform?

This repository contains all the **infrastructure code** needed to deploy a microservices application called Spring Petclinic to Amazon Web Services (AWS). The application itself is not here — only the code that *creates and manages* the cloud resources (servers, databases, networks, etc.) the application runs on.

### The Application Being Deployed

Spring Petclinic Microservices is an 8-service Java application. Each service has a specific responsibility:

| Service | Port | What It Does |
|---------|------|-------------|
| `config-server` | 8888 | Central configuration store — all other services fetch their config from here |
| `discovery-server` | 8761 | Service registry (Eureka) — services find each other by name, not IP |
| `api-gateway` | 8080 | Single entry point — routes external traffic to the right service |
| `customers-service` | 8081 | Manages pet owners and their pets |
| `visits-service` | 8082 | Tracks veterinary visit records |
| `vets-service` | 8083 | Manages vet staff and specialties |
| `genai-service` | 8084 | AI-powered features using OpenAI |
| `admin-server` | 9090 | Monitoring dashboard for all services |

### What "Production-Grade" Means Here

A production-grade setup means:
- **Repeatable** — any engineer can recreate the entire environment from code alone
- **Safe** — guardrails prevent accidental deletion or exposure of secrets
- **Observable** — you can see what's happening at all times
- **Auditable** — every change is tracked in version control
- **Cost-controlled** — resources are sized appropriately and nothing runs unnecessarily

This repository is built to those standards, even though it is also a learning project.

---

## 2. Repository Structure

```
petclinic-platform/
├── .claude/                    # AI assistant configuration
│   ├── agents/                 # Specialized review agents
│   ├── hooks/                  # Safety guardrail scripts
│   ├── rules/                  # File-pattern coding conventions
│   ├── skills/                 # Slash commands (/terraform-plan, etc.)
│   ├── settings.json           # Hook wiring (committed to git)
│   └── settings.local.json     # Your personal local settings (NOT committed)
├── .mcp.json                   # MCP server definitions (AI tool plugins)
├── .gitignore                  # Files that must never enter git
├── terraform/
│   ├── environments/
│   │   ├── dev/                # Dev environment root module
│   │   └── prod/               # Prod environment root module
│   └── modules/
│       ├── vpc/                # Reusable network module
│       ├── eks/                # Reusable Kubernetes cluster module
│       ├── ecr/                # Reusable container registry module
│       ├── rds/                # Reusable database module
│       ├── dns/                # Reusable DNS/certificate module
│       ├── secrets/            # Reusable secrets module
│       └── observability/      # Reusable monitoring module
├── helm/                       # Kubernetes deployment templates
├── helm-values/                # Per-service and per-environment values
├── k8s/                        # Raw Kubernetes manifests
├── scripts/                    # Operational helper scripts
└── docs/                       # This documentation
```

### Why Two Separate Directories (environments/ and modules/)?

This is one of the most important structural decisions in Terraform:

- **`modules/`** are blueprints. They define *how* to build a VPC, but not *which* VPC to build. They are reusable.
- **`environments/`** are the actual builds. They say "build me a VPC using that blueprint, with these specific settings, in this account."

**Real-world analogy:** Think of modules as an architect's house design. The design is reusable — you can build the same house in London or New York. The environment is the specific house at a specific address with specific customizations (paint color, lot size, etc.).

---

## 3. E-0: Claude Code Setup

Before writing a single line of infrastructure code, the team configured Claude Code — an AI coding assistant. This might seem like an unusual first step, but there are strong production reasons for doing it first.

### Why Configure the AI Tool First?

Every subsequent task (writing Terraform, creating Kubernetes manifests, setting up CI/CD) benefits from:
1. The AI having full context about conventions and standards
2. Safety hooks preventing the AI from running dangerous commands
3. Specialized review agents that catch errors before they reach AWS

Getting this right at the start means every future interaction is safer and more consistent.

---

### 3.1 MCP Servers

**File:** `.mcp.json`

MCP (Model Context Protocol) servers are plugins that give Claude Code access to external tools and documentation. Think of them as specialized reference books the AI can look up in real time.

```json
{
  "mcpServers": {
    "awslabs.terraform-mcp-server": { ... },
    "aws-knowledge-mcp": { ... },
    "awslabs.aws-pricing-mcp-server": { ... },
    "context7": { ... },
    "atlassian": { ... }
  }
}
```

#### Why Each MCP Server Exists

**`awslabs.terraform-mcp-server`**
Gives Claude access to official AWS Terraform provider documentation and can run Checkov security scans. Without this, Claude relies on training data that may be months old and miss new resource arguments or deprecated options.

**`aws-knowledge-mcp`**
Direct access to AWS's own documentation. Useful for checking service limits, regional availability, and IAM permission requirements.

**`awslabs.aws-pricing-mcp-server`** (region: `eu-central-1`)
Real AWS pricing data. When designing resources, Claude can estimate actual costs — for example, knowing that an EKS control plane costs $0.10/hour ($73/month) before recommending it.

**`context7`**
Up-to-date documentation for libraries and frameworks (Terraform, Kubernetes, Helm, etc.). Claude's training data has a cutoff date; context7 provides current docs, including recent API changes.

**`atlassian`**
Jira ticket management. Engineers can ask Claude to check ticket requirements, update ticket status, or reference acceptance criteria — all without leaving the terminal.

#### Production Relevance

In a real company, engineers constantly reference documentation. Wiring documentation sources directly into the AI tool means:
- No copy-pasting documentation into chat
- Always current information (no stale training data)
- Automatic cost awareness when designing resources

---

### 3.2 Safety Hooks

**Files:** `.claude/hooks/*.sh`, `.claude/settings.json`

Safety hooks are scripts that run automatically before or after Claude Code executes a command. They act as a layer of protection between Claude's intentions and your actual infrastructure.

#### Why Hooks Are Critical in Infrastructure Work

Infrastructure commands are uniquely dangerous compared to regular software development:

| Action | Software Development | Infrastructure |
|--------|---------------------|----------------|
| Wrong command | App crashes, restart it | VPC deleted, recovery takes hours |
| Accidental delete | `git checkout` recovers the file | EKS cluster gone, 2+ hours to rebuild |
| Secret in git | Minor concern | Major security incident, keys must be rotated |
| Bulk apply | Tests fail | $10,000 in unexpected AWS charges |

Hooks turn these potential disasters into blocked operations with clear explanations.

#### The Six Hooks

**`block-destroy.sh`** — Hard Block (exit code 2)

Prevents `terraform destroy`, `terraform apply -destroy`, and `kubectl delete` of critical resources in production. 

```bash
# This is BLOCKED by the hook:
terraform destroy

# Error message shown to user:
# BLOCKED: 'terraform destroy' is not allowed via Claude Code.
# Destroying infrastructure must be done manually with explicit human oversight.
```

**Why this matters in production:** At many companies, a single accidental `terraform destroy` in production has caused multi-hour outages. The hook forces the engineer to run the command manually in their terminal — a deliberate action that makes them think twice.

**`block-dangerous-rm.sh`** — Hard Block (exit code 2)

Blocks `rm -rf` on protected directories: `terraform/`, `k8s/`, `helm/`, `helm-values/`, `.github/`, `docs/`, `scripts/`, `.claude/`.

```bash
# BLOCKED:
rm -rf terraform/

# ALLOWED (specific file deletion):
rm terraform/environments/dev/plan.out
```

**Why this matters:** All infrastructure code lives in these directories. Deleting a directory with `rm -rf` deletes git history too until a fresh pull. While recoverable, it wastes time and causes panic.

**`warn-apply-without-plan.sh`** — Warning (exit code 1)

When Claude tries to run `terraform apply` without a saved plan file, this hook stops and asks for confirmation.

```bash
# This triggers the warning:
terraform apply

# The safe workflow (this is ALLOWED):
terraform plan -out plan.out    # Step 1: Save the plan
terraform apply plan.out         # Step 2: Apply exactly that plan
```

**Why this matters:** The Terraform safe workflow is `plan → review → apply`. When you skip the plan:
1. Terraform re-plans at apply time — the changes may differ from what you expected
2. You cannot review what will change before it changes
3. In production, this is how unexpected resource deletions happen

**`suggest-validate.sh`** — Informational (exit code 0)

After editing a `.tf`, `.yaml`, or `.yml` file, this hook suggests running the appropriate validation command. It never blocks — it only informs.

```
Tip: You edited a Terraform file. Run 'terraform validate' in terraform/modules/vpc/ to check for errors.
     Also run 'terraform fmt -check' to verify formatting.
```

**`block-secret-commit.sh`** — Hard Block (exit code 2)

Blocks `git add .`, `git add -A`, and `git add` of files matching secret patterns (`.env`, `*.tfvars`, `*.pem`, `*.key`, `kubeconfig`, etc.).

```bash
# BLOCKED:
git add .
git add -A
git add terraform.tfvars

# Required instead (explicit staging):
git add terraform/modules/vpc/main.tf
```

**Why this matters:** Once a secret is committed to git, it is permanent — even if you delete it in a later commit, it lives in git history forever. The only fix is a full history rewrite and immediate key rotation. This hook prevents that incident from ever starting.

**`block-mcp-destroy.sh`** — Hard Block (exit code 2)

The same protection as `block-destroy.sh`, but for MCP tool calls. Claude Code can invoke Terraform through MCP servers directly (bypassing the Bash shell). This hook closes that gap.

```
Blocked tool: mcp__terraform__ExecuteTerraformCommand with command=destroy
```

---

### 3.3 The Three-Tier Hook Model

The hooks follow a deliberate three-tier severity model:

```
Exit Code 2 → BLOCK     → Claude cannot proceed. Human must act.
Exit Code 1 → WARN      → Claude pauses and asks the user for explicit approval.
Exit Code 0 → INFORM    → Claude continues, but shows a helpful message.
```

This design is borrowed from real security tooling (like pre-commit hooks at companies like Google and GitHub). The three tiers prevent alert fatigue — if everything is a hard block, engineers disable the hooks. By calibrating severity to actual risk, hooks stay useful and stay on.

---

### 3.4 Rules

**Files:** `.claude/rules/*.md`

Rules are Markdown files with `paths:` frontmatter. Claude Code loads them automatically when you open or edit a file matching the specified glob pattern.

```yaml
---
paths:
  - "terraform/**/*.tf"
---
# Terraform Rules
...conventions, naming standards, security requirements...
```

#### The Four Rule Files

| Rule File | Triggers When Editing | What It Enforces |
|-----------|----------------------|-----------------|
| `terraform.md` | Any `.tf` file | Naming (`petclinic-{env}-{resource}`), required tags, module structure, state management, workflow |
| `kubernetes.md` | Any `k8s/**/*.yaml` | Required labels, health probes, resource limits, startup order, secrets via ExternalSecret |
| `pipelines.md` | Any `.github/workflows/**/*.yml` | OIDC auth (no static keys), image SHA tagging, no kubectl in CI, Trivy scanning |
| `docs.md` | Any `docs/**/*.md` | H1 title, Last Updated date, purpose statement, ToC for long docs |

#### Why Rules Instead of Just a README?

A README requires engineers to remember to check it. Rules are loaded automatically at the right time — when you're actually editing the relevant file type. An engineer editing a GitHub Actions workflow automatically gets the CI/CD security rules in context, without having to think about it.

In large engineering teams, this is how coding standards stay consistent without code review becoming adversarial. The AI enforces the standard before the code is even written.

---

### 3.5 Agents

**Files:** `.claude/agents/*.md`

Agents are specialized Claude instances configured for a specific review task. They are read-only — they can read files and run dry-run commands, but they cannot write or edit anything.

#### The Six Agents

**`terraform-reviewer`** — Security, cost, and best-practice review of Terraform code
- Checks for hardcoded secrets, open security groups, missing encryption
- Verifies all resources have required tags
- Estimates cost implications
- Produces structured findings: Critical → Warning → Info

**`k8s-validator`** — Kubernetes manifest validation
- Checks that every Deployment has readiness and liveness probes
- Verifies resource requests and limits are set
- Confirms images use SHA tags, not `latest`
- Can run `kubectl apply --dry-run=client` to catch syntax errors

**`security-auditor`** — Cross-cutting security review
- Reviews Terraform, Kubernetes, and CI/CD together for security gaps
- Checks the full secret management chain: AWS Secrets Manager → ExternalSecret → K8s Secret → Pod
- Produces a compliance summary table

**`cost-reviewer`** — AWS cost estimation
- Analyzes Terraform configs and estimates monthly spend per environment
- Identifies top cost drivers
- Flags potential unexpected charges (data transfer, API calls, etc.)

**`doc-reviewer`** — Documentation quality review
- Cross-checks documented file paths against what actually exists
- Verifies commands are syntactically correct and copy-pasteable
- Checks for exposed secrets or personal information

**`pipeline-reviewer`** — CI/CD pipeline security review
- Verifies OIDC authentication (no long-lived AWS keys)
- Checks that Docker images use SHA tags
- Confirms no `kubectl apply` in CI (ArgoCD handles deployment)

#### Why Separate Agents Instead of One?

Each agent uses a different model size optimized for its task:
- Reviewers that just read code use `haiku` (fast, cheap)
- Security auditor (comprehensive cross-cutting analysis) uses `sonnet` (more capable)

Specialization also means cleaner, more focused output. A terraform reviewer doesn't need to know Kubernetes conventions and vice versa.

---

### 3.6 Skills

**Files:** `.claude/skills/*/SKILL.md`

Skills are slash commands — shortcuts for common multi-step operations. Type `/terraform-plan dev` and Claude runs the full init → plan workflow automatically.

#### The Nine Skills

| Skill | Type | What It Does |
|-------|------|-------------|
| `/terraform-plan [env]` | Manual | `terraform init` + `terraform plan -out plan.out` |
| `/terraform-apply [env]` | Manual | Checks for plan.out, shows summary, asks confirmation, applies |
| `/security-scan [module\|all]` | Manual | Checkov scan on Terraform, categorizes findings by severity |
| `/deploy-dev [service\|all]` | Manual | Deploy to petclinic-dev via ArgoCD (or Helm for bootstrap) |
| `/deploy-prod [service\|all]` | Manual | Deploy to petclinic-prod with extra confirmation step |
| `/smoke-test [env]` | Manual | Health-check all 8 services via /actuator/health |
| `/logs [service] [env]` | Manual | Fetch and surface pod logs and events |
| `/rollback [service] [env]` | Manual | Roll back a deployment to the previous revision |
| `/review-terraform [path]` | Auto | Review Terraform code against project checklist |

#### Manual vs Auto-Invocable Skills

Eight of the nine skills have `disable-model-invocation: true`. This means Claude **cannot** run them on its own — a human must explicitly type `/terraform-plan dev`. Claude can suggest it, but cannot execute it.

Only `/review-terraform` is auto-invocable. Claude can invoke it proactively after writing Terraform code, because reviewing your own work has no blast radius — it reads files and reports findings.

The manual-only design for deploy, rollback, and apply commands is a deliberate production safety pattern. These commands change real infrastructure or running services. Human intent must be explicit.

#### Deploy-Prod Safety

`/deploy-prod` has an additional confirmation step that `/deploy-dev` does not:

```
You are deploying to PRODUCTION (petclinic-prod).
This will affect live services. Confirm? [yes/no]
```

Claude will not proceed without typing "yes". This pattern — a forced acknowledgment before production changes — is standard practice at companies like Netflix, Airbnb, and Amazon.

---

## 4. E-1: Foundation & Remote State

With the AI tooling configured, the next step is setting up Terraform — the tool that actually creates AWS resources.

---

### 4.1 Why Infrastructure as Code?

Before Terraform, infrastructure was created manually: log in to the AWS console, click through menus, create a VPC, create subnets, create security groups. This approach has critical problems in production:

| Problem | Manual Console | Infrastructure as Code |
|---------|---------------|----------------------|
| Reproducibility | Can you recreate it exactly? Probably not. | `terraform apply` — identical every time |
| Documentation | Screenshots that go stale | The code itself is the documentation |
| Change tracking | Nobody knows who changed what | Every change is a git commit with author, date, message |
| Disaster recovery | Start from scratch, hope you remember everything | `terraform apply` recovers the full environment |
| Team collaboration | "I changed a security group, FYI" | Pull request, code review, merge, auto-applied |
| Environment consistency | Dev and prod drift over months | Same code, different variable values |

IaC is not optional in any serious engineering organization. It is the baseline.

---

### 4.2 Why Terraform Specifically?

Several IaC tools exist (AWS CloudFormation, Pulumi, Ansible). Terraform is chosen for this project because:

1. **Cloud-agnostic** — the same mental model works for AWS, GCP, Azure. Skills transfer.
2. **Declarative** — you describe the desired end state, not the steps to get there. Terraform figures out the steps.
3. **State management** — Terraform tracks what it created, so it knows what to change or delete.
4. **Massive ecosystem** — 3,000+ providers, 10,000+ modules on the Terraform Registry.
5. **Industry standard** — used by the majority of DevOps teams globally.

**Declarative vs Imperative — what does this mean?**

```
IMPERATIVE (like a script):
1. Create VPC with CIDR 10.0.0.0/16
2. Create subnet 10.0.1.0/24 in us-east-1a
3. Create internet gateway
4. Attach internet gateway to VPC
5. Create route table
6. Add route 0.0.0.0/0 → internet gateway
7. Associate route table with subnet

DECLARATIVE (Terraform):
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}
# Terraform figures out the order and dependencies
```

---

### 4.3 Why Remote State?

Terraform tracks everything it creates in a **state file** — a JSON document that maps your code to real AWS resources. By default, this file is created locally as `terraform.tfstate`.

#### The Problem with Local State

Imagine two engineers on the same team:

```
Engineer A                          Engineer B
-----------                         -----------
git pull                            git pull
terraform plan     ← sees state     terraform plan     ← sees DIFFERENT state
terraform apply    ← creates VPC    terraform apply    ← tries to create SAME VPC
                                                        → CONFLICT, possible duplicate
```

If Engineer B doesn't have Engineer A's local state file, Terraform thinks nothing has been created yet and tries to create everything again. This causes:
- Duplicate resources (two VPCs, two EKS clusters)
- State corruption
- Hours of debugging

#### The Solution: Remote State

Store the state file in a shared location that everyone reads from and writes to:

```
Engineer A                          Engineer B
-----------                         -----------
terraform apply                     terraform apply
  ↓                                   ↓
Reads state from S3 ←──────────────→ Reads state from S3
Writes updated state to S3            (waits for lock to clear)
```

**Remote state** stores `terraform.tfstate` in an S3 bucket accessible to all engineers. Everyone works from the same source of truth.

---

### 4.4 S3 + DynamoDB: How the State Backend Works

The state backend in this project uses two AWS services working together:

```
┌─────────────────────────────────────────────────────────┐
│                     terraform apply                      │
└──────────────┬──────────────────────────────────────────┘
               │
       ┌───────▼────────┐
       │   DynamoDB      │  ← "I'm working, nobody else touch this"
       │  (Lock Table)   │     LockID: petclinic/dev/terraform.tfstate
       └───────┬────────┘     State: LOCKED
               │ (lock acquired)
       ┌───────▼────────┐
       │    S3 Bucket    │  ← Read current state
       │  (State Store)  │     Key: petclinic/dev/terraform.tfstate
       └───────┬────────┘
               │ (make changes to AWS)
       ┌───────▼────────┐
       │    S3 Bucket    │  ← Write updated state
       └───────┬────────┘
               │
       ┌───────▼────────┐
       │   DynamoDB      │  ← "Done, others can work now"
       │  (Lock Table)   │     Lock released
       └────────────────┘
```

#### S3 Bucket Configuration (Why Each Setting Matters)

**Versioning enabled:**
```bash
aws s3api put-bucket-versioning \
  --versioning-configuration Status=Enabled
```
If a state file gets corrupted (it happens — network failures during writes), you can recover the previous version instantly. Without versioning, a corrupt state file means manually reconciling what Terraform thinks exists vs what actually exists in AWS.

**AES256 Encryption (SSE-S3):**
```bash
aws s3api put-bucket-encryption \
  --server-side-encryption-configuration '{ "SSEAlgorithm": "AES256" }'
```
The state file contains sensitive information: resource IDs, ARNs, and sometimes secret values. Encryption at rest ensures that if someone gains raw access to the S3 bucket storage, the data is unreadable without the encryption key.

**All four public access blocks:**
```bash
BlockPublicAcls=true
IgnorePublicAcls=true
BlockPublicPolicy=true
RestrictPublicBuckets=true
```
Without these, a misconfigured bucket policy or ACL could accidentally expose the state file to the internet. These four settings provide defense in depth — even if one layer fails, the others remain.

#### DynamoDB Lock Table (Why It Exists)

S3 is eventually consistent for some operations. If two engineers simultaneously tried to write state without a lock:

1. Both read the current state: `{ vpc: vpc-abc123 }`
2. Engineer A applies, writes: `{ vpc: vpc-abc123, subnet: subnet-111 }`
3. Engineer B applies (from old read), writes: `{ vpc: vpc-abc123, subnet: subnet-222 }` ← OVERWRITES A's state

Engineer A's subnet is now orphaned — it exists in AWS but not in state. Terraform will try to create it again next time.

DynamoDB prevents this with an atomic lock (PutItem with condition). Only one `terraform apply` can hold the lock at a time. Others wait.

**The lock entry looks like:**
```json
{
  "LockID": "petclinic-terraform-state-123456789/petclinic/dev/terraform.tfstate",
  "Info": "{\"ID\":\"abc123\",\"Operation\":\"OperationTypeApply\",\"Who\":\"engineer@laptop\",\"Version\":\"1.7.0\",\"Created\":\"2026-05-20T10:00:00Z\"}"
}
```

If a `terraform apply` crashes mid-run, the lock may stay. You'll see: `Error: Error acquiring the state lock`. To manually release: `terraform force-unlock <lock-id>`.

#### Bucket Naming: Why Include the Account ID?

```
petclinic-terraform-state-569144120198
```

S3 bucket names are **globally unique across all AWS accounts worldwide**. If two students both name their bucket `petclinic-terraform-state`, the second one gets an error. Including the account ID guarantees uniqueness.

---

### 4.5 Directory Structure: Environments vs Modules

#### Root Modules (environments/)

A **root module** is the entry point for a `terraform apply`. You always run Terraform from inside an environment directory:

```bash
cd terraform/environments/dev
terraform init
terraform plan
terraform apply
```

Each environment directory is independent:
- Has its own state file in S3
- Has its own variable values
- Can be applied and destroyed separately from other environments

**Files in each environment:**

```
terraform/environments/dev/
├── backend.tf          ← WHERE to store state (S3 bucket, key, region)
├── versions.tf         ← WHICH versions of Terraform and providers to use
├── providers.tf        ← HOW to configure the AWS provider (region, default tags)
├── variables.tf        ← WHAT inputs this environment accepts
├── main.tf             ← WHAT modules to call (VPC, EKS, RDS, etc.)
├── outputs.tf          ← WHAT values to expose after apply (VPC ID, etc.)
└── terraform.tfvars.example  ← EXAMPLE variable values (template, not secrets)
```

#### Child Modules (modules/)

A **child module** is a reusable blueprint. It defines how to create a resource type, but has no idea which environment it's running in.

```hcl
# modules/vpc/main.tf — doesn't know if it's dev or prod
resource "aws_vpc" "main" {
  cidr_block           = var.cidr_block        # provided by caller
  enable_dns_support   = true
  enable_dns_hostnames = true
}
```

The environment calls the module:
```hcl
# environments/dev/main.tf
module "vpc" {
  source     = "../../modules/vpc"
  cidr_block = "10.0.0.0/16"    # dev-specific value
  environment = "dev"
}
```

```hcl
# environments/prod/main.tf
module "vpc" {
  source     = "../../modules/vpc"
  cidr_block = "10.1.0.0/16"    # prod-specific, non-overlapping
  environment = "prod"
}
```

**Why modules?** Without modules, you'd copy-paste the same VPC code into both dev and prod. When a security requirement changes (add a tag, change a setting), you'd update it in two places and risk them drifting. Modules are the "Don't Repeat Yourself" principle applied to infrastructure.

#### Files in Each Module

Per CLAUDE.md conventions, every module has exactly four files:

```
terraform/modules/vpc/
├── main.tf         ← Resource definitions
├── variables.tf    ← Input variables (what the caller must provide)
├── outputs.tf      ← Output values (what the caller gets back)
└── versions.tf     ← Required provider versions
```

**`main.tf`** — The actual resources. For the VPC module, this will contain `aws_vpc`, `aws_subnet`, `aws_internet_gateway`, `aws_route_table` resources.

**`variables.tf`** — The module's API. What does the caller need to provide?
```hcl
variable "cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev or prod)"
  type        = string
}
```

**`outputs.tf`** — What does the module give back to the caller?
```hcl
output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.main.id
}

output "subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}
```

Other modules (EKS, RDS) will reference these outputs:
```hcl
module "eks" {
  source     = "../../modules/eks"
  vpc_id     = module.vpc.vpc_id        # ← using VPC module's output
  subnet_ids = module.vpc.subnet_ids    # ← using VPC module's output
}
```

---

### 4.6 Provider Configuration

**File:** `terraform/environments/{env}/providers.tf`

```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
```

#### What Is a Provider?

A **provider** is a plugin that teaches Terraform how to talk to a specific API. The AWS provider knows how to create VPCs, EC2 instances, RDS databases, etc. by calling AWS APIs.

Terraform downloads the provider during `terraform init`:
```
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.42.0...
```

#### Why `default_tags`?

The `default_tags` block in the provider automatically applies the specified tags to **every** AWS resource created by this provider configuration. Without it, you'd need to add these tags manually to every single resource:

```hcl
# Without default_tags — TEDIOUS and error-prone:
resource "aws_vpc" "main" {
  tags = {
    Project     = "petclinic"
    Environment = var.environment
    ManagedBy   = "terraform"
    Name        = "petclinic-dev-vpc"
  }
}

resource "aws_subnet" "public" {
  tags = {
    Project     = "petclinic"     # ← easy to forget
    Environment = var.environment  # ← easy to forget
    ManagedBy   = "terraform"      # ← easy to forget
    Name        = "petclinic-dev-public-1"
  }
}
```

With `default_tags`, Project, Environment, and ManagedBy are automatically applied everywhere. You only add the `Name` tag to individual resources.

#### Why Tags Matter in Production

Tags serve multiple purposes:
- **Cost allocation** — filter AWS Cost Explorer by `Environment=dev` to see dev-only spending
- **Resource grouping** — find all resources belonging to this project
- **Compliance** — demonstrate that all resources are managed (not rogue/untracked)
- **Automation** — scripts can target `ManagedBy=terraform` to identify IaC-managed resources

Many companies mandate specific tags on all resources. Untagged resources are flagged in compliance audits.

---

### 4.7 Version Constraints

**File:** `terraform/environments/{env}/versions.tf`

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

#### Understanding Version Constraint Syntax

| Constraint | Meaning | Example Match | Example Rejection |
|-----------|---------|--------------|------------------|
| `>= 1.6.0` | 1.6.0 or higher | 1.6.0, 1.7.0, 2.0.0 | 1.5.9 |
| `~> 5.0` | 5.x only (minor updates OK, major NOT) | 5.0, 5.1, 5.42 | 6.0 |
| `= 5.42.0` | Exactly this version | 5.42.0 | 5.42.1 |
| `>= 5.0, < 6.0` | Explicit range | Same as `~> 5.0` but more explicit | 6.0 |

#### Why `~> 5.0` for the AWS Provider?

The `~>` operator (pessimistic constraint) allows patch and minor updates but blocks major version bumps. This means:
- You automatically get bug fixes and new resource support (minor versions)
- You don't accidentally upgrade to AWS provider v6.0 which may have breaking changes

#### Why Pin Terraform Itself?

If Engineer A is on Terraform 1.5 and Engineer B is on Terraform 1.7, the state file format may differ. This `required_version` check fails fast:

```
Error: Unsupported Terraform Core version
  This configuration does not support Terraform version 1.5.0.
  To proceed, either choose another supported Terraform version or update this configuration.
```

Better to fail immediately than to produce inconsistent state.

#### The Lock File: `.terraform.lock.hcl`

When you run `terraform init`, Terraform creates `.terraform.lock.hcl`:

```hcl
provider "registry.terraform.io/hashicorp/aws" {
  version     = "5.42.0"
  constraints = "~> 5.0"
  hashes = [
    "h1:AbCdEf...",  # cryptographic hash for verification
  ]
}
```

This file **must be committed to git**. It pins the exact provider version so that every engineer and every CI pipeline uses the exact same provider binary. Without it, Engineer A might use 5.42.0 while CI uses 5.43.1, and a subtle behavioral difference causes a hard-to-debug issue.

Notice the `.gitignore` explicitly avoids excluding this file:
```gitignore
# Do NOT ignore .terraform.lock.hcl — it should be committed for reproducible builds
```

---

### 4.8 Variables and Outputs

**File:** `terraform/environments/{env}/variables.tf`

```hcl
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be 'dev' or 'prod'."
  }
}

variable "project" {
  description = "Project name used in resource naming and tagging"
  type        = string
  default     = "petclinic"
}
```

#### Variable Best Practices Demonstrated Here

**`description`** — Every variable has a description. This is the documentation. Engineers reading this file six months later understand what each variable does without reading all the code.

**`type`** — Enforces that the value is the right type. `type = string` prevents accidentally passing a list or a number where a string is expected.

**`default`** — Sensible defaults mean running Terraform in the simplest case requires zero extra configuration. `terraform plan` just works with the defaults.

**`validation`** — The `environment` variable only accepts "dev" or "prod". If you pass "staging", Terraform fails immediately with a clear error:
```
Error: Invalid value for variable
  environment = "staging"
  Environment must be 'dev' or 'prod'.
```
Without validation, the error might appear later as a cryptically named resource (`petclinic-staging-vpc`) that violates naming conventions.

#### How Variables Are Set in Practice

Variables can be set in multiple ways (lowest to highest priority):

```
1. Default value in variables.tf          ← lowest priority
2. terraform.tfvars file                  ← common in local development
3. *.auto.tfvars files                    ← auto-loaded
4. -var="environment=prod" flag           ← command line
5. TF_VAR_environment environment var     ← CI/CD pipelines
```

For this project, developers copy `terraform.tfvars.example` to `terraform.tfvars` and customize it locally. The `.tfvars` file is gitignored to prevent committing actual values.

#### Outputs

**File:** `terraform/environments/{env}/outputs.tf`

```hcl
output "aws_region" {
  description = "AWS region in use"
  value       = var.aws_region
}

output "account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}
```

Outputs serve two purposes:
1. **Display** — After `terraform apply`, Terraform prints output values. Useful for getting VPC IDs, EKS endpoints, etc.
2. **Cross-module reference** — Parent modules read child module outputs: `module.vpc.vpc_id`

As more modules are added (VPC, EKS, RDS), more outputs will be added here so CI/CD pipelines and scripts can read infrastructure values.

---

### 4.9 The Bootstrap Process

**File:** `scripts/bootstrap-state.sh`

Before `terraform init` can work, the S3 bucket and DynamoDB table must already exist. But you can't use Terraform to create them (that's a chicken-and-egg problem — Terraform needs state storage to run, but state storage doesn't exist yet).

The bootstrap script solves this by using the AWS CLI directly:

```bash
./scripts/bootstrap-state.sh
# or with a custom region:
./scripts/bootstrap-state.sh --region us-west-2
```

#### How the Script Works (Step by Step)

**Step 1: Get the AWS Account ID**
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="petclinic-terraform-state-${ACCOUNT_ID}"
```
`aws sts get-caller-identity` returns information about the currently authenticated AWS identity. We use the account ID to build a globally unique bucket name.

**Step 2: Create the S3 Bucket (Idempotent)**
```bash
if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  echo "Bucket already exists — skipping creation."
else
  aws s3api create-bucket ...
fi
```
The script checks if the bucket exists before trying to create it. Running the script twice gives the same result — this is called **idempotency**. Critical for scripts that might be run multiple times or in automation.

**Note on us-east-1:** AWS S3 has a quirk — `create-bucket` for `us-east-1` must not include the `LocationConstraint` parameter. All other regions require it. The script handles this:
```bash
if [[ "${REGION}" == "us-east-1" ]]; then
  aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${REGION}"
else
  aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}"
fi
```

**Step 3: Configure the Bucket**
```bash
# Enable versioning
aws s3api put-bucket-versioning --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption --server-side-encryption-configuration '...'

# Block all public access
aws s3api put-public-access-block --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

**Step 4: Create the DynamoDB Table (Idempotent)**
```bash
TABLE_STATUS=$(aws dynamodb describe-table --table-name "${DYNAMO_TABLE}" \
  --query 'Table.TableStatus' --output text 2>/dev/null || echo "NOT_FOUND")

if [[ "${TABLE_STATUS}" == "ACTIVE" ]]; then
  echo "Table already exists — skipping."
else
  aws dynamodb create-table \
    --table-name "${DYNAMO_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST
fi
```

`PAY_PER_REQUEST` billing mode means you only pay per operation, not for a provisioned capacity you may not use. For a lock table with rare operations, this costs pennies per month.

**Step 5: Print Next Steps**
```
======================================
  Bootstrap complete!
  Next steps:
  1. Update backend.tf in each environment:
     Replace ACCOUNT_ID with: 569144120198
  
  terraform/environments/dev/backend.tf
  terraform/environments/prod/backend.tf

  2. Run terraform init in each environment:
     cd terraform/environments/dev && terraform init
     cd terraform/environments/prod && terraform init
======================================
```

---

### 4.10 Backend Configuration

**File:** `terraform/environments/{env}/backend.tf`

```hcl
# Run scripts/bootstrap-state.sh first, then replace ACCOUNT_ID with your AWS account ID:
#   aws sts get-caller-identity --query Account --output text
terraform {
  backend "s3" {
    bucket         = "petclinic-terraform-state-569144120198"
    key            = "petclinic/dev/terraform.tfstate"
    region         = "eu-central-1"
    encrypt        = true
    dynamodb_table = "petclinic-terraform-locks"
  }
}
```

#### Why Literal Values (Not Variables)?

Terraform's backend configuration is processed before variables are loaded. This means `var.aws_region` is not available in the `backend {}` block — it would cause an error. All backend values must be literal strings.

This is why the bucket name must be hardcoded after the bootstrap script runs.

#### The State Key Design

| Environment | Key |
|-------------|-----|
| Dev | `petclinic/dev/terraform.tfstate` |
| Prod | `petclinic/prod/terraform.tfstate` |

Using path-like keys in the same bucket (rather than separate buckets) is a common pattern:
- One bucket to manage and secure
- Clear organization by environment
- Easy to add more environments (`petclinic/staging/terraform.tfstate`)

The forward slash is not a real directory separator in S3 — it's just part of the object key. But S3 console displays it as a folder structure, which is convenient.

#### What Happens When You Run `terraform init`

```bash
cd terraform/environments/dev
terraform init
```

1. Downloads the AWS provider (pinned version from `.terraform.lock.hcl`)
2. Connects to the S3 backend and verifies the bucket exists
3. Verifies the DynamoDB table exists
4. Creates the local `.terraform/` directory (gitignored)

After this, `terraform plan` and `terraform apply` can run.

---

## 5. E-2: Networking (VPC)

**Jira Epic:** E-2 | **Tickets:** PETPLAT-6, PETPLAT-8, PETPLAT-9 | **Blocks:** E-3 (EKS), E-5 (RDS), E-6 (Secrets)

The VPC is the network foundation every other resource lives inside. No EKS cluster, RDS instance, or load balancer can be created without it. This epic provisions a reusable VPC module and wires it into the `dev` environment root module.

---

### 5.1 Why a Custom VPC?

AWS creates a default VPC in every region and account. You could deploy directly into it, but you should not in real projects, for three reasons:

1. **No isolation** — the default VPC is shared across everything you deploy in that region. A misconfigured resource could affect unrelated workloads.
2. **No tagging control** — the default VPC has no project tags, making cost attribution impossible.
3. **Unpredictable CIDR** — the default VPC uses `172.31.0.0/16`, which may clash with on-premise or VPN networks in real organisations.

A custom VPC gives you full control over the address space, subnets, routing, and access rules from day one.

---

### 5.2 All-Public Subnet Design (ADR-0001)

A standard production VPC uses **private subnets** for compute and **public subnets** only for load balancers, with a NAT Gateway routing outbound internet traffic from the private side. This costs ~$35–45/month per AZ.

For this learning platform, all resources (EKS nodes, RDS) are placed in **public subnets**. Security groups enforce access control instead of network topology.

| Approach | Monthly cost | Isolation method |
|----------|-------------|-----------------|
| Private subnets + NAT Gateway | ~$70/mo (2 AZs) | Network topology |
| Public subnets + Security Groups | $0 extra | Security group rules |

**What this means in practice:** EKS nodes have public IP addresses, but the security groups block all inbound traffic except what is explicitly allowed (ALB → NodePort, control plane → kubelet). RDS only accepts connections from the EKS node SG on port 3306. The effective security posture is the same; the cost difference is significant for a student environment.

See `docs/adr/0001-public-subnets.md` for the full decision record.

---

### 5.3 What the VPC Module Creates

The module lives in `terraform/modules/vpc/`. It is called from each environment root module and receives all config via input variables.

```
terraform/modules/vpc/
├── main.tf        # All resource definitions
├── variables.tf   # Input variables (env name, CIDR, AZ list, cluster name)
├── outputs.tf     # vpc_id, subnet_ids, and all four SG IDs
└── versions.tf    # Provider constraints
```

**Resources provisioned:**

| Resource | Count | Name pattern |
|----------|-------|--------------|
| `aws_vpc` | 1 | `petclinic-{env}-vpc` |
| `aws_internet_gateway` | 1 | `petclinic-{env}-igw` |
| `aws_subnet` (public) | 2 | `petclinic-{env}-public-{1,2}` |
| `aws_route_table` | 1 | `petclinic-{env}-public-rt` |
| `aws_route_table_association` | 2 | one per subnet |
| `aws_security_group` | 4 | `alb-sg`, `eks-cluster-sg`, `eks-node-sg`, `rds-sg` |
| `aws_security_group_rule` | 10 | ingress/egress rules for each SG |

**Total: 21 resources per environment.**

The VPC CIDR for dev is `10.0.0.0/16`. Subnets are `/24` slices:

| Subnet | CIDR | AZ |
|--------|------|----|
| `petclinic-dev-public-1` | `10.0.1.0/24` | `eu-central-1a` |
| `petclinic-dev-public-2` | `10.0.2.0/24` | `eu-central-1b` |

Two AZs are required for EKS (the control plane demands multi-AZ subnets) and for RDS subnet groups.

---

### 5.4 Security Groups: The Real Perimeter

Four security groups are created, each scoped to a single role. Rules use **security group references** (not CIDR blocks) wherever possible, which means rules automatically track any IP change to the referenced group.

#### ALB Security Group (`petclinic-{env}-alb-sg`)

| Direction | Port | Source/Dest | Why |
|-----------|------|-------------|-----|
| Ingress | 80 | `0.0.0.0/0` | HTTP from the public internet |
| Ingress | 443 | `0.0.0.0/0` | HTTPS from the public internet |
| Egress | 8080 | EKS node SG | Health checks to the API Gateway pod |
| Egress | 30000–32767 | EKS node SG | NodePort services |

#### EKS Cluster Security Group (`petclinic-{env}-eks-cluster-sg`)

Protects the Kubernetes API server endpoint.

| Direction | Port | Source/Dest | Why |
|-----------|------|-------------|-----|
| Ingress | 443 | EKS node SG | Worker nodes must reach the API server |
| Egress | all | `0.0.0.0/0` | Control plane initiates kubelet/webhook calls |

#### EKS Node Security Group (`petclinic-{env}-eks-node-sg`)

Applied to every EC2 worker node.

| Direction | Port | Source/Dest | Why |
|-----------|------|-------------|-----|
| Ingress | all | self (node SG) | Pod-to-pod communication across nodes |
| Ingress | all | EKS cluster SG | Control plane to kubelet / exec / logs |
| Ingress | 10250 | EKS cluster SG | Kubelet API specifically |
| Ingress | 30000–32767 | ALB SG | NodePort traffic from ALB |
| Egress | all | `0.0.0.0/0` | ECR pulls, S3, Secrets Manager, DNS |

#### RDS Security Group (`petclinic-{env}-rds-sg`)

| Direction | Port | Source/Dest | Why |
|-----------|------|-------------|-----|
| Ingress | 3306 | EKS node SG | MySQL from application pods only |

No other ingress. No egress rule needed for RDS (AWS adds a default allow-all egress on creation that is effectively unused since RDS never initiates connections).

---

### 5.5 Kubernetes Tags on Subnets

The public subnets carry two extra tags that EKS and the AWS Load Balancer Controller require:

```hcl
"kubernetes.io/cluster/petclinic-{env}" = "shared"
"kubernetes.io/role/elb"                = "1"
```

- **`kubernetes.io/cluster/{name}=shared`** — tells EKS which subnets it can use for managed node group placement and ENI attachment.
- **`kubernetes.io/role/elb=1`** — tells the AWS Load Balancer Controller where to provision internet-facing ALBs. Without this tag, `kubectl apply` of an Ingress resource will fail with "no subnets found."

These tags must match the EKS cluster name exactly (case-sensitive).

---

### 5.6 Dev Environment Apply: What Was Created

The dev VPC was applied on 2026-06-26. All resources are in `eu-central-1`.

| Output | Value |
|--------|-------|
| `vpc_id` | `vpc-0d4df9298830d864a` |
| `subnet_ids[0]` (eu-central-1a) | `subnet-05d902f36b8ac3135` |
| `subnet_ids[1]` (eu-central-1b) | `subnet-09c1e16d4ae229e37` |
| `alb_sg_id` | `sg-00b5c7599d0ea1da8` |
| `eks_cluster_sg_id` | `sg-0c3cc8f9be19ce808` |
| `eks_node_sg_id` | `sg-0b1ba0476a516a7f3` |
| `rds_sg_id` | `sg-0ad551c0f1e139d9a` |

These IDs are stored in Terraform state (`petclinic/dev/terraform.tfstate` in S3) and will be consumed automatically by the EKS module via `terraform_remote_state` or module outputs.

---

### 5.7 Known Gotcha: Non-ASCII Characters in SG Descriptions

**Symptom:** `terraform apply` fails with:

```
Error: creating Security Group: InvalidParameterValue: Value (...) for parameter
GroupDescription is invalid. Character sets beyond ASCII are not supported.
```

**Cause:** AWS Security Group `description` fields only accept ASCII characters. The initial VPC module used an em dash (`—`, Unicode U+2014) in two SG descriptions, which AWS rejected.

**Fix applied** in `terraform/modules/vpc/main.tf`: replaced `—` with `-` (standard hyphen) in the `alb` and `rds` security group descriptions.

**Rule going forward:** Never use typographic characters (em dashes, curly quotes, ellipsis `…`) in any AWS resource name, description, or tag value. Stick to plain ASCII. This applies to all `description` fields in `aws_security_group`, `aws_iam_policy`, `aws_db_instance`, etc.

---

## 6. E-3: EKS Cluster

**Jira Epic:** E-3 | **Tickets:** PETPLAT-12, PETPLAT-13, PETPLAT-14, PETPLAT-15, PETPLAT-16 | **Blocks:** E-8, E-9, E-10, E-11

The EKS cluster is the compute platform — every application pod, every sidecar, every background job runs here. Nothing downstream (Kubernetes manifests, Helm charts, ArgoCD, CI pipeline) can be built without it.

---

### 6.1 Why EKS?

EKS is AWS's managed Kubernetes service. You could run Kubernetes yourself on EC2, but you would be responsible for control plane availability, etcd backups, API server upgrades, and certificate rotation. EKS handles all of that and charges a flat fee ($0.10/hr per cluster) for the control plane. For a learning project the important benefit is that you get a real, production-grade Kubernetes API without managing masters.

Alternatives considered:

| Option | Why not used |
|--------|-------------|
| Self-managed K8s on EC2 | Operational burden; would dominate project time |
| ECS (Fargate) | Not Kubernetes — different tooling, no `kubectl`, no Helm |
| App Runner / Lambda | Not suitable for stateful microservices with service discovery |

---

### 6.2 Cluster Configuration Decisions

| Parameter | Value | Why |
|-----------|-------|-----|
| Kubernetes version | `1.32` | Standard support as of mid-2026; spec originally said 1.29 which would incur extended support charges |
| Authentication mode | `API_AND_CONFIG_MAP` | Supports both modern API-based access entries and legacy aws-auth ConfigMap |
| `bootstrap_cluster_creator_admin_permissions` | `true` | Automatically grants the deploying IAM identity cluster-admin so `kubectl` works immediately after apply without any extra configuration |
| Endpoint access | Public only | Private endpoint requires VPN or bastion; public is acceptable for a learning project with SG-enforced access |
| Control plane logs | `api`, `audit`, `authenticator` | The three most useful for debugging auth failures and API issues. `scheduler` and `controllerManager` omitted to reduce CloudWatch cost |

---

### 6.3 IAM Roles: Cluster vs Nodes

EKS requires two separate IAM roles. Students often confuse these.

#### Cluster Role (`petclinic-dev-eks-cluster-role`)

Used by the **EKS control plane** (the managed master nodes that AWS runs). It needs permission to:
- Create ENIs for pod networking
- Describe EC2 resources (to place nodes, manage load balancers)
- Write to CloudWatch Logs

The single managed policy `AmazonEKSClusterPolicy` covers all of this.

#### Node Role (`petclinic-dev-eks-node-role`)

Used by the **EC2 worker nodes** (your t4g.small instances). Each node assumes this role at boot and uses it to:
- Register with the cluster (`AmazonEKSWorkerNodePolicy`)
- Configure pod networking — assign/de-assign ENIs for pod IPs (`AmazonEKS_CNI_Policy`)
- Pull images from ECR (`AmazonEC2ContainerRegistryReadOnly`)

**Why two roles and not one?** Least privilege. The cluster role is assumed by AWS-managed infrastructure with a high trust boundary. The node role is assumed by EC2 instances you control. Merging them would give your EC2 instances permission to modify cluster-level AWS resources, and vice versa.

---

### 6.4 OIDC Provider and IRSA

IRSA (IAM Roles for Service Accounts) lets individual Kubernetes pods assume specific IAM roles — without storing credentials in Secrets or granting the entire node role extra permissions.

**How it works:**

1. EKS exposes an OIDC issuer URL (e.g. `https://oidc.eks.eu-central-1.amazonaws.com/id/ABA87A9B...`)
2. We register this URL as an IAM OIDC Identity Provider (`aws_iam_openid_connect_provider`)
3. When creating an IAM role for a pod, we add a trust policy that says: "allow the OIDC provider to assume this role, but only for the service account `namespace/name`"
4. The pod's service account token is automatically mounted and exchanged for AWS credentials via the OIDC federation

**Why this matters:** The EBS CSI driver (which manages PersistentVolumes) uses IRSA. So does the AWS Load Balancer Controller (E-6), External Secrets Operator (E-7), and any custom app that needs to call AWS APIs. Every IRSA role in this project references the OIDC provider ARN created here.

The `tls` provider is used to fetch the OIDC endpoint's TLS thumbprint, which IAM requires during provider registration.

---

### 6.5 Managed Node Group: ARM/Graviton

The node group `petclinic-dev-nodes` runs on `t4g.small` instances (2 vCPU, 2 GiB RAM, ARM64 architecture).

| Parameter | Value | Why |
|-----------|-------|-----|
| AMI type | `AL2_ARM_64` | Amazon Linux 2 for ARM — required for t4g instances |
| Capacity type | `ON_DEMAND` | Graviton free trial covers ON_DEMAND; Spot would not qualify |
| Min/desired/max | 2 / 2 / 4 | Min 2 for HA across AZs; Karpenter (E-14) handles auto-scaling beyond desired |
| Disk size | 20 GB | Fits within the 30 GB EBS free tier; enough for base OS + container images |
| Architecture note | All Docker images must be built for `linux/arm64` | x86 images will fail to start on these nodes — CI uses `docker buildx` + QEMU |

**Why ARM?** AWS offers a Graviton free trial for t4g instances (750 hrs/month until Dec 2026). Two t4g.small instances running 24/7 = ~1,464 hrs/month — one node is fully free, the second costs ~$11/month. For a learning project this is the lowest-cost option that still gives you a real multi-node cluster.

---

### 6.6 EKS Managed Add-ons

EKS managed add-ons are cluster components AWS installs and manages for you. Versions are pinned by querying `aws_eks_addon_version` at plan time (most recent for the given K8s version).

| Add-on | Purpose | IRSA |
|--------|---------|------|
| `coredns` | DNS resolution for all pods (`svc.cluster.local`) | No |
| `kube-proxy` | `iptables`/`ipvs` rules for Service routing on each node | No |
| `vpc-cni` | AWS VPC CNI — assigns real VPC IPs to pods (not an overlay network) | No |
| `aws-ebs-csi-driver` | Provisions EBS volumes for PersistentVolumeClaims | Yes — `petclinic-dev-ebs-csi-driver-role` |

**Why `OVERWRITE` for conflict resolution?** On a fresh cluster there are no existing add-on configurations to protect. `OVERWRITE` ensures the managed version always wins, which is the correct behaviour for initial setup. You would change this to `PRESERVE` if you customised add-on configuration in-cluster.

**CoreDNS dependency:** CoreDNS pods cannot schedule until there are Ready worker nodes. The `depends_on = [aws_eks_node_group.main]` in the module ensures Terraform waits for nodes before trying to install add-ons.

---

### 6.7 kubectl Access: How It Works

With `bootstrap_cluster_creator_admin_permissions = true`, the IAM identity that ran `terraform apply` is automatically granted `system:masters` cluster access. No extra steps needed for the deploying user.

To configure `kubectl`:

```bash
aws eks update-kubeconfig --name petclinic-dev --region eu-central-1
kubectl get nodes        # should show 2 Ready nodes
kubectl get pods -n kube-system  # should show coredns, kube-proxy, aws-node pods
```

To grant additional IAM users/roles cluster-admin, add their ARNs to the `cluster_admin_arns` variable in `terraform/environments/dev/main.tf`:

```hcl
module "eks" {
  ...
  cluster_admin_arns = [
    "arn:aws:iam::569144120198:user/another-dev",
    "arn:aws:iam::569144120198:role/ci-role",
  ]
}
```

This creates `aws_eks_access_entry` + `aws_eks_access_policy_association` resources for each ARN using the `AmazonEKSClusterAdminPolicy`.

---

### 6.8 Dev Environment Apply: What Was Created

The dev EKS cluster was applied on 2026-06-26. Total provisioning time: ~11 minutes.

| Output | Value |
|--------|-------|
| `cluster_name` | `petclinic-dev` |
| `cluster_endpoint` | `https://ABA87A9B2745140A4FF2F157283E5C13.gr7.eu-central-1.eks.amazonaws.com` |
| `oidc_provider_arn` | `arn:aws:iam::569144120198:oidc-provider/oidc.eks.eu-central-1.amazonaws.com/id/ABA87A9B2745140A4FF2F157283E5C13` |
| `node_role_arn` | `arn:aws:iam::569144120198:role/petclinic-dev-eks-node-role` |
| `kubeconfig_command` | `aws eks update-kubeconfig --name petclinic-dev --region eu-central-1` |

**Provisioning timeline:**
- Cluster IAM roles + policy attachments: ~3s
- EKS control plane (`petclinic-dev`): 7m4s
- OIDC provider + EBS CSI IRSA role: ~3s
- Node group (`petclinic-dev-nodes`): 2m41s
- All four add-ons: ~60s

---

## 7. The Full Setup Workflow

Here is the complete sequence to go from zero to a working Terraform setup:

```bash
# Step 1: Run bootstrap (once, ever)
./scripts/bootstrap-state.sh

# Step 2: Note the account ID printed, update backend.tf files
# terraform/environments/dev/backend.tf  → replace ACCOUNT_ID
# terraform/environments/prod/backend.tf → replace ACCOUNT_ID

# Step 3: Initialize dev environment
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars   # copy example, customize locally
terraform init                                  # downloads providers, connects to S3

# Step 4: Validate and format
terraform fmt -recursive ../../                 # format all .tf files
terraform validate                              # syntax check

# Step 5: Plan (always before apply)
terraform plan -out plan.out                    # save the plan

# Step 6: Review the plan
# Read the output carefully. Look for any unexpected destroys.

# Step 7: Apply
terraform apply plan.out                        # apply exactly the saved plan
```

---

## 8. Security Practices Explained

### Why `*.tfvars` Is Gitignored

Terraform variable files (`.tfvars`) often contain sensitive values: API keys, passwords, account IDs. Committing them to git means:
- Everyone with repo access sees the secrets
- The secrets are permanent — even after deletion, they live in git history
- If the repo is ever made public, all secrets are exposed

The project uses `terraform.tfvars.example` (tracked in git) with placeholder values. Engineers copy this to `terraform.tfvars` locally and fill in real values.

### Why `plan.out` Is Gitignored

A saved plan file is a binary representation of exactly what Terraform will change. It can contain resource configurations, including sensitive values. It also becomes stale the moment any infrastructure changes — committing it would be confusing and potentially dangerous.

### Why the AWS Provider Region Is Set in Code

```hcl
provider "aws" {
  region = var.aws_region  # ← set explicitly
}
```

Without this, Terraform uses whatever region is set in `~/.aws/config` or the `AWS_REGION` environment variable. This is dangerous — an engineer might have `us-east-1` as their default and accidentally create resources in the wrong region. Explicit is always safer than implicit.

### The Principle of Least Privilege

The IAM user or role used for Terraform should have only the permissions needed — nothing more. For this project, the required permissions are documented in the CI/CD setup (E-10). Never use the AWS root account for Terraform.

---

## 9. Cost Considerations

This project is designed for learning while minimizing AWS costs. Key decisions:

| Decision | Cost Saving | Trade-off |
|----------|------------|-----------|
| All-public subnets (no NAT Gateway) | ~$35-65/month saved | Security groups must be extra restrictive |
| t4g.small nodes (ARM/Graviton) | ~40% cheaper than x86 | Images must be built for ARM64 |
| db.t4g.micro RDS | Free tier eligible | Not suitable for real production load |
| Single-AZ RDS (no Multi-AZ) | ~50% cheaper | No automatic failover |
| PAY_PER_REQUEST DynamoDB | ~$0.10/month for lock table | Slightly more expensive at high scale |

The DynamoDB table for state locking is effectively free — it processes a lock and unlock for each `terraform apply`, which is maybe a few operations per day. At $1.25 per million operations, you'd pay fractions of a cent per month.

The S3 bucket storage cost for state files is also negligible — state files are typically a few kilobytes each. Even with versioning enabled, you'd accumulate a few megabytes over the lifetime of the project, costing less than $0.01/month.

---

## 10. Common Mistakes and How to Avoid Them

### Mistake 1: Running `terraform apply` Without a Plan

```bash
# WRONG — surprises possible:
terraform apply

# RIGHT — predictable:
terraform plan -out plan.out
terraform apply plan.out
```

Without a saved plan, Terraform re-plans at apply time. If someone else changed infrastructure between your plan and your apply, you'll apply a different set of changes than you reviewed.

### Mistake 2: Committing `.terraform/`

The `.terraform/` directory contains downloaded provider binaries (hundreds of megabytes) and the backend configuration. It's gitignored for good reason. If you accidentally commit it:

```bash
git rm -r --cached .terraform/
git commit -m "remove accidentally committed .terraform/ directory"
```

### Mistake 3: Not Running `terraform fmt`

Terraform has an opinionated formatter. If your code isn't formatted, `terraform fmt -check` fails in CI. Always run `terraform fmt -recursive` before committing:

```bash
terraform fmt -recursive terraform/
```

### Mistake 4: Deleting the State File

The S3 state file is the source of truth for what Terraform has created. Deleting it means Terraform no longer knows those resources exist. The next `terraform apply` will try to create everything again, causing duplicate resources or errors.

S3 versioning protects against accidental deletion — but don't test this unnecessarily.

### Mistake 5: Using the Root AWS Account

Never use AWS root account credentials for Terraform. Create an IAM user or role with only the required permissions. Root account has no permission boundaries — a mistake with root credentials can do unlimited damage.

### Mistake 6: Hard-Coding the Account ID in Shared Code

The account ID (`569144120198`) should only appear in `backend.tf`, which is specific to your environment. Shared code (modules) should use `data.aws_caller_identity.current.account_id` to reference the account ID dynamically.

---

## 11. Glossary

| Term | Definition |
|------|-----------|
| **IaC (Infrastructure as Code)** | Managing infrastructure through code files rather than manual console clicks |
| **Terraform** | An open-source IaC tool by HashiCorp that uses HCL (HashiCorp Configuration Language) |
| **Provider** | A Terraform plugin that knows how to talk to a specific API (e.g., AWS) |
| **Resource** | A single infrastructure object managed by Terraform (e.g., one VPC, one EC2 instance) |
| **Module** | A reusable group of Terraform resources with input variables and output values |
| **Root Module** | The top-level Terraform directory where you run `terraform apply` |
| **Child Module** | A module called by a root module; provides reusable blueprints |
| **State File** | A JSON file tracking what Terraform has created (`terraform.tfstate`) |
| **Remote State** | Storing the state file in a shared location (S3) rather than locally |
| **State Locking** | Preventing simultaneous `terraform apply` operations using DynamoDB |
| **Backend** | Terraform configuration for where to store state |
| **Plan** | A Terraform preview of what changes will be made without actually making them |
| **Apply** | Actually executing the changes previewed in a plan |
| **Idempotent** | Running the same operation multiple times produces the same result |
| **MCP Server** | Model Context Protocol — a plugin system giving AI tools access to external APIs |
| **Hook** | A script that runs automatically before/after a Claude Code tool call |
| **Tags** | Key-value labels on AWS resources used for cost allocation and organization |
| **ARN** | Amazon Resource Name — unique identifier for any AWS resource |
| **IAM** | Identity and Access Management — AWS permission system |
| **CIDR** | Classless Inter-Domain Routing — IP address range notation (e.g., `10.0.0.0/16`) |
| **VPC** | Virtual Private Cloud — isolated network in AWS |
| **EKS** | Elastic Kubernetes Service — managed Kubernetes in AWS |
| **RDS** | Relational Database Service — managed databases in AWS |
| **ECR** | Elastic Container Registry — private Docker image registry |
| **S3** | Simple Storage Service — object storage in AWS |
| **DynamoDB** | Managed NoSQL database in AWS |
| **SSE** | Server-Side Encryption — encrypting data at rest on the server |
| **GitOps** | Using git as the source of truth for both application code and infrastructure |
