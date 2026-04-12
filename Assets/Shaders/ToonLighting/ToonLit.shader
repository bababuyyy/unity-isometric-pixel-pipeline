Shader "Custom/ToonLit"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        
        // Palette System.
        _HighlightColor ("Highlight Color", Color) = (1, 1, 1, 1)
        _MidtoneColor ("Midtone Color", Color) = (0.7, 0.7, 0.7, 1)
        _ShadowColor ("Shadow Color", Color) = (0.3, 0.3, 0.4, 1)
        [Toggle] _UsePalette ("Use Palette", Float) = 0

        _Cuts ("Cuts", Range(1, 8)) = 3
        _Steepness ("Steepness", Range(1, 8)) = 1.0
        _Wrap ("Wrap", Range(-2.0, 2.0)) = 0.0
        _ThresholdGradientSize ("Threshold Gradient Size", Range(0.0, 1.0)) = 0.2
        
        // Dithering.
        [Toggle] _UseDither ("Use Dither", Float) = 0
        _DitherStrength ("Dither Strength", Range(0.0, 1.0)) = 0.1
        
        // Patch System properties.
        _Color2 ("Color 2 (Patch)", Color) = (0.3, 0.5, 0.2, 1)
        _Noise2 ("Noise 2", 2D) = "white" {}
        _Noise2Scale ("Noise 2 Scale", Range(0.0, 1.0)) = 0.005
        _Noise2Threshold ("Noise 2 Threshold", Range(0.0, 1.0)) = 0.604

        _Color3 ("Color 3 (Patch)", Color) = (0.25, 0.45, 0.15, 1)
        _Noise3 ("Noise 3", 2D) = "white" {}
        _Noise3Scale ("Noise 3 Scale", Range(0.0, 0.1)) = 0.003
        _Noise3Threshold ("Noise 3 Threshold", Range(0.0, 1.0)) = 0.661
    }
    
    SubShader
    {
        Tags 
        { 
            "RenderType" = "Opaque" 
            "RenderPipeline" = "UniversalPipeline" 
            "Queue" = "Geometry" 
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile _ _FORWARD_PLUS

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 positionWS  : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
            };

            sampler2D _Noise2;
            sampler2D _Noise3;

            // Cloud Shadows Global Parameters.
            sampler2D _CloudNoise;
            float _CloudScale;
            float _CloudWorldY;
            float _CloudSpeed;
            float _CloudContrast;
            float _CloudThreshold;
            float4 _CloudDirection;
            float _CloudShadowMin;
            float _CloudDivergeAngle;
            float4 _CloudLightDirection;
            float _CloudPower;

            // Unified CBUFFER for SRP Batcher.
            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                
                // Palette system variables.
                half4 _HighlightColor;
                half4 _MidtoneColor;
                half4 _ShadowColor;
                float _UsePalette;

                int _Cuts;
                float _Steepness;
                float _Wrap;
                float _ThresholdGradientSize;
                
                float _UseDither;
                float _DitherStrength;
                
                half4 _Color2;
                float _Noise2Scale;
                float _Noise2Threshold;
                
                half4 _Color3;
                float _Noise3Scale;
                float _Noise3Threshold;
            CBUFFER_END

            float GLSLMod(float x, float y)
            {
                return x - y * floor(x / y);
            }

            float2 RotateVec2(float2 v, float angleDeg)
            {
                float rad = radians(angleDeg);
                float c = cos(rad);
                float s = sin(rad);
                return float2(v.x * c - v.y * s, v.x * s + v.y * c);
            }

            float GetCloudNoise(float3 worldPos)
            {
                float t = (_CloudWorldY - worldPos.y) / _CloudLightDirection.y;
                float3 hitPos = worldPos + t * _CloudLightDirection.xyz;
                float invScale = 1.0 / _CloudScale;
                
                float2 cloudDir1 = RotateVec2(_CloudDirection.xy, _CloudDivergeAngle);
                float2 cloudDir2 = RotateVec2(_CloudDirection.xy, -_CloudDivergeAngle);
                
                float2 cloudTimeDir1 = _Time.y * _CloudSpeed * normalize(cloudDir1);
                float2 cloudTimeDir2 = _Time.y * _CloudSpeed * normalize(cloudDir2);
                
                float sample1 = tex2D(_CloudNoise, hitPos.xz * invScale + cloudTimeDir1).r;
                float sample2 = tex2D(_CloudNoise, hitPos.xz * (invScale * 0.8) + (cloudTimeDir2 * 0.89 * 1.047)).r;

                float cloudSample = sample1 * sample2;
                float lightValue = saturate(cloudSample + _CloudThreshold);

                lightValue = (lightValue - 0.5) * _CloudContrast + 0.5;
                lightValue = clamp(lightValue + _CloudThreshold, _CloudShadowMin, 1.0);
                lightValue = pow(lightValue, _CloudPower);

                return lightValue;
            }

            // 4x4 Bayer matrix for pixel art dithering.
            float BayerDither(float2 screenPos)
            {
                int x = int(fmod(screenPos.x, 4.0));
                int y = int(fmod(screenPos.y, 4.0));
                
                // Use static const to prevent array allocation errors during compilation.
                static const float bayer[16] = {
                     0.0,  8.0,  2.0, 10.0,
                    12.0,  4.0, 14.0,  6.0,
                     3.0, 11.0,  1.0,  9.0,
                    15.0,  7.0, 13.0,  5.0
                };

                return bayer[y * 4 + x] / 16.0;
            }

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                output.positionHCS = TransformWorldToHClip(output.positionWS);
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                float noise2Val = tex2D(_Noise2, input.positionWS.xz * _Noise2Scale).r;
                float noise3Val = tex2D(_Noise3, input.positionWS.xz * _Noise3Scale).r;

                half3 albedo = _BaseColor.rgb;
                if (noise2Val > _Noise2Threshold) albedo = _Color2.rgb;
                if (noise3Val > _Noise3Threshold) albedo = _Color3.rgb;

                float3 normalWS = normalize(input.normalWS);
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);

                float diffuseAmount = dot(normalWS, mainLight.direction) + _Wrap;
                diffuseAmount *= _Steepness;

                float cloudLight = GetCloudNoise(input.positionWS);
                diffuseAmount = min(diffuseAmount, cloudLight);

                if (_UseDither > 0.5)
                {
                    // Access screen pixel position directly via HCS clip space.
                    float2 screenPos = input.positionHCS.xy;
                    float bayerVal = BayerDither(screenPos);
                    diffuseAmount = clamp(diffuseAmount + (bayerVal - 0.5) * _DitherStrength * 0.25, 0.0, 1.0);
                }

                float cutsInv = 1.0 / float(_Cuts);
                float cut = cutsInv;

                float originalIndex = ceil(diffuseAmount * float(_Cuts));
                float originalStepped = saturate(originalIndex * cut);

                float diffuseStepped = saturate(diffuseAmount + GLSLMod(1.0 - diffuseAmount, cutsInv));

                if (_ThresholdGradientSize > 0.0)
                {
                    float nearestK = floor(diffuseAmount / cut + 0.5);
                    float threshold = nearestK * cut;

                    if (nearestK >= 0.0 && nearestK <= float(_Cuts))
                    {
                        float halfWidth = 0.5 * cut * _ThresholdGradientSize;
                        float low = max(0.0, threshold - halfWidth);
                        float high = min(1.0, threshold + halfWidth);

                        float blend = 0.0;
                        if (high > low)
                            blend = smoothstep(low, high, diffuseAmount);
                        else
                            blend = step(threshold, diffuseAmount);

                        float leftValue = threshold;
                        float rightValue = min(threshold + cut, 1.0);
                        diffuseStepped = lerp(leftValue, rightValue, blend);
                        diffuseStepped = saturate(diffuseStepped);
                    }
                    else
                    {
                        diffuseStepped = originalStepped;
                    }
                }

                float shadow = mainLight.distanceAttenuation * mainLight.shadowAttenuation;
                float lit = diffuseStepped * shadow;
                half3 finalColor;

                if (_UsePalette > 0.5)
                {
                    // Interpolate between 3 colors based on lighting.
                    half3 paletteLow = _ShadowColor.rgb;
                    half3 paletteMid = albedo; // Albedo already includes patches.
                    half3 paletteHigh = _HighlightColor.rgb;
                    
                    half3 paletteColor = albedo * lerp(_ShadowColor.rgb, _HighlightColor.rgb, lit);
                        
                    finalColor = paletteColor;
                }
                else
                {
                    // Preserve original behavior.
                    float3 finalLighting = diffuseStepped * mainLight.color * shadow;
                    float3 ambient = float3(0.15, 0.15, 0.2);
                    finalColor = albedo * (finalLighting + ambient);
                }

                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
            };

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                
                half4 _HighlightColor;
                half4 _MidtoneColor;
                half4 _ShadowColor;
                float _UsePalette;

                int _Cuts;
                float _Steepness;
                float _Wrap;
                float _ThresholdGradientSize;
                
                float _UseDither;
                float _DitherStrength;
                
                half4 _Color2;
                float _Noise2Scale;
                float _Noise2Threshold;
                
                half4 _Color3;
                float _Noise3Scale;
                float _Noise3Threshold;
            CBUFFER_END

            float3 _LightDirection;

            Varyings vert(Attributes input)
            {
                Varyings output;
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.positionHCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                return 0;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
            };

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                
                half4 _HighlightColor;
                half4 _MidtoneColor;
                half4 _ShadowColor;
                float _UsePalette;

                int _Cuts;
                float _Steepness;
                float _Wrap;
                float _ThresholdGradientSize;
                
                float _UseDither;
                float _DitherStrength;
                
                half4 _Color2;
                float _Noise2Scale;
                float _Noise2Threshold;
                
                half4 _Color3;
                float _Noise3Scale;
                float _Noise3Threshold;
            CBUFFER_END

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionHCS = TransformObjectToHClip(input.positionOS.xyz);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                return 0;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 normalWS    : TEXCOORD0;
            };

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                
                half4 _HighlightColor;
                half4 _MidtoneColor;
                half4 _ShadowColor;
                float _UsePalette;

                int _Cuts;
                float _Steepness;
                float _Wrap;
                float _ThresholdGradientSize;
                
                float _UseDither;
                float _DitherStrength;
                
                half4 _Color2;
                float _Noise2Scale;
                float _Noise2Threshold;
                
                half4 _Color3;
                float _Noise3Scale;
                float _Noise3Threshold;
            CBUFFER_END

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionHCS = TransformObjectToHClip(input.positionOS.xyz);
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                float3 normal = normalize(input.normalWS);
                return half4(normal * 0.5 + 0.5, 0.0);
            }
            ENDHLSL
        }
    }
}