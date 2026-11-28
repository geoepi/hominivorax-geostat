# Atlas GeoStat refresh and artifact-retention policy

Audit date: 2026-11-27

This policy separates routine data refreshes from scientific model revisions.
The repository implements these rules as metadata and a read-only
cleanup-eligibility report. It does not authorize deletion or change current
production retention.

## Release classes

### ROUTINE_REFRESH

Use only when the approved model specification is unchanged: same likelihood, fixed effects, random effects, priors, spatial/temporal structure, and product semantics; only observations, environmental inputs, or the analysis endpoint advance. Record and compare a model-specification digest before using this class. W44 is provisionally a routine refresh of the original model if the specification digest matches; preserve it as a qualified scientific result and use the completed versioned provenance reconciliation without rewriting source records.

### MODEL_REVISION

Use when scientific structure or assumptions change, including fixed effects, likelihood, random effects, priors, hyperparameters, spatial/temporal definitions, or consequential product semantics. Assign a new model version and preserve the qualification evidence and artifacts required to reproduce and compare it. Do not expire it under routine-refresh rules.

## Routine-refresh retention

- Current qualified release: retain the fit, required upstream inputs, immutable release manifest, product package, checksums, qualification evidence, and compact execution logs.
- Immediately superseded release: retain the full rollback set for at least 90 days and at least two later qualified refresh cycles, whichever is longer. Keep the immediately previous qualified fit and product package available throughout that interval.
- Older superseded runs: after the rollback window, retain compact run manifests, input/config/code identities, product checksums, gate summaries, and job-log metadata indefinitely or under publication/funder requirements. Retain large fit/intermediate/product payloads only where reproducibility, publication, or a live consumer requires them.
- Stage 1 through Stage 3A: retain with the current release and rollback set. After the window, keep them only if required to reproduce the fit or scientific results; otherwise retain their checksums, lineage, configuration, and regeneration instructions.
- Stage 3B fit: retain current and rollback fits; do not replace a fit in place. Older routine fits may be eligible for retirement only after a checksum-verified replacement, consumer update, and evidence review.
- Prediction and reporting products: retain current and rollback accepted packages. Do not treat diagnostic or partial outputs as qualified products.
- Successful Slurm logs: retain compact status and log checksums for one year; keep full logs through the rollback window and longer if needed for a publication or audit. Failed-job logs remain until root cause is closed and for at least one year after closure.
- Failed execution directories: preserve the manifest, status, logs, and smallest evidence set needed to explain the failure. Review large partial payloads after 90 days, but remove only after the failed run is closed and no active consumer/job refers to them.
- Worktrees and validation clones: retain through their PR/qualification decision. After merge or closure, retain validation evidence and untracked user outputs; review the checkout for archival or owner-authorized cleanup after 30 days and a reference scan. A clean Git status alone is not grounds for removal.

## MODEL_REVISION retention

Retain each approved model revision as an independent scientific identity. Keep the fit and the exact upstream artifacts/configuration/code/environment records needed to reproduce it, its qualification and predictive-validation evidence, and its principal publication products. Preserve model-comparison products and known limitations. Retain according to publication, funder, data-license, and institutional policy; do not apply the 90-day routine refresh expiry. Store revision metadata and artifact manifests in immutable locations.

C1 and the frozen historical fit remain separate scientific identities. The C1 result is archived and not selected for production. Do not merge C1 or W44 evidence into a generic “latest” folder.

## Required provenance for every retained release

Record model and specification IDs/digests; refresh class; observation/environmental release IDs and hashes; analysis window; code commit; configuration hash; runtime/environment identity; stage paths and checksums; fit job and SHA; fit-health/extraction/predictive-validation evidence; reporting and product hashes; release qualification state; active/rollback event references. Secrets and private credential values must never enter manifests or reports.

## Cleanup eligibility gate

A candidate is eligible for a future cleanup review only when all conditions are met:

1. no active Slurm job or open workflow refers to the path;
2. the artifact is not the current release, rollback set, distinct model revision, publication source, or required validation evidence;
3. source and downstream consumer searches are complete, with owner confirmation for private/local consumers;
4. retained replacement artifacts and manifests have been checksum-verified and can be read by intended consumers;
5. the scientific and operational retention requirement has expired;
6. the deletion set and estimated savings are reviewed and explicitly authorized by the data owner;
7. the cleanup is logged with paths, hashes, reason, approver, and date.

Never infer that similar names, equal sizes, a clean checkout, or an old timestamp makes an artifact disposable. Deletion must be a separate reviewed implementation, not an automatic side effect of a refresh.

## Current candidate disposition

- Exact duplicate jcat_2025-10-25.rds pair: 6.10 GiB can be saved if local/private references are cleared and the retained canonical path is selected.
- Two 56 MiB reporting trees: hash and manifest comparison still required.
- Similar-size extraction files and historical runs: not proven duplicates.
- Validation clones and worktrees: retain until PR/evidence review.
- W44 registry copy: not currently present; avoid a permanent second copy by deciding the artifact-store contract before promotion.

The release framework reports eligibility and estimated recoverable storage
for review. It never removes files. No cleanup was run and no production
retention was changed.

## Implemented metadata checks

The report requires an owner, byte count, classification, known source
references, downstream consumers, retention start date, count of subsequent
qualified refreshes, active-job references, replacement path and SHA-256,
replacement-verification flag, scientific-preservation flag, and duplicate
finding. A candidate is eligible for review only when it is a superseded
routine refresh, both the 90-day and two-refresh conditions have elapsed,
references and consumers are resolved, a verified replacement is recorded,
and neither preservation nor duplicate review blocks it. The report records
blockers, estimated recoverable bytes, and required owner/governance approval.
It performs no deletion.

The confirmed duplicate model-file pair remains an audit finding until
consumer references are resolved. C1, frozen scientific models, failed-run
evidence, and open qualification work are not subject to routine-refresh
expiry.
