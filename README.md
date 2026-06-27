# Yalla Pro – Yalla Lite Tweak

iOS tweak (dylib) for Yalla Lite with auto-tap, position targeting, speed control and account merge.

## Features

- ⚡ **Floating draggable button** – tap to open the control panel
- ▶️ **Auto-tap toggle** – start/stop automatic tapping
- 🎯 **Position selector** – tap anywhere on screen to set the click target
- ⏱ **Speed slider** – 0.5x to 20x tap speed
- 🔄 **Account merge** – one-tap merge accounts
- 📍 **Position display** – shows current X/Y coordinates
- 💾 **Persistent position** – your last selected position is saved

## Build

```bash
make package
```

## Install on device

```bash
make package install
```

Requires a jailbroken device with Theos and mobilesubstrate.

## Requirements

- iOS 12.0+
- Theos
- Jailbroken device (arm64 / arm64e)
