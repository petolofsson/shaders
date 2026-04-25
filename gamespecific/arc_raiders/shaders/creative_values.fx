// creative_values.fx — tune here
// HERMITE : 0 = passthrough, 100 = full effect
// ZONE / CHROMA : -100 to +100 — negative flattens contrast / desaturates
// filmic: HERMITE_STRENGTH 50–100  ZONE_STRENGTH 15–25  CHROMA_STRENGTH 10–20

#define HERMITE_STRENGTH  50  // display-referred Hermite S-curve contrast (OKLab L)
#define ZONE_STRENGTH     25  // tonal contrast
#define CHROMA_STRENGTH   15  // color lift
