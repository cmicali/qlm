# Skins

A skin draws qlm's main window and its OSD. The app draws every piece of text, every symbol, and the knob's angle. [docs/ui.md](../../../docs/ui.md) gives the why. This file gives the keys.

A skin is one directory:

```
<name>/
  skin.json
  png/        each image as <image>.png and <image>@2x.png
```

The app ships its skins in `Resources/Skins/`. A user's skins go in `~/Library/Application Support/qlm/Skins/`. The reader is strict. An unknown key, a missing element or slot, a frame outside the window, a missing image, an element with both an image and a draw, a bad color, or a size below the reference refuses the skin, and the app falls back to modern.

## Values

| Value | Form |
| --- | --- |
| Frame | `[x, y, width, height]` in points, from the top left |
| Size | `[width, height]` |
| Color | `"#RRGGBB"`, `"#RRGGBBAA"`, or a name in `palette` |
| Insets | `[top, left, bottom, right]`, as the pack orders them, or one number for all four |
| Anchors | A list of `"left"`, `"right"`, `"top"`, and `"bottom"`. Left and top when absent. |

**Anchors** are springs and struts. As the window grows, an element keeps its distance to each edge it names. Both edges of an axis stretch it along that axis. One edge keeps it at that edge. Neither keeps it centered. A text slot's anchors work the same way inside its element.

## The file

| Key | Holds |
| --- | --- |
| `format` | `1` |
| `size` | The window's reference size, at least 640 by 480. The window never goes below it. |
| `palette` | Named colors, each `#RRGGBB` or `#RRGGBBAA` |
| `elements` | The eight elements below, each by its name |
| `button` | The buttons' style |
| `led` | `on` and `off` colors, and `glow`, a radius |
| `markings` | `color`, `width`, `lines`, and `boxes` |
| `osd` | The OSD |

Every element has `frame`, and may have `anchors` and `text`. Its other keys are its kind's:

| Element | Its own keys | Its text slots |
| --- | --- | --- |
| `panel` | image or draw | |
| `nameplate` | image or draw | `logo` and `tagline`, both optional |
| `status` | `led`, a frame in the element | `online` |
| `groups` | `columns`, `rows`, `gap` | `groupsTitle` |
| `display` | image or draw, `disabledOverlay` | `caption`, `level`, `unit`, `output`, `max` |
| `toggles` | `columns`, `rows`, `gap` | |
| `knob` | `body`, `pointer`, `focus`, and optionally `ticks`, `shadow`, `arc` | `min`, `max`, `caption` |
| `footer` | `symbols`: `monitors` and `power`, SF Symbol names | `monitors`, `power` |

`groups` lays up to six buttons in its cells, row by row. `toggles` lays Mute and Dim in its first two. `gap` is `[x, y]`.

**Image or draw.** An element takes `image`, with `capInsets`, or `draw`, never both. An image of one state is `png/<image>.png`. The button takes eight states, as `<image>-normal`, `-hover`, `-pressed`, `-disabled`, `-selected`, `-selected-hover`, `-selected-pressed`, and `-selected-disabled`. The knob's body takes the first four.

**A draw block** has `fill` or `gradient` (two colors, top then bottom), `border`, `borderWidth`, `radius`, `inset`, `rings` (each `inset`, `color`, `width`), and `shadow` (`color`, `blur`, `offset`). All are optional. A button's or a knob body's block may add `states`: each state's overrides, by the state names above. A selected state takes `selected`'s overrides, then its own.

**A text slot** has `frame`, `size`, and `color`, and optionally `anchors`, `font` (a face the Mac has, else the system font), `mono` (the system monospaced font when the face is missing), `weight` (`ultralight` to `black`), `italic`, `alignment` (`left`, `center`, `right`), `tracking`, and `accent` (the color of a trailing period). With `scales`, its frame and size grow with its element's height, from the element's origin, and its anchors don't apply.

**The knob.** `body` has `size`, a diameter, and an image or draw. `ticks` has `count`, `inner`, `outer`, `width`, and `color`, with radii from the center. `pointer` has `inner`, `outer`, `width`, `color`, and `disabledColor`. `focus` has `color`, `width`, `radius`, and `outset`. `arc` has `radius`, `width`, `track`, and `fill`. The sweep is fixed: −135° to +135°, clockwise from straight up.

**The button.** `button` has an image or draw, `title` (`size`, `color`, and optionally `font`, `weight`, `tracking`, `selectedColor`, `disabledColor`, `prefixColor`), `focus`, and optionally `led`: `size`, and `gap` to sit just before the title, or `x` to sit that far from the left edge.

**Markings.** Each of `lines` is `element` and `y`: a line across the element's width, `y` from its top. Each of `boxes` is `element`, and optionally `outset` (insets), `radius`, and `gap`, a slot of the element its top edge breaks around.

**The OSD.** `osd` has `size`, at least 300 by 72, an image or draw, `disabledOverlay`, `bar` (`frame`, `track`, `fill`, `radius`), and `text` with `level`, `unit`, `title`, and `subtitle`. Its frames are in the OSD.
