// creative_values.fx — tune here
// YOUVAN / OPENDRT : 0 = passthrough, 100 = full effect (no useful negative)
// ZONE / CHROMA    : -100 to +100 — negative flattens contrast / desaturates
// filmic: YOUVAN_STRENGTH 100  OPENDRT_STRENGTH 100  ZONE_STRENGTH 15–25  CHROMA_STRENGTH 10–20

#define YOUVAN_STRENGTH   50  // hue correction toward neutral
#define HERMITE_STRENGTH 100  // display-referred Hermite S-curve contrast (OKLab L)
#define ZONE_STRENGTH     25  // tonal contrast
#define CHROMA_STRENGTH   15  // color lift
