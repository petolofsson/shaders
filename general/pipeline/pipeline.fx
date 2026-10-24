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

technique ShaderPipeline
{
    pass AnalysisSpatial
    {
        VertexShader = PostProcessVS;
        PixelShader = TexHwyWriteSpatialPS;
        RenderTarget = TexHwyTex;
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
    pass AnalysisEntropy
    {
        VertexShader = PostProcessVS;
        PixelShader = HistEntropyPS;
        RenderTarget = EntropyTex;
    }
    pass AnalysisPercentiles
    {
        VertexShader = PostProcessVS;
        PixelShader = CDFWalkPS;
        RenderTarget = PercTex;
    }
    pass AnalysisSceneCut
    {
        VertexShader = PostProcessVS;
        PixelShader = SceneCutPS;
        RenderTarget = SceneCutTex;
    }
    pass AnalysisNearClip
    {
        VertexShader = PostProcessVS;
        PixelShader = NearClipPS;
        RenderTarget = NearClipTex;
    }
    pass AnalysisHighPercentiles
    {
        VertexShader = PostProcessVS;
        PixelShader = CDFWalkHighPS;
        RenderTarget = PercHighTex;
    }
    pass AnalysisMeanChroma
    {
        VertexShader = PostProcessVS;
        PixelShader = MeanChromaPS;
        RenderTarget = MeanChromaTex;
    }
    pass AnalysisMode
    {
        VertexShader = PostProcessVS;
        PixelShader = CDFWalkModePS;
        RenderTarget = ModeTex;
    }
    pass AnalysisTextureHighway
    {
        VertexShader = PostProcessVS;
        PixelShader = TexHwyWriteDataPS;
        RenderTarget = TexHwyTex;
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
        PixelShader = CorrectiveTexHwyWritePS;
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
    pass GradeTextureHighway
    {
        VertexShader = PostProcessVS;
        PixelShader = TexHwyWritePS;
        RenderTarget = TexHwyTex;
    }
}
