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

The app starts with local demo data. With a TMDB Read Access Token saved in Tracking, Home loads trending metadata and Search can query TMDB's movie/TV catalog. Metadata does not include playable streams. Big Buck Bunny is included as a sample playback target; it is not a catalog or streaming service.

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

## Optional live metadata

1. Create or open your TMDB account and visit [API settings](https://www.themoviedb.org/settings/api).
2. Copy the TMDB API **Read Access Token**.
3. In CineNex, open Tracking, enter the token in Live Catalog, and save it.
4. Return to Home and pull down or tap the refresh icon to load trending metadata. In Search, enter a title and tap Search TMDB to find movies and series outside the trending list. Disconnecting TMDB disables remote search and returns Home to the demo catalog.

The token is currently saved in local app preferences; moving it to Keychain is a planned security hardening step. Do not share it or commit it to the repository. TMDB metadata access does not grant rights to stream, download, or redistribute any title. Follow TMDB attribution and API terms for distribution.

## Content and rights

CineNex is a player and discovery app, not a source of universal streaming rights. Integrations must respect the source's access rules, copyright, DRM, and download permissions. A catalog result does not imply that a playable stream or download is available.

## Security

Do not commit API secrets, account credentials, signing certificates, provisioning profiles, or private keys. Configure provider credentials through appropriate build settings or GitHub Actions secrets when needed.
