-- =====================================================================
-- Getronics CloudOps Platform — canonical data model
-- PostgreSQL 16+. Multi-tenant by row-level security.
--
-- Systems of record (the platform never becomes the master for these):
--   ServiceNow  — incidents, changes, change tasks, service requests,
--                 project tasks, CSAT surveys
--   OpsRamp     — alerts, resource availability, monitored inventory
--   Qualys      — OS and application vulnerabilities
--   CMP         — provisioning / blueprints
-- Everything else in this schema is mastered by the platform.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";

CREATE SCHEMA IF NOT EXISTS cloudops;
SET search_path TO cloudops, public;

-- ---------------------------------------------------------------------
-- 1. TENANCY
-- The alias table is the single most important object in this schema.
-- The same customer appears as "Agria" (revenue sheet), "AGRIA PET
-- INSURANCE LIMITED" (ServiceNow), "Agriapet" (Qualys asset tags) and
-- "Agria" (OpsRamp client name). Nothing joins until this is populated.
-- ---------------------------------------------------------------------

CREATE TYPE delivery_location AS ENUM ('India', 'Budapest', 'Mixed');
CREATE TYPE coverage_model    AS ENUM ('8x5', '16x5', '24x7');
CREATE TYPE support_model     AS ENUM ('Bronze', 'Silver', 'Gold');

CREATE TABLE tenant (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    canonical_name      text NOT NULL UNIQUE,     -- "Agria Pet Insurance"
    short_code          text NOT NULL UNIQUE,     -- "AGRIA"
    status              text NOT NULL DEFAULT 'active'
                        CHECK (status IN ('prospect','transitioning','active','offboarding','exited')),
    delivery_location   delivery_location NOT NULL DEFAULT 'India',
    coverage            coverage_model    NOT NULL DEFAULT '24x7',
    support             support_model     NOT NULL DEFAULT 'Gold',
    data_residency      text NOT NULL DEFAULT 'EU',
    contract_start      date,
    contract_end        date,
    created_at          timestamptz NOT NULL DEFAULT now()
);

-- Alias resolution. source_system values: servicenow | opsramp | qualys | cmp
-- | azure | aws | finance. Resolution is exact-match first, then normalised
-- (lowercase, punctuation and legal suffixes stripped), then manual review.
CREATE TABLE tenant_alias (
    id              bigserial PRIMARY KEY,
    tenant_id       uuid NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    source_system   text NOT NULL,
    alias           text NOT NULL,
    alias_norm      text GENERATED ALWAYS AS (lower(regexp_replace(alias,'[^a-zA-Z0-9]','','g'))) STORED,
    confidence      numeric(3,2) NOT NULL DEFAULT 1.00,
    confirmed_by    text,
    confirmed_at    timestamptz,
    UNIQUE (source_system, alias)
);
CREATE INDEX ON tenant_alias (alias_norm);
CREATE INDEX ON tenant_alias (tenant_id);

-- Unresolved names land here instead of being silently dropped.
CREATE TABLE tenant_alias_quarantine (
    id              bigserial PRIMARY KEY,
    source_system   text NOT NULL,
    alias           text NOT NULL,
    first_seen      timestamptz NOT NULL DEFAULT now(),
    last_seen       timestamptz NOT NULL DEFAULT now(),
    occurrence_count bigint NOT NULL DEFAULT 1,
    suggested_tenant_id uuid REFERENCES tenant(id),
    UNIQUE (source_system, alias)
);

-- ---------------------------------------------------------------------
-- 2. COMMERCIAL — from the SOWs and the people-cost data
-- ---------------------------------------------------------------------

