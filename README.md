# hominivorax-geostat

*Cochliomyia hominivorax* geostatistical model for biased sampling.

The repository also provides a configuration-driven preprocessing reference implementation. It converts point observations and spatial covariates into audited Tier 1, Tier 2, and prediction objects. Copy `config/preprocessing.example.yml` to the ignored `config/preprocessing.yml` for private operational inputs, or run `Rscript scripts/run_preprocessing_demo.R` for the synthetic demonstration. Operational surveillance data and exact coordinates remain private.

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
