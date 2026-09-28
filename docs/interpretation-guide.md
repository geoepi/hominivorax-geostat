# Interpretation guide

Tier 1 surfaces describe modeled detection/report occurrence under the observation-support design. A high value means the model ranks a supported location-week as more likely to produce a report, conditional on fitted covariates and random effects. It is not a prevalence estimate and background rows are not confirmed absences.

Tier 2 surfaces describe modeled positive-count intensity with terrestrial area as exposure. Interpret them alongside exposure, covariates, uncertainty, and validation diagnostics. A low observed count can reflect no report, low opportunity, or response-training policy rather than a confirmed biological zero.

An SPDE spatial random field is a smooth latent spatial effect. Its range describes approximate correlation distance and its standard deviation describes latent variation on the model scale. Weekly RW1 effects describe adjacent-week departures; the copied field is the Tier 1 spatial component transferred into Tier 2 through an estimated coefficient. Random-effect precision is inverse variance and is not a standard deviation.

Potential abundance is standardized intensity multiplied by nominal raster-cell area. RPI summarizes persistence above a calibrated threshold and converts continuous suitable duration to generations; report it with its threshold and temporal support.
