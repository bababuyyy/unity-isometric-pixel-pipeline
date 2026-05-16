using UnityEngine;

public class CloudShadowManager : MonoBehaviour
{
    [Header("References")]
    [Tooltip("Main directional light (Sun).")]
    public Light directionalLight;
    
    [Tooltip("Noise texture used to generate clouds.")]
    public Texture2D cloudNoise;

    [Header("Cloud Parameters")]
    public float cloudScale = 50.0f;
    public float cloudWorldY = 20.0f;
    public float cloudSpeed = 0.02f;
    public float cloudContrast = 2.0f;
    [Range(-1f, 1f)] public float cloudThreshold = 0.3f;
    public Vector2 cloudDirection = new Vector2(1, 0);
    [Range(0f, 1f)] public float cloudShadowMin = 0.3f;
    [Range(0f, 45f)] public float cloudDivergeAngle = 10.0f;
    [Range(1f, 5f)] public float cloudPower = 1.0f;

    // Cache global shader property IDs for performance.
    private int _cloudNoiseId;
    private int _cloudScaleId;
    private int _cloudWorldYId;
    private int _cloudSpeedId;
    private int _cloudContrastId;
    private int _cloudThresholdId;
    private int _cloudDirectionId;
    private int _cloudShadowMinId;
    private int _cloudDivergeAngleId;
    private int _cloudLightDirectionId;
    private int _cloudPowerId;

    private void Awake()
    {
        if (directionalLight == null)
        {
            Debug.LogError("CloudShadowManager: Directional Light not assigned in Inspector!");
        }
        if (cloudNoise == null)
        {
            Debug.LogError("CloudShadowManager: Cloud Noise texture not assigned in Inspector!");
        }

        // Cache IDs during initialization.
        _cloudNoiseId = Shader.PropertyToID("_CloudNoise");
        _cloudScaleId = Shader.PropertyToID("_CloudScale");
        _cloudWorldYId = Shader.PropertyToID("_CloudWorldY");
        _cloudSpeedId = Shader.PropertyToID("_CloudSpeed"); // Mantido conforme constraint
        _cloudContrastId = Shader.PropertyToID("_CloudContrast");
        _cloudThresholdId = Shader.PropertyToID("_CloudThreshold");
        _cloudDirectionId = Shader.PropertyToID("_CloudDirection");
        _cloudShadowMinId = Shader.PropertyToID("_CloudShadowMin");
        _cloudDivergeAngleId = Shader.PropertyToID("_CloudDivergeAngle");
        _cloudPowerId = Shader.PropertyToID("_CloudPower");
    }

    private void Update()
    {
        if (directionalLight == null || cloudNoise == null) return;

        // Assign global texture.
        Shader.SetGlobalTexture(_cloudNoiseId, cloudNoise);

        // Assign global floats.
        Shader.SetGlobalFloat(_cloudScaleId, cloudScale);
        Shader.SetGlobalFloat(_cloudWorldYId, cloudWorldY);
        // A responsabilidade do _CloudSpeed agora é do DayNightCycleManager
        Shader.SetGlobalFloat(_cloudContrastId, cloudContrast);
        Shader.SetGlobalFloat(_cloudThresholdId, cloudThreshold);
        Shader.SetGlobalFloat(_cloudShadowMinId, cloudShadowMin);
        Shader.SetGlobalFloat(_cloudDivergeAngleId, cloudDivergeAngle);
        Shader.SetGlobalFloat(_cloudPowerId, cloudPower);

        // Assign global vectors.
        Shader.SetGlobalVector(_cloudDirectionId, new Vector4(cloudDirection.x, cloudDirection.y, 0, 0));
    }
}