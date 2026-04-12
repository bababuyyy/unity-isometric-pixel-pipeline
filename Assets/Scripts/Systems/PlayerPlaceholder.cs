using UnityEngine;

[RequireComponent(typeof(Rigidbody))]
public class PlayerPlaceholder : MonoBehaviour
{
    [Header("Movement")]
    public float moveSpeed = 5f;

    [Header("Jump")]
    public float jumpForce = 5f;
    public LayerMask groundLayer;

    [Header("Ground Check")]
    [SerializeField] private float _groundCheckRadius = 0.3f;
    [SerializeField] private float _groundCheckDistance = 0.2f;

    private Rigidbody _rb;
    private bool _isGrounded;

    private void Awake()
    {
        _rb = GetComponent<Rigidbody>();
        if (_rb == null)
        {
            Debug.LogError("[Player] Rigidbody not found!");
            return;
        }

        // Apply ideal physics settings for the player.
        _rb.freezeRotation = true;
        _rb.interpolation = RigidbodyInterpolation.Interpolate;
        _rb.collisionDetectionMode = CollisionDetectionMode.Continuous;

        Debug.Log("[Player] Placeholder initialized successfully.");
    }

    private void Update()
    {
        CheckGrounded();

        // Check jump input in Update for better responsiveness.
        if (Input.GetKeyDown(KeyCode.Space) && _isGrounded)
        {
            Jump();
        }
    }

    private void FixedUpdate()
    {
        Move();
    }

    private void CheckGrounded()
    {
        // Spherecast downwards to detect ground.
        _isGrounded = Physics.SphereCast(
            transform.position,
            _groundCheckRadius,
            Vector3.down,
            out RaycastHit hit,
            _groundCheckDistance,
            groundLayer
        );
    }

    private void Move()
    {
        float h = Input.GetAxis("Horizontal");
        float v = Input.GetAxis("Vertical");

        // Project camera vectors onto the XZ plane.
        Vector3 camForward = Camera.main.transform.forward;
        camForward.y = 0f;
        camForward.Normalize();

        Vector3 camRight = Camera.main.transform.right;
        camRight.y = 0f;
        camRight.Normalize();

        // Calculate direction based on camera perspective.
        Vector3 moveDir = (camForward * v + camRight * h).normalized;

        // Use linearVelocity for Unity 6 compatibility.
        _rb.linearVelocity = new Vector3(moveDir.x * moveSpeed, _rb.linearVelocity.y, moveDir.z * moveSpeed);
    }

    private void Jump()
    {
        _rb.AddForce(Vector3.up * jumpForce, ForceMode.Impulse);
    }

    private void OnDrawGizmosSelected()
    {
        // Visualize the ground check radius in the Editor.
        Gizmos.color = Color.magenta;
        Gizmos.DrawWireSphere(transform.position + Vector3.down * _groundCheckDistance, _groundCheckRadius);
    }
}