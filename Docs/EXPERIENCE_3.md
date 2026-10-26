# CineNex 3: discovery, readiness and interface rebuild

## What changes

- Source search skips redundant IMDb resolution, shares missing-ID lookup work, uses cancellable wall-clock HTTP deadlines, caches manifests/IDs privately and recent source responses in memory, and displays each add-on's reply independently. Refresh bypasses the response cache. Provider progress measures completed provider responses; it is not a fabricated movie-download percentage.
- Find a ready release replaces Play top release. It checks native startup readiness, stops a failed preparation, then tries the next distinct torrent/file or direct link. Attempts are bounded to 1–5 (default 3), duplicate torrents across providers are not retried, and failed rows are marked. Manual selection remains available. Direct checks use bounded HEAD responses and media MIME types; servers that reject HEAD can still be tried manually. A successful check does not prove decoder compatibility or the availability of every later piece.
- Torrent preparation waits for verified opening/container-index pieces. It reports actual rate, downloaded bytes, peers, seeds and required/available pieces. Metadata/startup waits have 20-second budgets checked around native calls; native synchronous calls cannot be preempted. Player buffer progress comes from VLC. The opening target, VLC cache and control timeout are configurable.
- Native prefetch is smaller and bounded by bytes. No energy, bandwidth or startup improvement is claimed from a device benchmark yet.
- Home, Discover, Search, Library, anime browsing and title layouts are rebuilt around an artwork spotlight, a compact solid navigation dock, clearer controls and a growing home grid. Wide player gradients/timeline blur are removed. Small floating controls retain native glass where supported.
- Discover and source lists have real metadata/name filters, grid/list layouts, reset/active states and persisted layout/playback preferences. Unknown metadata stays unknown. No age classification or working-source guarantee is invented.

## Validation required before release

Run repository Python checks and iOS simulator XCTest. Device review must cover a true cold launch, a stalled provider alongside a fast provider, closing/reopening source search, rapid episode changes, cancellation/retry during native startup, Smart selection falling through a dead release, seeking during download, long playback and background/foreground transitions.

Review small and large iPhones with Dynamic Type and Reduce Transparency, every dock destination, Cinema/Anime switching, Discover pagination under restrictive filters, artwork/cache maintenance and persisted settings. Measure latency, responsiveness and energy on the physical device before calling those improvements verified. The Linux editing environment cannot render SwiftUI or exercise the native player.

Account registration status remains in ACCOUNT_LOGIN.md; this redesign does not enable unregistered anime account clients.
