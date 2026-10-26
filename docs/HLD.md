## Purpose and scope

An agentic AI layer over the platforms Getronics already runs, covering ticket lifecycle and remediation, near-real-time estate analysis, FinOps, security and Well-Architected assurance, solution estimation and project delivery — for a portfolio of managed customers across Azure, AWS, private cloud and data centre estates, with both Getronics and customer audiences on one application.

It replaces none of the existing platforms. ServiceNow owns tickets, changes and the CMDB. Qualys owns vulnerability scanning and posture. CoreStack owns cloud financial management. CloudBolt owns provisioning. Resolve Actions Pro owns day-2 workflows. SharePoint owns customer documents. AMARA is the conversational front door. What the platform adds is the work that is manual today: cross-system correlation, cost reconciliation and margin, effort modelling, audit evidence, reporting, remediation, and a learning loop that makes the next ticket faster than the last.

### What the platform masters

| Domain | Master | Platform role |
| --- | --- | --- |
| Tickets, changes, CMDB | ServiceNow | Read; write back notes, closures, change records, owned CI fields |
| Vulnerabilities and posture | Qualys | Read findings and scan state; age against SLA; map to controls |
| Cost, budgets, optimisation advice | CoreStack | Read findings alongside raw billing exports |
| Provisioning and blueprints | CloudBolt | Request, govern, reconcile |
| Day-2 workflows and patching | Resolve Actions Pro | Trigger approved workflows through the execution plane |
| Customer documents | SharePoint | Read for knowledge and estimation; write generated documents |
| Conversational front door | AMARA | Structured requests in, pushed events out |
| Identity | Entra ID | Read for access control and audit evidence |
| Customer master and alias map | **Platform** | Sole master |
| Estate inventory | **Platform** | Sole master, reconciled to the CMDB |
| Telemetry, availability, performance | **Platform** | Sole master, streamed from Azure Monitor and AWS CloudWatch |
| Cost reconciliation and margin | **Platform** | Sole master, from billing exports plus CoreStack findings |
| SOW commercials, people cost, FX | **Platform** | Sole master |
| Effort and pricing model | **Platform** | Sole master |
| Audit responses and evidence | **Platform** | Sole master |
| Runbooks, knowledge, learning loop | **Platform** | Sole master |
| Execution record and transcripts | **Platform** | Sole master, immutable |

CoreStack reports cost but does not hold the SOW, so the platform still ingests raw billing exports itself. That is what allows cost to reconcile to the provider invoice and margin to be computed per customer.

### Read and act are separate

The most important structural decision in the design. Two integration paths, different credentials, different approval chains, different blast radius.

| Path | Component | Reaches |
| --- | --- | --- |
| **Read** | Connector and telemetry framework | ServiceNow, Qualys, CoreStack, SharePoint, Azure, AWS |
| **Act** | Execution plane, isolated subscription | Azure, AWS, ServiceNow, CloudBolt, Resolve, SharePoint |

Read is continuous, broad and low-risk. Act is narrow, episodic and heavily gated: nothing reaches it without a matched signed runbook, a policy decision, and for anything above the lowest risk class a human approval.

### Client estates

Azure subscriptions by Lighthouse delegation, AWS accounts by AssumeRole with an external ID, private cloud on VMware and Nutanix, and data centre servers, network and storage. Cloud estates are reached directly by the execution plane; private cloud and physical estate through Resolve Actions Pro, which already holds that connectivity.

### Design principles

1. **Correctness before coverage.** A figure that cannot be reconciled is not shown. Cost reconciles to invoice within 0.5% or displays as unverified.
2. **Provenance on every number.** Source system, as-of timestamp, query reference. Modelled values are visually distinct from observed.
3. **Four layers of tenant isolation.** Gateway scope, database row-level security, tenant filter inside retrieval, per-tenant credential brokering.
4. **Execution is privileged, not default.** Intent classification, blast-radius assessment, policy evaluation, approval, recorded rollback.
5. **Human in the loop is a policy, not a prompt.** Configured per customer and action class, enforced in the workflow engine.
6. **Two audiences, one truth.** Customer views never expose margin, cost base or rate card — enforced at the database.
7. **Gaps are visible.** No SOW shows "not captured", never zero. No evidence shows "manual", never compliant.

### Out of scope for the first release

