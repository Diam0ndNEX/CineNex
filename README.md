# CineNex

CineNex is an iPhone-first SwiftUI media discovery and playback app. Its architecture separates catalog metadata from playable sources so additional compatible providers can be added without rebuilding the UI.

## Current status

The first foundation is committed:

- Native dark SwiftUI interface with Home, Search, and My List tabs.
- Demo movie and series catalog with title details.
- Search by title, genre, and media type.
- In-memory favorites.
- AVPlayer screen for a compatible HTTPS sample video.
- Catalog provider protocol for future metadata integrations.
- Unit tests for catalog identity and the playable sample.
- GitHub Actions simulator build and test workflow.

The catalog is currently local demo data. Most entries are illustrative and do not have playable sources. Big Buck Bunny is included as a sample playback target; it is not a catalog or streaming service.

## Build locally

Requirements: macOS, Xcode with an iOS Simulator runtime, and XcodeGen.

```sh
brew install xcodegen
xcodegen generate
open CineNex.xcodeproj
```

Select the `CineNex` scheme and an iPhone Simulator, then build and run. To run tests from the terminal:

```sh
xcodebuild -project CineNex.xcodeproj -scheme CineNex -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO test
```

## Architecture and roadmap

See [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) and [Docs/ROADMAP.md](Docs/ROADMAP.md).

## Content and rights

CineNex is a player and discovery app, not a source of universal streaming rights. Integrations must respect the source's access rules, copyright, DRM, and download permissions. A catalog result does not imply that a playable stream or download is available.

## Security

Do not commit API secrets, account credentials, signing certificates, provisioning profiles, or private keys. Configure provider credentials through appropriate build settings or GitHub Actions secrets when needed.
