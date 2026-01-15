# HypnoticSpiral Configuration Manual

This document describes the JSON configuration file format for HypnoticSpiral.

## File Structure

Configuration files are JSON documents with this top-level structure:

```json
{
  "name": "ConfigName",
  "description": "Optional description of the configuration",
  "base": null,
  "properties": { ... },
  "scripts": { ... }
}
```

### Top-Level Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Display name for the configuration |
| `description` | string | No | Human-readable description |
| `base` | string/null | No | Parent config name for inheritance |
| `properties` | object | Yes | Visual, audio, and timing settings |
| `scripts` | object | Yes | Named scripts containing words and commands |

### Inheritance

Configs can inherit from a parent by setting `base` to the parent's name:

```json
{
  "name": "MyVariant",
  "base": "Standard",
  "properties": { ... }
}
```

Child configs inherit all properties and scripts from the parent, overriding only what they specify.

---

## Properties

The `properties` object controls appearance, timing, and behavior.

### Display Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `size` | [int, int] | [1280, 800] | Window size in pixels [width, height] |
| `fullscreen` | bool | false | Start in fullscreen mode |
| `broken_fonts` | bool | false | Legacy font rendering workaround |

### Spiral Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `spiral_type` | string | "fermat" | Spiral algorithm (see below) |
| `color` | [int, int, int] | [255, 255, 255] | Spiral RGB color (0-255 each) |
| `alpha` | int | 127 | Spiral opacity (0-255) |
| `spiral_arms` | int | 4 | Number of spiral arms (symmetry) |
| `spiral_tightness` | float | 0.2 | Controls spacing/density |
| `spiral_line_width` | float | 4.0 | Width of spiral lines |
| `spiral_range` | int | 90 | Degrees before pattern repeats |
| `spiral_step` | int | 1 | Degrees per animation frame |
| `spiral_counter_rate` | float | 0.7 | Counter-rotation speed for twist type |
| `spiral_fill_color` | [int, int, int] | null | Fill color for "filled" spiral type |
| `spiral_image` | string | "" | Path to custom spiral image file |
| `scale` | int | 10 | Generation scale factor |

#### Spiral Types

| Type | Description |
|------|-------------|
| `fermat` | Classic expanding spiral (r = t²) with constant spacing |
| `logarithmic` | Constant-angle "swoopy" spiral (r = a × e^(bθ)) |
| `filled` | Alternating colored sectors (half-screen tint effect) |
| `twist` | Counter-rotating double-layer spirals |
| `nimja` | Curved wedge sectors with strong pull effect |
| `chromatic` | Shader-style with RGB chromatic aberration |

### Text Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `text_color` | [int, int, int] | [0, 51, 204] | Text RGB color |
| `text_alpha` | int | 254 | Text opacity (0-255) |

### Timing Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `frame_rate` | int | 60 | Target frames per second |
| `time_scale` | int | 2 | Speed multiplier for frequency counters |
| `frequencies` | object | See below | Event timing configuration |
| `minimum_delay` | int | 0 | Minimum random delay (unused) |
| `maximum_delay` | int | 0 | Maximum random delay (unused) |

#### Frequencies Object

Controls how often events occur (in frames at base rate):

```json
"frequencies": {
  "spiral": 1,    // Spiral rotation frequency
  "images": 50,   // Frames between image changes
  "words": 40     // Frames between word advances
}
```

Lower values = faster. With `time_scale: 2` and `frame_rate: 60`:
- `words: 40` means ~3 words per second
- `images: 50` means ~2.4 image changes per second

### Audio Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `music` | string | null | Background music filename (from Music folder) |
| `voice` | string | null | Text-to-speech voice name |

### Image Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `image_dir` | string | "images/" | Directory containing images |
| `image_alpha` | int | 255 | Image opacity (0-255) |
| `shuffle_images` | bool | true | Randomize image order |

