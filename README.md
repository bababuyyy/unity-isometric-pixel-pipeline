# Unity Isometric Pixel Art Pipeline
**A complete pixel art render pipeline for Unity 6 URP** — toon shading, GPU-instanced grass, adaptive outline, and sharp upscale with pixel-perfect panning.

Built for isometric 3D games targeting a hand-crafted pixel art aesthetic, inspired by the work of [t3ssel8r](https://www.youtube.com/@t3ssel8r).



https://github.com/user-attachments/assets/2ce64edf-1cb1-42fd-8b4b-039c94fd1b00



---

## Features

- **ToonLit Shader** — toon stepping, Bayer dithering, cloud shadows, world-space patch system, palette toggle
- **GrassBlade Shader** — GPU instancing, billboard wind, cloud shadows, fake perspective, accent sprites
- **Outline Shader** — adaptive 1px silhouette + crease detection (KodyKing/Dylearn method), color-based darkening
- **Sharp Upscale** — pixel-perfect upscale from internal resolution with sub-texel panning compensation
- **PixelRendererFeature** — 5-pass URP render graph pipeline (copy → downsample → outline → composite → upscale)
- **CloudShadowManager** — scrolling cloud shadows via global noise texture, affects all shaders simultaneously
- **IsometricCameraController** — orthographic isometric camera with orbit, zoom, follow target, and pixel snap

---

## Requirements

- Unity 6 (6000.x)
- Universal Render Pipeline (URP)
- SSAO must be disabled (causes artifacts with GPU grass)

---

## Setup

1. Copy the `Rendering/RenderFeatures` folder into your URP project
2. Add `PixelRendererFeature` to your URP Renderer asset
3. Assign the three materials: `MAT_Outline`, `MAT_Composite`, `MAT_SharpU`
4. Add `CloudShadowManager` to any GameObject and assign your directional light and `CloudNoise_v5.png`
5. Place `IsometricCameraController` on your camera pivot and drag in the `PixelRendererFeature` reference

---

## Project Structure

```
Assets/
├── Rendering/
│   └── RenderFeatures/
│       ├── PixelRendererFeature.cs
│       └── OutlineRendererFeature.cs
├── Scripts/
│   └── Systems/
│       ├── CloudShadowManager.cs
│       ├── GrassSpawner.cs
│       ├── IsometricCameraController.cs
│       └── PlayerPlaceholder.cs
└── Shaders/
    ├── ToonLighting/
    │   ├── ToonLit.shader
    │   └── GrassBlade.shader
    └── Grass/
        ├── OutlineShader.shader
        ├── CompositeShader.shader
        └── SharpUpscaleShader.shader
```

---

## Known Limitations

- Crease detection at object bases where grass occludes the depth buffer — less noticeable with dense grass and real assets
- Cloud shadow cuts clamp diffuse before toon stepping — workaround pending
- Grass is excluded from depth/normals passes to avoid outline artifacts

---

## License

MIT — free for personal and commercial use. If this helped your project, consider leaving a star.

---

Made by [Bababuyyy](https://github.com/bababuyyy)
