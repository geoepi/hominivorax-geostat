# W44 Existing-Fit Adoption Dry-Run

Observed on 2026-11-27 22:43:03 UTC under the Atlas `atlas-r44-spatial-v1` profile (R 4.4.3).

## Result

- Adoption validation: **PASS_WITH_WARNINGS**.
- Scheduler submissions: **0** Prepare, **0** Fit, **0** Post-fit.
- Artifact registration: **not performed**.
- Production activation: **not performed**.
- Output overwrite: **none**; after the run, the proposed run root and registry destination were both absent.
- Active-release pointer: **not initialized**.
- Exit status: **0**.

The request has `dispatch_authorized: false`. This invocation used `--mode dry-run`; it validated adoption and printed the single intended Post-fit command without executing it. The completed W44 fit was reused as an input and was not refit.

## Request and source identity

- Request: `docs/archive/original-refresh-w44-2026/original_refresh_w44_2026_refresh_request.yml`
- Request SHA-256: `58b0f921944789c80feebc915b8227999c2a81c8d7fbef08659f73aac5111367`
- Versioned qualification evidence: `docs/archive/original-refresh-w44-2026/original_refresh_w44_2026_production_manifest_v2.json`
- Evidence SHA-256: `f7799eb0220bafb7b9915b1cacda1ad5eb6a7df12bd4461a2a26cb93db6dafdc`
- Original historical JSON SHA-256 retained: `eed2d7cda3d8aa562f545b9d9e423e8d3495481d4e2f39626cd92a3da17c9786`
- Input observations SHA-256: `784168081cc1d3206f3537b8731994cbfc34be15be7c515fe06710d4ea9bdaac`
- Resolved horizon: `2022-W01` through `2026-W44` (252 weeks).
- Active production configuration: SHA-256 `0667d4ab1c6780da0ce435bd3a7e67fa83a2b90d0c8cc8b4658909d3d4f6ea49`; compatibility with the W44 candidate reported **FALSE**.

## Verified artifacts

| Stage | SHA-256 |
| --- | --- |
| Stage 1 model inputs | `64571f7b3a7aa59625cbe788d10ce8f149f1b53b8015efcabceed99dcc25f9af` |
| Stage 2 model inputs | `1a09657781f6989154d331a7467c6dbc28d7be8011991709d3259e94eac95fe0` |
| Stage 3A INLA build | `74dc75e578474712cc06c62634b50c26631779003c8e804bbd2f7ff62bbb74a5` |
| Stage 3B saved fit | `e9409c37ca88dedb0441d65c184c2c5cae9ca1dcf923aeb52db03bf8e451605c` |
| Fit metadata | `60deea11ed39f059402c08ce2f75bf4ec2af74c1198bde1d1866c1f92b0d3599` |
| Adoption artifact inventory overlay | `222487eaf50a4365399504380735df1d55d1538c1e26ac2e5069b8d85f5c043e` |
| Normalized formula audit | `123cdb4c74a0db1d3427784999efaf6d2458f79b29da4dedc7079705a01c72da` |
| Formula-audit duplicate reconciliation | `b0156d9c1a6bfe4dbbc5a04ca87552f7123e38ac21451791bcd3f94d1b31abeb` |
| Fit-source reconciliation | `8792892040e2a44ad4702536520cd4bed6e38b50308d31e966a3470c5fa118fc` |

The W44 artifact inventory resolved the original Stage 1–3B paths. All four artifact hashes matched the declared inventory, and direct stage lineage, configuration identity, observation release, and the original 16-coefficient formula passed adoption validation. The formula audit has one `fit_not_executed=FALSE` row in the adoption-only view. The source audit and source inventory remain unchanged; both original duplicate rows and their detail strings are recorded in the duplicate reconciliation file.

## Planned Post-fit destination

The dry-run reported the run root as:

`/project/disease_ecology/nws-geostat-output/production_runs/adopt-original-refresh-w44-2026-adoption`

The intended Post-fit job uses the production orchestration profile: account `disease_ecology`, partition `bigmem`, 4 CPUs, 64 GB memory, 12 hours, no Slurm dependency on historical fit job `21355414`. The fit job ID is recorded as provenance only. The planned sequence and per-stage output paths are in [the Post-fit execution plan](original_refresh_w44_2026_postfit_execution_plan_v1.json).

## Warnings and limits

- Atlas spatial runtime preflight passed. The installed `sf`/`terra` libraries emitted existing GEOS compile-time/runtime version warnings.
- The host emitted its configured local-RTC time-zone warning.
- `readLines()` warned that the source-provenance reconciliation JSON has no final newline. The record checksum and content validation passed; no scientific or lineage validation was skipped.
- The active W39 production configuration is not compatible with the W44 candidate. This is a release/activation boundary, not a failed W44 artifact identity check.
- No Post-fit products or prediction rasters were generated in this dry-run. No production files or configuration were changed.
