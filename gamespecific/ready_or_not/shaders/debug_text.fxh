// debug_text.fxh — 3×5 pixel font for effect debug overlays
// Usage: col = DrawLabel(col, pos, float(BUFFER_WIDTH)-17.0, y0, c0,c1,c2,c3, tint);
// Each char is 3px wide, 1px gap between chars → 4px stride, 15px total for 4 chars.
// Slot y0: slot * 8 + 4  (5px tall label + 3px gap)

uint _FP(uint ch)
{
    if (ch == 56u) return 31727u; // 8
    if (ch == 49u) return 29842u; // 1
    if (ch == 50u) return 31183u; // 2
    if (ch == 51u) return 29647u; // 3
    if (ch == 52u) return  5101u; // 4
    if (ch == 53u) return 29671u; // 5
    if (ch == 54u) return 31719u; // 6
    if (ch == 55u) return  4687u; // 7
    if (ch == 65u) return 23530u; // A
    if (ch == 67u) return 14627u; // C
    if (ch == 68u) return 27502u; // D
    if (ch == 69u) return 31207u; // E
    if (ch == 71u) return 15203u; // G
    if (ch == 72u) return 23533u; // H
    if (ch == 76u) return 31012u; // L
    if (ch == 77u) return 23549u; // M
    if (ch == 78u) return 23421u; // N
    if (ch == 79u) return 11114u; // O
    if (ch == 80u) return 18862u; // P
    if (ch == 82u) return 23470u; // R
    if (ch == 83u) return 25251u; // S
    if (ch == 90u) return 30863u; // Z
    if (ch == 48u) return 31599u; // 0
    if (ch == 57u) return  5103u; // 9
    if (ch == 46u) return  8192u; // .
    return 0u;
}

float4 DrawLabel(float4 col, float2 pos, float x0, float y0,
                 uint c0, uint c1, uint c2, uint c3, float3 tint)
{
    if (pos.x < x0 || pos.x >= x0 + 15.0 || pos.y < y0 || pos.y >= y0 + 5.0)
        return col;
    uint lx   = uint(pos.x - x0);
    uint ly   = uint(pos.y - y0);
    uint ci   = lx / 4u;
    uint cx   = lx % 4u;
    if (cx >= 3u) return col;
    uint ch   = ci == 0u ? c0 : ci == 1u ? c1 : ci == 2u ? c2 : c3;
    uint bits = (_FP(ch) >> (ly * 3u)) & 7u;
    if ((bits >> (2u - cx)) & 1u)
        return float4(tint, 1.0);
    return col;
}

// Draw float [0,1] as "X.XX" (4 chars, 15px wide). Requires glyphs '0','9','.'.
float4 DrawFloat(float4 col, float2 pos, float x0, float y0, float v, float3 tint)
{
    float sv  = saturate(v);
    uint  tens = uint(sv * 10.0);
    uint  c0   = (tens >= 10u) ? 49u : 48u;
    uint  d1   = tens % 10u + 48u;
    uint  d2   = uint(sv * 100.0) % 10u + 48u;
    return DrawLabel(col, pos, x0, y0, c0, 46u, d1, d2, tint);
}
