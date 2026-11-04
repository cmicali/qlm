# The UI pass: a main window, an OSD, and skins

**Status, 2026-11-04.** Planned. Nothing here is built yet. The menu bar popover stays as it is until its own redesign, later.

qlm has run on all six monitors through a plain AppKit popover. That was enough to prove the protocol. This doc plans the first real UI: a main window that can be opened and left open, an on-screen display that shows the level when the knob turns, and a skin system that draws both. Three skins come with it: modern, vintage, and retro. The mockups and the assets are in [`qlm/App/Skins/`](../qlm/App/Skins/), one directory per skin, and this doc refers to them by name.

The plan's rules still hold. The window and the OSD read snapshots on the main queue and drive System. They never touch GLMAdapter. The ceiling, the allowlist, and the refusal of a group with an unverified rate hold under every skin, because the skin only draws.

## What the user sees

### The main window

One fixed-size panel, with no title bar of its own. The skin draws the whole thing, and the app draws text over it. From the top:

| Element | Shows | Reads | Drives |
| --- | --- | --- | --- |
| Logo and tagline | The skin's logo | | |
| Status LED | "6 ONLINE", from the monitor list's counts. The LED is lit while any monitor is online, dim otherwise. A bus problem replaces the count with its title. | `QLMMonitorList.entries`, `QLMBusProblemTitle` | |
| Listening setup | One button per group of the loaded setup file, in the file's order, lit for the active group | `QLMSetup.groups`, `snapshot.activeGroupName`, `snapshot.applying` | `applyGroup:` |
| Display | The active group's name at the top left, the level large in the middle, and `OUTPUT` and `MAX` along the bottom | `snapshot.volumeDecibels`, `snapshot.handBack.volumeDecibels`, `snapshot.ceilingDecibels` | |
| Mute, Dim | Toggles, lit while on. Dim's title carries its depth, `DIM −20`. | `snapshot.allMuted`, `snapshot.dimmed` | `setAllMuted:`, `setDimmed:` |
| Knob | The level on the slider's range, from the lowest level to the ceiling. The end labels are the range. | `preferences.lowestDecibels`, `preferences.ceilingDecibels` | `setVolumeDecibels:` |
| Footer | Monitors on the left, Standby or Wake on the right | `snapshot.anyOn` | the monitors window, `sleep`, `wake` |

Two things from the mockups go. The word `LEVEL` leaves the display's top right, and the `MAIN · ACTIVE` line leaves the footer's middle, since the display already names the group. The footer keeps its two buttons at the edges.

The display's three numbers mean three different things. The large one is the level the user set, undimmed. `OUTPUT` is what goes out now: the level after dim, or `MUTED` while mute all is on. `MAX` is the ceiling. While the level waits for the knob's first reading, after a start or a gap, the large number shows an em dash, as the popover does.

**The listening setup buttons.** "Setup" here is what the plan calls a group: one group of the loaded `.sam` file. The buttons show as many groups as the skin's grid holds, in the file's order: modern six, in two rows of three, and vintage and retro four, in one row. A file with more shows the first ones, and Settings says so. A file with none, or no file, hides the row and shows the file's name or its error in its place. A click applies the group. While an apply runs, every button is disabled, and the chosen one blinks, in the skin's own way. The same rule as the popover's picker disables them: no System, no monitors tracked, or an apply in flight. **The refusal stands.** A group with a model whose filter design rate is unverified refuses as it does today, and the error shows under the buttons, in the display's bottom line, until the next click.

**The knob.** A drag turns it, as a real knob turns: the pointer follows the angle from the knob's center to the mouse. A scroll wheel over it moves one step per tick. The arrow keys move one step while the window is key. Every move snaps to GLM's 0.5 dB steps and goes to System at once, which coalesces to one frame per 50 ms. The knob never goes above the ceiling, since its top is the ceiling. Like the popover's slider, it ignores snapshots for half a second after a move, so a stale snapshot can't pull it back mid-drag. Its sweep is 270°, from 225° to −45°, the convention every mockup draws.

