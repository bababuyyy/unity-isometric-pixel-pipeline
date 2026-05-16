# Unity Isometric Pixel Art Pipeline

**A complete pixel art render pipeline for Unity 6 URP** — toon shading, GPU-instanced grass, adaptive outline, and sharp upscale with pixel-perfect panning.

Built for isometric 3D games targeting a hand-crafted pixel art aesthetic, inspired by the work of [t3ssel8r](https://www.youtube.com/@t3ssel8r).

https://github.com/user-attachments/assets/2ce64edf-1cb1-42fd-8b4b-039c94fd1b00

---

## Table of Contents
- [How It Works](#how-it-works)
- [The 5-Pass Pipeline](#the-5-pass-pipeline)
- [Shaders](#shaders)
- [Day/Night Cycle](#daynight-cycle)
- [Pixel-Perfect Panning](#pixel-perfect-panning)
- [Why Not PBR?](#why-not-pbr)
- [Requirements](#requirements)
- [Project Structure](#project-structure)
- [Scene Hierarchy Reference](#scene-hierarchy-reference)
- [Setup From Scratch](#setup-from-scratch)
- [Inspector Parameters Reference](#inspector-parameters-reference)
- [Known Limitations](#known-limitations)
- [References & Credits](#references--credits)
- [License](#license)

---

## How It Works

The core idea is simple: render a 3D scene at a very low internal resolution (640×360), apply a 1-pixel outline shader at that resolution, then upscale to the screen with a sharp filter. Because the outline is computed at the internal resolution, every edge is guaranteed to be exactly 1 pixel — this is what makes it read as pixel art.

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐     ┌───────────┐     ┌──────────────┐
│ Scene        │────▶│ Downsample   │────▶│ Outline 1px  │────▶│ Composite │────▶│ Sharp        │
│ (full res)   │     │ (640×360)    │     │ (640×360)    │     │ (640×360) │     │ Upscale      │
└─────────────┘     └──────────────┘     └──────────────┘     └───────────┘     └──────────────┘
```

The outline shader samples Unity's depth and normals buffers to detect two types of edges:
- **Silhouette** — where objects meet the background (depth discontinuity)
- **Crease** — where two faces of the same object meet at a sharp angle (normal discontinuity)

Both are combined into a single RGBA mask (color + alpha) that gets composited over the scene color.

---

## The 5-Pass Pipeline

The `PixelRendererFeature` implements a 5-pass pipeline using Unity 6's Render Graph API:

### Pass 0 — CopyColor
Copies the full-resolution camera output to a safe buffer. This is necessary because the camera target can't be read and written simultaneously in the Render Graph.

### Pass 1 — Downsample Color
Downscales the scene from full resolution to the internal resolution (default 640×360) using bilinear filtering. This is the low-res scene that will become the final pixel art image.

### Pass 2 — Outline at Internal Resolution
**This is the most important architectural decision.** The outline shader runs at 640×360, not at full resolution. Because `_BlitTexture_TexelSize` is `(1/640, 1/360)`, each kernel step equals exactly 1 pixel in the final image. This guarantees 1px outlines regardless of screen resolution.

The shader samples `SampleSceneDepth` and `SampleSceneNormals` (which are still full-res buffers from the engine) but at UV coordinates spaced 1 internal pixel apart.

The outline is written to a separate texture with `FilterMode.Point` and `GraphicsFormat.R8G8B8A8_UNorm` — Point filter prevents bleed between pixels, and RGBA format is critical because the alpha channel carries the outline intensity.

### Pass 3 — Composite
Blends the outline mask over the low-res scene color. Silhouette darkens using the neighboring pixel's color. Crease brightens the center pixel's color. Both use alpha blending from the outline mask.

### Pass 4 — Sharp Upscale
Upscales from 640×360 to the screen resolution using a sharp interpolation method (fwidth + smoothstep). This avoids both the blurriness of bilinear filtering and the harshness of nearest-neighbor, producing clean pixel edges with mathematically smooth transitions at texel boundaries.

This pass also applies the **pixel-perfect panning offset** (`_PixelPanOffset`) to compensate for sub-texel camera movement.

---

## Shaders

### ToonLit (`Custom/ToonLit`)
Standard opaque material shader with toon stepping.

- **Toon Stepping** — Quantizes diffuse lighting into discrete bands (`_Cuts` parameter). 3 cuts = 3 visible color bands per material.
- **Cloud Shadows** — Global scrolling noise texture that modulates lighting. Controlled by `CloudShadowManager.cs`.
- **Bayer Dithering** — Optional 4×4 ordered dithering to break up toon band boundaries.
- **Patch System** — World-space noise-driven color variation. Two noise layers (`_Color2`, `_Color3`) overlay the base color based on world XZ position. Used for terrain color variation.
- **Palette System** (toggle) — Replaces the standard `albedo × lighting` with `albedo × lerp(ShadowColor, HighlightColor, lit)`. Allows artistic control over shadow/highlight tint per material. Disabled by default.
- **4 passes** — ForwardLit, ShadowCaster, DepthOnly, DepthNormals. All share identical CBUFFER for SRP Batcher compatibility.

### GrassBlade (`Custom/GrassBlade`)
Billboard grass with GPU Instancing.

- **GPU Instancing** — Each blade is a billboard quad. ~35k instances in the demo scene.
- **Color Inheritance** — Sprites carry only alpha/shape. Color comes from the same patch system as the terrain, so grass blends seamlessly with the ground.
- **Wind** — Dual-layer noise-driven sway. Each blade samples wind noise at its world position for organic variation.
- **Cloud Shadows** — Same global cloud system as ToonLit, applied per-blade at the instance root position.
- **Accent Sprites** — Random replacement of grass blades with flower/decoration sprites at configurable frequency.
- **Fake Perspective** — UV distortion based on wind and camera direction for depth illusion.
- **2 passes only** — ForwardLit and ShadowCaster. Intentionally excluded from DepthOnly/DepthNormals to avoid outline artifacts (each sprite would generate its own outline, creating visual noise).

### OutlineShader (`Hidden/OutlineShader`)
Screen-space edge detection at internal resolution.

- **Silhouette Detection** — Samples 8 neighbors in a 3×3 grid. Detects depth discontinuities with an adaptive threshold that scales based on surface angle relative to the camera (`_AngleZScale`). Uses the color of the nearest neighbor (closest to camera) darkened by `_LineDarken`.
- **Crease Detection** — Uses **directional contrast** method on 4 cardinal neighbors. Instead of summing `1 - dot(normal_center, normal_neighbor)` (which falsely triggers on curved faces), it computes `abs(d_top - d_bottom)` and `abs(d_left - d_right)` and takes the max. On a curved face, opposite neighbors vary equally so contrast ≈ 0. On a real edge, one side varies much more than the other so contrast is high. Brightens the center pixel's color by `_CreaseBrighten`.
- **Output** — RGBA mask where RGB = edge color and A = edge intensity. Background is `float4(0,0,0,0)`.

### CompositeShader
Simple alpha blend of the outline mask over the scene color. Samples `_OutlineTexture` (set as global texture via `SetGlobalTextureAfterPass`) and blends it over `_BlitTexture` (the low-res scene).

### SharpUpscaleShader (`Hidden/SharpUpscale`)
Upscales from internal resolution to screen resolution.

- Uses `fwidth()` to calculate the ratio between source texels and screen pixels
- Applies `smoothstep` at texel boundaries for mathematically sharp transitions
- Adds `_PixelPanOffset` UV compensation for sub-texel camera movement
- Samples with `sampler_LinearClamp` at LOD 0

---

## Day/Night Cycle

https://github.com/user-attachments/assets/c3f1c248-9554-4c48-9f8b-f6d56a40e7ac

The cycle is managed by two scripts with separate responsibilities.

**`DayNightCycleManager`** — single source of truth for time. Controls sun/moon orbit rotation, light intensity and color via dot product, global ambient, and cloud shadow direction. Sets GPU globals directly via `Shader.SetGlobalColor`, `Shader.SetGlobalVector`, and `Shader.SetGlobalFloat`.

**`CloudShadowManager`** — manages cloud visual parameters (scale, contrast, threshold, scroll direction). Does not set `_CloudSpeed` or `_CloudLightDirection` — those are owned by `DayNightCycleManager` to avoid a race condition between scripts. Zero inverse coupling.

### How intensity works

Light intensity is derived from geometry, not time:

```csharp
float sunDotProduct = Mathf.Clamp01(
    Vector3.Dot(sunLight.transform.forward, Vector3.down)
);
float lightIntensity = lightIntensityCurve.Evaluate(sunDotProduct);

sunLight.intensity  = Mathf.Lerp(0f, maxSunIntensity, lightIntensity);
moonLight.intensity = Mathf.Lerp(maxMoonIntensity, 0f, lightIntensity);
```

The moon is automatically the inverse of the sun — no extra logic required.

### Why cloud shadow direction is fixed

Using a dynamic `_CloudLightDirection` driven by the sun angle causes shadow compression and stretching at low sun angles — mathematically correct, visually wrong for pixel art. The direction is a fixed `Vector3` in the Inspector, independent of sun angle.

### Cloud speed synced with cycle duration

```csharp
float scaledSpeed = isTimePassing
    ? cloudShadowManager.cloudSpeed / dayDurationInSeconds
    : 0f;
Shader.SetGlobalFloat(CloudSpeedId, scaledSpeed);
```

Adjust only `cloudSpeed` as a base value — the system scales automatically with cycle duration.

### Inspector Parameters

| Parameter | Recommended | Description |
|---|---|---|
| `sunriseTime` | 6 | Sunrise hour (0–24) |
| `sunsetTime` | 18 | Sunset hour (0–24) |
| `orbitAxisY` | 45 | Aligns sun arc with isometric camera |
| `maxSunIntensity` | 1.2 | Peak sun intensity |
| `maxMoonIntensity` | 0.2 | Peak moon intensity |
| `cloudShadowDirection` | (0.2, -1, 0.2) | Fixed cloud shadow direction |
| `dayDurationInSeconds` | 840 | Full cycle duration in real seconds |

**Recommended gradients** (evaluated by dot product):
- `sunColor`: `#FF6619` → `#FFF2CC`
- `moonColor`: `#000000` → `#99B3FF`
- `ambientColor`: `#1A1A2E` → `#262633`

---

## Pixel-Perfect Panning

Moving a camera through a 3D scene at low resolution causes **pixel creep** — pixels appear to swim and jitter because the camera position doesn't align with the texel grid.

The fix is a two-step process:

1. **Snap** the camera position to the nearest texel-sized grid point in view space. This eliminates creep but makes movement choppy.
2. **Compensate** the snap error as a UV offset in the upscale shader. This recovers smooth movement while keeping the pixel grid stable.

In `IsometricCameraController.cs`:
```
true position → convert to camera local space → snap XY to texel grid → compute snap error → 
convert error to UV space → apply snapped position to camera → send UV offset to shader
```

In `SharpUpscaleShader.shader`:
```hlsl
float2 uv = input.texcoord;
uv += _PixelPanOffset.xy;  // sub-texel compensation
// ... sharp sample as normal
```

**References:**
- [aarthifical — Pixel Perfect 2D (YouTube)](https://youtu.be/jguyR4yJb1M) — explains the technique in 2D
- [David Holland — 3D Pixel Art Rendering](https://www.davidhol.land/articles/3d-pixel-art-rendering/) — 3D adaptation with orthographic camera

---

## Why Not PBR?

The pipeline is designed for **flat toon shading with discrete color bands**. PBR textures (roughness, metallic, normal maps) produce smooth gradients that conflict with toon stepping:

- At 640×360, PBR gradients become visual noise between the discrete bands
- Raising resolution to accommodate PBR (1280×720+) loses the pixel art aesthetic
- There's no resolution sweet spot that satisfies both PBR and pixel art

The intended workflow is hand-picked flat colors per material — think color palettes, not painted textures.

---

## Requirements
- Unity 6 (6000.x)
- Universal Render Pipeline (URP)
- SSAO **must be disabled** (causes artifacts with GPU-instanced grass)

---

## Project Structure
```
Assets/
├── Materials/
│   ├── Pipeline/
│   │   ├── MAT_Outline.mat          ← Shader: Hidden/OutlineShader
│   │   ├── MAT_Composite.mat        ← Shader: Hidden/CompositeShader
│   │   └── MAT_SharpU.mat           ← Shader: Hidden/SharpUpscale
│   ├── Toon/
│   │   ├── MAT_ToonGreen.mat        ← Shader: Custom/ToonLit (example terrain material)
│   │   ├── MAT_ToonGray.mat         ← Shader: Custom/ToonLit (example stone material)
│   │   └── ...
│   └── Grass/
│       └── MAT_Grass.mat            ← Shader: Custom/GrassBlade
├── Rendering/
│   ├── PC_Renderer.asset            ← URP Renderer Data with PixelRendererFeature added
│   └── RenderFeatures/
│       ├── PixelRendererFeature.cs
│       └── OutlineRendererFeature.cs ← Standalone version (not used in 5-pass pipeline)
├── Scripts/
│   └── Systems/
│       ├── DayNightCycleManager.cs
│       ├── CloudShadowManager.cs
│       ├── GrassSpawner.cs
│       ├── IsometricCameraController.cs
│       └── PlayerPlaceholder.cs
├── Shaders/
│   ├── ToonLighting/
│   │   ├── ToonLit.shader
│   │   └── GrassBlade.shader
│   └── PostProcess/
│       ├── OutlineShader.shader
│       ├── CompositeShader.shader
│       └── SharpUpscaleShader.shader
├── Textures/
│   ├── CloudNoise_v5.png            ← Seamless noise for cloud shadows
│   ├── WindNoise.png                ← Seamless noise for grass wind
│   └── GrassSprite.png             ← Alpha cutout grass blade sprite
└── Scenes/
    └── DemoScene.unity              ← Ready-to-play demo scene
```

---

## Scene Hierarchy Reference

How the demo scene is organized. Use this as a guide when building your own scene:

```
Scene
├── Directional Light             ← Main sun light
├── Moon Light                    ← Secondary directional light (DayNightCycleManager)
├── Global Volume                 ← URP post-processing (SSAO disabled)
├── EnvironmentManager            ← DayNightCycleManager.cs + CloudShadowManager.cs
├── GrassManager                  ← GrassSpawner.cs
├── Plane                         ← Terrain with ToonLit material
├── PlayerPlaceholder             ← Follow target for the camera
├── Camera Pivot                  ← IsometricCameraController.cs
│   └── Main Camera               ← Camera component (Orthographic, child of pivot)
├── [scene objects]               ← Cubes, rocks, etc. with ToonLit materials
└── Wall / Wall (1) / ...         ← Invisible walls (Box Collider only, Mesh Renderer disabled)
```

### Component Placement

| Script | GameObject | Fields to Assign |
|--------|-----------|------------------|
| DayNightCycleManager | EnvironmentManager | Sun Light, Moon Light, Cloud Shadow Manager reference |
| IsometricCameraController | Camera Pivot | Target → PlayerPlaceholder, Pixel Renderer Feature → PixelRendererFeature asset |
| CloudShadowManager | EnvironmentManager | Cloud Noise → CloudNoise_v5.png |
| GrassSpawner | GrassManager | Grass Material → MAT_Grass, terrain reference, density settings |

### Notes
- The **Camera Pivot** is an empty GameObject. The actual Camera is a **child** of it — this separation is what allows pixel-perfect snapping without jitter.
- **PlayerPlaceholder** can be any GameObject with a Transform. The camera will follow its position.
- **Invisible walls** are regular cubes with Mesh Renderer disabled but Box Collider kept active. They prevent the player from falling off the map.
- All scene objects use **Custom/ToonLit** materials. The terrain uses the patch system (`_Color2`, `_Color3`) for color variation.

---

## Setup From Scratch

If you want to integrate this pipeline into an existing project instead of using the demo scene:

### Step 1 — Import Files
Copy the `Shaders/`, `Scripts/`, and `Rendering/RenderFeatures/` folders into your URP project.

### Step 2 — Create Pipeline Materials
Create 3 materials and assign the correct shader to each:

| Material | Shader |
|----------|--------|
| MAT_Outline | Hidden/OutlineShader |
| MAT_Composite | Your composite shader |
| MAT_SharpU | Hidden/SharpUpscale |

These names are for your reference only — the important thing is assigning them in the PixelRendererFeature inspector.

### Step 3 — Configure URP Renderer
1. Select your **URP Renderer Data** asset
2. Click **Add Renderer Feature** → **PixelRendererFeature**
3. Assign the 3 materials in the inspector slots
4. Set internal resolution (default: 640 width, 360 height)
5. **Disable SSAO** if enabled

### Step 4 — Camera Setup
1. Create an empty GameObject named `CameraPivot`
2. Add `IsometricCameraController` component to it
3. Create a Camera as a **child** of CameraPivot
4. Set the Camera to **Orthographic**
5. Drag the `PixelRendererFeature` asset into the `Pixel Renderer Feature` field on the controller
6. Set Fixed Rotation to `(20, 45, 0)` for standard isometric angle

### Step 5 — Cloud Shadows
1. Add `CloudShadowManager` component to any GameObject
2. Assign `CloudNoise_v5.png` (or any seamless noise texture)
3. Recommended starting values: Scale 60, Contrast 3, Threshold 0.4, ShadowMin 0.3

### Step 6 — Day/Night Cycle (Optional)
1. Add `DayNightCycleManager` to your EnvironmentManager GameObject
2. Assign your **Sun** (Directional Light) and **Moon** (secondary Directional Light)
3. Assign the `CloudShadowManager` reference
4. Configure gradients for `sunColor`, `moonColor`, and `ambientColor`
5. Recommended starting values: `sunriseTime` 6, `sunsetTime` 18, `orbitAxisY` 45, `dayDurationInSeconds` 840

### Step 7 — Create Toon Materials
For each object material:
1. Create a material with shader `Custom/ToonLit`
2. Set `Base Color` to your desired flat color
3. Set `Cuts` to 3 (three visible light bands)
4. Adjust `Steepness` and `Wrap` to taste

### Step 8 — Grass (Optional)
1. Create a material with shader `Custom/GrassBlade`
2. Assign a grass sprite texture (alpha cutout PNG)
3. Add `GrassSpawner` to your terrain
4. Configure density, scale, and color patches to match your terrain material

---

## Inspector Parameters Reference

### PixelRendererFeature — Outline Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| **Internal Resolution** | | |
| Width | 640 | Internal render width in pixels |
| Height | 360 | Internal render height in pixels |
| **Silhouette** | | |
| Line Darken | 0.0 | 0 = black outline, >0 = darkened neighbor color |
| Line Alpha | 1.0 | Silhouette opacity |
| Z Delta Cutoff | 0.15 | Depth difference threshold for silhouette detection |
| Angle Z Cutoff | 0.3 | Surface angle where adaptive threshold kicks in |
| Angle Z Scale | 4 | How much the threshold scales for angled surfaces |
| Kernel Radius | 1.0 | Sampling distance. Keep at 1.0 for 1px lines at internal res |
| **Crease** | | |
| Crease Brighten | 1.0 | How much to brighten crease edges |
| Crease Alpha | 1.0 | Crease opacity |
| Depth Diff Low | 0.0 | Lower bound of depth smoothstep for crease suppression |
| Depth Diff High | 0.05 | Upper bound of depth smoothstep for crease suppression |
| Normal Smooth Low | 0.05 | Minimum directional contrast to start showing crease |
| Normal Smooth High | 0.3 | Directional contrast where crease is fully visible |

### IsometricCameraController

| Parameter | Default | Description |
|-----------|---------|-------------|
| Fixed Rotation | (20, 45, 0) | Initial camera angle (pitch, yaw, roll) |
| Smoothing | 5 | Follow target smoothing speed |
| Use Pixel Snap | true | Enable pixel-perfect panning |
| Pixel Renderer Feature | — | Drag your PixelRendererFeature asset here |

### DayNightCycleManager

| Parameter | Recommended | Description |
|-----------|-------------|-------------|
| `sunriseTime` | 6 | Sunrise hour (0–24) |
| `sunsetTime` | 18 | Sunset hour (0–24) |
| `orbitAxisY` | 45 | Aligns sun arc with isometric camera |
| `maxSunIntensity` | 1.2 | Peak sun intensity |
| `maxMoonIntensity` | 0.2 | Peak moon intensity |
| `cloudShadowDirection` | (0.2, -1, 0.2) | Fixed cloud shadow direction |
| `dayDurationInSeconds` | 840 | Full cycle duration in real seconds |

---

## Known Limitations

1. **Crease at object bases** — Where objects meet the terrain, a crease line may appear at the base. This is because grass doesn't write to the depth/normals buffers. Less noticeable with dense grass and detailed assets.

2. **Cloud shadow cuts** — Under heavy cloud shadow, toon stepping bands can collapse because the cloud shadow clamps the diffuse value before toon stepping occurs.

3. **Grass excluded from depth/normals** — Adding DepthOnly/DepthNormals passes to the grass shader causes each blade to generate its own outline, creating visual noise. The grass intentionally remains invisible to the outline shader.

4. **Not designed for PBR** — The pipeline assumes flat toon shading. PBR textures will produce noisy results at the internal resolution.

5. **Cloud shadow pause/resume offset** — `_Time.y` continues advancing in the shader even when `isTimePassing = false`. Cloud shadows will resume at a different position. Fix requires a manual time accumulator in C#.

6. **No palette blending per time of day** — Material colors don't change with the cycle. Only directional light color and ambient are affected.

---

## References & Credits

This project was built by studying and adapting techniques from multiple sources:

- **[t3ssel8r](https://www.youtube.com/@t3ssel8r)** — Original inspiration. Pixel art 3D in realtime, outline technique, cloud shadows on grass, palette-driven iteration.
- **[David Holland](https://www.davidhol.land/articles/3d-pixel-art-rendering/)** — Pixel aligned panning (snap + UV compensation), volumetric god rays via shell texturing, grass LIGHT_VERTEX technique. Implemented in Godot.
- **[KodyKing](https://github.com/KodyJKing/hello-threejs)** — Crease detection method using depth and normal differences. hello-threejs repository.
- **[Roystan](https://roystan.net/articles/outline-shader/)** — Roberts Cross outline technique (depth + normals), depth threshold modulation. Unity tutorial.
- **[keijiro/Kino](https://github.com/keijiro/Kino)** — Post-processing effects collection for Unity. Referenced for Recolor edge detection.
- **[aarthifical](https://youtu.be/jguyR4yJb1M)** — Pixel-perfect camera movement explanation in 2D.
- **[Dylearn](https://www.youtube.com/@Dylearn)** — Grass shader techniques, crease detection approach.

---

## Support

If this project helped you, consider:
- ⭐ Starring the repository
- 🎮 Checking out the [itch.io demo](https://bababuyyyy.itch.io/unity-isometric-pixel-art-shader-demo) (pay-what-you-want)
- ☕ [Buy me a coffee](https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=danilolima.se@hotmail.com)

---

## License

MIT — free for personal and commercial use.

---

Made by [Bababuyyy](https://github.com/bababuyyy)
