QLM SKIN ASSETS

Two separate skins:
  vintage         The earlier interactive Vintage design, reconstructed as vector assets.
  retro  The realistic Walnut design, prepared from clean material renders.

Each skin contains 30 assets, with transparent PNGs at 1x and 2x.
Production assets contain no text or logos. The preview files contain sample labels.
The main panel is 640 x 480 points. The OSD is 300 x 72 points.
The two skins use the same asset names, point sizes, and placement coordinates.

START HERE

1. Inspect vintage/contact-sheet.jpg and retro/contact-sheet.jpg.
2. Add QLMSkins.xcassets to the app's source list in project.yml. Regenerate the project.
3. Use the names in manifest.json to load images from the asset catalog.
4. Use each skin's layout.json for frames, text styles, colors, and control positions.
5. Use appkit/QLMSkinAssets.h and .m as a drawing reference. They use AppKit and Objective-C.

This pack does not modify qlm or its settings. It contains visual assets and drawing helpers.
The drawing helpers do not connect to System or the adapter.
Existing System rules and control enablement remain the responsibility of the app.

CONTENTS

  QLMSkins.xcassets/    Both skins, with macOS 1x and 2x representations.
  manifest.json        Every asset, its size, file paths, pivot, and cap insets.
  vintage/            PNGs, editable masters, layout, and previews.
  retro/     PNGs, masters, layout, and previews.
  appkit/              Small Objective-C drawing helpers.
  sources/             Original references, clean raster masters, extraction crops, and prompts.
  tools/               Reproducible export and validation scripts.
  validation.json      Results of asset and catalog checks.

ASSET INVENTORY, PER SKIN

  panel-background         Empty cabinet. Wood and panel material only, with tiny screws.
  panel-markings           Separate outlines and separator lines. No letters or numbers.
  display-glass            Blank display glass and its surround.
  display-disabled-overlay Dim layer for a disabled display.
  nameplate                Blank badge. Render qlm as live text if desired.
  osd-background           Empty OSD housing and glass.
  osd-disabled-overlay     Dim layer for a disabled OSD.
  osd-track, osd-fill       Separate volume track and fill. Clip the fill to the level.

  button-normal
  button-hover
  button-pressed
  button-selected
  button-selected-hover
  button-selected-pressed
  button-disabled
  button-selected-disabled
  button-focus-ring        Overlay the current enabled button state.

  knob-shadow              Static. Draw beneath the knob body.
  knob-body-normal
  knob-body-hover
  knob-body-pressed
  knob-body-disabled
  knob-pointer             Transparent pointer, initially pointing up.
  knob-pointer-disabled
  knob-ticks               Static 270-degree scale, with no numbers.
  knob-focus-ring          Static focus overlay.

  led-on, led-off, led-disabled

STATE RULES

Choose disabled first, then pressed, then hover, then normal. Selection is independent.
Keep keyboard focus as a separate overlay. A selected button can also be hovered or pressed.
Button states share one canvas and source geometry. Pressed faces move slightly within that
canvas, as a physical key would. Do not move the control's frame or text baseline.

LEDs are separate from buttons. Use them for selection, mute, or connection state as needed.
The active surface tint is subtle. Always pair it with a visible label or indicator.
The disabled assets already include attenuation. Do not apply another 50% opacity.

KNOB COMPOSITION

All body, pointer, focus, and shadow layers use a 144 x 144 point canvas.
Their rotation pivot is (72, 72). The 176 x 176 point tick layer has pivot (88, 88).
Center both canvases on the same point. Use square frames.

Draw shadow, ticks, body, pointer, then focus. Rotate only the pointer.
The body and its highlights stay fixed. Rotating the shaded body makes the light move.

The reference pointer range is -135 to +135 degrees clockwise from straight up.
Map a normalized fraction with: angle = -135 + fraction * 270.
The helper assumes a flipped NSView, with an origin at the top left.
For Core Animation, use an anchorPoint of (0.5, 0.5) and convert degrees to radians.

The sample level is -42.0 dB. The sample slider bounds are -80 and -30 dB.
These are visual reference values, not an application volume policy.
Use the current System snapshot, configured ceiling, and enabled states in the real app.

TEXT AND SYMBOLS

Render text with AppKit at the current backing scale. No text belongs in the background PNG.
Use monospaced digits for the level and status values. The layout lists font sizes in points.
Use SF Symbols for power, sliders, plus, and minus. Their suggested names are in layout.json.
Set labels, accessibility values, keyboard navigation, and hit areas on native controls.
Mute, dim, standby, applying, and connection errors should remain explicit text states.

RESIZING

The reference layout is fixed at 640 x 480 points. Prefer a layout reflow over stretching it.
The asset dimensions are logical points. An @2x bitmap has twice as many pixels per axis.
Set NSImage.size to the point size if loading PNGs outside the asset catalog.
Never interpret a 1280 x 960 @2x background as a 1280 x 960 point window.

Cap insets are in points, ordered top, left, bottom, right in manifest.json.
Buttons support horizontal stretching. Keep their reference height of 40 points.
Display and OSD glass are best at their reference sizes, so highlights keep their proportions.
The catalog contains ordinary macOS images; the drawing helper sets button cap insets explicitly.

SOURCE AND RESOLUTION

Vintage is a vector reconstruction of the selected HTML concept. Its SVG masters can be
rerendered at higher scales. The embedded wood is a texture from that concept.
Walnut preserves the approved material direction. It is not a pixel-perfect cutout of the
original labeled concept: the cabinet and components were re-rendered clean, then isolated.
States are deterministic transformations of the same base artwork.

The Walnut cabinet master is 1448 x 1086 pixels. The component master is 1254 x 1254 pixels.
The extracted glass is 549 x 238 pixels and is normalized to 712 x 264 for its @2x export.
The OSD crop is 556 x 172 and is normalized to 600 x 144. Those exports include resampling;
they should not be treated as independent native-resolution 3x textures.
All PNGs use straight alpha and no baked checkerboard. Light and dark background checks are
included in qa. The raw masters are retained so later retouching does not compound resampling.

REBUILD

Requirements: Python 3, Pillow, NumPy, and rsvg-convert (librsvg).
Run: python3 tools/build_assets.py
Run: python3 tools/validate_assets.py

Preview labels use macOS fonts. Fonts are not redistributed.
The export script writes both skins and the shared catalog.
The material prompts are retained in sources/asset-prompts.json.