**The window's chrome.** The window has the standard title bar, made transparent, with the title hidden and the content under it, so the three traffic lights sit over the skin's top left corner. That keeps Cmd-W, Escape, and the accessibility tree without a custom close button. The window resizes, from the skin's reference size up. The display takes the extra room, the button rows widen with it, and everything else keeps its place, as [Resizing](#resizing) lays out. The skin's background drags the window. The window remembers its size and position. It opens from a button in the popover's footer, `Window…`, and from the app's Window menu, and Settings gains "Open the window at launch". The popover's button is the one change the popover takes now.

### The OSD

When the knob on the adapter turns, a small panel shows the new level, then fades. Its shape is the mockups' second image: the level large on the left, `Main monitors` and `qlm · Output level` on the right, and a bar across the bottom that fills from the lowest level to the ceiling. The bar is the level's place in the slider's range. The panel is bigger than the mockups draw it: the number at about 56 pt and the panel about 480 by 150 points, so it reads from across the room.

The OSD is a floating panel that takes no focus and no clicks. It joins every Space and shows over full-screen apps, as the Mac's own volume bezel does. It shows on the main screen, in one of six places the user picks: the top or bottom of the screen, at the left, center, or right. Each show restarts its timer, so a turn that goes on keeps it up. When the timer ends it fades over about a quarter second.

What triggers it is a turn of the adapter's knob. Not the window's knob, not the popover's slider, and not `qlmctl`. System's snapshot doesn't yet say what moved the level, so it gains one fact: the last call that changed the level was the knob. The OSD shows when a snapshot arrives with that set and a level that differs from the last shown. That needs a small change in System, with a test over the knob golden captures.

Three settings come with it, in a new "On-screen display" section of Settings:

| Setting | Values | Default |
| --- | --- | --- |
| Show the OSD when the knob turns | on, off | on |
| Place | top left, top center, top right, bottom left, bottom center, bottom right | bottom center |
| Keep it up for | 0.5 to 10 s, in half seconds | 2 s |

The OSD draws in the current skin, from the skin's own `osd` section.

### Skins

A skin draws the window and the OSD. The app draws every piece of text, every symbol, and the knob's angle. So a skin is images and a layout, and the layout says where everything goes and what colors and fonts the text takes. Switching skins changes nothing but the look.

Three ship in the app. The assets for two of them are in the repo already, under [`qlm/App/Skins/`](../qlm/App/Skins/), delivered as one pack on 2026-11-04. Its `README-pack.txt` is the pack's own guide, and each skin's `contact-sheet.jpg` shows every asset.

| Skin | The mockup | Assets |
| --- | --- | --- |
| modern | The first image: flat, dark, an orange arc on the knob | None. Every element is drawn from colors and radii. |
| vintage | The second: olive panel, wood rails, red display, tick marks around the knob | In the repo, as `vintage/`. A vector reconstruction, so its SVG masters re-render at any size. |
| retro | The third: the photoreal one | In the repo, as `retro/`. Re-rendered clean from the mockup's materials, then isolated, so it's close to the mockup but not a cutout of it. |

The pack called them heritage and heritage-walnut. The repo uses the owner's names, and the pack's tools were renamed to match.

## How skins work

### The format

The pack describes thirty assets per skin, and about half of them are geometry a skin need not ship: tick rings, pointers, LEDs, focus rings, shadows, bars, outlines, and dimming overlays. In the pack they're SVGs rendered to PNG, which fixes their size and color. The app draws geometry better than an image does, at any size and in the skin's colors, and the panel's outlines then follow the layout instead of being painted where the pack's sample layout put them. So qlm splits the vocabulary by one rule: **material is an image, geometry is drawn.**

What the app draws, from the skin's colors and metrics:

