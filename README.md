# HypnoticSpiral

A cross-platform iOS/macOS app that generates animated hypnotic spirals synchronized with text-to-speech narration, background music, and interactive prompts. Programs are defined entirely through JSON configuration files.

## Features

- Multiple spiral visualization algorithms (twist, fermat, logarithmic, chromatic, and more)
- Text-to-speech with word-by-word display
- Background music playback
- Image cycling with configurable timing
- Interactive prompts and branching logic
- Voice recognition for mantra validation
- Session persistence and resume
- Fully configurable via JSON

## Requirements

- macOS 13+ or iOS 17+
- Xcode 15+
- Apple Developer account (for device deployment)

## Building

1. Clone the repository
2. Open `HypnoticSpiral.xcodeproj` in Xcode
3. Select your target (macOS or iOS)
4. Build and run (Cmd+R)

For iOS device deployment, you'll need to configure signing in the project settings.

## Usage

1. Launch the app
2. Select a configuration from the list
3. The spiral and script will begin automatically
4. Use the tempo slider to adjust playback speed
5. Close to return to config selection

## Adding Content

- **Configs**: Add JSON files to the `Configs/` directory (see [CONFIGS.md](CONFIGS.md) for format)
- **Music**: Add MP3 files to the `Music/` directory
- **Images**: Create subdirectories in `Images/` and reference via `image_dir` property

## Configuration

See [CONFIGS.md](CONFIGS.md) for complete documentation of the JSON configuration format, including all available properties and commands.

## License

Copyright 2025-2026 Yonah Arakoslav <arakoslav@protonmail.com>

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License version 2 as published by the Free Software Foundation.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
