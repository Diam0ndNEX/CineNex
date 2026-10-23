# CineNex Roadmap

## Milestone 1 — Foundation

- Native SwiftUI app and four-tab navigation.
- Demo catalog with movie and series entries.
- Search by title, genre, and type.
- Detail pages and persistent favorites.
- AVPlayer playback for a compatible HTTPS demo source.
- GitHub Actions simulator build and unit-test workflow.

Acceptance: app builds for iOS Simulator; search, details, favorites, tracking setup, and demo playback entry points work.

## Milestone 2 — Playback continuity

- Persist playback position locally.
- Resume the last saved position when reopening a playable title.
- Show unfinished playable titles in Continue Watching.
- Remove saved progress when playback reaches the completion threshold.
- Test invalid values, persistence, and completion cleanup.

Acceptance: progress survives app relaunches, completed playback no longer appears in Continue Watching, and playback state remains local to the device.

## Milestone 3 — Watch tracking

- Trakt device authorization, Keychain token storage, token refresh, and movie scrobbling.
- Trakt history, ratings, and watchlist import/sync with duplicate-safe conflict handling.
- Letterboxd CSV import/export based on official user exports.
- Explicit review screen before importing, adding, or changing watched entries.
- Keep local progress available when integrations are disconnected.

Acceptance: integrations are opt-in, can be disconnected, and report partial failures without interrupting playback.

## Milestone 4 — Catalog integration

- Select a documented metadata provider.
- Implement network loading, decoding, cancellation, and clear loading/error/empty states.
- Add artwork loading with caching and accessible fallback artwork.
- Map catalog entries to verified TMDB, IMDb, and Trakt IDs where available.

Acceptance: search and details show live metadata and recover from network/API failures.

## Milestone 5 — Playback quality

- Playback state and recoverable errors.
- Subtitle and audio track discovery and selection where supported.
- Picture in Picture and AirPlay behavior validation.
- Support for series seasons and episodes.

Acceptance: supported streams play consistently and state persists across app launches.

## Milestone 6 — Offline library and release readiness

- Download eligibility per source.
- Download queue, progress, pause/resume, cancellation, and storage accounting.
- Local media playback and offline library.
- Accessibility, localization, privacy disclosures, broader tests.
- Signed IPA workflow after signing and distribution method are configured.

Acceptance: providers are individually testable, release builds are reproducible, and no secrets are stored in repository files.