| Drawn | From the skin |
| --- | --- |
| The panel's markings: the separator lines and the box around the groups and the mute and dim pair | A line color and width. The boxes follow the elements' frames. |
| LEDs, on, off, and disabled | Two colors and a glow radius |
| The knob's tick ring, pointer, shadow, and focus ring | The ticks' count, lengths, and color, the pointer's length, width, and color, the shadow's blur, the focus color |
| Modern's knob arc | The track and fill colors |
| The buttons' focus ring | A focus color and radius |
| The OSD's track and fill | Two colors and a height |
| The display's and the OSD's dimming when disabled | An overlay alpha |
| Every piece of text | The slots below |

What a skin supplies as images, at 1x and 2x, or as a `draw` block where it has no material:

| Element | Images | States |
| --- | --- | --- |
| `panel` | The empty cabinet, at the window's size | 1 |
| `nameplate` | The blank badge | 1 |
| `button` | One stretchable face, with cap insets, at 40 points high | 8: normal, hover, pressed, selected, each with and without the other, plus disabled and selected-disabled |
| `display` | The blank glass and its surround | 1 |
| `knobBody` | The body alone, with its highlight and no pointer | 4: normal, hover, pressed, disabled |
| `osd` | The empty housing and glass | 1 |

That's sixteen images for retro, whose every surface is a photoreal material, and the same sixteen for vintage, since its gradients and bevels are easier to keep exact as the pack's rendered SVGs than to rebuild in code. Modern supplies none: each element's `draw` gives a fill, a border, a radius, and, for a button, the selected border's color. The reader takes an image or a `draw` for each element, never both, so one code path serves all three skins. The pack's other fourteen assets stay in each skin's `masters/`, and their PNGs in its `png/`, as the record of what the drawing should look like. The bundle leaves them out.

The split pays twice. Retro's larger knob needs one re-export, its body, since the ring, pointer, and shadow draw at whatever size the layout gives. And a user's skin needs sixteen pictures and a palette, not thirty cutouts.

So a qlm skin is one self-contained directory:

```
<name>/
  skin.json
  png/            the images above, each as name.png and name@2x.png
```

`skin.json` is one file, and it says:

1. **The sizes and the palette.** The window's and the OSD's sizes in points, with the origin at the top left, and the colors the drawn geometry and the text use.
2. **The elements.** Each with its frame at the reference size, its anchors and whether it stretches, and an image name or a `draw` block. The images' cap insets sit with the element, so a user's skin edits nothing outside its directory. The pack's `asset_catalog_name` goes, with the asset catalog.
3. **A grid for the groups, not three buttons.** The pack places three setup buttons by role. The skin gives one `groups` element: a frame, the columns and rows, and the gap. The app lays as many buttons in it as it has cells, up to six, in the file's order, and leaves the rest of the grid empty. A file with more groups shows the first ones. Modern's grid is two rows of three. Vintage's and retro's is one row of four, since their setup box has room for one row of 40-point buttons.
4. **The knob's metrics.** Its frame, the ticks, the pointer, the shadow, and the sweep, −135° to +135° clockwise from straight up, as the pack has it. Only the pointer rotates. The body's highlight stays where the light is.
5. **Text slots, not sample text.** The pack's layout lists sample strings at sample frames, `LEVEL` and `MAIN · ACTIVE` among them. The skin instead names each slot the app fills, with its frame, font, size, weight, alignment, and color: `online`, `groupsTitle`, the display's `caption`, `level`, `unit`, `output`, and `max`, the knob's `min`, `max`, and `caption`, the footer's `monitors` and `power`, and the OSD's `level`, `unit`, `title`, and `subtitle`. The strings are the app's. A skin can't put words on the panel, and the app can't put text where the skin left no slot. Fonts name a face the Mac has, and a face it lacks falls back to the system font, or the system monospaced font for a slot marked `mono`. The display's digits are monospaced in every skin.

The state rules are the pack's: disabled first, then pressed, then hover, then normal, with selection independent and focus an overlay. The symbol names are the pack's too.