Replacing any existing platform, chargeback invoice generation, multi-currency contracts beyond the current set, and unsupervised remediation of any action class rated medium risk or above.

## Architecture

### Layers

| Layer | Contents |
| --- | --- |
| Presentation | Getronics console, customer portal, AMARA assistant |
| Tenant scope gate | Entra ID sign-on and customer federation, role and attribute checks, customer scope set on every connection |
| CloudOps agentic AI layer | Operations, Commercial, Assurance, Delivery, Inventory and customer master, Reporting, Knowledge, GenAI layer |
| Self-learning loop | Index knowledge, promote validated fixes, grow runbooks, evaluation gate |
| Integration | Connector and telemetry framework (read); execution plane (act), isolated subscription |
| Systems of record | ServiceNow, Qualys, CoreStack, SharePoint, CloudBolt, Resolve |
| Client estates | Azure, AWS, private cloud, data centres |

Everything passes one gate, so customer isolation is enforced in one place rather than in every screen. The execution plane sits beside the connectors rather than inside them, because reading a customer environment and acting on one are different privileges.

### Service topology

A modular monolith for domain services, with connectors and execution workers as separately deployable. At the planned team size microservices would cost more in coordination than they return; module boundaries are enforced in code so the split is available later.

| Component | Scaling driver |
| --- | --- |
| Web app and API | Concurrent users, request rate |
| Domain services | CPU on report generation |
| Connector workers | Source volume and rate limits |
| Telemetry processors | Metric throughput |
| Workflow engine (Temporal) | Long-running ingest and remediation |
| AI gateway | Token throughput |
| Execution workers | Remediation volume, isolated subscription |

### Request lifecycle

Browser presents an Entra ID token; the gateway validates it and resolves role and tenant scope; the BFF shapes the request for that role; the domain service acquires a connection through the tenancy package, which sets tenant and role on that connection; the query runs under row-level security; the response is assembled with provenance on every metric; access is written to the audit log. Any code path reaching the database without the tenancy package fails CI.

### Refresh cadence

| Data | Cadence |
| --- | --- |
| Telemetry | Streamed, under 2 minutes |
| Tickets and changes | 5 minutes, plus webhook on create |
| Inventory | 15 minutes, plus event-driven |
| Vulnerabilities, CoreStack findings | Daily |
| Cost | Daily, with month-end reprocessing |
| Audit assessment | Weekly, plus on demand |
| Margin | Daily recompute, monthly close |

Cost is deliberately not near-real-time. Provider cost APIs are incomplete and do not reconcile to invoice; showing a figure that later moves is worse than yesterday's figure with an honest timestamp.

## Modules

Twenty-two modules in six layers. Dependency order is strict: nothing above the foundation works until customer and resource identity resolve.

| Ref | Module | Purpose |
| --- | --- | --- |
| M1 | Tenant and customer master | Canonical customer, alias map across every source, SOW and people-cost registers |
| M2 | Customer onboarding | Access templates, connection validation, discovery, linkage, go-live gates |
| M3 | Inventory and CMDB reconciliation | Discovery, normalisation, entity resolution, coverage gaps, tag compliance |
| M4 | Connector and telemetry framework | Pull, stream, normalise, resolve identity, quarantine, replay |
| M5 | Credential broker and execution plane | Short-lived credentials, signed runbooks, session transcripts, kill switch |
| M6 | Agentic ticket remediation | Ten-stage pipeline from intake to learning, gated by action class |
| M7 | Operations console | Unified queue, agent triage panel, resource context, SLA, effort capture |
| M8 | Signal correlation | Ticket-to-telemetry linkage, recurrence clustering, change correlation |
| M9 | Automation and runbook library | Candidate detection, business case, signed runbook register, deflection |
| M10 | FinOps and cost intelligence | Billing ingest, charge classification, invoice reconciliation, anomalies |
| M11 | Effort and pricing | Versioned rate card, quote engine, slab headroom, modelled versus actual |
| M12 | Margin and contribution | Revenue against modelled and actual cost, variance attribution, health banding |
| M13 | SecOps posture and guardrails | Qualys ingest, ageing against SLA, scanner coverage, posture score |
| M14 | Well-Architected and audit | 98 controls plus Well-Architected, evidence routing, AI-drafted responses |
| M15 | Evidence and documentation | Evidence store, signed export packs, policy library, retention |
| M16 | Solution and estimation studio | Requirement intake, reference matching, estimate, design, document generation |
| M17 | Project delivery and governance | Stage gates, budget burn, test policy, handover |
| M18 | Provisioning | CloudBolt orders behind quota, budget, tagging, naming and region pre-flight |
| M19 | Reporting and packs | Monthly pack generated from live data, narrative drafted for review |
| M20 | Knowledge and document intelligence | SharePoint, close notes, runbooks, policies indexed with tenant scope |
| M21 | GenAI horizontal layer | Gateway, retrieval, tools, memory, guardrails, evaluation |
| M22 | Customer portal and identity | Customer roles on the same application, federated identity |

