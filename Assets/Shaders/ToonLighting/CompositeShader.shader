Shader "Hidden/CompositeShader"
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

            // URP native declaration for textures and samplers.
            TEXTURE2D(_OutlineTexture);
            SAMPLER(sampler_OutlineTexture);

            half4 frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                
                // Sample the low-resolution scene color.
                half4 color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv);
                
                // Sample the low-resolution outline mask.
                half4 outline = SAMPLE_TEXTURE2D(_OutlineTexture, sampler_OutlineTexture, uv);

                // Replace color with the outline where alpha is greater than zero.
                float3 result = lerp(color.rgb, outline.rgb, outline.a);
                
                return half4(result, 1.0);
            }
            ENDHLSL
        }
    }
}