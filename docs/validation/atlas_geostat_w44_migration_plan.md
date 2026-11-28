# W44 model adoption and product migration plan

Audit date: 2026-11-27

## Current source and evidence

The W44 candidate lives at /project/disease_ecology/hominivorax-geostat-original-refresh-w44-2026/outputs/original_refresh_w44_2026 inside a separate feature/original-refresh-w44-2026 checkout. It occupies about 11 GiB including reports, logs, validation, and source artifacts. The four primary stage artifacts total 10,664,345,110 bytes, about 9.93 GiB:

| Stage | Bytes | SHA-256 |
| --- | ---: | --- |
| Stage 1 | 697,619,900 | 64571f7b3a7aa59625cbe788d10ce8f149f1b53b8015efcabceed99dcc25f9af |
| Stage 2 | 697,271,352 | 1a09657781f6989154d331a7467c6dbc28d7be8011991709d3259e94eac95fe0 |
| Stage 3A | 2,634,681,832 | 74dc75e578474712cc06c62634b50c26631779003c8e804bbd2f7ff62bbb74a5 |
| Stage 3B fit | 6,634,772,026 | e9409c37ca88dedb0441d65c184c2c5cae9ca1dcf923aeb52db03bf8e451605c |

The fit is qualified with limitations. The launch-record and runtime-metadata commits differ, but the completed reconciliation established that the R, scripts, config, and tests trees are identical; differences are confined to archived documentation/evidence. See docs/archive/original-refresh-w44-2026/w44-adoption-readiness-2026-11-27.md, docs/archive/original-refresh-w44-2026/original_refresh_w44_2026_source_provenance_reconciliation_v1.json, and docs/archive/original-refresh-w44-2026/original_refresh_w44_2026_production_manifest_v2.json on PR #16. The original fit metadata and qualification evidence remain unchanged. This commit difference is not an outstanding adoption blocker. The W44 request remains planning-only with dispatch_authorized false. No W44 Post-fit result exists in the production output tree, and no activation occurred.

PR #16 documents a full artifact copy, then hash verification, into production_runs/model_registry/production-id. That destination was not present in this audit. A full copy of the four large objects adds about 9.93 GiB. The W44 native source currently remains the only observed authoritative fit location.

## Proposed migration procedure after separate authorization

1. Use the completed versioned W44 source-commit reconciliation as provenance evidence; do not rewrite the launch record, fit metadata, or original qualification files. Confirm the model-specification digest, data/config identity, qualification scope, and lineage. If the approved specification is unchanged from the original, classify it ROUTINE_REFRESH; otherwise require MODEL_REVISION and its qualification.
2. Freeze a source artifact manifest containing the paths, byte sizes, SHA-256 values, Stage 1 to Stage 2 to Stage 3A to fit lineage, job IDs, health/extraction/validation evidence, and release classification.
3. Select one durable model-artifact store. Prefer avoiding two permanent copies. Before implementation, revise or qualify the registry to reference immutable source objects by checksum, or use an Atlas-tested deduplication method. Do not assume a hardlink, reflink, symlink, or cross-directory atomic operation is supported.
4. If the current registry-copy implementation remains, budget at least 9.93 GiB additional space for the primary artifact set, plus Post-fit output and scratch. Copy once, verify every target checksum, and make the registry copy authoritative. Do not retire the source copy until the exact manifest, all checksums, permissions, consumers, PR evidence, and reproducibility requirements are reviewed and the owner authorizes that cleanup.
5. Use a timestamp-shaped run ID accepted by CHIME, while retaining a separate immutable production/model ID for ORIGINAL_REFRESH_W44_2026. Coordinate an adapter update because CHIME currently treats adopted Prepare/Fit stages differently from executed stages; do not mark unperformed stages as PASS just to satisfy discovery.
6. Run Post-fit only under a separate explicit production authorization, using the approved wrapper and established environment. Write native run outputs beneath production_runs/<run-id>. Store the accepted product envelope under the existing postfit_acceptance root.
7. Include the final fit and each product class in a release manifest: prediction, structural, temperature-masked, RPI, figures/tables, and metadata. Record each path, SHA-256, size, analysis endpoint, qualification state, source fit identity, and source run.
8. Review acceptance gates and external consumer compatibility. CHIME must recognize the run and package; compare checksums and product manifests; perform the approved active-pointer compare-and-swap only after a human chooses the active model and rollback target.
9. Keep W39 available as the rollback candidate for the agreed interval. Preserve W44 qualification history, compact manifests, and every artifact needed to reproduce its fit. Do not remove C1 or historical-model evidence as part of W44 promotion.
10. After qualification and publication, inventory the W44 development tree and validation clones again. A source-output cleanup can be considered only after no job/consumer references remain, the canonical artifact set is verified, PR and validation evidence is preserved, the rollback policy is satisfied, and the data owner explicitly authorizes a separate cleanup.

## Storage and product estimate

Current W39 accepted-package output occupies 789 MiB; related reporting trees are about 119 MiB and a W39 continuation is 680 MiB. These are comparators, not a W44 forecast: W44 has no completed Post-fit package, and the audit did not measure peak scratch or establish how reporting size scales with its analysis horizon. Reserve the registry-copy amount above if copies remain, then perform a bounded resource forecast before a separately authorized Post-fit dispatch. Do not infer a W44 raster footprint from the fit size.

## Temporary and validation directories

Three small separate validation clones (PR #15 and PR #16) and nested C1 validation worktrees exist. They are not cleanup-eligible merely because they are small or detached. Preserve evidence, branch refs, and untracked files through PR closure and validation-owner review. Future worktrees can use the already existing /project/disease_ecology/worktrees area; do not add project-root worktrees.

This is a plan only. No files were copied or moved; no Post-fit or raster job was submitted; no release was registered or activated.

## Directory and release framework integration status (2026-11-27)

The governed release implementation now references core artifacts only when
they already resolve beneath canonical `production_runs`. Artifacts from a
development output tree such as W44 require one verified canonical copy if a
future adoption is authorized; no such copy was made here. The accepted
products root remains `nws-geostat-output/postfit_acceptance`. CHIME adapter
changes and synthetic tests are maintained in the CHIME development
repository.

The no-job W44 directory/release integration and its limitations are recorded
in [the W44 directory integration dry-run](atlas_geostat_w44_directory_integration_dry_run.md).
The dry-run confirmed the W44 fit identity and release metadata, but the
current W39 production configuration is incompatible with W44. No canonical
W44 artifact registration, Post-fit package, active pointer, or activation was
created. The source remains in its development output tree. Any subsequent
copy, Post-fit execution, source cleanup, or activation requires its separate
authorization.
