# Phase 2 — Terraform foundation

Read these first: `docs/LLD.md`, `docs/01-system-design.png`, `AZURE-ACCESS.md`

Write the Terraform for the development environment.

Important constraint: I am building in a SINGLE Azure subscription for development,
not the five-subscription model in the LLD. Use resource groups for separation, with
the subscription id as a variable per stack, so moving to five subscriptions later is
configuration rather than rework.

Stacks, in this order — each must apply cleanly before the next:
  1. infra/terraform/stacks/01-network     VNet, subnets, NSGs, private DNS zones, NAT
  2. infra/terraform/stacks/02-security    Key Vault, Key Vault Premium, managed identities
  3. infra/terraform/stacks/03-observability  Log Analytics, Application Insights
  4. infra/terraform/stacks/04-data        PostgreSQL Flexible Server, Redis, storage, Event Hubs
  5. infra/terraform/stacks/05-aks         AKS with node pools, excluding npexec

Follow the LLD exactly for naming, address space, SKUs and settings. Specifically:
- PostgreSQL with the parameter overrides in the LLD, pgvector enabled
- All data services with public network access disabled and private endpoints
- Storage accounts with shared key access disabled, Entra ID auth only
- AKS private cluster, Workload Identity, no local accounts, Azure CNI overlay
- Mandatory tags on every resource, enforced by a module that refuses to omit them

Backend: azurerm with use_azuread_auth = true. No storage account key anywhere.

Run terraform init and terraform plan for stack 01 and show me the plan.
DO NOT run terraform apply — I will run it myself after reviewing.
