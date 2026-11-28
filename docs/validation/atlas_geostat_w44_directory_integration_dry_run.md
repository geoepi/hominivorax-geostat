# W44 directory and release integration dry-run

Date: 2026-11-27 (America/Chicago)

## Result

`PASS_WITH_WARNINGS` for read-only adoption validation. This is a no-job
integration result, not production activation or a completed W44 release.

- Model: `ORIGINAL_REFRESH_W44_2026`
- Release class: `ROUTINE_REFRESH`
- Model specification ID: `original_joint_inla_v1`
- Data release ID: `2026-11-13`
- Analysis period: `2022-W01` through `2026-W44`
- Specification SHA-256: `812fd38b9c5c41874ffbb982bf1c42bc3b58c30d3a94641970467587760421e8`
- Comparison specification ID and digest: `original_joint_inla_v1`, same digest
- Historical source Fit job: `21355414` (provenance only)
- Fit SHA-256: `e9409c37ca88dedb0441d65c184c2c5cae9ca1dcf923aeb52db03bf8e451605c`
- Proposed execution run ID: `20261128_020837_882bfc5b` (UTC timestamp plus eight hexadecimal characters)
- W44 request SHA-256: `cbbdf767cc4f1bd00250a51893b2c57837f2fcc37178b368bd99ed7aa3907107`

The descriptor was calculated with the canonical JSON/SHA-256 helper. It
records the audited frozen formula and fixed-effect order, two likelihoods,
random-effect and temporal structure, W44 prior settings, Stage 1
transformation contract, and reporting product semantics. The source-commit
reconciliation confirms the `R`, `scripts`, `config`, and `tests` trees
match between fit launch and metadata commits; the differences are archived
documentation and evidence. The formula regeneration audit passed against the
frozen original formula. The small 2,376-byte fit metadata file records ten
hyperparameters and the effective negative-binomial `pc.mgamma` prior.

The scientific evidence references are:

- Formula audit: `docs/archive/original-refresh-w44-2026/original_refresh_formula_audit_adoption_v2.csv`, SHA-256 `123cdb4c74a0db1d3427784999efaf6d2458f79b29da4dedc7079705a01c72da`.
- Stage 1 transformation audit: the W44 `stage1_reuse_audit.csv`, SHA-256 `43bb8accf5af8606f344bfe51def925a7ccebe14d06847bd1f83c5eaf6b38aea`.
- Stage 2 config: `joint_model.yml`, SHA-256 `22aafb5781a226d52decd63ff8a4cbf04e1ecb9515fe2370f7607c3bb27da0a5`.
- Stage 3A config: `joint_inla.yml`, SHA-256 `be68cc2bc3417c48144be3761fda966df6b4a2bcc4525a477a4083c2f8e86484`.
- Fit-launch/runtime-metadata reconciliation: `docs/archive/original-refresh-w44-2026/original_refresh_w44_2026_source_provenance_reconciliation_v1.json`, SHA-256 `8792892040e2a44ad4702536520cd4bed6e38b50308d31e966a3470c5fa118fc`.

## Dry-run findings

- Runtime profile: `atlas-r44-spatial-v1`, R 4.4.3; spatial preflight passed.
- Adoption validation: `PASS_WITH_WARNINGS`.
- Planned stages: adoption validation followed by Post-fit.
- Prepare jobs: 0.
- Fit jobs: 0.
- Post-fit jobs submitted: 0.
- Total scheduler jobs submitted: 0.
- Artifact registration or large artifact copies: 0.
- New run directory: absent.
- W44 model registry destination: absent.
- Accepted package: not created; canonical destination remains `/project/disease_ecology/nws-geostat-output/postfit_acceptance`.
- Active-release pointer: absent; it was not initialized.
- Production configuration SHA-256 after the dry-run remains `0667d4ab1c6780da0ce435bd3a7e67fa83a2b90d0c8cc8b4658909d3d4f6ea49`.
- Project-root Geostat directory count after the dry-run: 11, unchanged from the audit.
- Cleanup actions: 0.

The dry-run reports the current production configuration as incompatible with
the W44 candidate. That is expected: the observed private configuration is
still the W39 deployment. It remains a blocker to any production dispatch or
activation. The no-job request planned a Post-fit stage but did not submit it.

## Limitations and warnings

The W44 source artifacts are outside canonical `production_runs`. The
registration code would require one verified staged copy before an authorized
release can stop depending on the development output tree. That copy was not
performed because this task prohibits large W44 copies. The dry-run therefore
does not establish a canonical W44 model artifact reference, accepted
products, or a rollback set.

The compact fit metadata does not contain the complete model signature; the
2.63 GiB Stage 3A RDS was not loaded. The digest was reconstructed from the
checksummed model configs, frozen-formula audit, transformation audit, fit
metadata prior record, and reporting contract. The historical qualified
record does not carry a previously issued model-specification digest, so the
comparison digest is a reproducible descriptor of the audited
`original_joint_inla_v1` reference rather than a hash read from an existing
release manifest. A future routine request should preserve the descriptor and
evidence reference in an immutable qualified release record.

The current Atlas environment emitted the local-RTC notice and GEOS
compile/runtime-version warnings; the provenance reconciliation JSON also
has no final newline. These are recorded warnings, not failed scientific
checks.

No production configuration, active pointer, W44 artifact, run directory,
accepted package, or project-root directory was changed or created. No
Prepare, Fit, or Post-fit job, raster, cleanup, or activation was performed.

## Regression validation

The change is Category D because it changes release metadata, artifact storage
and production discovery behavior.

- HGE canonical command: `Rscript tests/run_tests.R`.
- Environment: Atlas `atlas-r44-spatial-v1`, R 4.4.3, INLA 25.9.19; runtime preflight passed.
- Result: 37 executed, 21 PASS, 16 WARN, 0 FAIL, 0 SKIP; runner exit status 0.
- Warnings included the local-RTC notice, GEOS compile/runtime version notices,
  existing INLA and geometry deprecations, and expected negative-path
  diagnostics. The changed release test file warned only for the local-RTC
  notice.
- CHIME focused adapter suite: 32 passed (previously run in the CHIME worktree
  with its documented virtual environment and `PYTHONPATH=src`). The complete
  CHIME suite was not run because only the Geostat adapter surface changed.
- Final staged diff check passed for both HGE and CHIME changes.
