# GPGeze

A native macOS app for managing GPG keys, organizing recipients into groups, and encrypting/decrypting files — with Finder right-click integration.

## Features

- **Key Management** — Import, view, export, and delete GPG public and secret keys
- **Groups** — Organize keys into named groups (e.g. "Team Alpha", "Finance")
- **Encrypt** — Encrypt files for a group with one click; optionally always include your own key
- **Decrypt** — Decrypt `.gpg` files (passphrase handled by system pinentry)
- **Finder Integration** — Right-click any file in Finder → **Services → Encrypt with GPGeze…** / **Decrypt with GPGeze…**
- **Settings** — Configure GPG binary path, own-key auto-include, signing, and output options

## Requirements

- macOS 14.0 (Sonoma) or later
- GPG installed (`brew install gnupg` or [GPG Suite](https://gpgtools.org))

## Build

```bash
# Install xcodegen if not already installed
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Open in Xcode
open GPGeze.xcodeproj
```

Or build from the command line:

```bash
xcodebuild -project GPGeze.xcodeproj -scheme GPGeze -destination "platform=macOS" build
```

## Finder Right-Click Services

After first launch, GPGeze registers two macOS Services:

- **Encrypt with GPGeze…** — Select files in Finder, right-click → Services → Encrypt with GPGeze…
- **Decrypt with GPGeze…** — Right-click `.gpg` files → Services → Decrypt with GPGeze…

The app must be running (or will be launched automatically) when a service is invoked. If services don't appear immediately, log out and back in, or run:

```bash
/System/Library/CoreServices/pbs -update
```

## Project Structure

```
GPGeze/
├── project.yml                        # xcodegen project spec
└── GPGeze/
    ├── Sources/
    │   ├── GPGezeApp.swift            # App entry point
    │   ├── AppDelegate.swift          # NSServices registration
    │   ├── AppState.swift             # Central state & business logic
    │   ├── Models/
    │   │   ├── GPGKey.swift
    │   │   ├── KeyGroup.swift
    │   │   └── AppSettings.swift
    │   ├── Services/
    │   │   ├── GPGService.swift       # GPG shell command wrapper
    │   │   └── ServiceHandler.swift   # Finder right-click handler
    │   └── Views/
    │       ├── ContentView.swift
    │       ├── Keys/                  # Key list, import, export
    │       ├── Groups/                # Group management
    │       ├── Encrypt/               # File encryption UI
    │       ├── Decrypt/               # File decryption UI
    │       ├── Settings/              # App settings
    │       └── Shared/                # Reusable components
    └── Resources/
        ├── Info.plist                 # NSServices registration
        └── Assets.xcassets
```

## Notes

- App sandbox is **disabled** to allow running `gpg` and accessing arbitrary files. This app is for direct distribution, not App Store.
- Passphrase entry for decryption is handled entirely by GPG's system pinentry agent — GPGeze never handles passphrases directly.
- Groups and settings are stored in `~/Library/Application Support/GPGeze/`.
