# Canonical Atlas runtime and spatial validation

This document is the operational record for the validated Atlas runtime used
by the Hominivorax-Geostat production and post-fit workflows. It complements
the phase-specific wrappers; it does not install packages, rebuild the
environment, or replace the module stack.

## Canonical module stack

Atlas production wrappers must establish this environment explicitly before
calling `Rscript`:

```bash
module purge
module load udunits proj geos/3.12.1 gdal/3.8.5 \
  intel-oneapi-mkl/2023.2.0 r/4.4.3
```

The validated runtime record is:

| Component | Validated value |
| --- | --- |
| R | 4.4.3 |
| INLA | 25.9.19 |
| terra | 1.7.78 |
| sf | 1.0.21 |
| Matrix | 1.7.0 |
| User library | `/home/john.humphreys/R/x86_64-pc-linux-gnu-library/4.4` |

Wrappers should print the hostname, loaded modules, `which R`, `R --version`,
`.libPaths()`, and the versions of `INLA`, `Matrix`, `terra`, and `sf` before
substantive work. The spatial wrappers should also print
`sf::sf_extSoftVersion()` and the relevant `terra` GDAL/PROJ details.

## Operational lessons

1. **The login-node shell is not the canonical runtime.** Modules may be
   absent there even though the compute environment is valid. A failed module
   lookup on a login node is not evidence that the Atlas production runtime is
   unavailable.
2. **Spatial work should be tested inside an interactive compute allocation**
   with the module stack loaded there before production submission. Use the
   site-approved interactive allocation command, start a shell on the
   allocated compute node, load the canonical stack above, and run the spatial
   smoke checks in that same environment.
3. **Do not infer that `terra`/`sf` are missing just because the current shell
   cannot load them.** First recover the known-good module stack and
   `.libPaths()` inside the compute allocation, then check package discovery
   and versions.

## Interactive validation workflow

The exact partition, account, and time limits are site policy. Use the
site-approved equivalent of the following workflow; do not copy login-node
module state into production:

```bash
# Request an interactive compute allocation using site-approved flags.
salloc --account=disease_ecology --time=00:30:00 --cpus-per-task=2 --mem=8G
srun --pty bash

module purge
module load udunits proj geos/3.12.1 gdal/3.8.5 \
  intel-oneapi-mkl/2023.2.0 r/4.4.3

hostname
module list
which R
Rscript --vanilla -e '
  cat("R=", R.version.string, "\n", sep = "")
  print(.libPaths())
  for (p in c("INLA", "Matrix", "terra", "sf")) {
    cat(p, "=", if (requireNamespace(p, quietly = TRUE))
      as.character(utils::packageVersion(p)) else "unavailable", "\n", sep = "")
  }
  if (requireNamespace("sf", quietly = TRUE)) print(sf::sf_extSoftVersion())
  if (requireNamespace("terra", quietly = TRUE)) print(terra::gdal())
'
```

The interactive check should include a small `terra` read/write round trip and
an `sf` read/transform operation using a non-production temporary directory.
Run the relevant package tests there before submitting a production wrapper.
The successful compute-node check, not a login-node shell check, is the
evidence used to interpret package availability.

## GEOS ABI observation

The R spatial packages were compiled against GEOS 3.12.1, while runtime
resolution may report GEOS 3.14.0. This warning has been observed in the
validated environment; Phase 2/3 production execution and spatial round-trip
QA passed. Do not rebuild or alter the environment solely to remove this
warning without separate validation.

This is a provenance warning, not an automatic acceptance failure. Record the
observed compile/runtime versions in the job metadata when available.

## Environment boundaries and wrapper requirements

The canonical reference artifacts remain separate from the runtime record:

* fit: `/project/disease_ecology/nws-geostat-output/joint_inla_fit/joint_model_fit.rds`;
* Phase 2: `/project/disease_ecology/nws-geostat-output/joint_inla_fit/prediction_projection_20725437/`;
* Phase 3: `/project/disease_ecology/nws-geostat-output/joint_inla_fit/raster_surfaces_20725437/`;
* reporting output: `/project/disease_ecology/nws-geostat-output/postfit_reporting/20725437/`.

Atlas wrappers must establish their environment explicitly rather than rely on
an inherited login shell. They must not install packages or change module
versions as part of a reporting run. See the [production workflow](production-workflow.md),
[post-fit acceptance protocol](post-fit-acceptance.md), and
[post-fit reporting architecture](post-fit-reporting.md) for the workflow
boundaries that use this runtime.
