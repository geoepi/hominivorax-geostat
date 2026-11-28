# Atlas GeoStat directory and artifact audit summary

Audit date: 2026-11-27

## Decision

DIRECTORY_CONSOLIDATION_DESIGN_READY_WITH_LIMITATIONS

The directory design is ready for human review. It is not authorization to restructure paths or clean up files. The W44 launch/runtime commit difference has been reconciled: the R, scripts, config, and tests trees are identical, and the differences are confined to archived documentation/evidence. See docs/archive/original-refresh-w44-2026/w44-adoption-readiness-2026-11-27.md and docs/archive/original-refresh-w44-2026/original_refresh_w44_2026_source_provenance_reconciliation_v1.json. Remaining limitations are CHIME's run-ID/adoption assumptions, unverified private/local consumers, unavailable project quota details, and the lack of an unambiguous active-release pointer.

## Findings

1. **Project-root count:** 11 Geostat-related directories immediately under /project/disease_ecology were inventoried.
2. **Canonical locations:** /project/disease_ecology/hominivorax-geostat is the clean canonical main source checkout; hominivorax-geostat-config is the private config/deployment root; nws-geostat-output is the production/run/artifact/reporting root.
3. **Temporary/development locations:** W44 feature checkout, C1 validation checkout, three PR validation clones, the reporting source checkout, and linked worktrees. Several contain unique scientific or qualification evidence. None is cleared for removal.
4. **Unique scientific evidence:** C1 experiment and qualification archive; W44 qualified-with-limitations fit and stage lineage; historical frozen 16-coefficient fit; W39 production runs and accepted post-fit package; full-horizon prefit diagnostics; other historical model variants under nws_geostat_models.
5. **Storage:** the 11 directories use about 134 GiB, based on rounded du summaries. The shared /project filesystem reports 8.1 TiB total, 3.6 TiB used, 4.5 TiB available (45% used). User quota was not readable and the lfs utility is unavailable; this is not a project-specific quota measurement.
6. **Potential savings:** one exact duplicate RDS pair is 6,543,291,801 bytes (about 6.10 GiB) with matching SHA-256. Savings are conditional on path-reference clearance and owner selection. Another pair of 56 MiB reporting trees is only a candidate; no other storage is counted as safely recoverable. The PR #16 W44 registry copy would add about 9.93 GiB if retained as a second copy.
7. **Known consumers:** CHIME reads production run metadata under production_runs and accepted packages under postfit_acceptance. It has environment overrides, but exact run and package contracts. The canonical repository workflow also uses production_runs. GitHub Pages sources did not show Atlas output paths. Other local/private consumers remain unverified.
8. **Canonical paths:** retain production_runs for immutable execution history and the existing postfit_acceptance root for accepted product packages. Keep hominivorax-geostat-reporting as source code; it is already a Git checkout and is not a products directory. Put the stable active-release pointer in the existing private config root.
9. **After a routine refresh:** retain current qualified artifacts and product package, plus the immediately prior qualified rollback set for at least 90 days and two qualified refresh cycles, whichever is longer. Keep compact manifests, hashes, gates, job metadata, and provenance for older routine runs. Remove payloads only after the cleanup gate and explicit authorization.
10. **After a model revision:** retain an independent model identity, reproducible fit inputs/artifacts, qualification and comparison evidence, and principal products under publication/institutional retention rules; never expire as a routine refresh.
11. **Framework changes needed:** add explicit release_type and model-specification digest; add retention and product-manifest fields; revise full-copy model_registry behavior to support one durable checksum-verified artifact set; define canonical_report_root; establish active pointer by owner decision; update CHIME to follow the active/accepted contract and correctly inspect adopted fits.
12. **W44 incorporation:** use the completed versioned provenance reconciliation without rewriting historical fit metadata. Then checksum and manifest the four source artifacts, verify the unchanged original specification, choose one durable artifact store, use a CHIME-compatible run ID plus stable model ID, run Post-fit only after separate authorization, publish through postfit_acceptance, preserve W39 rollback, and activate only after qualification and human selection.
13. **Cleanup candidates:** exact jcat duplicate (conditional 6.10 GiB); possible duplicate reporting folders (56 MiB); unverified similar extraction files; superseded routine runs after consumer review; small validation clones only after PR/evidence review. No directory is currently approved for cleanup.
14. **Human authorization still required:** choose active W39/W44 state and release identity; approve changes to the release/consumer contract; confirm external consumers, quota policy, retention exceptions, and any future deletion or activation.

## Recommended implementation order

1. Human owner confirms W44 release classification and model specification using the completed provenance reconciliation.
2. Map private/local consumers and select the canonical artifact store and product root.
3. Update and qualify the release contract, registry deduplication/reference behavior, and product manifest.
4. Update CHIME discovery for active releases and adopted-fit semantics; test timestamp IDs and acceptance links.
5. Define and qualify the active pointer and rollback protocol without changing the scientific computation.
6. Reconcile deployment identity and current W39/W44 state with the owner.
7. Only then prepare a separately authorized W44 Post-fit plan and storage forecast.
8. Handle any cleanup as a separate owner-approved change with a path/hash evidence package.

## Scope and validation

Read-only audit only. It inspected bounded Atlas metadata, directory sizes/counts/ownership/modes/base ACLs, Git status/worktree relationships, selected artifact hashes, W39/W44 manifests and configuration identities, CHIME code, and relevant repository docs. One bounded Slurm query showed no active jobs for john.humphreys. A targeted SHA-256 confirmed only the reported jcat pair. No filesystem restructuring, model fitting, Post-fit, raster generation, registration, activation, code/config change, or deletion was performed.

This is a documentation-only Category A change. No executable tests were run because these reports do not affect executable behavior.

## Implementation status (2026-11-27)

The companion release framework now derives the accepted-products and model
registry locations from the configured `production_runs` root, supports
validated active-manifest discovery, and reports cleanup eligibility without
deleting files. CHIME's separate Geostat adapter change adds adopted-fit
lineage and timestamp-shaped execution IDs. These code changes do not resolve
the audit's remaining private-consumer, quota, or active-release-owner
questions. W44 still lacks canonical registered artifacts and accepted
products; see the no-job integration report for its exact limitations.
