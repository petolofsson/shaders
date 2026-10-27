// Current source-luma observations for the lift consumer only.
// Existing smoothed statistics and their update rates remain separate.
float4 CurrentLiftObservationPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float mass = 0.0;
    [loop] for (int b = 0; b < HIST_BINS; b++)
        mass += DecodeLumHistFraction(tex2Dlod(LumHistRaw, float4((float(b)+0.5)/float(HIST_BINS),0.5,0,0)).r);
    float cumulative = 0.0, p10 = 0.10, p25 = 0.25, p50 = 0.50, p90 = 0.90;
    float4 locked = float4(0,0,0,0);
    float best = 0.0, mode = 0.5 / float(HIST_BINS);
    [loop] for (int b = 0; b < HIST_BINS; b++)
    {
        float fraction = DecodeLumHistFraction(tex2Dlod(LumHistRaw,
            float4((float(b)+0.5)/float(HIST_BINS),0.5,0,0)).r) / max(mass,1e-5);
        float previous = cumulative;
        cumulative += fraction;
        float inv = fraction > 0.0 ? 1.0 / fraction : 0.0;
        float4 targets = float4(0.10,0.275,0.50,0.90);
        float4 values = (float(b)+saturate((targets-previous)*inv)) / float(HIST_BINS);
        float4 take = step(targets,cumulative) * (1.0-locked);
        p10=lerp(p10,values.r,take.r); p25=lerp(p25,values.g,take.g);
        p50=lerp(p50,values.b,take.b); p90=lerp(p90,values.a,take.a);
        locked=saturate(locked+take);
        float better=step(best+1e-6,fraction);
        best=lerp(best,fraction,better); mode=lerp(mode,(float(b)+0.5)/float(HIST_BINS),better);
    }
    float valid=step(0.5,mass*float(DS_W*DS_H));
    return lerp(float4(p25,p50,p90,mode),float4(p10,mass,0,valid),step(2.0,pos.x));
}
