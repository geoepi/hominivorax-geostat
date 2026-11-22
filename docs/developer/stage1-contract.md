# Stage 1 contract

`scripts/run_preprocessing.R` owns cleaning, spatial support, the common time index, Tier 1/Tier 2/prediction construction, transformations, covariate extraction, temporal provenance, and Tier 1 thinning provenance. It fails on missing required dynamic weeks and does not silently truncate the requested temporal domain.

Configuration C supplies a versioned input manifest. Stage 1 resolves its
registered static and weekly sources into the existing extraction interface,
verifies the approved observation SHA-256 before and after reading, records
source units and transformation metadata, and fails with a missingness audit
when a required registered covariate is non-finite. The explicit C endpoint is
2026-W44; later source observations remain in the source archive.