**Why M5 is foundational.** Once the platform logs into customer environments, credential brokering stops being an implementation detail and becomes the control determining whether a compromise reaches every managed estate. M6, M13 and M18 all depend on it, and it cannot be retrofitted.

**Why M22 is cross-cutting.** Building a second front end for customers duplicates every view and guarantees divergence. The same application serves both audiences, with the boundary enforced in the database.

### Scale assumptions

| Dimension | Initial release | Design target |
| --- | --- | --- |
| Managed customers | Tens | 100 |
| Cloud accounts and subscriptions | Tens | 250 |
| Resources under management | Low thousands | 50,000 |
| Tickets per month | Low thousands | 10,000 |
| Metric samples per day | — | 50 million |
| Getronics users | Tens | 200 |
| Customer users | Pilot only | 600 |
| Automated remediations per month | — | 1,200 |

Sizing is driven by telemetry volume and remediation throughput, not user count. This is a low-concurrency, high-ingest system.

## Agentic remediation and safety

### Pipeline

| Stage | What happens | Fails safe by |
| --- | --- | --- |
| 1 Intake | Ticket arrives from ServiceNow | Unrecognised type routes to a human |
| 2 Classify | Intent, affected CI, customer, action class, risk | Low confidence routes to a human |
| 3 Enrich | Resource context, recent changes, telemetry, prior resolutions, runbook match | Missing context lowers confidence |
| 4 Plan | Runbook with parameters, expected effect, blast radius, rollback, verification | No signed runbook means no execution |
| 5 Policy | Customer automation policy, change freeze, maintenance window, CAB requirement | Denial stops the workflow |
| 6 Approve | Human approval where the action class requires it | Timeout cancels, never proceeds |
| 7 Execute | Broker mints credentials; runbook runs; everything recorded | Step failure triggers rollback |
| 8 Verify | Post-condition test proves the issue is resolved | Failure escalates to a human |
| 9 Close | Work notes, ticket update, CMDB fields, change record | Nothing closes without verification |
| 10 Learn | Outcome and corrections feed the evaluation set and runbook library | — |

### Action classes

Risk class, not model confidence, decides who approves. Configured per customer, enforced in the workflow engine.

| Class | Examples | Default approval | Window |
| --- | --- | --- | --- |
| A Read only | Log retrieval, metric query, triage | None | Any |
| B Reversible | Service restart, cache clear, log rotation | Engineer until a clean record is earned | Any |
| C Recoverable | Disk extension, certificate and secret rotation | Engineer | Any |
| D Production | Resizing production, failover, firewall change, patching | Engineer plus delivery lead, with change record | Maintenance window |
| E Irreversible | Deletion, data operations, identity and network changes | Dual approval plus CAB. **Never agent-initiated** | CAB-approved |

Promotion between classes is earned, not configured: an action moves to unattended only after a documented volume of clean supervised executions, reviewed per customer. Class E never moves.

### Runbooks, not free-form commands

The agent selects and parameterises a signed runbook; it does not compose shell. Every runbook is version-controlled, peer-reviewed and signed; parameters are typed and bounded with no string interpolation; pre-conditions are asserted; rollback is required for class C and above; a post-condition test proves the fix separately from the action; and a declared blast-radius ceiling limits the target count.

### Guardrails