The first two `skin.json` files are written from the pack's layouts by hand in PR 5, and `tools/build_assets.py` learns to write `skin.json` and export only the sixteen images when the assets are next re-exported. The pack's `layout.json` and `manifest.json` stay until then.

A user's skin is a directory of the same shape in `~/Library/Application Support/qlm/Skins/`, read at launch and when Settings' skin list opens. A missing image, a frame outside the window, an unknown key, or an element with both an image and a `draw` refuses the skin, with the reason in Settings, and the app falls back to modern. The reader is strict, as the setup reader is.

### Resizing

The window grows from the skin's reference size, 640 by 480 points for the two image skins, and never below it. It doesn't scale. Each element in `skin.json` says which edges it is anchored to, and whether it stretches, as springs and struts: the extra width goes to the display and the button rows, and the extra height to the display row. So:

| Element | On a wider window | On a taller window |
| --- | --- | --- |
| Header: nameplate, online count | The count moves right | Stays |
| Groups grid, mute and dim pair | Stretch, and their buttons fill their columns | Stay |
| Display | Stretches, and its level text scales with its height | Stretches |
| Knob column | Keeps its width, anchored right | Centers in the display row |
| Footer | Standby moves right | Moves down |
| Markings | Follow the frames | Follow the frames |

The layout pass is one function over the anchors, and a test resizes the fixture skin and checks every frame. Two images have to stretch well. The cabinet stretches through the 9-slice cap insets the pack gives, so its wood rails stretch along their grain. The display glass stretches through its own insets. Vintage's is a flat gradient and stretches as is. **Retro's glass has a glossy sweep that smears when stretched**, so it needs a re-render as a 9-slice with the highlight kept in the corners, or a larger master scaled down. That joins the asset work below.

The OSD is a bezel, not a window, and stays at its size.

### What the assets don't settle yet

The pack delivers both skins at the reference sizes, and four things go past them:

- **Retro's knob should be larger.** The pack draws both skins' knob bodies on 144 point canvases. The retro body comes from a 1254 pixel component master, so it can be re-exported at about 200 points. The ring, pointer, and shadow draw at any size, and the layout reflows around the knob's frame.
- **Retro's display glass must stretch.** See [Resizing](#resizing).
- **The shipped knob bodies are cropped.** Each body's `png/` images are cut from the pack's 144 point canvas to the body itself, 98 points for vintage and 112 for retro, so `body.size` is the knob's diameter and the shadow, the focus ring, and the drag follow it. The masters keep the canvas. A re-export from them must crop again, or `tools/build_assets.py` learns to.
- **The OSD should be larger than 300 by 72.** The plan wants about 480 by 150 points, so it reads from across the room. Vintage's housing is vector and re-renders at that size. Retro's was normalized from a 556 by 172 pixel crop, so at that size it needs a fresh render from its master, not a scale-up.

Each is asset work with `tools/build_assets.py`, after the engine lands. The engine takes any size the layout gives.

### What draws it

Four classes in `qlm/App/`, over the resources:

- `QLMSkin` reads a skin's `skin.json` into values: the window's size, each element's frame and style, the fonts, the colors, the cap insets, and the OSD's layout. It loads no image itself. It is Foundation only, so the hostless tests cover it, with the two shipped layouts and a fixture for each refusal.
- `QLMSkinView` is the window's content view. It draws the panel and its markings and hosts one subview per element, laid out from the skin's frames, with no Auto Layout, since every frame is given. Each subview draws its element from the skin's style and the state the controller hands it, by the pack's state rules, and draws the geometry itself: LEDs, rings, bars, and overlays. `appkit/QLMSkinAssets.m` in the pack shows the button and knob drawing, and the engine takes it as reference, not as code to compile: it loads from an asset catalog, and qlm loads from the skin's directory, so user skins load the same way.
- `QLMKnobControl` is the knob, an `NSControl` with a `doubleValue` in dB. It draws the shadow, the tick ring, the body image, the pointer, and the focus ring, in that order. Its angle math is a C header, `QLMKnobMath.h`, which the tests cover: dB to angle, angle to dB, the step snap, and each tick's position.
- `QLMMainWindowController` owns the window, reads the monitor list's snapshot, renders each element, and drives System. It mirrors `QLMPopoverController`'s rules for what is enabled and when, and shares its helpers in `QLMFormat`.
- `QLMOSDController` owns the OSD panel, its timer, and its fade. Its rule for when to show, and for how the timer restarts, is a plain object with an injectable clock, so the tests cover it.

