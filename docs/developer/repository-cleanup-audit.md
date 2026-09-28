# Repository cleanup audit

This release keeps reproducible implementation and historical diagnostics while
removing obsolete material from the normal user path. No model, inference, or
accepted scientific artifact is changed by this audit.

| Material | Classification | Rationale |
| --- | --- | --- |
| `scripts/submit_full_pipeline.sh` and `scripts/run_pipeline.R` | KEEP | Current single-command production entry points. |
| Stage, post-fit, structural, and reporting scripts | KEEP | Executable workflow contract and reproducibility surface. |
| `scripts/run_provenance_residency_audit.R` | KEEP | Required source-lineage and data-residency audit. |
| `scripts/run_validation_simplification_audit.R` | KEEP | Immutable accepted-run validation audit; it does not fit or copy observations. |
| `scripts/compare_spatial_support.R` | KEEP / DIAGNOSTIC | Historical support comparison remains useful for spatial-method diagnostics and is not a production stage. |
| `scripts/*.sh.example` | KEEP / TEMPLATE | Atlas deployment examples remain useful without embedding private paths. |
| `docs/deferred-development.md` | KEEP / REVISED | Future thermal sensitivity, input updates, and data minimization remain explicitly deferred. |
| Rendered Quarto pages under `docs/` | KEEP | Existing public-site artifacts and links remain part of the repository output. |
| `local/`, `outputs/`, and private production configuration | KEEP IGNORED | Execution-local or governed-environment material; not source release content. |
| Obsolete repair scripts, duplicate release notes, and stale TODO messages | NONE FOUND | No tracked item was demonstrably superseded without losing reproducibility or history. |

No files were removed, moved, or renamed. Historical terminology that remains
in model compatibility, host-normalization, or regression utilities describes a
real compatibility contract and is intentionally retained.
