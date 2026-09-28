# Model workflow overview

## Ecological purpose

Hominivorax-Geostat estimates where New World screwworm is detected and how much positive-count intensity is supported across space and time. Surveillance records are informative but uneven: a report can indicate detection, while a missing report does not establish absence. The model therefore represents detection and abundance as related, distinct processes.

## Input observations

Input records contain case or report information, a date or epidemiological week, spatial coordinates, and host information. Stage 1 standardizes dates, hosts, coordinates, administrative units, spatial support, covariates, and the common epidemiological-week index. Records removed during cleaning remain in auditable exclusion files.

## Tier 1: detection and reporting occurrence

Tier 1 is a binary detection model. Positive records are compared with availability/background support generated across the analysis domain and week sequence. Background rows are not confirmed biological zeros or true absences; they represent locations where a detection could have been observed under the support design.

The accepted production behavior retains all Tier 1 zero/background rows. When enabled, positive observations are thinned to one representative per year × epidemiological week × raster cell using seed `1976`; unselected positives, including positives outside the template, are retained in a traceable exclusion artifact. A broad spatial random field, weekly random-walk temporal effect, administrative effect, and fixed detection/reporting covariates describe variation in detection opportunity and reporting.

## Tier 2: positive-count intensity

Tier 2 aggregates observations to spatial polygons and epidemiological weeks. Its response is the positive count, with terrestrial area used as exposure. Polygon-weeks with no observed count are support rows and are not automatically interpreted as biological zeros; the configured response-training policy determines which rows enter the likelihood.

Tier 2 includes its own spatial random field, the copied Tier 1 spatial field, a weekly temporal effect, a cattle random-walk effect, environmental covariates and interactions, and livestock fixed effects. This separates local abundance intensity from the observation/reporting process while allowing the two processes to share broad spatial structure.

## Joint structure and prediction

Tier 1 and Tier 2 are assembled into one joint model with binomial and negative-binomial likelihoods, respectively. The copied Tier 1 field lets Tier 2 borrow broad spatial information learned from detections while the Tier 2 field remains independent.

The prediction grid covers the supported raster cells and the same intended epidemiological-week domain as both tiers. The default endpoint is the last complete week represented by the cleaned observation data; an explicit week or date can be supplied for a reproducible override. Missing dynamic covariate weeks stop preprocessing with a coverage diagnostic. Posterior component projection produces Tier 1 detection probability and Tier 2 intensity surfaces. Raster reconstruction assigns values directly to source cell IDs; it does not interpolate, rescale, or change geometry.

## Potential abundance and RPI

`potential_abundance` is the accepted standardized reporting quantity:

```text
Tier 2 intensity plugin × nominal raster-cell area
```

It is useful for comparing standardized potential across cells, but it is not a direct posterior expected count for every partial or coastal cell. RPI uses the accepted threshold-calibration procedure, maximum continuous suitable duration, conversion from weeks to generations, and historical four classes. A new full-horizon RPI must use the new full-horizon potential-abundance stack.

## Validation

Tier 1 validation evaluates ranking of presences against background support using weighted and unweighted PB-AUC, continuous Boyce index, and same-week percentile diagnostics. Tier 2 validation evaluates held-out positive-count prediction using MAE, RMSE, Pearson and Spearman association, calibration ratio, and terrestrial-area exposure semantics. These metrics do not turn background into confirmed absence.
