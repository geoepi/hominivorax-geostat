# W44 Adoption and Refresh Readiness

Observed 2026-11-27 22:43:03 UTC. This report records existing-fit adoption qualification and the planned Post-fit run; it does not represent a production activation.

## Independent outcomes

| Classification | Result | Evidence |
| --- | --- | --- |
| `W44_EVIDENCE_RECONCILED` | **PASS** | Versioned qualification record, strict parser tests, fit-source reconciliation, and source-preserving audit overlay. |
| `W44_EXISTING_FIT_ADOPTION_READY` | **READY_WITH_LIMITATIONS** | Atlas adoption dry-run returned `PASS_WITH_WARNINGS`; no scheduler jobs or registration were performed. |
| `W39_LEGACY_BASELINE_VERIFIED` | **BLOCKED** | The W39 state is partially reconstructed; the deployment record disagrees with observed code/config, qualification is not established, and the expected registry root is absent. |
| `W44_POSTFIT_EXECUTION_READY` | **READY_WITH_LIMITATIONS** | One production-profile Post-fit job is planned; it consumes the saved fit and runs the established serial stages. No job was submitted and no W44 Post-fit product has yet been generated. |
| `W44_ACTIVATION_READY` | **BLOCKED** | No verified W39 rollback target or active pointer exists, and this task did not authorize pointer initialization under SAE. |

## W44 evidence and fit provenance

The original qualification JSON remains unchanged (SHA-256 `eed2d7cda3d8aa562f545b9d9e423e8d3495481d4e2f39626cd92a3da17c9786`). The versioned evidence record uses unique JSON keys and separates `qualification_status` from `qualification_evidence`; the request pins its SHA-256. Tests cover acceptance of valid evidence, duplicate-key rejection, missing status/evidence rejection, checksum mismatch rejection, and the unchanged historical record.

The fit-launch commit remains `42f27497b251cdcd84d2b44b1844cd18292610a8`; metadata records runtime commit `5bf5e8d0f54de55e58f3a698daefb223ddc9d2e0`. The versioned reconciliation compares the repository trees and identifies only five archived evidence/documentation paths changed between those commits. The `R`, `scripts`, `config`, and `tests` trees are identical; executable and scientific-model changes were excluded. The original fit identity is retained and the fit metadata was not rewritten.

The adoption-only formula audit view consolidates the two semantically identical source `fit_not_executed` rows. It retains the shared PASS/FALSE/FALSE result, references the duplicate reconciliation record with both original details, and does not modify the original formula audit or artifact inventory. The 16 fixed effects and model formula remain unchanged.

## W44 no-job adoption result

The canonical no-job dry-run was run on branch commit `c5de930425b22665fe1857eab0c225e7fb718d7d` in Atlas `atlas-r44-spatial-v1`, R 4.4.3. Adoption validation returned `PASS_WITH_WARNINGS`, exit code 0. Prepare, Fit, and Post-fit submissions were each zero; artifact registration and activation were not performed. The proposed run and registry destinations were absent after the dry-run. The detailed report is [w44-adoption-dry-run-2026-11-27.md](w44-adoption-dry-run-2026-11-27.md).

Warnings were limited to the configured RTC local-time-zone notice, pre-existing `sf`/`terra` GEOS version notices, and an incomplete final line in the source-provenance JSON. Runtime preflight passed. Production-configuration compatibility was reported false because the active private config still describes W39.

## W39 baseline and rollback

The versioned W39 record is [w39_legacy_production_baseline_v1.json](../production-release-baselines/w39_legacy_production_baseline_v1.json). The observed W39 fit artifact checksum was independently rechecked, but the deployment manifest records commit `d2a2ff96766971416b41e00123b46ddbf1906322` and production-config SHA `45022942bca0fd9dd49fe50a7b19c0049badadf8d38f7071e0826e692b90b966`, while the current observed main checkout/config are `cf21c04ef53158b9bcca38dad75e7f75ee9e984a` and `0667d4ab1c6780da0ce435bd3a7e67fa83a2b90d0c8cc8b4658909d3d4f6ea49`. The current configuration also omits a model-version and existing-fit artifact field; the observed W39 run's Post-fit status is FAIL. Its historical qualification and active-release identity are not proven. No registry root, active-release pointer, or rollback pointer was created.

## Planned W44 Post-fit work

The single planned job consumes the verified W44 fit and runs extraction, production validation, prediction-grid projection, rasterization, structural reconstruction, temperature masking, RPI calibration, reporting, and integrity/completeness checks in sequence. The existing Stage 1, Stage 2, Stage 3A, and Stage 3B artifacts are inputs; there is no refit and no call to `INLA::inla()`. The plan preserves the W44 252-week window, `zero_mean` administrative-support policy, `lonlat`/EPSG:4326 source coordinates, 16 °C mask, same-week RPI calibration, 0.10 quantile, 21-day generation window, and 7-day layer.

The detailed versioned plan is [original_refresh_w44_2026_postfit_execution_plan_v1.json](original_refresh_w44_2026_postfit_execution_plan_v1.json). It names all 18 required reporting products, the run-scoped output paths, and the one-job resource profile. It does not authorize the Post-fit job, registry registration, or activation.

## Regression validation

- Focused strict-schema/provenance run: one focused test file executed, 36 excluded, 0 failures; status WARN reflected the Atlas RTC notice.
- Canonical Atlas suite at code commit `e792ee3`: 37 executed, 21 passed, 16 warned, 0 failed, 0 skipped; exit code 0. Runtime: Atlas `atlas-r44-spatial-v1`, R 4.4.3, INLA 25.9.19. The captured summary SHA-256 is `063bd12101f028bcdf57140094780219d3999212ca760fa881213f9ef42e11c8`.
- A commit comparison from `e792ee3` to the validated dry-run commit `c5de930` showed documentation/evidence changes only, so executable tests were not rerun after those doc-only commits.
- `git diff --check`: passed on the current feature branch before this report was added; it is rerun after this documentation commit.
- Full PR #16 diff classification: **D**, because its scope includes production orchestration and release operations. These final evidence/report additions are **A** documentation and non-executable metadata.

## Branch and release boundary

PR #16 remains open and draft, stacked on PR #15's feature branch. Neither PR was merged. No refit, Stage 1–3A regeneration, Post-fit job, prediction raster generation, artifact registration, private production configuration change, historical manifest rewrite, or production activation was performed.