1. **Ticket content is untrusted input.** The agent extracts structured intent and never follows instructions found in ticket text.
2. **The target set is resolved by the platform**, not the model, and anything outside the customer's tenant scope is rejected at the broker.
3. **Rate and concurrency limits** per customer, so a misclassification cannot cascade.
4. **Change freeze and maintenance windows** are honoured absolutely.
5. **Circuit breaker** on rising failure or rollback rate suspends automated execution for that customer.
6. **Every execution produces** an action-log entry, a session transcript, a ServiceNow work note and, for class C and above, a change record.

### The execution plane

The platform holds no long-lived credential to any customer environment. The broker mints short-lived, narrowly scoped credentials for a specific action, on a specific target, against a recorded authorisation.

| Capability | Implementation |
| --- | --- |
| Cloud plane | Lighthouse delegation and AssumeRole with external ID; separate read and action roles |
| OS plane, cloud | SSM Session Manager and Azure Arc or Run Command. No SSH keys, no RDP, no bastion credentials held |
| Private cloud and physical | Through Resolve Actions Pro, which already holds that connectivity |
| Provisioning | Through CloudBolt, after the platform's own pre-flight checks |
| Write-back | ServiceNow notes, closures and change records; documents into SharePoint |
| Ephemeral credentials | Minted per action, lifetime in minutes, bound to the target set, revoked on completion |
| Runbook signing | Key Vault Premium: HSM-backed, non-exportable keys, signing inside the service |
| Session recording | Every command, output and exit code, streamed to write-once storage |
| Kill switch | One action suspends execution for a customer or platform-wide, verified by a failed mint |

**Why Key Vault Premium rather than dedicated hardware.** The signing key is the one credential that, if forged, would let an attacker author a procedure the platform would execute. A dedicated managed HSM pool costs several thousand euro a month per pool for a marginal isolation gain; Premium already provides HSM-backed non-exportable keys as a shared service. If assurance later demands a pool, it is a key migration, not a redesign.

**No inbound path.** Execution is outbound-initiated through the provider control plane. No VPN, no tunnel, nothing listening on customer resources.

## AI platform and the assistant

### Azure services

| Capability | Service | Why |
| --- | --- | --- |
| Chat and reasoning | Azure OpenAI, private endpoint | Prompts and customer data stay inside the Getronics tenant and EU region |
| Embeddings | Azure OpenAI | Same tenancy and residency as the chat models |
| Vector storage | pgvector in the platform database | Isolation enforced by the same row-level security as every other table |
| Keyword search | PostgreSQL full-text | Hybrid retrieval without a second system |
| Second provider | AWS Bedrock behind the same gateway | Avoids single-provider dependency |

Three model tiers behind the gateway — small for classification and extraction, large for multi-step reasoning and drafting, plus embeddings. Which deployment fills each tier is chosen at build and pinned by version; changing one is gateway configuration, not an application change.

### Why pgvector rather than Azure AI Search

AI Search is the stronger search product, with a higher scale ceiling and built-in document enrichment. The deciding factor is isolation: keeping vectors in the platform database means one customer-isolation rule protects everything, tested by one suite, rather than a second access-control system configured and verified separately. The trigger to revisit is corpus size, retrieval latency, or a need to read scanned documents. Because retrieval sits behind the gateway's interface, the swap is contained.

### How a question is answered

Scope is resolved server-side from the user's organisation and assignment — never from a client-supplied claim. The small model classifies intent. The question is embedded and matched against knowledge chunks with the tenant predicate **inside** the SQL query, combined with full-text and re-ranked. The agent calls platform tools — cost trend, margin, findings, resource context — through a registry, never receiving credentials. The large model composes the answer within a token budget. Every factual claim must trace to a tool result or retrieved chunk. The answer carries sources and as-of timestamps. Prompt, retrieval set, tool calls, tokens, latency and cost are traced.

For a ticket the path is identical but ends in a plan — matched runbook, parameters, blast radius, rollback, verification — entering the approval machine.

### Self-learning

| Loop | Mechanism | Latency | Gate |
| --- | --- | --- | --- |
| Index new knowledge | Documents, runbooks, close notes embedded | Minutes | None |
| Live state | Tools query current data | Per query | None |
| Promote validated fixes | Engineer-approved resolutions become curated facts | Days | Human validation |
| Grow the runbook library | Repeat manual fixes become signed runbooks | Weeks | Peer review and signing |
| Classification accuracy | Engineer corrections feed the training set | Weeks | Evaluation suite |
| Model adaptation | Prompt tuning, re-ranking, optional fine-tune | Quarterly | Evaluation gate plus consent |

