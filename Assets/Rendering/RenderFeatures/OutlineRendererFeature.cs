using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

public class OutlineRendererFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class OutlineSettings
    {
        [Header("Colors")]
        public Color lineTint = new Color(0.05f, 0.05f, 0.08f, 1f);
        public Color creaseTint = new Color(1f, 0.55f, 0.1f, 1f);
        public bool flipPalettes = false;
        
        [Header("Silhouette (Line)")]
        public bool lineOverlay = false;
        [Range(0, 1)] public float lineAlpha = 1.0f;
        
        [Header("Crease")]
        public bool creaseOverlay = true;
        [Range(0, 1)] public float creaseAlpha = 1.0f;
        
        [Header("Sampling")]
        [Range(0.5f, 4f)] public float kernelRadius = 1.0f;
        
        [Header("Silhouette Detection")]
        [Range(0, 1)] public float zDeltaCutoff = 0.25f;
        [Range(0, 1)] public float angleZCutoff = 0.50f;
        [Range(0, 4)] public float angleZScale = 2.0f;
        
        [Header("Legacy Crease Detection")]
        public float convexCutoff = 0.10f;
        [Range(0, 0.5f)] public float creaseFeather = 0.0f;
        public float concaveCutoff = 0.01f;
        [Range(0, 1)] public float concaveZCutoff = 0.50f;
        
        [Header("Resources")]
        public Material outlineMaterial;
    }

    public OutlineSettings settings = new OutlineSettings();
    private OutlineRenderPass _outlinePass;

    public override void Create()
    {
        if (settings == null)
        {
            settings = new OutlineSettings();
        }

        _outlinePass = new OutlineRenderPass(settings)
        {
            renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing
        };
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (settings.outlineMaterial == null) return;
        
        if (renderingData.cameraData.cameraType == CameraType.Game || renderingData.cameraData.cameraType == CameraType.SceneView)
        {
            renderer.EnqueuePass(_outlinePass);
        }
    }

    private class OutlineRenderPass : ScriptableRenderPass
    {
        private OutlineSettings _settings;
        private Material _mat;

        public OutlineRenderPass(OutlineSettings settings)
        {
            _settings = settings;
            _mat = settings.outlineMaterial;
            
            // Requires color, depth, and normal buffers for view-space reconstruction and creases.
            ConfigureInput(ScriptableRenderPassInput.Color | ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);
        }

        private class PassData
        {
            public TextureHandle source;
            public TextureHandle destination;
            public Material material;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();
            TextureHandle colorTarget = resourceData.activeColorTexture;
            
            if (!colorTarget.IsValid() || _mat == null) return;

            TextureDesc desc = renderGraph.GetTextureDesc(colorTarget);
            desc.name = "_OutlineTempTexture";
            desc.clearBuffer = false;
            TextureHandle tempTarget = renderGraph.CreateTexture(desc);

            // Apply all parameters for shader translation.
            _mat.SetVector("_LineTint", new Vector4(_settings.lineTint.r, _settings.lineTint.g, _settings.lineTint.b, 0));
            _mat.SetVector("_CreaseTint", new Vector4(_settings.creaseTint.r, _settings.creaseTint.g, _settings.creaseTint.b, 0));
            _mat.SetFloat("_FlipPalettes", _settings.flipPalettes ? 1f : 0f);
            
            _mat.SetFloat("_LineOverlay", _settings.lineOverlay ? 1f : 0f);
            _mat.SetFloat("_LineAlpha", _settings.lineAlpha);
            
            _mat.SetFloat("_CreaseOverlay", _settings.creaseOverlay ? 1f : 0f);
            _mat.SetFloat("_CreaseAlpha", _settings.creaseAlpha);
            
            _mat.SetFloat("_KernelRadius", _settings.kernelRadius);
            
            _mat.SetFloat("_ZDeltaCutoff", _settings.zDeltaCutoff);
            _mat.SetFloat("_AngleZCutoff", _settings.angleZCutoff);
            _mat.SetFloat("_AngleZScale", _settings.angleZScale);
            
            _mat.SetFloat("_ConvexCutoff", _settings.convexCutoff);
            _mat.SetFloat("_CreaseFeather", _settings.creaseFeather);
            _mat.SetFloat("_ConcaveCutoff", _settings.concaveCutoff);
            _mat.SetFloat("_ConcaveZCutoff", _settings.concaveZCutoff);

            // Pass 1: Render outline.
            using (var builder = renderGraph.AddRasterRenderPass<PassData>("OutlinePass", out var passData))
            {
                passData.source = colorTarget;
                passData.destination = tempTarget;
                passData.material = _mat;

                builder.UseTexture(passData.source, AccessFlags.Read);
                builder.SetRenderAttachment(passData.destination, 0, AccessFlags.Write);

                builder.SetRenderFunc((PassData data, RasterGraphContext context) =>
                {
                    Blitter.BlitTexture(context.cmd, data.source, new Vector4(1, 1, 0, 0), data.material, 0);
                });
            }

            // Pass 2: Return buffer to pipeline.
            using (var builder = renderGraph.AddRasterRenderPass<PassData>("OutlineBackcopy", out var passData))
            {
                passData.source = tempTarget;
                passData.destination = colorTarget;

                builder.UseTexture(passData.source, AccessFlags.Read);
                builder.SetRenderAttachment(passData.destination, 0, AccessFlags.Write);

                builder.SetRenderFunc((PassData data, RasterGraphContext context) =>
                {
                    Blitter.BlitTexture(context.cmd, data.source, new Vector4(1, 1, 0, 0), 0, false);
                });
            }
        }
    }
}