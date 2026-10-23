# CineNex Architecture

## Product goal

CineNex is an iPhone-first media discovery and playback app. It separates catalog metadata from playable media so supported providers can be integrated without coupling the interface to a specific service.

## Current implementation

- SwiftUI provides the native navigation and screens.
- `MediaItem` represents a catalog entry and optional playable URL.
- `CatalogProvider` defines the boundary for metadata providers.
- `DemoCatalogProvider` supplies local sample entries.
- `PlayerView` uses AVPlayer for compatible HTTPS media.
- GitHub Actions generates the Xcode project with XcodeGen and builds/tests the iOS Simulator target.

## Planned boundaries

- Catalog providers: search, metadata, artwork, seasons, and episodes.
- Media providers: authorized playback URLs and source-specific capabilities.
- Playback services: AVPlayer lifecycle, playback state, track selection, and error reporting.
- Library persistence: favorites, recent playback, and progress.
- Download manager: queueing, progress, storage limits, and offline availability.

## Constraints and assumptions

- Initial deployment target is iOS 17.
- The first release uses local demo catalog data; no live catalog API key is required.
- A catalog listing is not proof of streaming or download rights.
- Only media sources that permit access and playback should be integrated.
- Secrets and signing credentials must not be committed to this public repository.
- Some streaming formats, DRM systems, and subtitle formats require provider-specific support and cannot be assumed to work in AVPlayer.

## Validation

Run `brew install xcodegen`, `xcodegen generate`, and then build/test the `CineNex` scheme in Xcode or with `xcodebuild`. The GitHub Actions workflow runs simulator build and unit tests on pushes and pull requests.
