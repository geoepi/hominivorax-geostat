# Validation and acceptance

Fit health requires `fit$ok == TRUE`, mode status zero, finite summaries, ten expected fitted hyperparameters, and expected random-effect components. The runtime and module stack are recorded.

Tier 1 reports weighted PB-AUC, unweighted PB-AUC, continuous Boyce index, and same-week percentile diagnostics. Background locations are availability support and are not relabeled as true absences.

Tier 2 reports MAE, RMSE, Pearson correlation, Spearman correlation, calibration ratio, and terrestrial-area exposure semantics for held-out positive counts.

Projection requires exact reconstruction of fitted linear predictors within established tolerances. Raster QA checks direct cell placement, no interpolation or rescaling, geometry identity, and round-trip equality.

Post-fit reporting retains all ten hyperparameters, both SPDE range/SD pairs, copy coefficient, temporal precision terms, administrative precision, cattle RW2 precision, and negative-binomial dispersion/size. It writes canonical objects, tables, figures, rasters, manifests, and checksums. RPI is generated only for the new full-horizon potential-abundance stack after threshold and calibration gates pass.
