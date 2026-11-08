#ifndef NATIVE_GUIDE_FXH
#define NATIVE_GUIDE_FXH

// Original source log-luma, observed before inverse/creative corrections.
// Native reconstruction must use the same signal domain as the guided fit.
texture2D NativeGuideLogTex { Width=BUFFER_WIDTH; Height=BUFFER_HEIGHT; Format=R32F; };
sampler2D NativeGuideLogSamp
{
    Texture=NativeGuideLogTex; MinFilter=POINT; MagFilter=POINT;
    AddressU=CLAMP; AddressV=CLAMP; SRGBTexture=false;
};
float4 NativeGuideLogPS(float4 pos:SV_Position,float2 uv:TEXCOORD0):SV_Target
{
    float3 raw_linear=SRGBToLinear(tex2D(BackBuffer,uv).rgb);
    return float4(log2(max(Luma(raw_linear),0.001)),0,0,1);
}

#endif
