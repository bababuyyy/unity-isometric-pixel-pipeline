using UnityEngine;

[ExecuteInEditMode]
public class DayNightCycleManager : MonoBehaviour
{
    [Header("Time Control")]
    [Range(0f, 1f)]
    public float timeOfDay = 0.5f; // 0.25 = Amanhecer, 0.5 = Meio-dia, 0.75 = Pôr do sol, 0.0 = Meia-noite
    public float dayDurationInSeconds = 120f;
    public bool isTimePassing = true;

    [Header("Cycle Settings")]
    [Range(0f, 24f)]
    public float sunriseTime = 6f;
    [Range(0f, 24f)]
    public float sunsetTime = 18f;

    [Header("Orbit Settings")]
    [Tooltip("Define a rotação do eixo orbital em Y. Para câmeras isométricas, ajuste este valor (ex: 45 ou -45) para que o arco do sol fique alinhado ou na diagonal perfeita da sua câmera, controlando a direção predominante das sombras.")]
    public float orbitAxisY = 45f;
    
    [Tooltip("Direção fixa para projeção das sombras de nuvem. Independente do ângulo do sol.")]
    public Vector3 cloudShadowDirection = new Vector3(0.2f, -1f, 0.2f);

    [Header("Light Sources")]
    public Light sunLight;
    public Light moonLight;

    [Header("Intensity Control")]
    public float maxSunIntensity = 1.2f;
    public float maxMoonIntensity = 0.2f;
    [Tooltip("Avaliada pelo Dot Product do sol (0 = horizonte, 1 = zênite). Define a curva de intensidade da luz baseada na altura do sol.")]
    public AnimationCurve lightIntensityCurve = AnimationCurve.Linear(0, 0, 1, 1);

    [Header("Visual Settings (Dot Product Based)")]
    [Tooltip("ATENÇÃO: As cores não são avaliadas pelo timeOfDay, mas sim pelo Dot Product do sol (0 = luz no horizonte, 1 = luz no zênite). O lado esquerdo do gradient (0) dita a cor do amanhecer/pôr do sol, e o direito (1) dita a cor do meio-dia. Ative [HDR].")]
    public Gradient sunColor;
    
    [Tooltip("ATENÇÃO: Avaliado pelo Dot Product da LUA. Esquerda (0) = lua no horizonte, Direita (1) = lua no zênite.")]
    public Gradient moonColor;
    
    [Tooltip("ATENÇÃO: Avaliado pelo Dot Product do sol. O lado esquerdo (0) afeta o horizonte (e toda a noite), o direito (1) afeta o meio-dia/zênite.")]
    public Gradient ambientColor;

    [Header("Cloud Settings")]
    public CloudShadowManager cloudShadowManager;

    // Identificadores para os Shader Globals cacheados
    private static readonly int CloudLightDirectionId = Shader.PropertyToID("_CloudLightDirection");
    private static readonly int GlobalAmbientColorId = Shader.PropertyToID("_GlobalAmbientColor");
    private static readonly int CloudSpeedId = Shader.PropertyToID("_CloudSpeed");

    void Update()
    {
#if UNITY_EDITOR
        if (!Application.isPlaying) 
        { 
            UpdateCycle(timeOfDay); 
            return; 
        }
#endif

        if (Application.isPlaying && isTimePassing && dayDurationInSeconds > 0)
        {
            timeOfDay += Time.deltaTime / dayDurationInSeconds;
            timeOfDay = Mathf.Repeat(timeOfDay, 1f);
        }

        UpdateCycle(timeOfDay);
    }

