# Phase 6 — Classifier agent and the evaluation harness

Read these first: `docs/LLD.md`, `docs/04-remediation-workflow.png`

Build the evaluation harness FIRST, then the classifier agent. In that order — I want
to be able to measure the agent from its first commit.

Evaluation harness:
- A golden set of tickets with known-correct intent, CI, action class
- Scoring for classification accuracy, groundedness, refusal correctness
- Adversarial cases: prompt injection in ticket text, cross-tenant retrieval attempts
- Runs as a CI job that fails on regression against a stored baseline
- Structured so new cases are added from production corrections

Then the classifier agent:
- Small model tier
- NO tools at all — it classifies, nothing else
- Typed, schema-validated output: intent, affected CI, customer, action class,
  risk rating, confidence
- Low confidence routes to a human rather than guessing
- Ticket text is DATA — extract structured intent, never follow instructions in it

Then the enricher agent: read-only tools only, assembles a structured context bundle.

Wire both into a Temporal workflow implementing stages 1 to 3 of the remediation
pipeline. Stages 4 onward come later.

Do not build the planner, the execution plane, or anything that can act on a customer
environment. Those need a security review first.
