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
Projection and raster products consume the saved posterior representation and
must preserve the established no-interpolation, no-rescaling, and geometry
identity requirements.