CREATE TABLE sow (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    reference               text NOT NULL,
    effective_from          date NOT NULL,
    effective_to            date,
    currency                char(3) NOT NULL DEFAULT 'EUR',
    monthly_manage_revenue  numeric(14,2) NOT NULL,
    hosting_acv             numeric(14,2),
    manage_acv              numeric(14,2),
    professional_services   numeric(14,2) DEFAULT 0,
    contracted_ci_count     integer,
    contracted_slab         text,
    coverage                coverage_model,
    support                 support_model,
    -- Charges that must be excluded from consumption before margin maths.
    -- Marco Services' ~EUR 270k Microsoft licence spend is the worked example.
    excludes_licence_spend  boolean NOT NULL DEFAULT true,
    document_uri            text,
    created_at              timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON sow (tenant_id, effective_from DESC);

-- Fully loaded cost per head per month, by location and grade.
CREATE TABLE people_cost (
    id                  bigserial PRIMARY KEY,
    location            delivery_location NOT NULL,
    role                text NOT NULL,
    grade               text,
    headcount           numeric(6,2) NOT NULL,
    annual_cost_local   numeric(16,2) NOT NULL,
    currency            char(3) NOT NULL,
    fx_to_eur           numeric(12,8) NOT NULL,
    shift_allowance     numeric(12,2) DEFAULT 0,
    oncall_allowance    numeric(12,2) DEFAULT 0,
    effective_from      date NOT NULL,
    effective_to        date,
    monthly_cost_eur    numeric(12,4) GENERATED ALWAYS AS (
                            ((annual_cost_local / 12.0) + COALESCE(shift_allowance,0)
                             + COALESCE(oncall_allowance,0)) * fx_to_eur
                        ) STORED
);
CREATE INDEX ON people_cost (location, effective_from DESC);

-- Snapshot of the engine output so a quote is reproducible months later.
CREATE TABLE quote_snapshot (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    as_of                   date NOT NULL,
    engine_version          text NOT NULL,
    critical_ci_count       integer NOT NULL,
    slab                    text NOT NULL,
    service_cost_eur        numeric(14,4) NOT NULL,
    base_pack_eur           numeric(14,4) NOT NULL,
    platform_cost_eur       numeric(14,4) NOT NULL,
    total_monthly_eur       numeric(14,4) NOT NULL,
    price_per_ci_eur        numeric(12,4) NOT NULL,
    implied_fte             numeric(8,4) NOT NULL,
    inputs                  jsonb NOT NULL,
    UNIQUE (tenant_id, as_of, engine_version)
);

-- ---------------------------------------------------------------------
-- 3. INVENTORY — platform-mastered, reconciled against OpsRamp and the clouds
-- ---------------------------------------------------------------------

CREATE TABLE cloud_account (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       uuid NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    provider        text NOT NULL CHECK (provider IN ('azure','aws')),
    native_id       text NOT NULL,            -- subscription GUID / AWS account id
    display_name    text NOT NULL,
    environment     text,
    region_default  text,
    onboarded_at    timestamptz,
    connection_state text NOT NULL DEFAULT 'pending'
                     CHECK (connection_state IN ('pending','validating','healthy','degraded','revoked')),
    last_discovery  timestamptz,
    UNIQUE (provider, native_id)
);

CREATE TABLE resource (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    account_id          uuid NOT NULL REFERENCES cloud_account(id) ON DELETE CASCADE,
    native_id           text NOT NULL,
    name                text NOT NULL,
    name_norm           text GENERATED ALWAYS AS (lower(split_part(name,'.',1))) STORED,
    fqdn                text,                 -- Qualys reports FQDN, OpsRamp short name
    ip_addresses        inet[],
    type_native         text NOT NULL,        -- Microsoft.Compute/virtualMachines
    type_canonical      text NOT NULL,        -- compute.vm
    catalog_type        text,                 -- joins to the pricing catalogue
    region              text,
    operating_system    text,
    is_critical_ci      boolean NOT NULL DEFAULT true,
    tags                jsonb NOT NULL DEFAULT '{}'::jsonb,
    state               text,
    first_seen          timestamptz NOT NULL DEFAULT now(),
    last_seen           timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz,
    -- External keys, so the same box is one row across four systems
    opsramp_resource_id text,
    servicenow_ci_sys_id text,
    qualys_asset_id     text,
    UNIQUE (account_id, native_id)
);
CREATE INDEX ON resource (tenant_id) WHERE deleted_at IS NULL;
CREATE INDEX ON resource (name_norm);
CREATE INDEX ON resource (type_canonical);
CREATE INDEX ON resource USING gin (tags);

-- Tag compliance is a first-class metric, not a report.
-- MarcoCapital baseline: 33/51 untagged, 51/51 missing mandatory tags.
CREATE TABLE tag_policy (
    id              bigserial PRIMARY KEY,
    tenant_id       uuid REFERENCES tenant(id) ON DELETE CASCADE,  -- NULL = global default
    tag_key         text NOT NULL,
    is_mandatory    boolean NOT NULL DEFAULT true,
    allowed_values  text[],
    UNIQUE (tenant_id, tag_key)
);

CREATE OR REPLACE VIEW tag_compliance AS
SELECT r.tenant_id,
       count(*)                                                   AS total_resources,
       count(*) FILTER (WHERE r.tags <> '{}'::jsonb)              AS tagged_resources,
       count(*) FILTER (WHERE r.tags ? 'owner'
                          AND r.tags ? 'environment'
                          AND r.tags ? 'costcenter'
                          AND r.tags ? 'application')             AS fully_compliant,
       round(100.0 * count(*) FILTER (WHERE r.tags ? 'owner'
                          AND r.tags ? 'environment'
                          AND r.tags ? 'costcenter'
                          AND r.tags ? 'application') / NULLIF(count(*),0), 1) AS compliance_pct
FROM resource r
WHERE r.deleted_at IS NULL
GROUP BY r.tenant_id;

-- ---------------------------------------------------------------------
-- 4. SERVICENOW MIRROR
-- Field names follow the export columns so the connector maps 1:1.
-- ---------------------------------------------------------------------

CREATE TABLE work_item (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    kind                    text NOT NULL CHECK (kind IN ('incident','change_task','service_request','project_task')),
    number                  text NOT NULL UNIQUE,     -- INC16666170 / CTASK3364467 / TASK6658375 / PRJTASK0046261
    change_request          text,                     -- CHG3132213
    company_raw             text NOT NULL,            -- as ServiceNow spells it; resolved via tenant_alias
    opened_at               timestamptz NOT NULL,
    closed_at               timestamptz,
    priority                text,                     -- "3 - Moderate"
    state                   text,
    assigned_to             text,
    assignment_workgroup    text,                     -- GTN PubC FSCE / GTN_AGR_PubC_CS / GTN PubC CS
    short_description       text,
    configuration_item      text,                     -- joins to resource.name_norm; "Default CI" = unlinked
    resource_id             uuid REFERENCES resource(id),
    change_type             text,                     -- Emergency / Normal / Unplanned
    resolve_sla             boolean,
    response_sla            boolean,
    made_sla                boolean,
    sla_breached            boolean,
    duration_seconds        bigint,
    resolve_time_seconds    bigint,
    pending_total_seconds   bigint,
    planned_hours           numeric(8,2),
    actual_hours            numeric(8,2),
    closure_code            text,                     -- "Resolved (Workaround)" / "Resolved (Permanently)"
    close_notes             text,
    -- Derived: workaround closures are the automation backlog
    is_workaround           boolean GENERATED ALWAYS AS (closure_code ILIKE '%workaround%') STORED,
    ingested_at             timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON work_item (tenant_id, kind, opened_at DESC);
CREATE INDEX ON work_item (resource_id) WHERE resource_id IS NOT NULL;
CREATE INDEX ON work_item (tenant_id) WHERE is_workaround;
CREATE INDEX ON work_item (company_raw);

CREATE TABLE csat_response (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    ticket_number       text NOT NULL,
    response_score      smallint CHECK (response_score BETWEEN 0 AND 10),
    category            text,
    assignment_group    text,
    resolved_by         text,
    recipient           text,
    comment             text,
    created_at          timestamptz NOT NULL,
    UNIQUE (ticket_number, created_at)
);

-- ---------------------------------------------------------------------
-- 5. OPSRAMP MIRROR
-- ---------------------------------------------------------------------

CREATE TABLE alert (
    id                  bigint PRIMARY KEY,           -- OpsRamp alert id
    tenant_id           uuid NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    created_at          timestamptz NOT NULL,
    client_name_raw     text NOT NULL,
    object_name         text,
    object_type         text,
    ip_address          text,
    resource_id         uuid REFERENCES resource(id),
    subject             text,
    metric              text,
    alert_type          text,
    current_state       text,
    is_inference_alert  boolean NOT NULL DEFAULT false,
    correlated_work_item uuid REFERENCES work_item(id)
);
CREATE INDEX ON alert (tenant_id, created_at DESC);
CREATE INDEX ON alert (metric, tenant_id);

CREATE TABLE availability_daily (
    tenant_id               uuid NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    resource_id             uuid NOT NULL REFERENCES resource(id) ON DELETE CASCADE,
    day                     date NOT NULL,
    up_pct                  numeric(6,3),
    down_pct                numeric(6,3),
    undefined_pct           numeric(6,3),
    unknown_pct             numeric(6,3),
    total_downtime_seconds      bigint,
    planned_downtime_seconds    bigint,
    unplanned_downtime_seconds  bigint,
    maintenance_seconds         bigint,
    PRIMARY KEY (resource_id, day)
);
CREATE INDEX ON availability_daily (tenant_id, day DESC);

-- ---------------------------------------------------------------------
-- 6. QUALYS MIRROR
-- Note: Qualys keys on FQDN ("VMUKSNC02.AGRIAPET.LOCAL"), OpsRamp on short
-- name ("VMADVKMS01"). resource_id is resolved on name_norm + IP.
-- ---------------------------------------------------------------------

CREATE TABLE vulnerability (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    qid                 integer NOT NULL,
    asset_name          text NOT NULL,
    asset_ipv4          text,
    resource_id         uuid REFERENCES resource(id),
    scope               text NOT NULL CHECK (scope IN ('os','application')),
    title               text NOT NULL,
    severity            smallint NOT NULL CHECK (severity BETWEEN 1 AND 5),
    operating_system    text,
    solution            text,
    threat              text,
    detection_type      text,                 -- Confirmed / Potential
    asset_tags          text[],
    first_detected      timestamptz NOT NULL,
    last_detected       timestamptz,
    remediated_at       timestamptz,
    detection_span_days numeric(8,3),
    fix_days            numeric(8,3) GENERATED ALWAYS AS (
                            CASE WHEN remediated_at IS NOT NULL
                            THEN EXTRACT(epoch FROM remediated_at - first_detected)/86400.0 END
                        ) STORED,
    UNIQUE (tenant_id, qid, asset_name, first_detected)
);
CREATE INDEX ON vulnerability (tenant_id, severity, remediated_at);
CREATE INDEX ON vulnerability (tenant_id) WHERE remediated_at IS NULL;

-- Ageing view. Enerveo's 94-day average fix time against a 36-day portfolio
-- average is the kind of thing this is here to surface automatically.
CREATE OR REPLACE VIEW vulnerability_ageing AS
SELECT tenant_id,
       severity,
       count(*) FILTER (WHERE remediated_at IS NULL)        AS open_count,
       round(avg(fix_days) FILTER (WHERE remediated_at IS NOT NULL), 1) AS avg_fix_days,
       round(avg(EXTRACT(epoch FROM now() - first_detected)/86400.0)
             FILTER (WHERE remediated_at IS NULL), 1)       AS avg_open_age_days,
       max(EXTRACT(epoch FROM now() - first_detected)/86400.0)
             FILTER (WHERE remediated_at IS NULL)           AS oldest_open_days
FROM vulnerability
GROUP BY tenant_id, severity;

-- ---------------------------------------------------------------------
-- 7. COST — platform-mastered, from billing exports (not APIs)
-- ---------------------------------------------------------------------

CREATE TYPE charge_class AS ENUM
    ('consumption','licence','marketplace','support','reservation','savings_plan','tax','credit','other');

CREATE TABLE cost_fact (
    id                  bigserial PRIMARY KEY,
    tenant_id           uuid NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    account_id          uuid NOT NULL REFERENCES cloud_account(id) ON DELETE CASCADE,
    resource_id         uuid REFERENCES resource(id),
    usage_date          date NOT NULL,
    invoice_period      text NOT NULL,
    service_native      text,
    service_canonical   text,
    -- The classification that stops licence spend contaminating margin.
    charge_class        charge_class NOT NULL DEFAULT 'consumption',
    unblended_cost      numeric(16,6) NOT NULL,
    amortized_cost      numeric(16,6) NOT NULL,
    currency            char(3) NOT NULL DEFAULT 'EUR',
    fx_to_eur           numeric(12,8) NOT NULL DEFAULT 1.0,
    tags_snapshot       jsonb,
    UNIQUE (account_id, usage_date, resource_id, service_native, charge_class)
);
CREATE INDEX ON cost_fact (tenant_id, usage_date);
CREATE INDEX ON cost_fact (tenant_id, charge_class, usage_date);

-- Release-blocking gate: platform totals must match the provider invoice.
CREATE TABLE cost_reconciliation (
    id                  bigserial PRIMARY KEY,
    account_id          uuid NOT NULL REFERENCES cloud_account(id) ON DELETE CASCADE,
    invoice_period      text NOT NULL,
    invoice_total_eur   numeric(16,2) NOT NULL,
    platform_total_eur  numeric(16,2) NOT NULL,
    drift_pct           numeric(8,4) GENERATED ALWAYS AS (
                            CASE WHEN invoice_total_eur <> 0
                            THEN 100.0*(platform_total_eur-invoice_total_eur)/invoice_total_eur END
                        ) STORED,
    status              text GENERATED ALWAYS AS (
                            CASE WHEN invoice_total_eur = 0 THEN 'unknown'
                                 WHEN abs(100.0*(platform_total_eur-invoice_total_eur)/invoice_total_eur) <= 0.5
                                 THEN 'pass' ELSE 'fail' END
                        ) STORED,
    checked_at          timestamptz NOT NULL DEFAULT now(),
    UNIQUE (account_id, invoice_period)
);

-- ---------------------------------------------------------------------
-- 8. AUDIT ENGINE — the 98 custom controls plus Well-Architected
-- ---------------------------------------------------------------------

CREATE TYPE control_result AS ENUM ('compliant','partially_compliant','non_compliant','not_applicable','manual');
CREATE TYPE evidence_source AS ENUM ('azure','aws','servicenow','opsramp','qualys','cmp','policy_library','human');

CREATE TABLE control (
    code            text PRIMARY KEY,         -- CA-001 .. CA-098, RE:01, SE:01, CO:01 ...
    framework       text NOT NULL,            -- 'getronics_custom' | 'waf_azure' | 'waf_aws'
    section         text NOT NULL,            -- Asset Management, Network Security, ...
    question        text NOT NULL,
    -- Which system can answer this without a human. NULL = genuinely manual.
    automatable_from evidence_source[],
    weight          numeric(4,2) NOT NULL DEFAULT 1.0
);

CREATE TABLE assessment (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       uuid NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    account_id      uuid REFERENCES cloud_account(id),
    started_at      timestamptz NOT NULL DEFAULT now(),
    completed_at    timestamptz,
    custom_score    numeric(5,2),
    waf_score       numeric(5,2),
    resources_seen  integer,
    findings_seen   integer
);

CREATE TABLE control_response (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_id   uuid NOT NULL REFERENCES assessment(id) ON DELETE CASCADE,
    tenant_id       uuid NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    control_code    text NOT NULL REFERENCES control(code),
    result          control_result NOT NULL,
    score           numeric(5,2),             -- 100 / 50 / 0 / NULL
    response_text   text NOT NULL,
    evidence        jsonb NOT NULL DEFAULT '[]'::jsonb,   -- [{source, query, value, retrieved_at}]
    remarks         text,
    -- AI-drafted answers are never authoritative until a human approves.
    drafted_by_ai   boolean NOT NULL DEFAULT false,
    approved_by     text,
    approved_at     timestamptz,
    UNIQUE (assessment_id, control_code)
);
CREATE INDEX ON control_response (tenant_id, control_code);

-- ---------------------------------------------------------------------
-- 9. AI LAYER
-- ---------------------------------------------------------------------

CREATE TABLE knowledge_chunk (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       uuid REFERENCES tenant(id) ON DELETE CASCADE,  -- NULL = Getronics-wide
    source_kind     text NOT NULL,            -- runbook | kb_article | close_note | sow | policy | audit_report
    source_ref      text,
    title           text,
    body            text NOT NULL,
    embedding       vector(1536),
    created_at      timestamptz NOT NULL DEFAULT now()
);
-- Tenant filter is applied INSIDE the vector query, never as a post-filter.
CREATE INDEX ON knowledge_chunk USING hnsw (embedding vector_cosine_ops);
CREATE INDEX ON knowledge_chunk (tenant_id, source_kind);

CREATE TABLE conversation (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         text NOT NULL,
    tenant_scope    uuid[] NOT NULL,          -- tenants this conversation may read
    role_at_start   text NOT NULL,
    title           text,
    summary         text,                     -- rolling summary once over token budget
    created_at      timestamptz NOT NULL DEFAULT now(),
    last_active_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE message (
    id                  bigserial PRIMARY KEY,
    conversation_id     uuid NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
    role                text NOT NULL CHECK (role IN ('user','assistant','tool')),
    content             text NOT NULL,
    tool_calls          jsonb,
    retrieved_chunks    uuid[],
    model               text,
    input_tokens        integer,
    output_tokens       integer,
    cost_eur            numeric(12,6),
    latency_ms          integer,
    feedback            smallint CHECK (feedback IN (-1,0,1)),
    created_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON message (conversation_id, created_at);

-- Facts promoted from conversations only after human validation.
CREATE TABLE curated_fact (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       uuid REFERENCES tenant(id) ON DELETE CASCADE,
    statement       text NOT NULL,
    source_message  bigint REFERENCES message(id),
    validated_by    text NOT NULL,
    validated_at    timestamptz NOT NULL DEFAULT now(),
    superseded_by   uuid REFERENCES curated_fact(id)
);

-- ---------------------------------------------------------------------
-- 10. ACTIONS AND AUDIT TRAIL — immutable
-- ---------------------------------------------------------------------

CREATE TYPE autonomy_level AS ENUM ('L0_explain','L1_recommend','L2_draft','L3_approved_execute','L4_auto');

CREATE TABLE action_log (
    id                  bigserial PRIMARY KEY,
    tenant_id           uuid REFERENCES tenant(id),
    actor               text NOT NULL,        -- user principal or 'agent:<name>'
    actor_is_agent      boolean NOT NULL DEFAULT false,
    autonomy            autonomy_level,
    action              text NOT NULL,
    target_kind         text,
    target_ref          text,
    approval_user       text,
    approval_at         timestamptz,
    change_request_ref  text,                 -- ServiceNow CHG
    blast_radius        jsonb,
    before_state        jsonb,
    after_state         jsonb,
    outcome             text NOT NULL DEFAULT 'pending'
                        CHECK (outcome IN ('pending','succeeded','failed','rolled_back','blocked')),
    created_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON action_log (tenant_id, created_at DESC);
REVOKE UPDATE, DELETE ON action_log FROM PUBLIC;

-- ---------------------------------------------------------------------
-- 11. ROW-LEVEL SECURITY
-- Set per request at the connection: SET LOCAL app.tenant_ids / app.role.
-- Enforced here so a missing WHERE clause in application code cannot leak.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION current_tenant_ids() RETURNS uuid[] AS $$
    SELECT CASE
        WHEN current_setting('app.tenant_ids', true) IS NULL
          OR current_setting('app.tenant_ids', true) = '' THEN ARRAY[]::uuid[]
        ELSE string_to_array(current_setting('app.tenant_ids', true), ',')::uuid[]
    END;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION is_portfolio_role() RETURNS boolean AS $$
    SELECT coalesce(current_setting('app.role', true), '') IN
           ('ceo','cfo','finops','secops','auditor','platform_admin');
$$ LANGUAGE sql STABLE;

DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'sow','quote_snapshot','cloud_account','resource','work_item','csat_response',
        'alert','availability_daily','vulnerability','cost_fact','assessment',
        'control_response','knowledge_chunk','action_log','tag_policy','curated_fact'
    ] LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
        EXECUTE format($f$
            CREATE POLICY tenant_isolation ON %I
            USING (tenant_id IS NULL OR tenant_id = ANY(current_tenant_ids()))
            WITH CHECK (tenant_id IS NULL OR tenant_id = ANY(current_tenant_ids()))
        $f$, t);
    END LOOP;
END $$;

-- Commercial data is withheld from engineering roles even inside their tenants.
CREATE POLICY commercial_visibility ON sow
    AS RESTRICTIVE
    USING (coalesce(current_setting('app.role', true), '') IN
           ('ceo','cfo','finops','delivery_lead','platform_admin','auditor'));

COMMENT ON TABLE tenant_alias IS
  'Populate this before anything else. Agria appears as "Agria", "AGRIA PET INSURANCE LIMITED" and "Agriapet" across three systems; nothing joins until every alias is mapped.';
COMMENT ON COLUMN cost_fact.charge_class IS
  'Licence and marketplace charges must be excluded from consumption before margin is calculated.';
