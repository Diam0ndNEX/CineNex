# CineNex Architecture

## Product goal

CineNex is an iPhone-first media discovery and playback app. It separates catalog metadata from playable media so supported providers can be integrated without coupling the interface to a specific service.

## Current implementation

- SwiftUI provides Home, Search, My List, and Tracking tabs.
- `MediaItem` represents a catalog entry and optional playable URL.
- `CatalogProvider` defines the boundary for metadata providers.
- `DemoCatalogProvider` supplies local sample entries when no live metadata provider is configured.
- `TMDBCatalogProvider` fetches trending movie/TV metadata with a user-supplied TMDB Read Access Token and maps posters, descriptions, years, genres, ratings, and TMDB IDs; metadata results never include playable URLs.
- `PlayerView` prefers SwiftVLC/libVLC for broad codec, container, subtitle, and protocol support, with AVPlayer available as a user-selectable fallback.
- The selected playback engine owns its timeline; progress persistence and Trakt scrobbling read the active engine's time and duration.
- `PlaybackProgressStore` persists resume positions in local UserDefaults.
- `TraktIntegration` handles device authorization, secure token storage, refresh, and optional movie scrobbling.
- The Tracking screen explains Letterboxd's API-access limitations and provides official links.
- GitHub Actions generates the Xcode project with XcodeGen and builds/tests the iOS Simulator target.

## Playback engine boundary

SwiftVLC is pinned to a specific source revision in `project.yml` so builds do not silently move with upstream `main`. SwiftVLC requires Xcode 26.4 / Swift 6.3 and iOS 18 or newer, so the app deployment target is iOS 18. The VLC binary is provided by SwiftVLC's package distribution; it is not copied from SceneBox's repository.

VLC is attempted first. If the initial VLC request throws, playback falls back to AVPlayer. Users can switch engines from the player toolbar when a stream starts but behaves poorly in one engine. A manual switch restarts the source at the last saved progress point. AVPlayer-only audio and subtitle menus are shown only while AVPlayer is active; VLC track selection is a separate follow-up integration.

This first hybrid layer does not claim that every source will work in either engine. VLC may still reject unsupported playlist wrappers, DRM, malformed URLs, or streams requiring provider-specific headers. HLS manifest URLs are supported by SwiftVLC, but classic M3U/PLS playlist containers must be resolved to their underlying media URL before playback.

## Planned boundaries

- Catalog providers: search, metadata, artwork, seasons, episodes, and external identifiers.
- Media providers: embedded API clients that discover authorized or openly licensed playback URLs, validate formats and source metadata, and expose source-specific capabilities.
- Playback services: engine selection, playback lifecycle, playback state, track selection, and error reporting.
- Tracking adapters: Trakt API and Letterboxd official data import/export.
- Library persistence: favorites, recent playback, and progress.
- Download manager: queueing, progress, storage limits, and offline availability.

## Constraints and assumptions

- Minimum deployment target is iOS 18 because the selected SwiftVLC version requires iOS 18.
- The app starts with local demo catalog data and can optionally load live TMDB trending metadata using a user-supplied Read Access Token.
- A catalog listing is not proof of streaming or download rights.
- Only media sources that permit access and playback should be integrated.
- Playback progress is stored locally on the device and is not synced between devices.
- Trakt credentials are per-user settings; OAuth tokens are stored in Keychain.
- Letterboxd API access is request-only and its current published policy does not grant access to private/personal projects.
- Some streaming formats, DRM systems, and subtitle formats require provider-specific support and cannot be assumed to work in either engine.
- VLC's PiP, audio-session, battery, and hardware-decoding behavior must be validated on physical devices; simulator build success is not proof of playback quality.

## Validation

Run `brew install xcodegen`, `xcodegen generate`, and then build/test the `CineNex` scheme in Xcode 26.4 or later with an iOS 18+ Simulator. The GitHub Actions workflow must use a compatible Xcode version before this dependency can pass CI.
