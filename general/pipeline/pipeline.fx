#define SHADER_PIPELINE_COMBINED
#include "creative_values.fx"

#define PassthroughPS AnalysisPassthroughPS
#define HighwayWritePS AnalysisHighwayWritePS
#include "../analysis-frame/analysis_frame.fx"
#undef HighwayWritePS
#undef PassthroughPS

#include "../inverse-grade/inverse_grade.fx"

#define PassthroughPS CorrectivePassthroughPS
#define HighwayWritePS CorrectiveHighwayWritePS
#define TexHwyWritePS CorrectiveTexHwyWritePS
#include "../corrective/corrective.fx"
#undef TexHwyWritePS
#undef HighwayWritePS
#undef PassthroughPS

#include "../grade/grade.fx"

// One highway write after corrective: analysis data row 0 (pixels 0-3) and corrective
// ChromaHistory rows 1-4; the spatial lane passes through. Nothing reads row 0 between
// the analysis stats and this pass. Pixel 4 (NeutralIllum) is unused here: the combined
// inverse grade reads NeutralIllumTex directly.
float4 CombinedTexHwyWritePS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    if (int(pos.y) == TEX_HWY_SPATIAL_H && int(pos.x) < 4)
        return TexHwyWriteDataPS(pos, uv);
    return CorrectiveTexHwyWritePS(pos, uv);
}

