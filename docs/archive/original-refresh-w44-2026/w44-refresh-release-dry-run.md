# W44 refresh and release dry-run

**Run date:** 2026-11-27 (CST)
**Code commit:** `85ea55878c6409cc765def1e430cd63219c8789d`
**Atlas runtime:** `atlas-r44-spatial-v1`, R 4.4.3
**Change classification:** D — production orchestration, artifact lineage, and release activation
**Execution:** adoption dry-run only; no scheduler submission

## Decision

- `REFRESH_FRAMEWORK_READY=READY_WITH_LIMITATIONS`
- `EXISTING_FIT_ADOPTION_READY=BLOCKED`
- `W44_ACTIVATION_READY=BLOCKED`
- `POSTFIT_EXECUTION_READY=BLOCKED` for W44; the post-fit interface is implemented, but the W44 adoption gate did not pass.

The dry-run stopped before fit and upstream artifact byte-level validation. It must not be interpreted as qualification or acceptance of the W44 artifacts for registration.

## Request and observed plan

The request SHA-256 was `76f293b9f1eddaf493be17e1b970e222001b7ec07914c7429d4ec93182df32f1`. It identifies candidate `ORIGINAL_REFRESH_W44_2026`, production release `ORIGINAL_W44_2026_PRODUCTION`, and historical fit job `21355414`. It declares fit artifact SHA-256 `e9409c37ca88dedb0441d65c184c2c5cae9ca1dcf923aeb52db03bf8e451605c` and the original 16-coefficient formula identity.

The approved observation file was `/project/disease_ecology/NWScrewworm/data/processed_data/case_detections/combined_clean_obs_2026-11-13.csv`, with observed checksum `784168081cc1d3206f3537b8731994cbfc34be15be7c515fe06710d4ea9bdaac`. The requested horizon resolved to `2022-W01` through `2026-W44` (252 weeks), honoring the versioned request.

The plan was `adoption_validation -> postfit`. The validator returned `BLOCKED` while parsing `docs/archive/original-refresh-w44-2026/original_refresh_w44_2026_production_manifest.json` (request-declared SHA-256 `eed2d7cda3d8aa562f545b9d9e423e8d3495481d4e2f39626cd92a3da17c9786`): `Duplicate map key: 'qualification'`. In the archived `candidate_model` object, `qualification` is used both for the qualification-status string and the qualification metrics object. The strict parser rejects this ambiguous map. The historical evidence was left unchanged. The dry-run therefore did not validate the fit and upstream artifact bytes or complete source-lineage checks.

A prior audit also found a source-lineage discrepancy that remains unresolved: fit launch output identifies source commit `42f27497b251cdcd84d2b44b1844cd18292610a8`, while fit metadata identifies commit `5bf5e8d0f54de55e58f3a698daefb223ddc9d2e0`. The latter was an Atlas-local, documentation-only C-1 archive commit recorded during the fit audit window. The current dry-run did not reach this check; no exception or attestation has been introduced.

The dry-run reported no Prepare jobs, no Fit jobs, no Post-fit jobs, no artifact registration, and `Scheduler jobs submitted: 0`. Its proposed output root was `/project/disease_ecology/nws-geostat-output/production_runs/adopt-original-refresh-w44-2026-adoption`; its proposed registry entry was `/project/disease_ecology/nws-geostat-output/production_runs/model_registry/ORIGINAL_W44_2026_PRODUCTION`. Read-only checks confirmed both paths are absent. No production rasters or post-fit products were generated.

## Deployment reconciliation

The read-only reconciliation command returned `overall_status: MISMATCH` for `/project/disease_ecology/hominivorax-geostat-config/deployment-manifest.yml` (observed checksum `7d1eae69290f63e7432d2a7c9fc9796a637981ffd96718808d187ad079e9fc16`).

- Observed canonical checkout: `cf21c04ef53158b9bcca38dad75e7f75ee9e984a`; recorded commit: `d2a2ff96766971416b41e00123b46ddbf1906322`.
- Observed production configuration checksum: `0667d4ab1c6780da0ce435bd3a7e67fa83a2b90d0c8cc8b4658909d3d4f6ea49`; recorded checksum: `45022942bca0fd9dd49fe50a7b19c0049badadf8d38f7071e0826e692b90b966`.
- Observed configuration points to the W39 observation release, starts at `2024-W01`, and uses `last_complete_epiweek`; the deployment record declares no observation checksum or model identity.
- `/project/disease_ecology/hominivorax-geostat-config/active-release.yml` is absent, so no previous active release identity is established for compare-and-swap activation or rollback.

The current production configuration is not compatible with the W44 candidate. The deployment manifest and private configuration were read only.

## Validation and preservation

On framework commit `85ea558`, the canonical command `Rscript tests/run_tests.R --log-dir /tmp/hominivorax-refresh-release-framework-85ea558-tests` ran under the repository Atlas runtime: 37 executed, 21 passed, 16 warned, 0 failed, 0 skipped. Warnings were existing geospatial/runtime version and timezone notices, legacy INLA deprecations, and expected diagnostic paths in tests. Atlas runtime preflight passed.

This report is a documentation-only addition. This report passed `git diff --check` before its documentation commit. The canonical `main` checkout remained clean at `cf21c04`. The pre-existing W44 source worktree was not changed; it still contains its prior untracked archives and Slurm logs. No model was refit, no configuration or active pointer was written, no historical evidence or fitted artifact was overwritten, and no activation was attempted.

## Remaining gates

1. Create a schema-valid, versioned qualification evidence record and update the refresh request checksum under the applicable evidence governance. Preserve the current historical JSON unchanged.
2. Re-run adoption validation to verify fit and Stage 1, Stage 2, and Stage 3A artifact bytes and full lineage. Reconcile the source-commit discrepancy above before registration.
3. Reconcile the existing W39 active model identity and deployment record; establish an authorized active-release pointer before activation or rollback can be evaluated.
4. After these gates pass, run Post-fit against the accepted fit and assess product qualification and activation separately.
