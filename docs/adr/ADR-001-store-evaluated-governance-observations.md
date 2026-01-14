# ADR-001: Store Evaluated Governance Observations (DGOs) Instead of Mirroring GitLab/Jira

## Status
Proposed

## Date
2026-01-13

## Context
We need application-centric continuous compliance signals from GitLab and Jira at large-enterprise scale (10,000s of developers, 24/7 activity). Requirements:

- Avoid mirroring raw GitLab/Jira payloads (cost, bloat, coupling).
- Avoid runtime dependency on GitLab/Jira for platform UX/performance.
- Data does not need to be real-time; periodic incremental extraction is acceptable.
- Persist what we observed **at the time of extraction** for auditability and drift detection.
- Support "since last run" incremental harvesting with a backstop rescan.
- Keep storage growth proportional to governance-relevant state changes, not raw activity volume.
- All observations are anchored to an **application** (`app_id`) as the primary organizing dimension.
- This platform provides observation and risk intelligence; **enforcement is handled by a separate layer** that consumes DGOs.

## Decision
We will persist **Derived Governance Observations (DGOs)**: point-in-time, evaluated outcomes of governance signals (pass/fail/warn) plus minimal context needed to explain the result later, without re-querying GitLab/Jira.

We will store:
1. **Append-only DGO history** when an observation changes state.
2. **A current-state table** for fast reads and "what's failing now" queries.
3. **Extractor run bookkeeping** to drive incremental harvesting ("since last run") and operational visibility.

DGOs are the durable data product. GitLab/Jira remain upstream sources only. The enforcement layer consumes DGOs to implement specific controls and gates.

### Terminology
- **DGO (Derived Governance Observation):** Evaluated governance fact persisted at extraction time.
- **Signal:** Human-readable name for a DGO type (e.g., `jira_approval_bypass`, `mr_missing_approvals`).
- **Signal Version:** Integer version allowing signal evaluation logic to evolve without breaking history.
- **Fingerprint:** Stable hash representing an evaluated observation result (used to dedupe).
- **App ID:** Application identifier; all observations are anchored to an application.

## Signal Catalog and Extraction Contract
Signals are evaluated at extraction time and persisted as DGOs. We persist only evaluated outcomes and minimal context (no raw payload mirroring).

> Notes:
> - `:last_run`, `:window_start`, `:scoped_projects` are runtime parameters.
> - Some signals are derived from prior DGOs (no Steampipe query).
> - Steampipe queries are templates; exact table/column names depend on plugin version and configuration.

### Canonical Signal Table

#### GitLab Signals

| Signal | Extraction | Persisted value | Steampipe query |
|---|---|---|---|
| MR missing required approvals | Compare approvals vs required for target branch | `result`, `required_approvals`, `actual_approvals`, `mr_id`, `repo_id`, `target_branch` | `select mr.id, mr.project_id, mr.target_branch, mr.approvals_required, mr.approvals_count from gitlab_merge_request mr where mr.state='opened' and mr.updated_at > :last_run;` |
| MR merged without required approvals | Evaluate approvals at merge time | `result`, `required_approvals`, `actual_approvals`, `merged_at`, `mr_id`, `repo_id` | `select mr.id, mr.project_id, mr.merged_at, mr.approvals_required, mr.approvals_count from gitlab_merge_request mr where mr.state='merged' and mr.merged_at > :last_run;` |
| MR without linked Jira issue | Parse MR title/body/branch for Jira key | `result`, `mr_id`, `repo_id`, `link_detected`, `link_method` | `select mr.id, mr.project_id, mr.title, mr.description, mr.source_branch from gitlab_merge_request mr where mr.updated_at > :last_run;` |
| Commits pushed directly to protected branch | Detect commits on protected branches without MR | `result`, `branch`, `commit_id`, `actor`, `repo_id` | `select c.id, c.project_id, c.ref, c.author_name, c.committed_at from gitlab_commit c join gitlab_branch b on b.project_id=c.project_id and b.name=c.ref where b.protected=true and c.committed_at > :last_run;` |
| Repo missing required branch protection | Evaluate repo protection config vs baseline | `result`, `repo_id`, `missing_controls` (array), `baseline_version` | `select p.id as project_id, p.path_with_namespace, b.name, b.protected from gitlab_project p left join gitlab_branch b on b.project_id=p.id and b.default=true where p.id in (:scoped_projects);` |
| Repo admin sprawl | Count admins vs threshold | `result`, `repo_id`, `admin_count`, `threshold`, `principal_breakdown` | `select m.project_id, count(*) as admin_count from gitlab_project_member m where m.access_level='admin' and m.project_id in (:scoped_projects) group by m.project_id;` |
| Repeated approval bypass (repo) | Aggregate prior DGOs over window | `result`, `repo_id`, `violation_count`, `window_start`, `window_end` | *(derived from DGO store)* |
| Large / unusual MR | Compute diff stats vs baseline | `result`, `mr_id`, `repo_id`, `files_changed`, `lines_changed`, `baseline_percentile` | `select mr.id, mr.project_id, mr.additions, mr.deletions, mr.changed_files, mr.updated_at from gitlab_merge_request mr where mr.updated_at > :last_run;` |
| Pipeline failed | Detect failed/canceled pipelines | `result`, `pipeline_id`, `repo_id`, `ref`, `failure_stage`, `duration_seconds` | `select p.id, p.project_id, p.ref, p.status, p.duration from gitlab_pipeline p where p.status in ('failed','canceled') and p.finished_at > :last_run;` |
| Pipeline flapping | Aggregate fail→pass→fail cycles over window | `result`, `repo_id`, `ref`, `flap_count`, `window_start`, `window_end` | *(derived from DGO store)* |
| Deployment to protected environment | Detect deployments to prod/staging | `result`, `deployment_id`, `repo_id`, `environment`, `deployer`, `ref`, `sha` | `select d.id, d.project_id, d.environment, d.status, d.ref, d.sha, d.user->>'username' as deployer from gitlab_deployment d where d.environment in ('production','staging') and d.updated_at > :last_run;` |
| Deployment without passing pipeline | Join deployment to pipeline status | `result`, `deployment_id`, `repo_id`, `pipeline_status`, `environment` | `select d.id, d.project_id, d.environment, p.status as pipeline_status from gitlab_deployment d join gitlab_pipeline p on p.sha = d.sha and p.project_id = d.project_id where d.updated_at > :last_run;` |