The first five deliver the behaviour people mean by "it learns" and carry acceptable risk. The last is a deliberate, reviewed decision — not automatic drift. **No continuous retraining on live multi-tenant conversation. No model assertion becomes a platform fact without a human. No cross-tenant learning.**

### Cost control

Model routing is the largest lever: small model for classification, retrieval and simple answers, large only for reasoning. Plus semantic caching, context budgeting with summarisation, per-tenant and per-user quotas, an agent loop ceiling, and a spend circuit breaker. Agent loops, not chat volume, drive token cost.

### External benchmarking

Allowlisted domains only — provider pricing and documentation, CIS, NIST, FinOps Foundation, NVD — through the controlled egress proxy. Queries are built from generic parameters; no customer names, identifiers or figures leave. Retrieved content is data, never instruction. Benchmarks are cached with a retrieval date so any claim in a customer report carries a source and a date.

## Integrations

| Source | Path | Auth | Mode |
| --- | --- | --- | --- |
| ServiceNow | Read and act | OAuth read account; separate field-scoped write account | 5-min incremental; webhook on create |
| Qualys | Read | Service account over TLS | Daily report pull |
| CoreStack | Read | API token | Daily |
| SharePoint | Read and act | Entra app, per-site selected consent | Nightly delta; write on generation |
| CloudBolt | Act | API token | On demand plus daily reconciliation |
| Resolve Actions Pro | Act | OAuth through the HTTP Gateway | On demand |
| AMARA | Read and act | Platform API | Event-driven |
| Azure management | Read and act | Lighthouse; separate read and action roles | Resource Graph 15-min; cost export daily |
| AWS management | Read and act | AssumeRole with external ID; separate roles | Config 15-min; CUR daily |
| Entra ID | Read | Graph, read-only | Daily |
| Azure Monitor, CloudWatch | Read | Diagnostic settings, metric streams | Continuous |

Read and act are different code paths with different credentials even into the same system. The ServiceNow read account cannot write; the write account is field-scoped and reachable only from the execution plane.

**Why no separate monitoring connector.** Alerting tools already raise tickets into ServiceNow, so ingesting their alerts would double-count every event. Ticket-borne signal comes from ServiceNow; raw telemetry comes from the cloud providers directly.

### Identity resolution

The same customer is spelled differently in every system. Resolution runs exact match on the alias table, then normalised match stripping punctuation and legal suffixes, then quarantine for manual review — never a guess at ingest. Resources resolve on external key, then normalised short name plus IP. Quarantine depth is a monitored metric: a rising quarantine means an upstream naming change nobody announced.

### Failure handling

Source unavailable: backoff, alert after three failures, last-good data served with a stale indicator. Rate limited: respect retry-after, reduce concurrency, resume from watermark. Schema drift: ingest continues, platform admin alerted. Partial batch: transactional, replayed from the raw layer. Unmatched identity: quarantined with occurrence count, never dropped.

## Data and multi-currency

### Storage

| Store | Technology | Holds |
| --- | --- | --- |
| Operational | PostgreSQL 16, HA, PITR | Canonical model, tickets, inventory, cost, commercial, audit |
| Vector | pgvector in the same database | Knowledge chunks, conversation memory |
| Telemetry | Column store | Metrics, availability samples |
| Streaming | Event Hubs | Metric and config-change ingest |
| Raw | Blob, lifecycle-tiered | Unmodified connector payloads |
| Transcripts | Blob, write-once, encrypted | Execution session evidence |
| Cache | Redis | Sessions, query cache, rate limits, approval state |
| Workflow | Temporal on PostgreSQL | Remediation and ingest workflows |

Transactional volumes are modest; PostgreSQL carries them comfortably. Telemetry at design scale needs a column store from the start — it is the one place where "do not over-engineer" does not apply.

### Layers and principles

Bronze holds raw payloads unmodified and is retained, because a normalisation bug will be found and history reprocessed. Silver holds canonical, identity-resolved entities. Gold holds serving marts.

A tenant identifier sits on every table carrying customer data. Row-level security is forced, not merely enabled. Mirror tables use source field names so a connector maps one-to-one. Soft delete with first-seen and last-seen. Monetary values are fixed-point, never floating point, rounded only at presentation. Both amortised and unblended cost are stored.

