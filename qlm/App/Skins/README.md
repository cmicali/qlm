# Skins

A skin draws qlm's main window and its OSD. It is a directory of images and one file, `skin.json`, that says where everything goes and what colors and fonts the text takes. The app draws every piece of text, every symbol, and the knob's angle, so a skin changes the look and nothing else. [docs/ui.md](../../../docs/ui.md) says why it splits this way.

```
<name>/
  skin.json
  png/        each image as <image>.png and <image>@2x.png
```

## Making a skin

Start from modern. Copy `qlm/App/Skins/modern/` to `~/Library/Application Support/qlm/Skins/<name>/`, then edit its `skin.json`. Modern draws every element from colors and radii, so it needs no images. To use pictures, give an element an `image` in place of its `draw`, and put the files in `png/`, at 1x and 2x. qlm reads the user's skins at launch, and again when Settings lists them.

The reader is strict. A skin it can't read is refused whole. The reason shows in Settings, and the app falls back to modern. Every reason names the key at fault, such as `elements.display.text.level.color is #ec917, which is not #RRGGBB or #RRGGBBAA`. The reader checks that each image file is there. It doesn't check that the file decodes. A file that won't decode draws nothing.

Frames are in points, from the window's top left. The reference size is the smallest window, and the window grows from it. Each element says how it grows with its `anchors`, as springs and struts: anchored to both edges of an axis, it stretches; to one, it keeps its distance to that edge; to neither, it stays centered. A text slot's frame is in its element, and its anchors work the same way inside it.

A slot with `scales` grows with its element instead, by the smaller of the element's height and width growth, from the element's origin. Modern's level does this, so a larger display shows a larger number, and the number never outgrows the display. A slot that scales must lie inside its element.

**States.** A button has eight states: normal, hover, pressed, and disabled, each with and without selected. The app picks one by the pack's rule: disabled first, then pressed, then hover, then normal. Selection is separate. A drawn button gives its normal look in `draw`, then overrides under `states`. Each override names only what changes. A selected state takes `selected`'s overrides first, then its own. So modern sets the accent border once, under `selected`, and its `selected-hover` sets only a fill. The knob's body has the first four states.

While a group applies, its button blinks. The app does this by switching its state between selected and normal, so a skin needs no key for it.

## The keys

| Value | Form |
| --- | --- |
| Frame | `[x, y, width, height]` |
| Size | `[width, height]` |
| Color | `"#RRGGBB"`, `"#RRGGBBAA"`, or a name in `palette` |
| Insets | `[top, left, bottom, right]`, as the pack orders them, or one number for all four |
| Anchors | A list of `"left"`, `"right"`, `"top"`, and `"bottom"`. Left and top when absent. |

The file's keys are all required:

| Key | Holds |
| --- | --- |
| `format` | `1` |
| `size` | The reference size, at least 640 by 480 |
| `palette` | Named colors, each `#RRGGBB` or `#RRGGBBAA` |
| `elements` | The eight elements below |
| `button` | The buttons' style |
| `led` | `on` and `off` colors, and `glow`, a radius |
| `markings` | `color`, `width`, `lines`, and `boxes` |
| `osd` | The OSD |

Every element has `frame`, and may have `anchors` and `text`. Its other keys are its kind's. Every slot is required unless the table marks it optional:

| Element | Its own keys | Its text slots |
| --- | --- | --- |
| `panel` | image or draw | |
| `nameplate` | image or draw | `logo`, optional |
| `status` | `led`, a frame in the element | `online` |
| `groups` | `columns`, `rows`, `gap` | `groupsTitle`, and `message`, which shows the setup file's name or its error while no groups show |
| `display` | image or draw, `disabledOverlay` | `caption`, `level`, `unit`, `output`, `max` |
| `toggles` | `columns`, `rows`, `gap` | |
| `knob` | `body`, `pointer`, `focus`, and optionally `ticks`, `shadow`, `arc` | `min`, `max`, `caption` |
| `footer` | `symbols`: `monitors` and `power`, each an SF Symbol's name | `monitors`, `power` |

`groups` lays up to six buttons in its cells, row by row. `toggles` lays Mute and Dim in its first two. `gap` is `[x, y]`, and no cell may come out empty. The pack's − and + step buttons have no element, since the window has none.

**Image or draw.** An element takes `image`, with `capInsets`, or `draw`, never both. The image is a file name in `png/`. One state's image is `png/<image>.png`. The button's are `<image>-normal`, `-hover`, `-pressed`, `-disabled`, `-selected`, `-selected-hover`, `-selected-pressed`, and `-selected-disabled`, as the pack names them. The knob body's are the first four. Cap insets can't be negative or meet across their frame. They are not checked against the PNG's own size. A button's frame is its smallest grid cell.

**A draw block** has `fill` or `gradient` (two colors, top then bottom), `border`, `borderWidth`, `radius`, `inset`, `rings` (each `inset`, `color`, `width`), and `shadow` (`color`, `blur`, `offset`). All are optional. A button's or a knob body's block may add `states`. A shadow's blur and offset are in points, and a positive y falls down. The shadow falls outside the element's frame, and nothing clips it.

**A text slot** has `frame`, `size`, and `color`. It may have `anchors`, `scales`, `font` (a face the Mac has, else the system font), `mono` (the system monospaced font when the face is missing), `weight` (`ultralight`, `thin`, `light`, `regular`, `medium`, `semibold`, `bold`, `heavy`, `black`), `italic`, `alignment` (`left`, `center`, `right`), `tracking`, and `accent` (the color of a trailing period, as in modern's logo).

**The button.** `button` has an image or draw, `title`, and `focus`, and may have `led`. `title` has `size` and `color`, and may have `font`, `weight`, `tracking`, `selectedColor`, `disabledColor`, and `prefixColor`, the color of a group's letter. `focus` has `color`, `width`, `radius`, and `outset`. `led` has `size`, and may have `gap`, the space between the LED and the title, 6 when absent. It may have `face`, insets that say where the face's edges sit inside the button's frame, past the image's shadow, and `pressedFace`, the face while pressed, which a press may move down. Each lies within the cap insets. `face` is 0 when absent, and `pressedFace` is `face`. The LED, the letter, and the title center together on the face. The label's capitals center on the face's height. A marking box around the buttons should leave the same room above and below their face.

**The knob.** The sweep is fixed, from −135° to +135°, clockwise from straight up, and only the pointer turns. `body` has `size`, a diameter, and an image or draw. `pointer` has `inner`, `outer`, `width`, `color`, and `disabledColor`. `ticks` has `count`, `inner`, `outer`, `width`, and `color`. `arc` has `radius`, `width`, `track`, and `fill`. Radii are from the center, and none may reach past half the knob's frame, counting the strokes' half-widths and the focus ring. `focus` is as the button's.

**Markings.** Each of `lines` is `element` and `y`: a line across the element's width, `y` from its top. Each of `boxes` is `element`, and may have `outset` (insets), `radius`, and `gap`, a slot of the element that the box's top edge breaks around.

**The OSD.** `osd` has `size`, at least 300 by 72, an image or draw, `bar`, and `text`, and may have `capInsets`. `bar` has `frame`, `track`, and `fill`, and may have `radius`. `text` has `level`, `unit`, `title`, and `subtitle`. Its frames are in the OSD. The OSD keeps its size, so its slots take no `anchors` or `scales`.

A `disabledOverlay` is a color laid over the display while System is stopped, in the shape of what it covers.

Since #86, `osd.disabledOverlay` and the nameplate's `tagline` slot are accepted and ignored, so a skin copied from modern before then still loads.

A slot that `scales` draws its text at the nearest half point.