#### Jira Signals

| Signal | Extraction | Persisted value | Steampipe query |
|---|---|---|---|
| Open Jira issue required for release | Required-for-release + not Done | `result`, `issue_key`, `project_key`, `status`, `fix_version` | `select i.key, i.project_key, i.status, i.fix_versions from jira_issue i where i.updated > :last_run and i.custom_required_for_release = true and i.status not in ('Done','Closed');` |
| Jira issue not in approved state | Status vs allowed states | `result`, `issue_key`, `status`, `allowed_states` | `select i.key, i.project_key, i.status from jira_issue i where i.updated > :last_run;` |
| Jira issue without approved change | Approval field/status/comment pattern | `result`, `issue_key`, `approval_present`, `approval_method` | `select i.key, i.project_key, i.status, i.custom_approval from jira_issue i where i.updated > :last_run;` |
| Jira issue flagged high risk | Risk field / priority / label | `result`, `issue_key`, `risk_level`, `risk_field_source` | `select i.key, i.project_key, i.priority, i.labels, i.custom_risk from jira_issue i where i.updated > :last_run;` |
| Jira issue reopened after Done | Detect Done → Reopened in changelog | `result`, `issue_key`, `reopen_count`, `last_reopen_at` | `select i.key, i.project_key, i.changelog from jira_issue i where i.updated > :last_run;` |
| Jira approval bypass | Approval state never visited | `result`, `issue_key`, `approval_states`, `visited_states` | `select i.key, i.project_key, i.changelog from jira_issue i where i.updated > :last_run;` |
| Late approval | approval_at > resolved_at | `result`, `issue_key`, `approval_at`, `resolved_at`, `delay_seconds` | `select i.key, i.project_key, i.custom_approval_at, i.resolutiondate from jira_issue i where i.updated > :last_run;` |
| Jira workflow missing approval step | Inspect workflow definition for required states | `result`, `project_key`, `missing_states`, `workflow_name` | `select w.project_key, w.name as workflow_name, w.statuses from jira_workflow w where w.project_key in (:scoped_projects);` |
| Jira exceptions becoming frequent | Aggregate exception-tagged issues over time window | `result`, `project_key`, `exception_count`, `window_start`, `window_end` | `select i.project_key, count(*) as exception_count from jira_issue i where i.updated > :window_start and 'exception' = any(i.labels) group by i.project_key;` |
| Jira issues missing required fields | Validate required fields at Done | `result`, `issue_key`, `missing_fields` | `select i.key, i.project_key, i.status from jira_issue i where i.updated > :last_run and i.status in ('Done','Closed');` |
| Jira workflow drift | Compare workflow hash vs previous extraction | `result`, `project_key`, `previous_hash`, `current_hash` | `select w.project_key, md5(w.statuses::text) as hash from jira_workflow w where w.project_key in (:scoped_projects);` |