### Core entities

`tenant` resolves through `tenant_alias` to every source spelling, and carries `sow`, `cloud_account`, `assessment`, `control_response`, `action_log` and `knowledge_chunk`. `cloud_account` carries `resource`, which carries `work_item`, `cost_fact`, `vulnerability` and `telemetry_sample`. `tenant_alias` and `resource` are what make everything joinable; `telemetry_sample` is the one entity outside PostgreSQL.

### Multi-currency

Contracts span multiple currencies and delivery cost sits in others. A single-currency model would misstate margin for most of the book.

| Concept | Rule |
| --- | --- |
| Transaction currency | Stored on every monetary row, never converted away |
| Contract currency | From the SOW; revenue recognised and reported in it |
| Reporting currency | Chosen by the viewer; customers default to their contract currency |
| Rate type | Closing for balances, average for flows |
| Rate date | The rate in force on the transaction date, never today's rate on history |
| Restatement | A correction creates a new effective-dated rate and an explicit entry |

**Margin is computed in the contract currency first, then converted.** Converting first and subtracting afterwards makes a currency movement look like a margin movement. FX impact reports as its own line.

### Retention

Raw payloads 13 months hot then cold to 7 years. Operational records contract term plus two years. Audit evidence and the action log 7 years, immutable. Conversations 12 months, summarised beyond. Customer data deleted on offboarding with a certificate issued.

## Infrastructure and deployment

Azure-hosted, given Entra ID for identity and Lighthouse for customer access. Portability is preserved through containers and infrastructure as code.

| Layer | Service |
| --- | --- |
| Edge | Front Door with WAF, separate hostnames for staff and customers |
| Compute | AKS, private cluster, node pools for web, ingestion, telemetry, AI, plus an isolated execution pool in its own subscription |
| Database | PostgreSQL Flexible Server, zone-redundant, PITR, read replica |
| Telemetry | Column store on AKS or managed equivalent |
| Streaming | Event Hubs |
| Cache | Azure Cache for Redis |
| Storage | Blob: raw archive, packs, evidence, write-once transcripts |
| Secrets | Key Vault; Key Vault Premium for signing and execution keys |
| AI | Azure OpenAI, private endpoint |
| Egress | NAT gateway with static IPs plus an allowlisting egress proxy |
| Observability | Azure Monitor, Grafana, LLM tracing |

All data services on private endpoints with public access disabled at the resource. EU region primary with per-tenant residency pinning supported in the data model from day one.

### Resilience

| Target | Initial release | Steady state |
| --- | --- | --- |
| Availability | 99.5% | 99.9% |
| RPO | 15 minutes | 15 minutes |
| RTO | 8 hours | 4 hours |
| DR failover test | Before go-live | Quarterly |

Do not commit to 99.9% before an on-call rota is staffed and a failover has been executed.

### Environments and release

Dev and Test on synthetic data, UAT on a masked customer subset, Production change-controlled, DR in the paired region. Trunk-based development with feature flags. GitOps: the cluster pulls desired state; the pipeline never applies to it. Canary at ten per cent with automatic rollback. Migrations are expand-then-contract, so a rollback never requires a data restore.

### Release gates

These block a release regardless of schedule pressure: the tenant-isolation suite across API, database, retrieval and execution paths; cost reconciliation within 0.5%; the pricing engine reproducing its reference case exactly; no AI evaluation regression; no critical or high security findings; migrations verified reversible.

## Security and non-functional requirements

### Identity

Staff on Entra ID with enforced MFA and roles from Entra groups, so joiner-mover-leaver is handled by existing HR processes. Customers federated through Entra ID B2B to their own provider, with their administrator managing their own users. Service accounts and agents use workload identity. Agents authenticate as themselves, never as a person: an action is attributed to the agent with the approving human recorded separately.

### Customer environment access

Read-only by default. Lighthouse delegation on Azure, AssumeRole with a unique external ID on AWS. Write access is a separate, narrow role approved individually per customer. Credentials live in Key Vault only, never in the database or configuration. Onboarding runs a permission self-test asserting exactly the expected scope and no more. One action revokes all access for a customer, verified by a failed read.

### Agentic execution threats

