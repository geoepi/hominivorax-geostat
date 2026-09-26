# Stage 1 contract

`scripts/run_preprocessing.R` owns cleaning, spatial support, the common time index, Tier 1/Tier 2/prediction construction, transformations, covariate extraction, temporal provenance, and Tier 1 thinning provenance. It fails on missing required dynamic weeks and does not silently truncate the requested temporal domain.
