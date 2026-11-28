# Atlas GeoStat canonical directory and product-discovery proposal

Audit date: 2026-11-27

## Observed layout

The eleven matching directories under /project/disease_ecology use three different roles today: canonical source and private configuration, development/validation checkouts, and data/output archives. The 37 GiB output tree already holds production runs, model artifacts, acceptance packages, and reporting products. The similarly named hominivorax-geostat-reporting directory is a 31 MiB Git checkout on feature/postfit-results-reporting, not a products directory. Writing rasters or reports into that checkout would mix generated files with source.

CHIME consumes the existing production_runs and postfit_acceptance roots. Its run adapter only discovers run directory IDs matching the timestamp plus 8-hex convention. The proposed W44 adoption ID adopt-original-refresh-w44-2026-adoption is invisible to that adapter. The acceptance adapter also expects a package linked to a recognized run.

## Recommended roles using current roots

| Role | Canonical location | Contents and contract |
| --- | --- | --- |
| Source | /project/disease_ecology/hominivorax-geostat | Canonical Git repository and workflow code. Future development worktrees should use the already existing /project/disease_ecology/worktrees area. |
| Private operations | /project/disease_ecology/hominivorax-geostat-config | Private production configuration, deployment identity, active-release pointer, and append-only activation events. |
| Execution | /project/disease_ecology/nws-geostat-output/production_runs | Immutable timestamp-shaped run directories containing each run manifest, statuses, logs, inputs, intermediates, and native stage outputs. Keep this root stable for CHIME and Slurm wrappers. |
| Fitted-model artifacts | /project/disease_ecology/nws-geostat-output/production_runs/model_registry | Immutable model-version artifact set plus a manifest. This matches the current PR #16 adoption contract; revise its copy behavior before routine refreshes create repeated multi-gigabyte copies. |
| Accepted products | /project/disease_ecology/nws-geostat-output/postfit_acceptance | Existing accepted package root for rasters, structural products, temperature-masked products, RPI products, figures, tables, QA, and reporting manifest. Preserve direct postfit_acceptance_* package discovery for CHIME. |
| Reporting source | /project/disease_ecology/hominivorax-geostat-reporting | Keep as a Git source checkout only. It is not a stable product directory. |

Do not add a new project-root directory for this proposal. The existing accepted-package root is the least disruptive product root discovered. The current reporting configuration has canonical_report_root set to null, so the stable accepted-product linkage still needs a defined contract.

## Current qualified-product discovery contract

Use a small, versioned active-release.yml at the existing private configuration root. It should identify the qualified release, without requiring an application to know a Slurm job ID, branch, worktree, or refresh date. Include:

- schema version, monotonically increasing generation, release ID, release type, and status;
- model ID, model-specification identity and SHA-256, observation release ID and SHA-256, analysis start/end, code commit, and configuration SHA-256;
- canonical fit path and SHA-256;
- one manifest entry per product class: prediction rasters, structural rasters, temperature-masked products, RPI products, figures/tables, and published metadata; each entry has path, checksum, size, media type, and analysis endpoint;
- qualification summary, required gate results, evidence-manifest path and SHA-256;
- previous release ID and rollback target.

The pointer should name one immutable model-release manifest under the run/registry tree and one immutable accepted product package under postfit_acceptance. Consumers read the pointer once, verify the referenced manifest and product checksums, then use those paths. Keep the existing per-run run_manifest.yml as operational history; it is not itself the active-product pointer.

PR #16 documents compare-and-swap activation with an expected generation and state hash plus append-only events. Use that mechanism only after the owner explicitly selects the active release. The existing private configuration and deployment manifest do not establish an unambiguous active fit, so do not initialize a pointer from them by inference.

## Filesystem and consumer compatibility

Do not use a symlink or atomic directory swap as the first product contract. The audit did not establish that filesystem rename semantics, symlink permissions, concurrent readers, and CHIME behavior have been qualified. A regular manifest avoids path replacement races and preserves immutable versioned locations. If a current symlink is later desired for legacy consumers, test replacement behavior and access rights on Atlas and update consumer code to follow the same contract.

CHIME currently reads run metadata and acceptance packages, not an active-release pointer. Before changing directory names, package roots, or the W44 run ID, update and qualify the CHIME adapter. A timestamp-shaped W44 ID is necessary for discovery, but adoption semantics must also avoid falsely reporting Prepare and Fit as performed by the adopted run. An acceptance package may report accepted products while the native run remains incomplete; preserve that distinction.

## Storage and layout controls

The current framework stages adoption artifacts under production_runs/model_registry/production-id by copying and rehashing the declared source files. It is safe and auditable, but a W44 copy of its four large stage artifacts alone adds about 9.93 GiB. Before routine adoption, revise the contract to allow immutable content-addressed references or another Atlas-qualified deduplication method. Do not assume hardlinks, reflinks, or symlinks work correctly without an implementation test. Keep one durable authoritative payload per model artifact identity, while recording every run's input/model identity in compact manifests.

Store run-specific intermediates in the run tree and accepted final reporting products in the existing acceptance root. Do not make a full copy of all reports and rasters into every run, registry, and reporting checkout. The product manifest should link each required product exactly once.

## Implementation order

1. Confirm the desired active W39/W44 status and use the completed W44 provenance reconciliation before any release publication.
2. Agree on release type and model-specification identity; use ROUTINE_REFRESH only when the approved specification hash is unchanged.
3. Define and qualify the artifact-reference/deduplication contract and checksum manifest.
4. Update CHIME to read the active pointer or the exact accepted-package contract, and to recognize adopted-fit lineage and run identifiers.
5. Define canonical report root behavior in production configuration while keeping the existing CHIME acceptance root stable.
6. Test a non-production manifest with all product classes and permissions; then perform a separately authorized production promotion.

This is a design only. No filesystem paths, configurations, code, run manifests, or active-release references were changed.

## Implementation disposition

The release framework keeps execution history in `production_runs`, accepted
packages in its existing `postfit_acceptance` sibling, and reporting source in
its own Git checkout. The registry is beneath `production_runs`. Existing
canonical payloads can be referenced by regular manifest paths and SHA-256;
payloads outside the canonical output root require a verified staged copy
before authorized publication. No symlink or directory-swap contract was
introduced. The active pointer remains under the private config root and is
not initialized from the observed W39 configuration.