### Deferred Signals (Future Iteration)
The following signals require direct GitLab API extraction outside of Steampipe:
- Security scan findings (SAST/DAST/dependency)
- Secrets detected

## Data Model (Postgres)

### 1) DGO History (append-only)
```sql
create schema if not exists gov;

create table if not exists gov.dgo (
  id               bigserial primary key,
  observed_at      timestamptz not null,
  source           text not null check (source in ('gitlab','jira')),
  signal_type      text not null,
  signal_version   int not null default 1,
  subject_type     text not null,
  subject_ref      text not null,
  result           text not null check (result in ('pass','fail','warn')),
  value            jsonb not null default '{}'::jsonb,
  extractor_run_id uuid not null,
  app_id           text not null,
  fingerprint      text not null
);

create index if not exists dgo_idx_subject_time
  on gov.dgo (subject_type, subject_ref, observed_at desc);

create index if not exists dgo_idx_signal_time
  on gov.dgo (signal_type, observed_at desc);

create index if not exists dgo_idx_app_time
  on gov.dgo (app_id, observed_at desc);
```

### 2) Current State (fast reads)
```sql
create table if not exists gov.dgo_current (
  source           text not null check (source in ('gitlab','jira')),
  signal_type      text not null,
  signal_version   int not null default 1,
  subject_type     text not null,
  subject_ref      text not null,
  app_id           text not null,
  last_observed_at timestamptz not null,
  result           text not null check (result in ('pass','fail','warn')),
  value            jsonb not null default '{}'::jsonb,
  extractor_run_id uuid not null,
  fingerprint      text not null,
  primary key (source, signal_type, subject_type, subject_ref)
);

create index if not exists dgo_current_idx_app
  on gov.dgo_current (app_id, result);
```

### 3) Extractor Run Bookkeeping
```sql
create table if not exists gov.extractor_run (
  id            uuid primary key,
  started_at    timestamptz not null default now(),
  finished_at   timestamptz null,
  source        text not null check (source in ('gitlab','jira')),
  scope_ref     text not null,
  status        text not null check (status in ('running','success','failed')),
  meta          jsonb not null default '{}'::jsonb
);

alter table gov.dgo
  add constraint dgo_extractor_run_fk
  foreign key (extractor_run_id) references gov.extractor_run(id);
```

## Write Path (After Extraction)

For each evaluated signal:

1. Compute a fingerprint from: `signal_type`, `signal_version`, `subject_type`, `subject_ref`, `result`, canonicalized `value`.
2. Read prior fingerprint from `gov.dgo_current`.
3. If fingerprint differs (state changed), insert into `gov.dgo`.
4. Upsert into `gov.dgo_current` (always).

## Extraction Strategy (Scale)

**Primary: incremental extraction since last run:**
- Jira: issues updated since `last_run`
- GitLab: merge requests, pipelines, deployments updated/finished since `last_run`

**Baselines/drift (low volume): run less frequently (e.g., daily / every 4–12h):**
- GitLab protections, membership/admin sprawl
- Jira workflows and drift

**Backstop: nightly sliding-window rescan (e.g., last 7 days)**

## Consequences

### Positive
- Platform reads from Postgres only; not dependent on GitLab/Jira for UX.
- Storage grows with governance state changes, not raw activity.
- Audit-friendly "as observed at time T" record.
- Stable contract: enforcement layer consumes DGOs, not vendor schemas.
- Application-centric model: all observations anchored to `app_id` for correlation.
- Signal versioning allows evaluation logic to evolve without breaking history.

### Negative / Tradeoffs
- DGOs are derived; deep forensics may require re-querying source systems.
- Incremental harvesting requires run tracking and periodic backstop.
- Some signals (security scans, secrets) require direct API extraction outside Steampipe.

## Alternatives Considered

1. **Full mirroring of GitLab/Jira entities**
   - Rejected: bloat, coupling, churn.

2. **Webhooks/event streaming as primary truth**
   - Rejected: operational complexity and reliability concerns.

3. **Query-on-demand from GitLab/Jira**
   - Rejected: performance dependency and poor UX.

## Decision Summary

Persist evaluated governance observations (DGOs) at extraction time, using append-only history + current-state + run tracking, driven by incremental harvesting with periodic reconciliation, anchored on the canonical signal catalog above. All observations are keyed to `app_id` for application-centric visibility. The enforcement layer consumes DGOs to implement specific controls.
