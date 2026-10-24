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
- Letterboxd CSV import/export for diary, watched, ratings, and watchlist files.
- Explicit review screen before importing, adding, or changing watched entries.
- Keep local playback progress available when integrations are disconnected.

Acceptance: integrations are opt-in, can be disconnected, and report partial failures without interrupting playback.

## Milestone 4 — Catalog integration

- TMDB trending movie/TV metadata provider with user-supplied Read Access Token.
- Decode trending metadata, map titles, overviews, release years, genres, ratings, poster paths, and TMDB IDs.
- Search the TMDB multi-search endpoint and show live poster artwork and ratings in title details.
- Add refresh, loading feedback, network/API error messages, and local demo fallback.
- Completed: Keychain storage for TMDB credentials with legacy migration, cached poster artwork, verified TMDB identifiers in Trakt movie scrobbles, and TMDB attribution notice.
- Completed: TV season summaries on title detail pages, including episode counts, air years, artwork, and overviews when TMDB provides them.
- Completed: per-season episode listings fetched on demand from TMDB and shown in a dedicated sheet, with episode stills, air dates, runtimes, and safe handling of malformed/duplicate records.
- Completed: fetch Trakt movie watchlists, watched-movie history, and ratings; review individual entries; and import selected records into separate persistent local lists with duplicate-safe merging. All three imports are one-way and do not modify Trakt.

Acceptance: search and details show live metadata and recover from network/API failures. Catalog metadata is kept separate from playable media sources; TMDB metadata alone is never treated as a stream.

## Milestone 5 — External streaming providers and source resolution

**Product requirement: CineNex must not require the user to host media or run a personal media server.** Playback sources should be discovered and resolved through supported external integrations, embedded APIs, and compatible community add-ons. Jellyfin, Plex, and Emby may be optional integrations in the future, but they are not the core provider strategy.

- Audit the current playback-provider abstractions and coordinator; clearly distinguish working integrations from interfaces, mock/demo providers, and unimplemented adapters.
- Research the Stremio add-on ecosystem and implement a real, testable integration where API compatibility, add-on manifests, metadata mapping, and iOS constraints permit.
- Investigate Torrential and other relevant torrent-based integrations, verifying their actual APIs, licensing/usage constraints, iOS feasibility, and whether they can produce streams that CineNex can play. Do not assume an Android implementation can be embedded directly in iOS.
- Evaluate additional compatible source integrations to broaden movie and series coverage without requiring a user-operated server.
- Implement provider discovery and stream resolution with timeouts, cancellation, source deduplication, provider identity and priority enforcement, and useful errors for unavailable or unsupported sources.
- Keep catalog metadata, add-on discovery, stream resolution, and playback as separate layers. A title appearing in a catalog or a provider returning a URL does not by itself mean playback will work.
- Validate resolved source formats, HTTP headers/authentication requirements, redirects, DRM or other access restrictions, and AVPlayer compatibility before presenting a source as playable.
- Make integrations opt-in where required, handle unavailable or incompatible add-ons gracefully, and never claim that a source is verified until it has passed the relevant checks.
- Document any required user configuration honestly. Do not make personal API tokens, self-hosted servers, or manual add-on setup mandatory for basic app use unless a specific integration genuinely requires it.

Acceptance: at least one real external provider integration is exercised end-to-end with tests and documented limitations; source discovery and resolution feed the native player; failures are recoverable; no personal media server is required. Provider coverage is measured by verified working integrations, not by the number of declared provider interfaces.

## Milestone 6 — Playback quality

- Playback state and recoverable errors.
- Completed: discover and select alternate audio tracks and subtitles when the stream exposes AVPlayer media-selection groups.
- Implemented: native AVPlayer controls expose Picture in Picture and AirPlay options when supported by the device and media source; physical-device validation remains.
- Complete series season/episode playback using actual resolved episode sources, not metadata-only episode listings.
- Add source switching, retry/fallback behavior, and clear status when a source fails or is incompatible.
- Validate resume/progress behavior across source changes, app lifecycle transitions, and episodic playback.

Acceptance: verified compatible sources play consistently; source failures do not strand the player; progress and episode state persist correctly across app launches.

## Milestone 7 — Offline library and release readiness

- Implemented foundation: persistent HLS download records, progress callbacks, cancellation, removal, recovery of background URL-session tasks, and local asset location lookup.
- Initial eligibility is intentionally limited to HTTPS HLS playlists ending in .m3u8; MP4 and DRM-protected sources are not treated as offline-downloadable.
- Completed: connect eligible HLS download actions to title details, play completed downloads from the offline library, show recursive local storage usage, and recover when a completed asset disappears.
- Completed: add pause/resume controls for active HLS downloads, preserve paused state when reconnecting background tasks, and restart cleanly if a paused task is no longer available.
- Completed: remove all completed offline downloads in one confirmed action while preserving queued, active, and paused downloads.
- Next: accessibility, localization, privacy disclosures, broader tests, and end-to-end testing of downloads from real provider-resolved sources when permitted and technically supported.
- Validate that download controls only appear for sources that are legally and technically eligible; do not bypass DRM or provider restrictions.
- Signed IPA workflow after signing and distribution method are configured.

Acceptance: eligible downloads recover safely and play offline; providers are individually testable; release builds are reproducible; and no secrets are stored in repository files.

## Cross-cutting requirements

- Prefer public, documented integration APIs and respect applicable provider terms, licensing, copyright, and access restrictions.
- Do not scrape or bypass authentication, DRM, paywalls, or other access controls as a substitute for supported integrations.
- Never describe metadata discovery as playable streaming availability.
- Add automated tests for provider parsing, malformed responses, duplicate sources, timeouts, cancellation, invalid URLs, unsupported media, and failure recovery.
- Keep provider integrations modular so one failing or discontinued add-on does not break catalog browsing or other providers.