| Threat | Control |
| --- | --- |
| Prompt injection via ticket content | Structured intent extraction; no instruction-following from ticket text; platform resolves the target set |
| Wrong target | Tenant-scoped resolution, blast-radius ceiling, cross-tenant rejection at the broker |
| Over-broad command | Signed parameterised runbooks only; no free-form shell |
| Credential theft | Ephemeral credentials, minutes not hours, never logged or shown |
| Compromised worker | Isolated pool, no inbound path, egress restricted to control planes |
| Approval bypass | Approval state in the workflow engine; absent or expired cannot execute |
| Cascade failure | Per-customer rate limits and a circuit breaker |
| Disputed action | Write-once transcript, immutable action log, change record, verification result |
| Insider misuse | Break-glass dual-approved, time-boxed, alerting on use |

### Platform security

TLS 1.3 in transit and mutual TLS between services. Encryption at rest, customer-managed keys where contracted. Immutable audit log of every view, export, chat exchange, tool call and change. STRIDE threat model per major feature, SBOM per release, signed images. Static, dynamic, dependency and container scanning in CI, plus external penetration test before go-live and annually. OWASP Top 10 for LLM Applications as an explicit checklist.

### Compliance

Confirm early whether the platform falls inside the existing ISO 27001 certificate or needs a scope extension — that answer changes the evidence burden. GDPR applies with a DPIA given personal data in ticket and survey records. **Contractual prerequisite:** confirmation that customer agreements permit aggregating operational data, and separately whether that data may be used for model training. Default position: aggregation permitted, training prohibited without written consent.

### Non-functional targets

| Requirement | Target |
| --- | --- |
| Dashboard load | p95 under 2 seconds at design scale |
| Report generation | Full monthly pack under 5 minutes |
| Telemetry ingest latency | Under 2 minutes end to end |
| AI first token | Under 3 seconds |
| Cost reconciliation drift | Under 0.5% monthly |
| Onboarding effort | Under 2 hours per customer |
| Concurrent users | 50 active, 200 provisioned |

## Prerequisites and hosting cost

### Monthly hosting cost

| Scope | Production | Non-production | Total per month |
| --- | --- | --- | --- |
| Initial release | ≈ €5,000 | ≈ €1,800 | **≈ €6,800** |
| Design scale, list price | ≈ €19,600 | ≈ €3,500 | **≈ €23,100** |
| Design scale, optimised | ≈ €13,000–14,500 | ≈ €3,500 | **≈ €16,500–18,000** |

List-price planning estimates for West Europe, derived line by line from the sizing in the low level design: node counts and SKUs multiplied by assumed hourly rates over 730 hours, HA pairs counted twice. **Validate against the Azure Pricing Calculator with the Enterprise Agreement discount before any figure enters a business case.** Hosting only — licences, API entitlements, the build team and the run team are excluded.

Three groups dominate, all controllable. **Telemetry** is roughly a third of the design-scale bill, driven entirely by metric grain and retention; a metric allowlist per resource type is the single largest lever. **Database** HA doubles compute and storage, which is the price of the availability target. **AI tokens** are driven by agent loops, controlled by routing, caching, quotas and the circuit breaker. With reservations and a metric allowlist, design-scale production lands near €13,000–14,500.

### Data Getronics must provide

The platform cannot create any of this; each gap degrades a specific module.

| Prerequisite | Needed for | Consequence if missing |
| --- | --- | --- |
| SOW commercials per customer, with currency | M11, M12 | Margin not computable; shows as not captured |
| Fully loaded people cost by location and grade | M11, M12 | Modelled cost cannot be derived |
| Nominated FX source with historic rates | M10, M12 | Multi-currency margin cannot be computed or restated |
| Historic cost reclassified to separate licence spend | M10 | Margin distorted by non-consumption spend |
| Twelve months of clean ticket, time and rate data | M11, M16 | Effort model can only be approximated |
| Customer alias list per source system | M1 and everything above | Nothing joins across systems |
| Tag remediation plan | M3, M10, M14 | No cost allocation, repeated Well-Architected failures |
| Policy library mapped to controls | M14, M15 | Narrative controls stay manual |

### Access and entitlements

