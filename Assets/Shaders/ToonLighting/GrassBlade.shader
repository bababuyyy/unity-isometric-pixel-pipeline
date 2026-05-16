Shader "Custom/GrassBlade"
{
    Properties
    {
        _GrassTexture ("Grass Sprite", 2D) = "white" {}
        _BaseColor ("Base Color", Color) = (0.35, 0.55, 0.2, 1)
        _Cutoff ("Alpha Cutoff", Range(0, 1)) = 0.5

        _Color2 ("Color 2 (Patch)", Color) = (0.3, 0.5, 0.2, 1)
        _Noise2 ("Noise 2", 2D) = "white" {}
        _Noise2Scale ("Noise 2 Scale", Range(0.0, 1.0)) = 0.005
 
        _Noise2Threshold ("Noise 2 Threshold", Range(0.0, 1.0)) = 0.604

        _Color3 ("Color 3 (Patch)", Color) = (0.25, 0.45, 0.15, 1)
        _Noise3 ("Noise 3", 2D) = "white" {}
        _Noise3Scale ("Noise 3 Scale", Range(0.0, 0.1)) = 0.003
        _Noise3Threshold ("Noise 3 Threshold", Range(0.0, 1.0)) = 0.661

        _AccentTexture1 ("Accent 1 Sprite", 2D) = "white" {}
        _AccentColor1 ("Accent 
1 Color", Color) = (0.4, 0.6, 0.1, 1)
        _AccentFrequency1 ("Accent 1 Frequency", Range(0.0, 0.05)) = 0.001
        _AccentHeight1 ("Accent 1 Height Offset", Range(0.0, 1.0)) = 0.5
        _AccentScale1 ("Accent 1 Scale", Range(0.0, 2.0)) = 1.0

        _AccentTexture2 ("Accent 2 Sprite", 2D) = "white" {}
        _AccentColor2 ("Accent 2 Color", Color) = (0.5, 0.7, 0.15, 1)
        _AccentFrequency2 ("Accent 2 Frequency", Range(0.0, 0.05)) = 
0.1
        _AccentHeight2 ("Accent 2 Height Offset", Range(0.0, 1.0)) = 0.5
        _AccentScale2 ("Accent 2 Scale", Range(0.0, 2.0)) = 1.0

        _Cuts ("Cuts", Range(1, 8)) = 3
        _Steepness ("Steepness", Range(1, 8)) = 1.0
        _Wrap ("Wrap", Range(-2.0, 2.0)) = 0.0
        _ThresholdGradientSize ("Threshold Gradient Size", Range(0.0, 1.0)) = 0.2

        _WindNoise ("Wind Noise", 2D) = "gray" {}
 
        _WindNoiseScale ("Wind Noise Scale", Range(0.0, 0.2)) = 0.071
        _WindNoiseSpeed ("Wind Noise Speed", Range(0.0, 0.2)) = 0.025
        _WindNoiseThreshold ("Wind Noise Threshold", Range(-1.0, 1.0)) = 0.365
        _WindDirection ("Wind Direction", Vector) = (0.0, 1.0, 0, 0)
        _WindSwayAngle ("Wind Sway Angle (degrees)", Range(0.0, 180.0)) = 60.0
        _NoiseDivergeAngle ("Noise Diverge Angle (degrees)", Range(0.0, 45.0)) = 10.0
        

        _FakePerspectiveScale ("Fake Perspective Scale", Range(-0.15, 0.6)) = 0.3
        
        [Toggle] _UseDither ("Use Dither", Float) = 0
        _DitherStrength ("Dither Strength", Range(0.0, 1.0)) = 0.1
    }

    SubShader
    {
        Tags 
        { 
            "RenderType" = "TransparentCutout" 
    
            "RenderPipeline" = "UniversalPipeline" 
            "Queue" = "AlphaTest" 
            "DisableBatching" = "True" 
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
     
            
            Cull Off 

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
         
            #pragma multi_compile _ _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl" 
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl" 

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID 
            };
            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 instancePosWS : TEXCOORD0; 
                float2 uv         : TEXCOORD1;
                float3 normalWS   : NORMAL;       
                float2 seeds      : TEXCOORD3;    
                float3 positionWS  : TEXCOORD4;
                float windNoiseSample : TEXCOORD5;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            sampler2D _GrassTexture;
            sampler2D _Noise2; 
            sampler2D _Noise3;
            sampler2D _AccentTexture1;
            sampler2D _AccentTexture2;
            sampler2D _WindNoise;

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
            
            float4 _GlobalAmbientColor;

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float _Cutoff;
                half4 _Color2;
                float _Noise2Scale;
                float _Noise2Threshold;
                
                half4 _Color3;
                float _Noise3Scale;
                float _Noise3Threshold;
                
                half4 _AccentColor1;
                float _AccentFrequency1;
                float _AccentHeight1;
                float _AccentScale1;
                half4 _AccentColor2;
                float _AccentFrequency2;
                float _AccentHeight2;
                float _AccentScale2;
                
                int _Cuts;
                float _Steepness;
                float _Wrap;
                float _ThresholdGradientSize;

                float _WindNoiseScale;
                float _WindNoiseSpeed;
                float _WindNoiseThreshold;
                float4 _WindDirection;
                float _WindSwayAngle;
                float _NoiseDivergeAngle;
                
                float _FakePerspectiveScale;
                
                float _UseDither;
                float _DitherStrength;
            CBUFFER_END 

            UNITY_INSTANCING_BUFFER_START(InstancedProps)
                UNITY_DEFINE_INSTANCED_PROP(float4, _TerrainNormal)
            UNITY_INSTANCING_BUFFER_END(InstancedProps)

            float HashPos(float2 p)
            {
                return frac(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
            }

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

            // 4x4 Bayer Dither Function.
            float BayerDither(float2 screenPos)
            {
                int x = int(fmod(screenPos.x, 4.0));
                int y = int(fmod(screenPos.y, 4.0));
                
                float bayer[16] = {
                     0.0,  8.0,  2.0, 10.0,
                    12.0,  4.0, 14.0,  6.0,
                     3.0, 11.0,  1.0,  9.0,
               
                    15.0,  7.0, 13.0,  5.0
                };
                return bayer[y * 4 + x] / 16.0;
            }

            float GetCloudNoise(float3 worldPos)
            {
                // Guard: previne divisão por zero quando luz está no horizonte
                if (abs(_CloudLightDirection.y) < 0.05f) return 1.0f;
                
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

            Varyings vert(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input); 
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                float3 instancePosWS = UNITY_MATRIX_M._m03_m13_m23;
                float scaleX = length(float3(UNITY_MATRIX_M._m00, UNITY_MATRIX_M._m10, UNITY_MATRIX_M._m20)); 
                float scaleY = length(float3(UNITY_MATRIX_M._m01, UNITY_MATRIX_M._m11, UNITY_MATRIX_M._m21));
                float seed1 = HashPos(instancePosWS.xz);
                float seed2 = HashPos(instancePosWS.xz + float2(3.14159, 3.14159)); 
                output.seeds = float2(seed1, seed2);

                float3 posOS = input.positionOS.xyz;
                if (seed1 < _AccentFrequency1)
                {
                    posOS.y += _AccentHeight1;
                    posOS *= _AccentScale1; 
                }
                else if (seed2 < _AccentFrequency2)
                {
                    posOS.y += _AccentHeight2;
                    posOS *= _AccentScale2; 
                }

                float2 windDir1 = RotateVec2(_WindDirection.xy, _NoiseDivergeAngle);
                float2 windDir2 = RotateVec2(_WindDirection.xy, -_NoiseDivergeAngle);

                float time = _Time.y;
                float2 windTimeDir1 = time * _WindNoiseSpeed * normalize(windDir1);
                float2 windTimeDir2 = time * _WindNoiseSpeed * normalize(windDir2);

                float4 uv1 = float4(instancePosWS.xz * _WindNoiseScale + windTimeDir1, 0, 0);
                float4 uv2 = float4(instancePosWS.xz * (_WindNoiseScale * 0.8) + (windTimeDir2 * 0.89 + float2(1.047, 1.047)), 0, 0);
                float windSample1 = tex2Dlod(_WindNoise, uv1).r;
                float windSample2 = tex2Dlod(_WindNoise, uv2).r;

                float windSample = windSample1 * windSample2;
                windSample = saturate(windSample + _WindNoiseThreshold);
                windSample = (windSample - 0.5) * 2.0;

                float windAngle = windSample * radians(_WindSwayAngle) * 0.5;
                float sinW = sin(windAngle);
                float cosW = cos(windAngle);

                float rotatedX = posOS.x * cosW - posOS.y * sinW;
                float rotatedY = posOS.x * sinW + posOS.y * cosW;

                posOS.x = rotatedX;
                posOS.y = rotatedY;

                float3 cameraUp = UNITY_MATRIX_V[1].xyz;
                float3 cameraRight = UNITY_MATRIX_V[0].xyz; 
                
                float3 positionWS = instancePosWS 
                                  + cameraRight * posOS.x * scaleX 
                                  + cameraUp * posOS.y * scaleY;
                output.positionHCS = TransformWorldToHClip(positionWS); 
                output.instancePosWS = instancePosWS;
                output.uv = input.uv;
                output.positionWS = positionWS;
                output.windNoiseSample = windSample; 

                float4 terrainNorm = UNITY_ACCESS_INSTANCED_PROP(InstancedProps, _TerrainNormal);
                output.normalWS = length(terrainNorm.xyz) < 0.1 ? float3(0, 1, 0) : terrainNorm.xyz;

                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                float2 uv = input.uv;

                uv.x -= 0.5;
                float fpSample = input.windNoiseSample * _FakePerspectiveScale;
                float3 camForward = -UNITY_MATRIX_V[2].xyz;
                fpSample *= dot(camForward.xz, normalize(_WindDirection.xy));
                uv.x *= uv.y * fpSample + 1.0;
                uv.x += 0.5;
                uv.x = clamp(uv.x, 0.0, 1.0);
                half4 spriteColor; 
                half3 albedo;
                if (input.seeds.x < _AccentFrequency1)
                {
                    spriteColor = tex2D(_AccentTexture1, uv);
                    clip(spriteColor.a - _Cutoff); 
                    albedo = _AccentColor1.rgb;
                }
                else if (input.seeds.y < _AccentFrequency2)
                {
                    spriteColor = tex2D(_AccentTexture2, uv);
                    clip(spriteColor.a - _Cutoff); 
                    albedo = _AccentColor2.rgb;
                }
                else
                {
                    spriteColor = tex2D(_GrassTexture, uv);
                    clip(spriteColor.a - _Cutoff); 

                    float noise2Val = tex2D(_Noise2, input.instancePosWS.xz * _Noise2Scale).r;
                    float noise3Val = tex2D(_Noise3, input.instancePosWS.xz * _Noise3Scale).r;

                    albedo = _BaseColor.rgb;
                    if (noise2Val > _Noise2Threshold) albedo = _Color2.rgb; 
                    if (noise3Val > _Noise3Threshold) albedo = _Color3.rgb;
                } 

                float3 normalWS = normalize(input.normalWS);
                float3 billboardWS = input.instancePosWS + float3(0, 0.15, 0); 
                billboardWS.xz += (input.seeds - 0.03) * 0.03;
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(billboardWS));
                float diffuseAmount = dot(normalWS, mainLight.direction) + _Wrap; 
                diffuseAmount *= _Steepness;

                float cloudLight = GetCloudNoise(input.instancePosWS);
                diffuseAmount = min(diffuseAmount, cloudLight);
                // Apply Bayer Dithering.
                if (_UseDither > 0.5)
                {
                    float2 screenPos = input.positionHCS.xy;
                    float bayerVal = BayerDither(screenPos);
                    diffuseAmount = saturate(diffuseAmount + (bayerVal - 0.5) * _DitherStrength * 0.25);
                }

                // Hybrid Toon Stepping.
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

                float3 finalLighting = diffuseStepped * mainLight.color * mainLight.shadowAttenuation;
                float3 ambient = _GlobalAmbientColor.rgb;
                half3 finalColor = albedo * (finalLighting + ambient); 
                return half4(finalColor, 1.0);
            } 
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            
            Cull Off

        
            HLSLPROGRAM 
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            struct Attributes
            {
   
                 float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID 
            };
            struct Varyings
            { 
                float4 positionHCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float2 seeds      : TEXCOORD1; 
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            sampler2D _GrassTexture;
            sampler2D _AccentTexture1;
            sampler2D _AccentTexture2;
            sampler2D _WindNoise;

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float _Cutoff; 
                
                half4 _Color2;
                float _Noise2Scale;
                float _Noise2Threshold;
                
                half4 _Color3;
                float _Noise3Scale;
                float _Noise3Threshold;
                
                half4 _AccentColor1;
                float _AccentFrequency1;
                float _AccentHeight1;
                float _AccentScale1; 
                
                half4 _AccentColor2;
                float _AccentFrequency2;
                float _AccentHeight2;
                float _AccentScale2;
                
                int _Cuts;
                float _Steepness;
                float _Wrap;
                float _ThresholdGradientSize;

                float _WindNoiseScale;
                float _WindNoiseSpeed;
                float _WindNoiseThreshold;
                float4 _WindDirection;
                float _WindSwayAngle;
                float _NoiseDivergeAngle;
                
                float _FakePerspectiveScale;
                
                float _UseDither;
                float _DitherStrength;
            CBUFFER_END 

            float3 _LightDirection;
            float HashPos(float2 p)
            {
                return frac(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
            } 

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

            Varyings vert(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input); 
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                float3 instancePosWS = UNITY_MATRIX_M._m03_m13_m23;
                float scaleX = length(float3(UNITY_MATRIX_M._m00, UNITY_MATRIX_M._m10, UNITY_MATRIX_M._m20));
                float scaleY = length(float3(UNITY_MATRIX_M._m01, UNITY_MATRIX_M._m11, UNITY_MATRIX_M._m21));
                float seed1 = HashPos(instancePosWS.xz);
                float seed2 = HashPos(instancePosWS.xz + float2(3.14159, 3.14159));
                output.seeds = float2(seed1, seed2);

                float3 posOS = input.positionOS.xyz;
                if (seed1 < _AccentFrequency1) 
                {
                    posOS.y += _AccentHeight1;
                    posOS *= _AccentScale1; 
                }
                else if (seed2 < _AccentFrequency2)
                {
                    posOS.y += _AccentHeight2;
                    posOS *= _AccentScale2; 
                }

                float2 windDir1 = RotateVec2(_WindDirection.xy, _NoiseDivergeAngle);
                float2 windDir2 = RotateVec2(_WindDirection.xy, -_NoiseDivergeAngle);

                float time = _Time.y;
                float2 windTimeDir1 = time * _WindNoiseSpeed * normalize(windDir1);
                float2 windTimeDir2 = time * _WindNoiseSpeed * normalize(windDir2);

                float4 uv1 = float4(instancePosWS.xz * _WindNoiseScale + windTimeDir1, 0, 0);
                float4 uv2 = float4(instancePosWS.xz * (_WindNoiseScale * 0.8) + (windTimeDir2 * 0.89 + float2(1.047, 1.047)), 0, 0);
                float windSample1 = tex2Dlod(_WindNoise, uv1).r;
                float windSample2 = tex2Dlod(_WindNoise, uv2).r;

                float windSample = windSample1 * windSample2;
                windSample = saturate(windSample + _WindNoiseThreshold);
                windSample = (windSample - 0.5) * 2.0;

                float windAngle = windSample * radians(_WindSwayAngle) * 0.5;
                float sinW = sin(windAngle);
                float cosW = cos(windAngle);

                float rotatedX = posOS.x * cosW - posOS.y * sinW;
                float rotatedY = posOS.x * sinW + posOS.y * cosW;

                posOS.x = rotatedX;
                posOS.y = rotatedY;

                float3 cameraUp = UNITY_MATRIX_V[1].xyz;
                float3 cameraRight = UNITY_MATRIX_V[0].xyz; 
                
                float3 positionWS = instancePosWS 
                                  + cameraRight * posOS.x * scaleX 
                                  + cameraUp * posOS.y * scaleY;
                output.positionHCS = TransformWorldToHClip(ApplyShadowBias(positionWS, float3(0,1,0), _LightDirection));
                output.uv = input.uv;
                
                return output;
            } 

            half4 frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                half4 spriteColor; 

                if (input.seeds.x < _AccentFrequency1)
                {
                    spriteColor = tex2D(_AccentTexture1, input.uv);
                } 
                else if (input.seeds.y < _AccentFrequency2)
                {
                    spriteColor = tex2D(_AccentTexture2, input.uv);
                } 
                else
                {
                    spriteColor = tex2D(_GrassTexture, input.uv);
                } 

                clip(spriteColor.a - _Cutoff);
                return 0; 
            }
            ENDHLSL
        }
    }
}