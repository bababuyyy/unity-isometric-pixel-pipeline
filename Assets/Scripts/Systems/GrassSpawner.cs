using System.Collections.Generic;
using UnityEngine;

public class GrassSpawner : MonoBehaviour
{
    [Header("Grass Settings")]
    [Tooltip("Total number of instances to spawn.")]
    public int grassCount = 10000;
    public Mesh grassMesh;
    public Material grassMaterial;
    
    [Header("Spawn Area")]
    [Tooltip("Center and size of the bounding box for random distribution.")]
    public Bounds spawnArea = new Bounds(Vector3.zero, new Vector3(50, 20, 50));
    public LayerMask terrainLayer = ~0; // Default: Everything

    [Header("Scale Variation")]
    public float minHeight = 0.8f;
    public float maxHeight = 1.2f;

    // DrawMeshInstanced supports a maximum of 1023 instances per draw call.
    private const int _maxInstancesPerBatch = 1023;
    
    // Store batches of instances.
    private List<Matrix4x4[]> _matrixBatches = new List<Matrix4x4[]>();
    private List<Vector4[]> _terrainNormalBatches = new List<Vector4[]>();
    
    private MaterialPropertyBlock _mpb;

    private void Start()
    {
        // Ensure resources are assigned.
        if (grassMesh == null || grassMaterial == null)
        {
            Debug.LogError("GrassSpawner: Mesh or Material not assigned in Inspector.");
            return;
        }

        _mpb = new MaterialPropertyBlock();
        _GenerateGrass();
    }

    private void _GenerateGrass()
    {
        int instancesLeft = grassCount;
        
        while (instancesLeft > 0)
        {
            int currentBatchSize = Mathf.Min(instancesLeft, _maxInstancesPerBatch);
            
            Matrix4x4[] matrixBatch = new Matrix4x4[currentBatchSize];
            Vector4[] normalBatch = new Vector4[currentBatchSize];

            int validInstances = 0;

            // Add a safety margin of attempts to prevent infinite loops if raycasts fail.
            for (int i = 0; i < currentBatchSize * 2 && validInstances < currentBatchSize; i++)
            {
                // Random point at the top of the bounds.
                Vector3 randomTopPoint = new Vector3(
                    Random.Range(spawnArea.min.x, spawnArea.max.x),
                    spawnArea.max.y,
                    Random.Range(spawnArea.min.z, spawnArea.max.z)
                );

                // Raycast downwards to find the terrain.
                if (Physics.Raycast(randomTopPoint, Vector3.down, out RaycastHit hit, spawnArea.size.y, terrainLayer))
                {
                    Vector3 spawnPos = hit.point;
                    Vector3 terrainNormal = hit.normal;
                    
                    // Apply random Y rotation to break geometric repetition.
                    Quaternion rotation = Quaternion.Euler(0, Random.Range(0, 360f), 0);
                    
                    float heightScale = Random.Range(minHeight, maxHeight);
                    Vector3 scale = new Vector3(0.35f, heightScale, 1);

                    // Build TRS matrix.
                    matrixBatch[validInstances] = Matrix4x4.TRS(spawnPos, rotation, scale);
                    // Store terrain normal as a Vector4 for buffer compatibility.
                    normalBatch[validInstances] = new Vector4(terrainNormal.x, terrainNormal.y, terrainNormal.z, 0);

                    validInstances++;
                }
            }

            // Store the batch if valid instances were found.
            if (validInstances > 0)
            {
                _matrixBatches.Add(matrixBatch);
                _terrainNormalBatches.Add(normalBatch);
            }

            instancesLeft -= currentBatchSize;
        }
    }

    private void Update()
    {
        if (grassMesh == null || grassMaterial == null || _matrixBatches.Count == 0) return;

        // Render all grass batches every frame.
        for (int i = 0; i < _matrixBatches.Count; i++)
        {
            // Inject terrain normals into the material property block.
            _mpb.SetVectorArray("_TerrainNormal", _terrainNormalBatches[i]);
            
            // Draw instances directly to avoid hierarchy overhead.
            Graphics.DrawMeshInstanced(grassMesh, 0, grassMaterial, _matrixBatches[i], _matrixBatches[i].Length, _mpb, UnityEngine.Rendering.ShadowCastingMode.Off, false);
        }
    }

    // Draw a translucent green cube in the Scene View to visualize the spawn bounds.
    private void OnDrawGizmosSelected()
    {
        Gizmos.color = new Color(0, 1, 0, 0.2f);
        Gizmos.DrawCube(spawnArea.center, spawnArea.size);
    }
}