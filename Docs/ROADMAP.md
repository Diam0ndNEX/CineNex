# CineNex Roadmap

## Milestone 1 — Foundation

- Native SwiftUI app and three-tab navigation.
- Demo catalog with movie and series entries.
- Search by title, genre, and type.
- Detail pages and in-memory favorites.
- AVPlayer playback for a compatible HTTPS demo source.
- GitHub Actions simulator build and unit-test workflow.

Acceptance: app builds for iOS Simulator; search, details, favorites, and demo playback entry points work; model tests pass.

## Milestone 2 — Catalog integration

- Select a documented metadata provider.
- Implement network loading, decoding, cancellation, and clear loading/error/empty states.
- Add artwork loading with caching and accessible fallback artwork.
- Keep provider credentials out of source control.

Acceptance: search and details show live metadata and recover from network/API failures.

## Milestone 3 — Playback quality

- Playback state and recoverable errors.
- Resume progress and recently watched items.
- Subtitle and audio track discovery and selection where supported.
- Picture in Picture and AirPlay behavior validation.
- Support for series seasons and episodes.

Acceptance: supported streams play consistently and state persists across app launches.

## Milestone 4 — Offline library

- Download eligibility per source.
- Download queue, progress, pause/resume, cancellation, and storage accounting.
- Local media playback and offline library.
- Subtitle file association and cleanup behavior.

Acceptance: permitted downloadable content can be played offline and storage state remains consistent after relaunch.

## Milestone 5 — Multiple sources and release readiness

- Add providers behind explicit capabilities and source metadata.
- Accessibility, localization, privacy disclosures, and robust error handling.
- Broader unit and UI tests.
- Signed IPA workflow after signing and distribution method are configured.

Acceptance: providers are individually testable, release builds are reproducible, and no secrets are stored in repository files.
