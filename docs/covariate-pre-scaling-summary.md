# Pre-scaling summary statistics for model covariates

Summary statistics are calculated from the raw covariate fields in the accepted Stage 1 `prediction_grid` immediately before model transformation. Dynamic climate covariates are summarized across all finite cell-week values in the accepted horizon; static covariates are summarized once per supported cell without weekly duplication. Missing static cell values are excluded.

| Variable | Mean | Median | Minimum | Maximum |
|---|---:|---:|---:|---:|
| Minimum temperature | 14.071 | 17.248 | -31.226 | 31.146 |
| Soil moisture | 0.282 | 0.300 | 0.000 | 0.662 |
| Relative humidity | 47.362 | 49.805 | 0.402 | 89.773 |
| Leaf area index | 1.622 | 1.702 | 0.000 | 4.085 |
| Cattle density | 16.198 | 7.406 | 0.000 | 434.272 |
| Pig density | 5.862 | 0.292 | 0.000 | 1,258.087 |
| Sheep density | 1.663 | 0.270 | 0.000 | 155.352 |
| Horse density | 128.337 | 55.271 | 0.000 | 22,219.629 |
| Goat density | 1.700 | 0.175 | 0.000 | 150.407 |
| Road density | 367.157 | 147.669 | 0.000 | 32,555.126 |
| Nighttime illumination | 3.396 | 0.000 | 0.000 | 63.000 |

The model-field mapping is: minimum temperature `mintemp`, soil moisture `soilmoist`, relative humidity `rhum`, leaf area index `leafarea`, cattle `cattle`, pigs `pigs`, sheep `sheep`, horses `horses`, goats `goats`, road density `road_density`, and nighttime illumination `night_illumination`.

Pre-scaling verification: `estimate_transformations()` records transformation parameters from the Stage 1 `tier2` training table, and `apply_transformations()` is then applied to the raw Tier 1, Tier 2, and prediction-grid fields. The summarized fields above are therefore upstream of the generated dynamic `*_z`, static `*_log1p`, and livestock RW2 midpoint fields. The prediction grid contains 15,899 supported cells over 133 weeks (2,114,567 cell-weeks); all four dynamic covariates have 2,114,567 finite values and no missing values. Static finite-cell counts are cattle 15,896, pigs 15,897, sheep 15,896, horses 15,839, goats 15,897, road density 15,899, and nighttime illumination 15,899.

Units are not shown because the accepted preprocessing configuration and artifact metadata do not establish unambiguous units for every covariate.

Source: existing pre-scaling values from the accepted Stage 1 artifact `/project/disease_ecology/nws-geostat-output/production_runs/20260928_235356_d2a2ff96/stage1/model_inputs.rds`, run `20260928_235356_d2a2ff96`, horizon `2024-W01`–`2026-W29`, manifest repository commit `d2a2ff96766971416b41e00123b46ddbf1906322`.