`project.yml` compiles all of `qlm/App` today, so the Skins directory needs an exclude there, and a resources entry that copies each skin's `skin.json` and `png/` into the bundle, leaving the masters, the mockups, the previews, the sources, the pack's layouts, and the tools out. The pack's `appkit/` is reference and compiles into nothing.

The images and the drawn controls are the app's own. vibe-libs' `ui/Controls` has drawn sliders and symbol buttons for another look, and none of this is general enough for a second app yet, so nothing goes there now. If a second app wants skins, the engine moves, by vibe-libs' own rule.

## The debug channel

Each new control gets a verb, so `.claude/skills/app-hardware-run` can drive the window on the monitors as it drives the popover:

| Verb | Does |
| --- | --- |
| `window <show|close>` | Opens or closes the main window |
| `group <name>` | Clicks that group's button, with the button's refusals |
| `knob <dB>` | Turns the window's knob, as a drag would |
| `osd <show|hide>` | Shows the OSD at the current level, or hides it, so a screenshot can check it |
| `skin <name>` | Switches the skin, as Settings does |

`dump_state` gains the skin's name, the OSD's settings, and whether the window and the OSD are showing. `dump_screenshot -` already captures the key window, so each skin's rendering can be checked by eye from a script.

## The work, in order

Five pull requests. The first two are independent, and the rest build on them.

1. **System: say when the knob moved the level.** One fact on the snapshot, kept until the next level change, with a test over the knob golden captures. `qlmctl poll` prints it. This is the only change outside the app.
2. **The skin engine, with modern built in.** `QLMSkin` and its reader, the fixture skin, each refusal's test, `QLMSkinView`, `QLMKnobControl` and `QLMKnobMath.h` with their tests, and the modern skin's layout. No window yet beyond what a test needs. `project.yml` excludes `qlm/App/Skins/` from the sources and copies each skin's `skin.json` and `png/` into the bundle.
3. **The main window.** `QLMMainWindowController` over the engine, the resize layout and its test, the popover's `Window…` button, the Window menu, the launch setting, the position kept, and the verbs `window`, `group`, `knob`, and `skin`. The listening setup buttons follow the picker's rules, refusal and all.
4. **The OSD and its settings.** `QLMOSDController`, the show rule and its tests, the Settings section, and the verb `osd`. Needs 1 and 2.
5. **Vintage and retro.** Their layouts wired to the shipped assets, the skin picker in Settings, which lists the user's folder too, and then the larger retro knob and the larger OSD re-exported from the masters. Needs 2 and 3.

A run on the monitors follows 3 and 4, through the verbs, under the skill's supervision: the knob from the window, a group button's refusal, and the OSD on a turn of the adapter's knob.

## Open questions

These are the owner's calls. Each has a default the work takes until it's made.

| Question | Default |
| --- | --- |
| More groups than the skin's grid holds: show the first ones, or scroll, or a popup for the rest? | Show the first ones, and say so in Settings |
| Should the OSD also show on the window's knob, or on `qlmctl volume`? | No. The adapter's knob only. |
| Should the OSD say `MUTED` or `DIM` when the knob turns under them? | Yes, in the subtitle's place, since the number alone would mislead |
| Does the window open at launch by default? | No. The menu bar item is still the app. |
| A fourth button per group row for a group's calibration state? | No. The display's caption names the group, and that's enough. |
| A window scale setting, 100%, 150%, or 200%, since the mockups were rendered at about twice the reference size? | Not now. The window resizes instead, and the 2x assets keep it crisp on a Retina display. |
