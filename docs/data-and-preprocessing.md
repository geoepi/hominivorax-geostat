# Data and preprocessing

GitHub contains source code, portable configuration examples, tests, schema documentation, and public examples. Private observations, processed observations, fitted RDS objects, large production rasters, internal logs, and credentials remain outside the public repository on the execution environment.

Tracked `config/*.example.yml` files define portable defaults and schema. Ignored local operational files supply private paths. Command-line output overrides take precedence over configured output directories. Stage artifacts record resolved configuration and source paths.

The default `temporal.end_week: auto_last_complete_observation_week` first reads enough source data to avoid truncating observations at the legacy `study.end_date`, then resolves the endpoint from cleaned observations. For dated records, a week is complete when its seven-day epidemiological interval ends on or before the cleaned maximum date. Standardized year/week inputs are treated as complete weekly units. The resolved endpoint, raw maximum date, cleaned maximum date, excluded post-endpoint observations, and week count are recorded and propagated to Stage 2.

The canonical thinning key is `tier1.positive_cellweek_thinning`. With `enabled: true`, eligible positive records are sampled to one per year × epidemiological week × raster cell using the configured seed. All zero/background rows remain. Unselected positives are retained with cell, duplicate, outside-template, and checksum provenance. `enabled: false` retains all eligible positives.

Dynamic raster filenames must encode year and epidemiological week. The extraction index checks that every requested week has a source layer. Missing required weeks stop the workflow and write diagnostics; the workflow does not silently shorten the model horizon.
