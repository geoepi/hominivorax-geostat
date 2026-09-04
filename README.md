# hominivorax-geostat

*Cochliomyia hominivorax* geostatistical model for biased sampling.

The repository also provides a configuration-driven preprocessing reference implementation. It converts point observations and spatial covariates into audited Tier 1, Tier 2, and prediction objects. Copy `config/preprocessing.example.yml` to the ignored `config/preprocessing.yml` for private operational inputs, or run `Rscript scripts/run_preprocessing_demo.R` for the synthetic demonstration. Operational surveillance data and exact coordinates remain private.

## Three-stage workflow

The workflow has three deliberate boundaries:

1. Stage 1 (`scripts/run_preprocessing.R`) performs canonical geostatistical preprocessing. Its `model_inputs.rds` artifact contains spatial support, mesh, canonical time fields, Tier 1/Tier 2/prediction rows, `admin_u`, and training-derived transformations.
2. Stage 2 (`scripts/prepare_joint_model.R`) prepares one statistical experiment from that artifact. It applies reporting censoring, deterministic validation holdouts, the Tier 2 zero-count policy, temporal grouping, a shared `admin_f` mapping, and Tier 2-fitted livestock RW2 features. Its `joint_model_inputs.rds` artifact is model-specific.
3. Stage 3A (`scripts/build_joint_inla.R`) deterministically constructs the INLA model assembly from Stage 2. It records SPDE objects, A matrices, stacks, formulas, priors, fit controls, and provenance but deliberately stops before fitting; fitted results remain outside Stage 2 and Stage 3A.

The Stage 3A shared-field prior follows the historical INLA specification exactly: `list(beta = list(prior = "normal", param = c(0.5, 0.2)))`. The configuration names `0.2` as `shared_field.beta_prior_precision` because INLA's normal-prior second parameter is precision, not standard deviation; the value is not converted.

Stage 2 choices are recorded in `config/joint_model.example.yml` and in the output metadata. The default reporting rule censors affected administrative units from epiweek 32 of 2025 when they reported before the cutoff but not afterward; holdouts sample only uncensored positive rows using stable identifiers and the configured seed; `tier2.zero_count_policy: exclude` removes zeros only from `response_training`; temporal indices are shared across all scopes; and livestock quantile bins are fitted from Tier 2 and reused for prediction.

The Stage 1 response contract is `tier1$Yi` for binary detections and `tier2$count` for polygon-week abundance counts. Stage 2 derives `response_observed`, `response_censored`, and `response_training` from those canonical fields without overwriting them.

## Supporting Information

This repository provides supporting information for:

*Disentangling Detection and Abundance to Infer Invasion Dynamics in New World Screwworm (in review)*

## External Links  
[Git Page](https://geoepi.github.io/hominivorax-geostat/): Website version of this repository       
  
  
[OSF Data Archive](https://osf.io/uvqmw/overview): Code and data archive on the Open Science Framework (OSF)   
  

## Repository Structure:  
  
```text
hominivorax-geostat/
|- R/                      # analysis and plotting functions
|- config/                 # example preprocessing configuration and host lookup
|- scripts/                # explicit preprocessing entry points and checks
|- preprocessing.qmd       # preprocessing workflow documentation
|- docs/                   # Rendered GitHub Pages
|- images/                 # Static images used by docs and examples
|- _quarto.yml             # Quarto site configuration
|- home.qmd                # Supporting information landing page
|- index.qmd               # Site index page
|- model.qmd               # Model description and example
|- response.qmd            # Construct bivariate response variable
|- simulation.qmd          # Simulation workflow and outputs
|- spatial_domain.qmd      # Spatial domain setup and diagnostics
|- README.md
|- hominivorax-geostat.Rproj
|- .gitignore

```
