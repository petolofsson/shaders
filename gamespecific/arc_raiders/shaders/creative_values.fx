// creative_values.fx — tune here
// YOUVAN / OPENDRT : 0 = passthrough, 100 = full effect (no useful negative)
// ZONE / CHROMA    : -100 to +100 — negative flattens contrast / desaturates
// filmic: YOUVAN_STRENGTH 100  OPENDRT_STRENGTH 100  ZONE_STRENGTH 15–25  CHROMA_STRENGTH 10–20

#define YOUVAN_STRENGTH    0  // hue correction toward neutral
#define OPENDRT_STRENGTH   0  // display tone curve
#define ZONE_STRENGTH      0  // tonal contrast
#define CHROMA_STRENGTH  100  // color lift
