using UnityEngine;

public class IsometricCameraController : MonoBehaviour
{
    [Header("Initial Rotation")]
    public Vector3 fixedRotation = new Vector3(13.206f, 51.511f, 1.494f);

    [Header("Follow Target")]
    public Transform target;

    [Header("Smoothing")]
    public float smoothing = 30f;

    [Header("Orbit (Right Mouse Drag)")]
    public float orbitSensitivity = 0.3f;
    public float minPitch = 5f;
    public float maxPitch = 60f;

    [Header("Zoom")]
    public float zoomSpeed = 2f;
    public float minZoom = 3f;
    public float maxZoom = 15f;
    public float defaultZoom = 5f;

    [Header("Pixel-Perfect")]
    public bool usePixelSnap = true;
    public PixelRendererFeature pixelRendererFeature;

    private Camera _cam;
    private Vector3 _truePosition;
    private Vector3 _targetPosition;
    private float _targetZoom;
    private float _currentYRotation;
    private float _targetYRotation;
    private float _currentXRotation;
    private float _targetXRotation;

    private void Awake()
    {
        _cam = GetComponentInChildren<Camera>();
        if (_cam == null)
        {
            Debug.LogError("[IsometricCamera] No Camera found in CameraPivot children!");
            return;
        }

        if (!_cam.orthographic)
        {
            Debug.LogWarning("[IsometricCamera] Camera is not Orthographic. Forcing adjustment.");
            _cam.orthographic = true;
        }

        _currentYRotation = fixedRotation.y;
        _targetYRotation = fixedRotation.y;
        _currentXRotation = fixedRotation.x;
        _targetXRotation = fixedRotation.x;

        transform.rotation = Quaternion.Euler(_currentXRotation, _currentYRotation, fixedRotation.z);

        if (target != null)
        {
            _truePosition = target.position;
        }
        else
        {
            _truePosition = transform.position;
        }

        _targetPosition = _truePosition;
        _targetZoom = defaultZoom;
        _cam.orthographicSize = _targetZoom;

        Debug.Log("[IsometricCamera] Camera Pivot initialized successfully.");
    }

    private void LateUpdate()
    {
        if (_cam == null) return;

        HandleOrbitInput();
        HandleZoomInput();
        HandleFollowTarget();
        ApplyTransformations();
    }

    private void HandleOrbitInput()
    {
        if (Input.GetMouseButton(1))
        {
            float mouseX = Input.GetAxis("Mouse X");
            float mouseY = Input.GetAxis("Mouse Y");

            _targetYRotation += mouseX * orbitSensitivity * 10f;
            _targetXRotation -= mouseY * orbitSensitivity * 10f;

            _targetXRotation = Mathf.Clamp(_targetXRotation, minPitch, maxPitch);
        }

        _currentYRotation = _targetYRotation;
        _currentXRotation = _targetXRotation;
    }

    private void HandleZoomInput()
    {
        float scroll = Input.GetAxis("Mouse ScrollWheel");
        if (scroll != 0f)
        {
            _targetZoom -= scroll * zoomSpeed;
            _targetZoom = Mathf.Clamp(_targetZoom, minZoom, maxZoom);
        }
    }

    private void HandleFollowTarget()
    {
        if (target != null)
        {
            _targetPosition = target.position;
        }
    }

    private void ApplyTransformations()
    {
        // Apply rotation to pivot.
        transform.rotation = Quaternion.Euler(_currentXRotation, _currentYRotation, fixedRotation.z);

        // Smooth zoom.
        _cam.orthographicSize = Mathf.Lerp(_cam.orthographicSize, _targetZoom, smoothing * Time.deltaTime);

        // Smooth pivot translation.
        _truePosition = Vector3.Lerp(_truePosition, _targetPosition, smoothing * Time.deltaTime);

        // Pixel-Perfect logic with sub-texel panning.
        if (usePixelSnap)
        {
            int pixelRenderHeight = pixelRendererFeature != null ? pixelRendererFeature.settings.height : 360;
            float texelSize = _cam.orthographicSize * 2f / pixelRenderHeight;
            
            // Convert to local space of the camera's visual perspective.
            Vector3 localPos = _cam.transform.InverseTransformPoint(_truePosition);
            
            // Snap XY to texel grid.
            float snappedX = Mathf.Round(localPos.x / texelSize) * texelSize;
            float snappedY = Mathf.Round(localPos.y / texelSize) * texelSize;
            
            // Calculate rounding error.
            Vector2 snapError = new Vector2(localPos.x - snappedX, localPos.y - snappedY);
            
            // Convert error to UV space.
            float uvOffsetX = snapError.x / (_cam.orthographicSize * 2f * _cam.aspect);
            float uvOffsetY = snapError.y / (_cam.orthographicSize * 2f);
            
            // Apply snapped position to pivot.
            Vector3 snappedPos = new Vector3(snappedX, snappedY, localPos.z);
            transform.position = _cam.transform.TransformPoint(snappedPos);
            
            // Pass global UV offset to the upscale shader to compensate for movement.
            Shader.SetGlobalVector("_PixelPanOffset", new Vector4(uvOffsetX, uvOffsetY, 0, 0));
        }
        else
        {
            transform.position = _truePosition;
            Shader.SetGlobalVector("_PixelPanOffset", Vector4.zero);
        }
    }
}