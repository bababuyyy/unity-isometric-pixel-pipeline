Shader "Hidden/OutlineShader"
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
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"

            // Uniform Parameters
            
            // Parameters based on scene color.
            float _LineDarken;
            float _CreaseBrighten;
            
            // Crease parameters.
            float _DepthDiffLow;
            float _DepthDiffHigh;
            float _NormalSmoothLow;
            float _NormalSmoothHigh;
            
            // Preserved parameters for C# compatibility.
            float3 _LineTint;        
            float3 _CreaseTint;      
            float _FlipPalettes;     
            float _LineOverlay;      
            float _LineAlpha;        
            float _CreaseOverlay;      
            float _CreaseAlpha;      
            float _KernelRadius;     
            float _ZDeltaCutoff;     
            float _AngleZCutoff;     
            float _AngleZScale;      

            // Reconstruct position in view-space.
            float3 ReconstructViewPos(float2 uv, float rawDepth)
            {
                float4 clipPos = float4(uv * 2.0 - 1.0, rawDepth, 1.0);
                #if UNITY_UV_STARTS_AT_TOP
                    clipPos.y = -clipPos.y;
                #endif
                
                float4 viewPos = mul(UNITY_MATRIX_I_P, clipPos);
                return viewPos.xyz / viewPos.w;
            }

            half4 frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float2 step_uv = _BlitTexture_TexelSize.xy * _KernelRadius;

                float3 vp[9];
                float3 vn[9];
                float2 sampleUVs[9];

                // Extract 3x3 grid.
                [unroll]
                for (int k = 0; k < 9; k++)
                {
                    float2 off = float2(k % 3 - 1, k / 3 - 1);
                    sampleUVs[k] = uv + off * step_uv;
                    
                    float rawDepth = SampleSceneDepth(sampleUVs[k]);
                    vp[k] = ReconstructViewPos(sampleUVs[k], rawDepth);
                    
                    float3 normalWS = SampleSceneNormals(sampleUVs[k]);
                    vn[k] = mul((float3x3)UNITY_MATRIX_V, normalWS); 
                }

                // Angular adaptation threshold for silhouette.
                float facing = 1.0 - vn[4].z;
                float t01 = saturate((facing - _AngleZCutoff) / (1.0 - _AngleZCutoff));
                float z_thresh = _ZDeltaCutoff * (t01 * _AngleZScale + 1.0);

                // Crease detection.
                int cardinals[4] = {1, 3, 5, 7};
                
                // Suppress creases near silhouettes using depth differences.
                float depthDifference = 0.0;
                float invDepthDifference = 0.0;
                
                [unroll]
                for (int i = 0; i < 4; i++) {
                    int idx = cardinals[i];
                    depthDifference += clamp(vp[idx].z - vp[4].z, 0.0, 1.0);
                    invDepthDifference += clamp(vp[4].z - vp[idx].z, 0.0, 1.0);
                }
                
                invDepthDifference = clamp(invDepthDifference, 0.0, 1.0);
                invDepthDifference = clamp(smoothstep(0.9, 0.9, invDepthDifference) * 10.0, 0.0, 1.0);
                depthDifference = smoothstep(_DepthDiffLow, _DepthDiffHigh, depthDifference);

                // Directional contrast between cardinal opposites.
                float d0 = 1.0 - dot(vn[4], vn[cardinals[0]]);
                float d1 = 1.0 - dot(vn[4], vn[cardinals[1]]);
                float d2 = 1.0 - dot(vn[4], vn[cardinals[2]]);
                float d3 = 1.0 - dot(vn[4], vn[cardinals[3]]);
                
                float contrast0 = abs(d0 - d3);
                float contrast1 = abs(d1 - d2);
                
                float normalDifference = max(contrast0, contrast1);
                
                normalDifference = smoothstep(_NormalSmoothLow, _NormalSmoothHigh, normalDifference);
                float crease_weight = saturate(normalDifference - invDepthDifference);

                // Silhouette detection.
                bool has_line = false;
                int closest_idx = 4;
                float max_z = vp[4].z; // Reversed-Z: Larger Z values are closer to the camera.
                
                int neighbors[8] = {0, 1, 2, 3, 5, 6, 7, 8}; // Sample 8 directions for outline.

                [unroll]
                for (int s = 0; s < 8; s++) 
                {
                    int idx = neighbors[s];
                    
                    // Check for depth discontinuities.
                    if ((vp[idx].z - vp[4].z) > z_thresh)
                    {
                        has_line = true;
                    }
                    
                    // Track the closest neighbor to use its color for the line.
                    if (vp[idx].z > max_z)
                    {
                        max_z = vp[idx].z;
                        closest_idx = idx;
                    }
                }

                // Mask output.
                float3 result = float3(0.0, 0.0, 0.0);
                float alpha = 0.0;

                // Return strictly the mask.
                if (has_line)
                {
                    // Darken the color of the closest pixel for the silhouette.
                    float3 closest_color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, sampleUVs[closest_idx]).rgb;
                    result = closest_color * _LineDarken;
                    alpha = _LineAlpha;
                }
                else if (crease_weight > 0.0)
                {
                    // Brighten the center color for the crease.
                    float3 center_color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).rgb;
                    result = center_color * (1.0 + _CreaseBrighten);
                    alpha = crease_weight * _CreaseAlpha;
                }

                return half4(result, alpha);
            }
            ENDHLSL
        }
    }
}