    private void UpdateCycle(float time)
    {
        float currentHour = time * 24f;
        
        // Verifica se é dia ou noite
        bool isDay = currentHour >= sunriseTime && currentHour < sunsetTime;
        
        // Calcula a rotação principal sem gimbal lock (Mathf.Lerp por percentage)
        float sunAngle = CalculateSunAngle(isDay, currentHour);
        float moonAngle = sunAngle + 180f;

        // Aplica as rotações usando quaternions separados para o eixo principal (right) e o offset isomátrico (up)
        if (sunLight != null)
        {
            sunLight.transform.rotation = Quaternion.Euler(0, orbitAxisY, 0) * Quaternion.AngleAxis(sunAngle, Vector3.right);
        }

        if (moonLight != null)
        {
            moonLight.transform.rotation = Quaternion.Euler(0, orbitAxisY, 0) * Quaternion.AngleAxis(moonAngle, Vector3.right);
        }

        // Calcula a intensidade baseada na inclinação do sol em relação ao zênite
        // Dot Product retorna: 1 (apontando direto pro chão), 0 (no horizonte), -1 (apontando pro céu)
        // O Clamp01 previne valores negativos que quebrariam a AnimationCurve durante a noite
        float sunDotProduct = 0f;
        if (sunLight != null)
        {
            sunDotProduct = Mathf.Clamp01(Vector3.Dot(sunLight.transform.forward, Vector3.down));
        }

        // Dot product isolado da lua para avaliar o moonColor corretamente
        float moonDotProduct = 0f;
        if (moonLight != null)
        {
            moonDotProduct = Mathf.Clamp01(Vector3.Dot(moonLight.transform.forward, Vector3.down));
        }

        // Avalia a curva de intensidade (baseada puramente na geometria do sol)
        float lightIntensity = lightIntensityCurve.Evaluate(sunDotProduct);

        if (sunLight != null)
        {
            sunLight.intensity = Mathf.Lerp(0f, maxSunIntensity, lightIntensity);
            sunLight.color = sunColor.Evaluate(sunDotProduct);
            sunLight.shadows = sunLight.intensity < 0.01f ? LightShadows.None : LightShadows.Soft;
        }

        if (moonLight != null)
        {
            // A lua usa o inverso da intensidade mapeada do sol de forma automática
            moonLight.intensity = Mathf.Lerp(maxMoonIntensity, 0f, lightIntensity);
            moonLight.color = moonColor.Evaluate(moonDotProduct);
            moonLight.shadows = moonLight.intensity < 0.01f ? LightShadows.None : LightShadows.Soft;
        }

        // Atualização da cor ambiente Global - Avaliada pelo dot product geométrico do sol
        Color currentAmbient = ambientColor.Evaluate(sunDotProduct);
        RenderSettings.ambientLight = currentAmbient;
        Shader.SetGlobalColor(GlobalAmbientColorId, currentAmbient);

        // Define a direção fixa das nuvens, normalizada para evitar distorções de escala
        Shader.SetGlobalVector(CloudLightDirectionId, cloudShadowDirection.normalized);

        // Sincroniza velocidade das nuvens com duração do ciclo usando o ID cacheado
        if (cloudShadowManager != null && dayDurationInSeconds > 0)
        {
            float scaledSpeed = isTimePassing ? cloudShadowManager.cloudSpeed / dayDurationInSeconds : 0f;
            Shader.SetGlobalFloat(CloudSpeedId, scaledSpeed);
        }
    }

    private float CalculateSunAngle(bool isDay, float currentHour)
    {
        if (isDay)
        {
            float dayDuration = sunsetTime - sunriseTime;
            float timePassed = currentHour - sunriseTime;
            float percentage = timePassed / dayDuration;
            
            return Mathf.Lerp(0f, 180f, percentage);
        }
        else
        {
            float nightDuration = (24f - sunsetTime) + sunriseTime;
            float timePassed;
            
            if (currentHour >= sunsetTime)
            {
                timePassed = currentHour - sunsetTime;
            }
            else
            {
                timePassed = (24f - sunsetTime) + currentHour;
            }
            
            float percentage = timePassed / nightDuration;
            return Mathf.Lerp(180f, 360f, percentage);
        }
    }
}