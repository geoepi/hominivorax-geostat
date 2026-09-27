# Post-fit extraction contract

Post-fit extraction consumes the saved Stage 3A build and Stage 3B fit
artifacts. It does not refit the model or infer dates that are absent from the
Stage 2 temporal mapping.

The stack row map is the authority for distinguishing Tier 1 and Tier 2
likelihood rows. Predictor indices, latent-effect indices, source row IDs, and
model term names remain separate namespaces. Extraction helpers must preserve
the fitted family, exposure, response-training status, and source identifiers
when creating canonical reporting objects.

Random-effect summaries use the fitted internal summaries and retain the
component-specific meaning of each term: Tier 1 and Tier 2 spatial fields,
the copied Tier 1 field, temporal effects, administrative effects, and cattle
RW2 effects. Human-readable summaries must not be used to reconstruct INLA
initialization vectors; those come only from the explicit Stage 3B theta
artifact.

Every derived table records its source run and source artifact provenance.

Temporal extraction derives its expected timestep support from the authoritative
Stage 2 `temporal_mapping`. Both `week_steps` and `tier2_week` must contain the
same complete timestep support, with year/week values reconciling to that
mapping. A historical horizon length is not a universal extraction requirement.

Grouped SPDE extraction derives its expected dimensions from the Stage 3A mesh
vertex count and grouped field indices. Each Tier 1, Tier 2, and copied Tier 1
field must contain the complete mesh-node/group cross-product with contiguous,
consistent group levels and no duplicate pairs. Copy-field validation compares
canonical mesh-node/group support; it does not require unrelated internal INLA
random-effect IDs to match. The old 105-timestep/8-group values describe only
the historical production run and are not extraction-contract constants.

Projection and raster products consume the saved posterior representation and
must preserve the established no-interpolation, no-rescaling, and geometry
identity requirements.
