# CineNex Roadmap

## Milestone 1 — Foundation

- Native SwiftUI app and three-tab navigation.
- Demo catalog with movie and series entries.
- Search by title, genre, and type.
- Detail pages and persistent favorites.
- AVPlayer playback for a compatible HTTPS demo source.
- GitHub Actions simulator build and unit-test workflow.

Acceptance: app builds for iOS Simulator; search, details, favorites, and demo playback entry points work; model and progress tests pass.

## Milestone 2 — Playback continuity

- Persist playback position locally.
- Resume the last saved position when reopening a playable title.
- Show unfinished playable titles in Continue Watching.
- Remove saved progress when playback reaches the completion threshold.
- Test invalid values, persistence, and completion cleanup.

Acceptance: progress survives app relaunches, completed playback no longer appears in Continue Watching, and playback state remains local to the device.

## Milestone 3 — Catalog integration

- Select a documented metadata provider.
- Implement network loading, decoding, cancellation, and clear loading/error/empty states.
- Add artwork loading with caching and accessible fallback artwork.
- Keep provider credentials out of source control.

Acceptance: search and details show live metadata and recover from network/API failures.

## Milestone 4 — Playback quality

- Playback state and recoverable errors.
- Subtitle and audio track discovery and selection where supported.
- Picture in Picture and AirPlay behavior validation.
- Support for series seasons and episodes.

Acceptance: supported streams play consistently and state persists across app launches.

## Milestone 5 — Offline library

- Download eligibility per source.
- Download queue, progress, pause/resume, cancellation, and storage accounting.
- Local media playback and offline library.
- Subtitle file association and cleanup behavior.

Acceptance: permitted downloadable content can be played offline and storage state remains consistent after relaunch.

## Milestone 6 — Multiple sources and release readiness

- Add providers behind explicit capabilities and source metadata.
- Accessibility, localization, privacy disclosures, and robust error handling.
- Broader unit and UI tests.
- Signed IPA workflow after signing and distribution method are configured.

Acceptance: providers are individually testable, release builds are reproducible, and no secrets are stored in repository files.