technique ShaderPipeline
{
    pass NativeGuideSource
    {
        VertexShader = PostProcessVS;
        PixelShader = NativeGuideLogPS;
        RenderTarget = NativeGuideLogTex;
    }
    pass AnalysisSpatial
    {
        VertexShader = PostProcessVS;
        PixelShader = TexHwyWriteSpatialPS;
        RenderTarget = TexHwyTex;
    }
    pass AnalysisLaneSamples
    {
        VertexShader = PostProcessVS;
        PixelShader = LaneSamplesPS;
        RenderTarget = LaneSampTex;
    }
    pass AnalysisHistogram
    {
        VertexShader = PostProcessVS;
        PixelShader = LumHistGatherPS;
        RenderTarget = LumHistRawTex;
    }
    pass AnalysisHistogramHistory
    {
        VertexShader = PostProcessVS;
        PixelShader = LumHistSmoothPS;
        RenderTarget = LumHistTex;
    }
    pass AnalysisSceneCut
    {
        VertexShader = PostProcessVS;
        PixelShader = SceneCutPS;
        RenderTarget = SceneCutTex;
    }
    pass AnalysisStats
    {
        VertexShader = PostProcessVS;
        PixelShader = AnalysisStatsPS;
        RenderTarget0 = NearClipTex;
        RenderTarget1 = MeanChromaTex;
        RenderTarget2 = EntropyTex;
        RenderTarget3 = PercTex;
        RenderTarget4 = ModeTex;
    }
    pass AnalysisHighPercentiles
    {
        VertexShader = PostProcessVS;
        PixelShader = CDFWalkHighPS;
        RenderTarget = PercHighTex;
    }
    pass AnalysisScalarHighway
    {
        VertexShader = PostProcessVS;
        PixelShader = AnalysisHighwayWritePS;
        RenderTarget = HighwayTex;
    }
    pass InverseGrade
    {
        VertexShader = PostProcessVS;
        PixelShader = InverseGradePS;
        SRGBWriteEnable = false;
    }
    pass CorrectiveZoneHistogram
    {
        VertexShader = PostProcessVS;
        PixelShader = ComputeZoneHistogramPS;
        RenderTarget = CreativeZoneHistTex;
    }
    pass CorrectiveZoneLevels
    {
        VertexShader = PostProcessVS;
        PixelShader = BuildZoneLevelsPS;
        RenderTarget = CreativeZoneLevelsTex;
    }
    pass CorrectiveZoneHistory
    {
        VertexShader = PostProcessVS;
        PixelShader = SmoothZoneLevelsPS;
        RenderTarget = ZoneHistoryTex;
    }
    pass CorrectiveChromaHistory
    {
        VertexShader = PostProcessVS;
        PixelShader = UpdateHistoryPS;
        RenderTarget = ChromaHistoryTex;
    }
    pass CorrectiveTextureHighway
    {
        VertexShader = PostProcessVS;
        PixelShader = CombinedTexHwyWritePS;
        RenderTarget = TexHwyTex;
    }
    pass CorrectiveScalarHighway
    {
        VertexShader = PostProcessVS;
        PixelShader = CorrectiveHighwayWritePS;
        RenderTarget = HighwayTex;
    }
    pass GradeLowFrequency1
    {
        VertexShader = PostProcessVS;
        PixelShader = LFDownscale1PS;
        RenderTarget = LowFreqMip1Tex;
    }
    pass GradeLowFrequency2
    {
        VertexShader = PostProcessVS;
        PixelShader = LFDownscale2PS;
        RenderTarget = LowFreqMip2Tex;
    }
    pass GradeNeutralIlluminant
    {
        VertexShader = PostProcessVS;
        PixelShader = NeutralIllumPS;
        RenderTarget = NeutralIllumTex;
    }
    pass GradeGuidedCoefficients
    {
        VertexShader = PostProcessVS;
        PixelShader = GuidedCoeffPS;
        RenderTarget = GuidedCoeffTex;
    }
    pass GradeGuidedBase
    {
        VertexShader = PostProcessVS;
        PixelShader = GuidedBasePS;
        RenderTarget = BilateralLogTex;
    }
    pass GradeTintGather  { VertexShader = PostProcessVS; PixelShader = TintGatherPS; RenderTarget0 = TintGatherATex; RenderTarget1 = TintGatherBTex; }
    pass GradeTintEnvH    { VertexShader = PostProcessVS; PixelShader = TintEnvHPS;   RenderTarget0 = TintEnvAHTex;   RenderTarget1 = TintEnvBHTex; }
    pass GradeTintEnvV    { VertexShader = PostProcessVS; PixelShader = TintEnvVPS;   RenderTarget0 = TintEnvATex;    RenderTarget1 = TintEnvBTex; }
    pass GradeTintRegion  { VertexShader = PostProcessVS; PixelShader = TintRegionPS;  RenderTarget = TintRegionTex; }
    pass GradeLLPoints { VertexShader = PostProcessVS; PixelShader = LLPointsPS; RenderTarget0 = LLPtCTex; RenderTarget1 = LLPtRTex; RenderTarget2 = LLPtDTex; }
    pass GradeLLDirections { VertexShader = PostProcessVS; PixelShader = LLDirectionsPS; RenderTarget0 = LLDirATex; RenderTarget1 = LLDirBTex; }
    pass GradeLLDivergence { VertexShader = PostProcessVS; PixelShader = LLDivergencePS; RenderTarget = LLA0Tex; }
    pass GradeLLDown1 { VertexShader = PostProcessVS; PixelShader = LLDown1PS; RenderTarget = LLA1Tex; }
    pass GradeLLDown2 { VertexShader = PostProcessVS; PixelShader = LLDown2PS; RenderTarget = LLA2Tex; }
    pass GradeLLDown3 { VertexShader = PostProcessVS; PixelShader = LLDown3PS; RenderTarget = LLA3Tex; }
    pass GradeLLDown4 { VertexShader = PostProcessVS; PixelShader = LLDown4PS; RenderTarget = LLA4Tex; }
    pass GradeLLUp3 { VertexShader = PostProcessVS; PixelShader = LLUp3PS; RenderTarget = LLB3Tex; }
    pass GradeLLUp2 { VertexShader = PostProcessVS; PixelShader = LLUp2PS; RenderTarget = LLB2Tex; }
    pass GradeLLUp1 { VertexShader = PostProcessVS; PixelShader = LLUp1PS; RenderTarget = LLB1Tex; }
    pass GradeLLUp0 { VertexShader = PostProcessVS; PixelShader = LLUp0PS; RenderTarget = LLB0Tex; }
    pass GradeLLAnchor { VertexShader = PostProcessVS; PixelShader = LLAnchorPS; RenderTarget = LLAnchorTex; }
    pass GradeSceneContext
    {
        VertexShader = PostProcessVS;
        PixelShader = SceneCtxPS;
        RenderTarget = SceneCtxTex;
    }
    pass GradeColorTransform
    {
        VertexShader = PostProcessVS;
        PixelShader = ColorTransformPS;
        SRGBWriteEnable = false;
    }
    pass GradeAdaptiveHistory
    {
        VertexShader = PostProcessVS;
        PixelShader = AdaptiveHistoryPS;
        RenderTarget = AdaptiveHistoryTex;
    }
}