| Prerequisite | Lead time |
| --- | --- |
| Azure management group, five subscriptions, quota, OpenAI access | Short |
| Lighthouse delegation or AWS stack per customer | **Long, per customer** |
| ServiceNow read and field-scoped write accounts, webhook rights, non-production instance | **Long** |
| Qualys, CoreStack and CloudBolt service accounts | Medium |
| Resolve Actions Pro OAuth through the HTTP Gateway | Medium |
| SharePoint per-site selected consent | **Long, per customer** |
| Entra ID Graph read-only | Short |
| Sandbox Azure and AWS accounts for connector and runbook testing | Short |
| Customer identity federation for portal pilots | **Long, per customer** |

The long-lead items are the usual schedule risk: obtaining and validating the ServiceNow write account and per-site SharePoint consents routinely takes longer than building the connectors that depend on them.

### People and legal

A team of roughly eleven to twelve at peak: tech lead and architect, three full-stack, two data and integration, an AI engineer, DevOps, UX, QA automation and a product owner, with fractional security, FinOps and cloud specialists. A named executive sponsor and one owner per persona before discovery starts.

Legal: confirmation that agreements permit aggregating operational data; written consent before any customer data is used for training; contract amendments authorising automated remediation and naming permitted action classes; ISO 27001 scope confirmation; a GDPR DPIA; and a review of insurance cover for agent-initiated actions.

## Open decisions and next steps

| Ref | Decision | Recommendation | Owner |
| --- | --- | --- | --- |
| D1 | Autonomy ceiling at go-live | Classes A–C supervised, D with approval and change record, E never agent-initiated | Security and Delivery |
| D2 | Customer consent for agentic execution | Contract amendment per customer naming the action classes. **Acting without written authorisation is a contractual and insurance exposure** | Legal and Commercial |
| D3 | Consent for data aggregation and AI training | Aggregation permitted; training prohibited without written consent | Legal |
| D4 | Customer portal in scope | Yes, with SLA and support model defined before first access | Executive sponsor |
| D5 | ISO 27001 scope | Confirm extension or inclusion | Security |
| D6 | 24×7 pricing multiplier discrepancy | Confirm the published table or the computed values | Commercial |
| D7 | Budapest people cost | Confirm the figure and FX basis | Finance |
| D8 | Licence spend treatment | Exclude from consumption, report separately | Finance and FinOps |
| D9 | Tagging as a contractual onboarding requirement | Mandatory tags a precondition, enforced at CloudBolt provisioning | Commercial |
| D10 | Data residency default | EU-resident processing, per-tenant pinning available | Architecture |
| D11 | Telemetry retention and metric allowlist | 13 months at full grain, downsampled beyond | Architecture and Finance |
| D12 | Private cloud and data centre estate scope | Confirm whether inventory, telemetry and cost for non-cloud estate is in the first release | Delivery |
| D13 | Vector store | pgvector, with Azure AI Search as documented fallback | Architecture |
| D14 | Insurance and liability for agent-initiated actions | Review cover before unattended execution | Legal and Finance |

**D12 deserves attention.** Private cloud and data centre estates have no billing exports or Resource Graph equivalent, so inventory, telemetry and cost for those estates need designing before they are real. The execution path through Resolve exists; the read path does not.

### Delivery order

Derived from dependency, not perceived value. Foundation (M1–M5) ends when identity resolves across every source and the broker passes security review. Operations and reporting (M7, M19) ends when a recent month's pack regenerates and matches. Triage — M6 stages 1 to 4 only — ends when classification accuracy is proven at real volume with a human executing. Commercial (M10–M12) ends when cost reconciles within 0.5%. Supervised execution (M6 stages 5 to 10, M9) ends when a documented volume of clean supervised runs exists. Then assurance, customer portal, delivery modules and the full intelligence layer.

**Why triage precedes execution.** Stages 1 to 4 carry almost no risk and deliver most of the engineer time saving, because the work in a typical ticket is diagnosis rather than the fix. Running them at real volume produces exactly the evidence needed to justify automated action later — so the customer conversation becomes a performance record rather than a request for trust.

### Before execution planning begins

Close D1 to D4, which change scope rather than detail. Confirm D6 and D7 with commercial and finance. Start SOW capture in parallel. Obtain brand guidelines. Select three pilot customers: one Azure-only, one AWS, one hybrid. Submit the long-lead access requests now, before the build is approved — none of them commits spend.
