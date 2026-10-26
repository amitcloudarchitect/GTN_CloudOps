# Azure access for the build

Read this before letting Cursor touch Azure.

## The short answer

**Do not give Cursor an Azure credential.** Authenticate *yourself* on the machine with Azure CLI; Terraform and the Azure SDK pick that session up automatically. Cursor then runs commands as you, with your rights, and no secret exists in the repository or in the chat.

```bash
az login                                    # opens a browser, signs in as amit.kumar@gtnmpn.onmicrosoft.com
az account set --subscription "<name or id>"
az account show                             # confirm the right subscription
```

Terraform's `azurerm` provider uses that session with no configuration:

```hcl
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id      # explicit, never hard-coded
}
```

This is the right model for a development build. No service principal, no client secret, nothing to leak or rotate.

## What you need to have

| Need | Why | How to check |
|---|---|---|
| A subscription you can create resources in | Everything | `az account list -o table` |
| **Contributor** on that subscription or a resource group | Create resources | `az role assignment list --assignee amit.kumar@gtnmpn.onmicrosoft.com -o table` |
| **User Access Administrator**, or a colleague who has it | Managed identities need role assignments | As above |
| Ability to create app registrations | Graph, SharePoint and ServiceNow connectors | `az ad app create --display-name test-delete-me` then delete it |
| Azure OpenAI access in the subscription | The AI layer | Check in the portal under Azure AI services |
| vCPU quota in West Europe | AKS node pools | `az vm list-usage -l westeurope -o table` |

**If you lack User Access Administrator**, Terraform will create resources but fail on role assignments. That is normal in a corporate tenant. Two options: have a platform admin run those applies, or split the Terraform so role assignments sit in a separate stack someone else runs. Tell Cursor which, so it structures the code accordingly.

**If `az ad app create` is blocked**, your tenant restricts app registration to admins. You will need a platform admin to create the app registrations and tell you the application IDs — which are *not* secrets and are safe to put in a tfvars file.

## Start with one sandbox subscription, not five

The LLD specifies five subscriptions under a management group with Azure Policy assigned at the management group scope. **You will almost certainly not have rights to do that**, and you do not need it to start building.

For the development build, use a single subscription with resource groups standing in for the subscription separation:

```
rg-cloudops-net-dev-weu
rg-cloudops-data-dev-weu
rg-cloudops-aks-dev-weu
rg-cloudops-sec-dev-weu
rg-cloudops-exec-dev-weu     ← keep this separate even in dev
```

Keep the execution resources in their own resource group with their own identity from day one, even though the real separation is a subscription boundary. It costs nothing now and means the production split is a Terraform variable rather than a refactor.

Write the Terraform with subscription as a variable per stack, so moving to the five-subscription model later is configuration, not rework. Tell Cursor this explicitly — it is in the prompts.

## Terraform state

Create the state storage by hand, once, before any Terraform runs:

```bash
az group create -n rg-cloudops-tfstate-dev-weu -l westeurope
az storage account create -n stcloudopstfstatedevweu \
  -g rg-cloudops-tfstate-dev-weu -l westeurope \
  --sku Standard_LRS --min-tls-version TLS1_2 \
  --allow-blob-public-access false
az storage container create -n tfstate \
  --account-name stcloudopstfstatedevweu --auth-mode login
```

Backend configuration, with no key in it:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-cloudops-tfstate-dev-weu"
    storage_account_name = "stcloudopstfstatedevweu"
    container_name       = "tfstate"
    key                  = "dev.tfstate"
    use_azuread_auth     = true          # uses your az login, not a storage key
  }
}
```

`use_azuread_auth` matters — without it Terraform wants a storage account key, which is a secret you would then have to handle.

## Letting Cursor run Terraform

Cursor's agent mode can run terminal commands. Configure it so that:

- **`terraform plan` runs freely.** It is read-only and the output is exactly what you want the model to reason about.
- **`terraform apply` is never automatic.** Review the plan yourself, then run apply yourself. Never `-auto-approve`.

In Cursor's settings, add `terraform apply`, `terraform destroy` and `az role assignment` to the command denylist if your version supports it. If not, the rules file instructs the model not to run them — but treat that as a reminder, not a control.

A workflow that works well: ask Cursor to write the Terraform and run `plan`; read the plan; if it is wrong, tell Cursor what is wrong and let it fix and re-plan; when the plan is right, you run apply.

## When you get to CI/CD

For GitHub Actions, use **OIDC federated credentials** — no secret at all:

```bash
az ad app create --display-name "cloudops-cicd-dev"
# then add a federated credential for your repo, in the portal under
# App registrations → Certificates & secrets → Federated credentials
# Issuer:  https://token.actions.githubusercontent.com
# Subject: repo:<org>/<repo>:ref:refs/heads/main
# Audience: api://AzureADTokenExchange
```

The workflow then uses `azure/login@v2` with `client-id`, `tenant-id` and `subscription-id` as repository *variables* — these are identifiers, not secrets. There is no client secret to store or rotate.

**Do not create a service principal with a client secret.** If something later forces you to, keep it in environment variables outside the repository, scope it to a single resource group, give it a short expiry, and never let it near Cursor's context.

## Connector credentials during development

Do not request real ServiceNow, Qualys or CoreStack credentials for the early build. Instead:

1. Build connectors against **recorded fixtures** — real response shapes with the data anonymised.
2. Ask the service owners for **non-production instances** in parallel, since those take weeks.
3. When real credentials arrive, they go into Key Vault, referenced by name. Application code reads them through workload identity.

This means Cursor never needs a connector credential, and the connector work is not blocked waiting for one.

## The one thing to get right

Every path by which Cursor reaches Azure should be *your* identity, interactively authenticated, with you approving anything that changes state. The moment you create a long-lived credential to make automation convenient, you have created the thing the whole execution plane design exists to avoid.
