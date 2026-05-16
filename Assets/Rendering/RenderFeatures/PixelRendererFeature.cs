using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.RenderGraphModule.Util;
using UnityEngine.Rendering.Universal;
using UnityEngine.Experimental.Rendering;

public class PixelRendererFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class PixelSettings
    {
        [Header("Internal Resolution")]
        public int width = 640;
        public int height = 360;

        [Header("Materials")]
        [Tooltip("Hidden/OutlineShader material (Pass 2).")]
        public Material outlineMaterial;
        [Tooltip("Hidden/CompositeShader material (Pass 3).")]
        public Material compositeMaterial;
        [Tooltip("Hidden/SharpUpscale material (Pass 4).")]
        public Material upscaleMaterial;

        [Header("Outline - Colors")]
        public Color lineTint = new Color(0.05f, 0.05f, 0.08f, 1f);
        public Color creaseTint = new Color(1f, 0.55f, 0.1f, 1f);
        public bool flipPalettes = false;
        
        [Header("Outline - Adaptive Colors")]
        [Range(0, 1)] public float lineDarken = 0.4f;
        [Range(0, 1)] public float creaseBrighten = 0.3f;

        [Header("Outline - Silhouette")]
        public bool lineOverlay = false;
        [Range(0, 1)] public float lineAlpha = 1.0f;

        [Header("Outline - Legacy Crease (Ignored in HLSL)")]
        public bool creaseOverlay = true;
        [Range(0, 1)] public float creaseAlpha = 1.0f;
        public float convexCutoff = 0.10f;
        [Range(0, 0.5f)] public float creaseFeather = 0.0f;
        public float concaveCutoff = 0.01f;
        [Range(0, 1)] public float concaveZCutoff = 0.50f;

        [Header("Outline - Sampling")]
        [Range(0.5f, 4f)] public float kernelRadius = 1.0f;

        [Header("Outline - Silhouette Detection")]
        [Range(0, 1)] public float zDeltaCutoff = 0.25f;
        [Range(0, 1)] public float angleZCutoff = 0.50f;
        [Range(0, 4)] public float angleZScale = 2.0f;

        [Header("Outline - Crease")]
        [Range(0, 1)] public float depthDiffLow = 0.25f;
        [Range(0, 1)] public float depthDiffHigh = 0.3f;
        [Range(0, 2)] public float normalSmoothLow = 0.2f;
        [Range(0, 2)] public float normalSmoothHigh = 0.8f;
    }

    public PixelSettings settings = new PixelSettings();
    private PixelRenderPass _pixelPass;

    public override void Create()
    {
        if (settings == null) settings = new PixelSettings();

        _pixelPass = new PixelRenderPass(settings)
        {
            renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing
        };
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (renderingData.cameraData.cameraType == CameraType.Game || renderingData.cameraData.cameraType == CameraType.SceneView)
        {
            renderer.EnqueuePass(_pixelPass);
        }
    }

    private class PixelRenderPass : ScriptableRenderPass
    {
        private PixelSettings _settings;

        public PixelRenderPass(PixelSettings settings)
        {
            _settings = settings;
            requiresIntermediateTexture = true;
            
            // Requires color, depth, and normal buffers for 3D reconstruction during the Outline pass.
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
            TextureHandle cameraTarget = resourceData.activeColorTexture;

            if (!cameraTarget.IsValid()) return;

            UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();

            // Texture and Descriptor Creation
            
            // Backup full resolution color to prevent read/write conflicts.
            TextureDesc colorCopyDesc = renderGraph.GetTextureDesc(cameraTarget);
            colorCopyDesc.name = "_ColorCopy";
            colorCopyDesc.msaaSamples = MSAASamples.None;
            colorCopyDesc.clearBuffer = false;
            TextureHandle colorCopy = renderGraph.CreateTexture(colorCopyDesc);

            // Low resolution scene color using Bilinear filtering to ensure Sharp Upscale works correctly.
            TextureDesc lowResDesc = new TextureDesc(_settings.width, _settings.height)
            {
                colorFormat = cameraData.cameraTargetDescriptor.graphicsFormat,
                depthBufferBits = DepthBits.None,
                useMipMap = false,
                filterMode = FilterMode.Bilinear,
                name = "_LowResColor"
            };
            TextureHandle lowResColor = renderGraph.CreateTexture(lowResDesc);

            // Low resolution outline mask. Point filter and R8G8B8A8_UNorm are required for crisp pixel art.
            TextureDesc lowResPointDesc = lowResDesc;
            lowResPointDesc.filterMode = FilterMode.Point;
            lowResPointDesc.colorFormat = GraphicsFormat.R8G8B8A8_UNorm; 
            lowResPointDesc.name = "_LowResOutline";
            TextureHandle lowResOutline = renderGraph.CreateTexture(lowResPointDesc);

            // Composite of the low resolution color and outline.
            lowResDesc.name = "_LowResComposite";
            TextureHandle lowResComposite = renderGraph.CreateTexture(lowResDesc);

            bool hasOutline = _settings.outlineMaterial != null && _settings.compositeMaterial != null;

            // Pass 0: Capture the original full resolution color.
            using (var builder = renderGraph.AddRasterRenderPass<PassData>("CopyColor", out var passData))
            {
                passData.source = cameraTarget;
                passData.destination = colorCopy;

                builder.UseTexture(passData.source, AccessFlags.Read);
                builder.SetRenderAttachment(passData.destination, 0, AccessFlags.Write);

                builder.SetRenderFunc((PassData data, RasterGraphContext context) =>
                {
                    Blitter.BlitTexture(context.cmd, data.source, new Vector4(1, 1, 0, 0), 0, false);
                });
            }

            // Pass 1: Downsample color to internal resolution.
            using (var builder = renderGraph.AddRasterRenderPass<PassData>("Downsample_Color", out var passData))
            {
                passData.source = colorCopy; 
                passData.destination = lowResColor;

                builder.UseTexture(passData.source, AccessFlags.Read);
                builder.SetRenderAttachment(passData.destination, 0, AccessFlags.Write);

                builder.SetRenderFunc((PassData data, RasterGraphContext context) =>
                {
                    Blitter.BlitTexture(context.cmd, data.source, new Vector4(1, 1, 0, 0), 0, false);
                });
            }

            // Pass 2: Generate outline at internal resolution.
            if (hasOutline)
            {
                // Apply base colors.
                _settings.outlineMaterial.SetVector("_LineTint", new Vector4(_settings.lineTint.r, _settings.lineTint.g, _settings.lineTint.b, 0));
                _settings.outlineMaterial.SetVector("_CreaseTint", new Vector4(_settings.creaseTint.r, _settings.creaseTint.g, _settings.creaseTint.b, 0));
                _settings.outlineMaterial.SetFloat("_FlipPalettes", _settings.flipPalettes ? 1f : 0f);
                
                // Apply adaptive colors.
                _settings.outlineMaterial.SetFloat("_LineDarken", _settings.lineDarken);
                _settings.outlineMaterial.SetFloat("_CreaseBrighten", _settings.creaseBrighten);
                
                // Apply opacities and overlays.
                _settings.outlineMaterial.SetFloat("_LineOverlay", _settings.lineOverlay ? 1f : 0f);
                _settings.outlineMaterial.SetFloat("_LineAlpha", _settings.lineAlpha);
                _settings.outlineMaterial.SetFloat("_CreaseOverlay", _settings.creaseOverlay ? 1f : 0f);
                _settings.outlineMaterial.SetFloat("_CreaseAlpha", _settings.creaseAlpha);
                
                // Apply silhouette and sampling parameters.
                _settings.outlineMaterial.SetFloat("_KernelRadius", _settings.kernelRadius);
                _settings.outlineMaterial.SetFloat("_ZDeltaCutoff", _settings.zDeltaCutoff);
                _settings.outlineMaterial.SetFloat("_AngleZCutoff", _settings.angleZCutoff);
                _settings.outlineMaterial.SetFloat("_AngleZScale", _settings.angleZScale);
                
                // Apply legacy parameters for backward compatibility.
                _settings.outlineMaterial.SetFloat("_ConvexCutoff", _settings.convexCutoff);
                _settings.outlineMaterial.SetFloat("_CreaseFeather", _settings.creaseFeather);
                _settings.outlineMaterial.SetFloat("_ConcaveCutoff", _settings.concaveCutoff);
                _settings.outlineMaterial.SetFloat("_ConcaveZCutoff", _settings.concaveZCutoff);
                
                // Apply crease detection parameters.
                _settings.outlineMaterial.SetFloat("_DepthDiffLow", _settings.depthDiffLow);
                _settings.outlineMaterial.SetFloat("_DepthDiffHigh", _settings.depthDiffHigh);
                _settings.outlineMaterial.SetFloat("_NormalSmoothLow", _settings.normalSmoothLow);
                _settings.outlineMaterial.SetFloat("_NormalSmoothHigh", _settings.normalSmoothHigh);

                using (var builder = renderGraph.AddRasterRenderPass<PassData>("Outline_LowRes", out var passData))
                {
                    passData.source = lowResColor; 
                    passData.destination = lowResOutline; 
                    passData.material = _settings.outlineMaterial;

                    builder.UseTexture(passData.source, AccessFlags.Read);
                    builder.SetRenderAttachment(passData.destination, 0, AccessFlags.Write);
                    
                    // Expose the outline texture globally for the Composite shader.
                    builder.SetGlobalTextureAfterPass(passData.destination, Shader.PropertyToID("_OutlineTexture"));
                    
                    // Prevent Unity from culling this pass.
                    builder.AllowPassCulling(false);

                    builder.SetRenderFunc((PassData data, RasterGraphContext context) =>
                    {
                        Blitter.BlitTexture(context.cmd, data.source, new Vector4(1, 1, 0, 0), data.material, 0);
                    });
                }
                
                // Pass 3: Composite the outline over the color.
                var mpb = new MaterialPropertyBlock();
                var blitParams = new RenderGraphUtils.BlitMaterialParameters(
                    lowResColor,          
                    lowResComposite,      
                    _settings.compositeMaterial,
                    0                     
                );
                
                renderGraph.AddBlitPass(blitParams, "Composite_Outline");
            }
            else
            {
                // Fallback to bypass outline if materials are missing.
                using (var builder = renderGraph.AddRasterRenderPass<PassData>("Composite_Fallback", out var passData))
                {
                    passData.source = lowResColor;
                    passData.destination = lowResComposite;

                    builder.UseTexture(passData.source, AccessFlags.Read);
                    builder.SetRenderAttachment(passData.destination, 0, AccessFlags.Write);

                    builder.SetRenderFunc((PassData data, RasterGraphContext context) =>
                    {
                        Blitter.BlitTexture(context.cmd, data.source, new Vector4(1, 1, 0, 0), 0, false);
                    });
                }
            }

            // Pass 4: Upscale to full resolution.
            using (var builder = renderGraph.AddRasterRenderPass<PassData>("Upsample_Sharp", out var passData))
            {
                passData.source = lowResComposite;
                passData.destination = cameraTarget; 
                passData.material = _settings.upscaleMaterial;

                builder.UseTexture(passData.source, AccessFlags.Read);
                builder.SetRenderAttachment(passData.destination, 0, AccessFlags.Write);

                builder.SetRenderFunc((PassData data, RasterGraphContext context) =>
                {
                    if (data.material != null)
                        Blitter.BlitTexture(context.cmd, data.source, new Vector4(1, 1, 0, 0), data.material, 0);
                    else
                        Blitter.BlitTexture(context.cmd, data.source, new Vector4(1, 1, 0, 0), 0, false);
                });
            }
        }
    }
}