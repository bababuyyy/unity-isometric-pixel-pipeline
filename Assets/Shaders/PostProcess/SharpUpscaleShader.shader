Shader "Custom/SharpUpscale"
{
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            // Receive the sub-texel offset calculated by the isometric camera.
            float4 _PixelPanOffset;

            half4 frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                
                // Apply snap error compensation during texture sampling.
                uv += _PixelPanOffset.xy;
                
                float2 px = _BlitTexture_TexelSize.xy;
                
                float2 fw = clamp(fwidth(uv) / px, 1e-5, 1.0);
                float2 grid = uv / px - 0.5 * fw;
                float2 blend = smoothstep(1.0 - fw, float2(1.0, 1.0), frac(grid));
                float2 finalUV = (floor(grid) + 0.5 + blend) * px;
                
                half4 color = SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_LinearClamp, finalUV, 0);
                
                return color;
            }
            ENDHLSL
        }
    }
}