### Subliminal Text Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `subliminal_alpha` | int | null | Subliminal text opacity |
| `subliminal_color` | [int, int, int] | null | Subliminal text RGB color |
| `subliminal_scatter` | int | null | Position scatter amount |
| `subliminal_moveprobability` | int | null | Probability of repositioning (0-100) |
| `subliminal_displayprobability` | int | null | Probability of showing (0-100) |
| `subliminal_changeprobability` | int | null | Probability of changing text (0-100) |

---

## Scripts

The `scripts` object contains named scripts. Each script is an array of elements:

```json
"scripts": {
  "text": [
    "!words_on()",
    "!jump('self.body')"
  ],
  "body": [
    "Word", "by", "word.",
    "!images_on()",
    "See", "the", "pictures."
  ]
}
```

The script named `"text"` is the entry point and runs first.

### Script Elements

Scripts contain three types of elements:

1. **Words** - Plain strings displayed and/or spoken
2. **Commands** - Strings starting with `!` that control behavior
3. **References** - Objects that include other scripts

#### Words

Simple strings are displayed on screen and spoken (if speech is enabled):

```json
["This", "is", "displayed."]
```

Words ending in `.` `!` `?` or `,` mark sentence boundaries for speech batching.

#### Variable Substitution

Use `$variableName` in words to substitute user-provided values:

```json
["Hello", "$name,", "welcome."]
```

If a variable isn't set when encountered, the user is automatically prompted.

#### Speech Markup

Control speech rate inline with `[[rate N]]` markup:

```json
["Normal", "speed.", "[[rate +2000]]", "Faster", "now."]
```

- Absolute: `[[rate 32768]]` sets to specific rate (Speech Manager scale 0-65535)
- Relative: `[[rate +1000]]` or `[[rate -500]]` adjusts current rate

Markup is stripped from displayed text.

#### Script References

Include another script inline:

```json
{"ref": "self.otherScript"}
```

Or from a parent config:

```json
{"ref": "parent.inheritedScript"}
```

---

## Commands Reference

Commands are prefixed with `!` and control program behavior.

### Display Control

| Command | Description |
|---------|-------------|
| `!spiral_on()` | Show the spiral animation |
| `!spiral_off()` | Hide the spiral |
| `!words_on()` | Enable word display |
| `!words_off()` | Disable word display |
| `!images_on()` | Show cycling images |
| `!images_off()` | Hide images |
| `!speaking_on()` | Enable text-to-speech |
| `!speaking_off()` | Disable text-to-speech |

### Text Commands

| Command | Description |
|---------|-------------|
| `!hold_text('text')` | Display persistent text (empty string clears) |
| `!background('text')` | Display background layer text |
| `!speak('text')` | Speak text immediately |
| `!whisper('text')` | Speak text at 30% volume |

### Image Commands

| Command | Description |
|---------|-------------|
| `!hold_image('filename.jpg')` | Lock display to specific image |
| `!hold_image_start()` | Begin capturing following words as filename |
| `!hold_image_end()` | End capture and show the named image |
| `!hold_image_blank()` | Clear held image, stop showing images |

### Music Commands

| Command | Description |
|---------|-------------|
| `!start_music()` | Start/resume music playback |
| `!stop_music()` | Stop music completely |
| `!pause_music()` | Pause music (can resume) |
| `!unpause_music()` | Resume paused music |

### Control Flow

| Command | Description |
|---------|-------------|
| `!jump('scriptName')` | Jump to another script |
| `!quit()` | End the program |

Jump supports `self.` and `parent.` prefixes:
```json
"!jump('self.body')"
"!jump('parent.inherited')"
```

### User Input Commands

#### `!prompt('message')`
Display a message with OK button. Pauses until dismissed.

```json
"!prompt('Welcome to the program.')"
```

#### `!short_prompt('message')`
Alias for `!prompt()`.

#### `!open_question('prompt', 'variableName')`
Ask a free-text question, store answer in variable.

```json
"!open_question('What is your name?', 'name')"
```

#### `!yn_question('question', 'yesScript', 'noScript')`
Ask yes/no question, branch to different scripts.

