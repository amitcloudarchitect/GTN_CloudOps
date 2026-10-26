# Building the CloudOps platform with Claude Code

Everything Claude Code needs, and the setup you do yourself.

## 1. What is in this pack

```
00-START-HERE.md        This file
CLAUDE.md               Project memory — Claude Code loads this automatically
AZURE-ACCESS.md         How Claude Code reaches Azure — read before anything else
PROMPTS.md              The seven build phases, in order
.claude/commands/       Each phase as a slash command
docs/HLD.md             High level design
docs/LLD.md             Low level design — the implementation spec
docs/*.png              The eight design diagrams
reference/schema.sql    Database schema with row-level security
reference/pricing_engine.py   Pricing logic, already regression-tested
```

Markdown rather than Word, deliberately — it reads far better. Keep the `.docx`
versions for humans.

## 2. Install Claude Code

Claude Code runs on your machine with access to your files and terminal. It works in
the terminal, in VS Code and JetBrains, and in the Claude desktop app.

**Get the current install command from the official docs** rather than from me —
requirements change and I would rather not give you a stale Node version:

- Overview and install: https://docs.claude.com/en/docs/claude-code/overview

It uses your existing Claude subscription, so there is no separate API key to manage
for the tool itself.

## 3. Set up the repository

```bash
mkdir getronics-cloudops && cd getronics-cloudops
git init
# unzip this pack into the folder, giving you:
#   CLAUDE.md, .claude/, docs/, reference/, PROMPTS.md, AZURE-ACCESS.md
```

Create `.gitignore` before anything else:

```
.env
.env.*
*.tfvars
!*.tfvars.example
.terraform/
terraform.tfstate*
__pycache__/
.venv/
node_modules/
*.pem
*.key
```

Commit, then start Claude Code in that directory. It reads `CLAUDE.md` automatically —
you do not attach it, and you do not need to repeat its contents in prompts.

## 4. How CLAUDE.md works

It is persistent project memory, loaded at the start of every session. That is why the
non-negotiable rules live there rather than in prompts: they apply to every piece of
work without you having to remember to restate them.

You can add to it mid-session by starting a message with `#` — useful when you discover
a convention worth making permanent. Review those additions before committing; memory
that accumulates noise becomes memory that gets ignored.

## 5. Permissions — the important part

Claude Code asks before editing files or running commands. Three habits make this work
well on a project where mistakes are expensive:

**Let it run read-only things freely.** `terraform plan`, `pytest`, `ruff`, `git diff`,
`az account show`. Approving these one by one wastes your attention; approve them as a
pattern when prompted.

**Never allow `terraform apply`, `terraform destroy`, or `az role assignment`.** Deny
them explicitly. The workflow is: Claude writes the Terraform and runs `plan`, you read
the plan, you run `apply` yourself.

**Use plan mode before large changes.** It explores and proposes without editing, so
you can correct the approach before any code is written. Worth it at the start of each
phase.

Permission settings live in `.claude/settings.json` for the project. The schema is in
the docs — https://docs.claude.com/en/docs/claude-code/overview — and it is worth ten
minutes to set the allow and deny lists once rather than approving repeatedly.

## 6. The build phases

`PROMPTS.md` has seven phases. Each is also a slash command in `.claude/commands/`, so
in a session you can type `/phase0` rather than pasting.

Run **one phase per session**. Use `/clear` between them. Long sessions drift: quality
drops, earlier constraints get forgotten, and the model starts inventing. A fresh
session with CLAUDE.md loaded beats a long one every time.

Order matters more than it looks:

1. **Phase 0** builds the tenancy package *and the CI check that prevents bypassing it*
   before any feature code exists. You cannot retrofit this.
2. **Phase 1** database schema with row-level security and the isolation suite.
3. **Phase 2** Terraform foundation — plan only, you apply.
4. **Phase 3** API and scope resolution. **Stop here and verify isolation works**
   before building anything on top.
5. **Phase 4** first connector end to end, as the pattern for the rest.
6. **Phase 5** AI gateway and tool registry.
7. **Phase 6** evaluation harness *then* the classifier agent. That order is deliberate
   — you want to be able to measure the agent from its first commit.

The execution plane comes last, after a human security review. Do not let it get built
early because it is the interesting part.

## 7. Working well with it

**Let it read before it writes.** At the start of a phase, ask it to read the relevant
LLD section and tell you its plan. Correct the plan, then let it build. This costs two
minutes and saves rewriting.

**Ask "where in the LLD is this specified?"** when something looks invented. It will
usually admit it guessed, which is exactly what you want to surface.

**Commit at each working checkpoint**, not at the end of a phase. Small commits make it
trivial to discard a wrong turn.

**Review every diff touching** `packages/tenancy`, the credential broker, or Terraform.
The design makes certain mistakes catastrophic rather than annoying — a missing `FORCE`
on an RLS policy is a silent cross-customer data leak that no test you did not write
will catch.

## 8. What this does not do

Claude Code will not deploy to Azure on its own, by design. It writes infrastructure
code and shows you plans; you hold the apply. See `AZURE-ACCESS.md` — the short version
is that you authenticate with `az login` as yourself and no credential is ever created
for the tool.

## 9. If you want it running while you are away

Claude Code is available in the Claude mobile app for delegating work remotely, and
there is a desktop experience for running tasks alongside your files. Useful once the
patterns are established and the work is more mechanical. I would not use it for the
early security-critical phases, where you want to be reading diffs closely.
