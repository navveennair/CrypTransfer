# Branding & Visual Assets

This module tracks the visual identity and platform-specific assets for CrypTransfer.

## Core Identity
- **Logo Concept**: Sky Blue & Navy Geometric Chevron, representing secure, directed transfer.
- **Primary Color**: `#0D1117` (GitHub Dark Background)
- **Accent Color**: `#58A6FF` (Primary Blue)

## Platform Assets

### Android
- **Launcher Icons**: Located in `android/app/src/main/res/mipmap-*`.
  - `hdpi`: 72x72
  - `mdpi`: 48x48
  - `xhdpi`: 96x96
  - `xxhdpi`: 144x144
  - `xxxhdpi`: 192x192
- **Security Visibility**: The `FLAG_SECURE` implementation in `MainActivity.kt` ensures these assets and the UI they represent are not leaked in task-switcher thumbnails.

### iOS
- **App Icons**: Located in `ios/Runner/Assets.xcassets/AppIcon.appiconset/`.
  - Includes all standard iPhone/iPad sizes (20pt, 29pt, 40pt, 60pt, 76pt, 83.5pt) at @2x and @3x scales.
  - Master 1024x1024 Store Icon.
- **Launch Screen**: Located in `ios/Runner/Assets.xcassets/LaunchImage.imageset/`.
  - Uses the geometric chevron logo on a dark background.

## Design System
- **Typography**: Inter for body text, Poppins for headers.
- **Button Style**: 3D "Glass" effect implemented via custom widgets to match the geometric theme.

## Maintenance
When updating brand assets, ensure all densities are generated to maintain visual fidelity across devices.