```json
"!yn_question('Do you want to continue?', 'self.continue', 'self.goodbye')"
```

Also available as `!question_yn()`.

#### `!challenge('prompt', 'variableName')`
Like `open_question` but styled as a challenge/test.

```json
"!challenge('What are you?', 'identity')"
```

#### `!set_pref('prompt', 'variableName')`
Persistent preference - only prompts if not already set. Value persists across sessions.

```json
"!set_pref('What is your name?', 'name')"
```

#### `!mantra('expectedText')`
Require user to type exact text before continuing.

```json
"!mantra('I obey')"
```

With timeout and script jump:
```json
"!mantra('I obey', 30, 'self.retrain')"
```

With timeout and word insertion:
```json
"!mantra('I obey', 30, ['Try', 'again.', 'Say', 'it.'])"
```

#### `!speak_mantra('expectedText')`
Like `!mantra()` but microphone auto-starts for voice recognition.

```json
"!speak_mantra('I obey', 30, 'self.retrain')"
```

### Conditional Command

#### `!cond('condition', thenWords, elseWords)`

Conditionally insert words into the script.

**Two-array form** (if-then-else):
```json
"!cond('self.draw_image', ['Images', 'are', 'on.'], ['Turn', 'images', 'on.'])"
```

**One-array form** (guard - insert if FALSE):
```json
"!cond('self.draw_image', ['Turn', 'on', 'images.'])"
```

**Supported conditions:**
- `self.draw_image` / `self.drawImages` - true if images are showing
- `self.draw_spiral` / `self.drawSpiral` - true if spiral is showing
- `self.draw_words` / `self.drawWords` - true if words are displaying
- `self.speak_words` / `self.speakWords` - true if speech is enabled
- `self.config.fullscreen` - true if config specifies fullscreen
- `self.is_fullscreen` / `self.isFullscreen` - true if currently fullscreen
- `variableName` - true if variable is set and non-empty
- `not <condition>` - negates any condition

### Camera Commands

| Command | Description |
|---------|-------------|
| `!camera_snapshot()` | Capture photo from camera |
| `!load_lastCameraShot()` | Load most recent captured image |
| `!show_lastCamImage()` | Display the captured image |
| `!hide_lastCamImage()` | Hide the captured image |

---

## Complete Example

```json
{
  "name": "Example",
  "description": "A minimal example configuration",
  "base": null,
  "properties": {
    "size": [1280, 800],
    "fullscreen": false,
    "color": [255, 255, 255],
    "alpha": 127,
    "spiral_type": "twist",
    "spiral_arms": 3,
    "spiral_tightness": 0.18,
    "spiral_line_width": 3.0,
    "text_color": [0, 51, 204],
    "text_alpha": 254,
    "frame_rate": 60,
    "time_scale": 2,
    "frequencies": {
      "spiral": 1,
      "images": 50,
      "words": 40
    },
    "music": "music6.mp3",
    "image_dir": "images/",
    "image_alpha": 255,
    "shuffle_images": true
  },
  "scripts": {
    "text": [
      "!set_pref('What is your name?', 'name')",
      "!words_on()",
      "!spiral_on()",
      "!jump('self.body')"
    ],
    "body": [
      "Hello", "$name.",
      "Watch", "the", "spiral.",
      "!images_on()",
      "See", "the", "pictures.",
      "!yn_question('Continue?', 'self.more', 'self.end')"
    ],
    "more": [
      "Good.", "Keep", "watching.",
      "!jump('self.body')"
    ],
    "end": [
      "Goodbye", "$name.",
      "!quit()"
    ]
  }
}
```

---

## Tips

1. **Start with `text` script** - This is always the entry point
2. **Use `set_pref` for names** - Persists across sessions
3. **End sentences with punctuation** - Enables proper speech batching
4. **Use inheritance** - Set `"base": "Standard"` to inherit defaults
5. **Test with short scripts** - Verify timing before writing long content
6. **Music files go in Music/** - Reference by filename only
7. **Images go in subdirectories** - Set `image_dir` to the folder name
