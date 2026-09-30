```mermaid
flowchart TD

    %% ---------------- INPUTS ----------------
    subgraph INPUTS["1. Input Data"]
        A["<b>Confirmed NWS infestation records</b><br/>• Location, date, host"]
        B["<b>Climate & vegetation covariates</b><br/>• Temperature, soil moisture, RH, LAI"]
        C["<b>Livestock host-density covariates</b><br/>• Cattle, horses, pigs, sheep, goats"]
        D["<b>Observation-process covariates</b><br/>• Road density, nighttime illumination"]
    end

    %% ---------------- PREPROCESSING ----------------
    subgraph PREP["2. Observation & Covariate Preprocessing"]
        E["<b>Surveillance preprocessing</b><br/>• Deduplicate same-location/day<br/>• Assign epidemiological week<br/>• Censor post-reporting jurisdictions"]
        F["<b>Covariate harmonization</b><br/>• Albers Equal-Area projection<br/>• Common 25 × 25 km analysis grid<br/>• Weekly climate aggregations"]
    end

    A --> E
    B --> F
    C --> F
    D --> F

    %% ---------------- SPATIAL SUPPORT ----------------
    subgraph SPACE["3. Spatial Discretization"]
        G["<b>Triangulated SPDE mesh</b><br/>Common continuous spatial support"]
        H["<b>Tier 1 quadrature points</b><br/>Detections + mesh-vertex background"]
        I["<b>Dual-mesh neighborhoods</b><br/>Tier 2 count aggregation + area exposure"]
        J["<b>Spatiotemporal replication</b><br/>Mesh replicated across epi-weeks"]
    end

    E --> G
    F --> G
    G --> H
    G --> I
    H --> J
    I --> J

    %% ---------------- JOINT MODEL ----------------
    subgraph MODEL["4. Joint Bayesian Hierarchical Model"]
        K["<b>Tier 1: Observation process</b><br/>• Bernoulli presence–background likelihood<br/>• Northward gradient + accessibility<br/>• Administrative iid + spatial field"]
        L["<b>Tier 2: Infestation-intensity process</b><br/>• Negative Binomial conditional counts<br/>• Climate + livestock covariates<br/>• Spatial field + temporal effects"]
        M["<b>Shared spatial effect</b><br/>Scaled copy of Tier 1 field"]
        N["<b>Joint Bayesian inference</b><br/>Integrated Nested Laplace Approximations (INLA)"]
    end

    J --> K
    J --> L
    K -.->|Copied & scaled| M
    M -.-> L
    K --> N
    L --> N

    %% ---------------- MODEL OUTPUTS ----------------
    subgraph OUTPUTS["5. Reconstructed Model Outputs"]
        O["<b>Detection probability</b><br/><i>P(detection | occurrence)</i>"]
        P["<b>Latent infestation intensity</b><br/>Underlying infestation counts"]
        Q["<b>Weekly reconstructed surfaces</b><br/>Spatiotemporal predictions"]
        R["<b>Ecological summaries</b><br/>Potential abundance & suitability"]
    end

    N --> O
    N --> P
    P --> Q
    P --> R

    %% ---------------- POST HOC ----------------
    subgraph POST["6. Post Hoc Invasion Analyses"]
        S["Invasion-front position & velocity"]
        T["Detection-to-front lag"]
        U["Colonization distance & persistence"]
        V["Reproductive Persistence Index"]
        W["Density-dependent population growth"]
        X["Clustering & forward propagation"]
    end

    Q --> S
    Q --> T
    Q --> U
    Q --> V
    Q --> W
    X --> Y

    %% ---------------- SYNTHESIS ----------------
    Y(["<b>Ecological Interpretation of Invasion Dynamics</b>"]):::terminal

    S --> Y
    T --> Y
    U --> Y
    V --> Y
    W --> Y
    X --> Y

    %% ---------------- STYLING ----------------
    classDef default font-family:sans-serif,font-size:12px;
    classDef terminal fill:#2d3748,stroke:#1a202c,stroke-width:2px,color:#fff,font-size:13px;
```

## Details

1. **Input data.** The analysis integrates confirmed NWS infestation detections with environmental, host-density, and observation-process covariates[cite: 1]. Surveillance records provide the response data, whereas climate, vegetation, livestock density, road density, and nighttime illumination provide predictors for the ecological and observation components of the model[cite: 1].
2. **Observation and covariate preprocessing.** Duplicate surveillance records occurring at the same geographic location on the same day are removed, and detections are assigned to epidemiological weeks[cite: 1]. Locations are not spatially thinned[cite: 1]. Spatial covariates are transformed to an Albers Equal-Area coordinate reference system and harmonized to a common 25 × 25 km analysis grid; temporally varying environmental covariates are summarized to weekly values[cite: 1].
3. **Spatial discretization.** A triangulated SPDE mesh defines the common spatial support for the hierarchical model[cite: 1]. Mesh vertices serve as integration or background locations for the Tier 1 presence–background likelihood, while the corresponding dual-mesh natural neighborhoods define the spatial units used to aggregate counts and calculate geographic exposure in Tier 2[cite: 1]. The spatial support is replicated through epidemiological time[cite: 1].
4. **Joint Bayesian hierarchical model.** Tier 1 represents the observation process and estimates the probability that an infestation is detected and reported[cite: 1]. Tier 2 represents latent infestation intensity and models counts conditional on detection[cite: 1]. Separate spatial and temporal effects are estimated for the two processes, while a scaled copy of the Tier 1 spatial field is included in Tier 2 to account for spatial structure associated with surveillance[cite: 1].
5. **Reconstructed model outputs.** Joint model fitting produces estimates of detection probability and latent infestation intensity through space and time[cite: 1]. These estimates are projected to weekly spatial surfaces and form the basis for subsequent estimates of potential abundance and reproductive persistence[cite: 1].
6. **Post hoc invasion analyses.** Weekly reconstructed surfaces are used to quantify invasion-front position and velocity, lag between reported detections and the estimated front, colonization distance and persistence, the Reproductive Persistence Index, density-dependent population growth, and the relationship between local clustering and subsequent forward propagation[cite: 1].