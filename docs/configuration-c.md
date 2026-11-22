# Configuration C

Configuration C is the revised development specification. It remains separate
from the frozen reference configuration and writes to the
`outputs/configuration_c/` namespace. The tracked examples do not change the
private production configuration or any existing model artifact.

The source and fixed-effect registry is
[`configuration-c-input-manifest.yml`](input-audits/2026-11-13/configuration-c-input-manifest.yml).
It fixes the observation checksum, ISO-week analysis window through 2026-W44,
the two SoilGrids rasters, weekly ERA5-Land pressure coverage, and the ordered
fixed-effect terms. It also retains the closed template-provenance comparison:
the current configured raster and the historical sidecar raster are different
binary files with equivalent values, NA mask, grid, and CRS; the matched
historical binary is tracked in the CDS repository. The observation archive
remains the full verified source; Stage 1's explicit endpoint filters records
after W44 from the analysis.

`clay`, `wv0010`, and `spressure` enter Tier 2 as additive linear terms. The
transformation is identity: clay remains in g/kg, `wv0010` remains in mapped
`10^-3 cm3 cm-3` units, and weekly surface pressure remains in kPa. Required
missing covariates fail with an audit instead of receiving an environmental
value from a different week. Pressure weeks are checked against the complete
ISO-week sequence by the Stage 1 dynamic-raster reader.

The structural model is unchanged: both likelihoods, row-specific family/link
mapping, SPDEs, weekly effects, administrative iid effect, copied Tier 1 field,
cattle RW2, censoring, and holdout settings remain as in the reference model.
The two existing temperature interactions remain; no new interactions are
added.

The example Stage 1 config still has placeholders for private study and
baseline covariate paths. Create a private copy and complete those paths before
any future Stage 1 execution. This implementation does not run preprocessing,
model fitting, or geographic prediction and does not qualify Configuration C
scientifically.
