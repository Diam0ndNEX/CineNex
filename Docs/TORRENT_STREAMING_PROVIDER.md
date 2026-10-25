# Native Torrent Streaming Provider

## Architecture

CineNex's native torrent provider is split across four boundaries:

- `StremioTorrentDescriptor` validates the selected Stremio torrent result and carries the magnet URI, info hash, and optional file index.
- `XITRIXTorrentPlaybackEngine` owns the libtorrent session, acquires metadata, selects a playable file, configures download priorities, and implements piece-aware availability scheduling.
- `TorrentLoopbackHTTPServer` serves AVPlayer-compatible HTTP responses from IPv4 loopback only. Each URL carries a random bearer token and an opaque resource identifier.
- `TorrentDiskByteReader` performs bounded random-access reads from the selected on-disk file only after the requested byte range is reported available.

`TorrentPieceRangePlanner` maps file-relative byte ranges to half-open global torrent-piece ranges, accounting for pieces shared across file boundaries and rejecting invalid or overflowing ranges. `TorrentPieceRangeAvailability` coordinates prioritization and waits for those pieces before allowing reads.

The HTTP server supports GET, HEAD, and single byte ranges, limits each read to 128 KiB, caps request headers at 16 KiB, and closes each connection after one response. It rejects duplicate headers, request bodies, transfer encodings, control characters, malformed or ambiguous request targets, and invalid bearer tokens. Registered resource URLs expire after two hours, and each server limits its active resource registry to 64 entries.

## XITRIX engine behavior

Before the first playback range is requested, the engine assigns a high priority to the selected file's first 2 MiB and a lower background priority to its last 16 MiB. This carries over the useful startup/tail priming strategy from the SceneBox architecture without coupling CineNex to SceneBox types. The moving playback window can temporarily promote any piece to the highest priority; when that window moves away, pinned head/tail pieces return to their startup priority instead of being accidentally demoted to the lowest background level. The pure `TorrentStartupPiecePriorityPlan` planner validates torrent-global offsets and piece bounds and is covered by unit tests.

The current engine adapter:

1. Creates a per-info-hash cache location and starts a libtorrent session from the selected magnet URI.
2. Waits for torrent metadata with cancellation checks and a bounded timeout.
3. Uses the explicitly selected file index when supplied; otherwise it selects the largest supported playable file.
4. Confines resolved file paths to the torrent's download root and rejects traversal or symlink escapes.
5. Sets all files to do-not-download, promotes the selected file, enables sequential download and first/last-piece prioritization, and raises priority for exact global piece ranges needed by playback reads.
6. Waits for the requested pieces to become available before reading, checks cancellation, validates byte ranges and file sizes, and rejects short reads rather than returning fabricated or incomplete data.
7. Exposes the prepared file as a normal CineNex playback source and stops the reader, torrent handle, session, and per-session download files when the playback session ends.

The currently recognized file extensions are MP4, M4V, MOV, MP3, M4A, AAC, and WAV. This is an extension-based allowlist, not a full media-codec probe; files in other containers are not currently offered by this adapter.

## Validation status

The merged GitHub Actions workflow passed for the XITRIX wrapper builds for iOS and simulator, simulator app build, XCTest suite, unsigned device build, and unsigned IPA packaging. Tests cover HTTP range and HEAD behavior, invalid bearer tokens and malformed requests, disk-reader bounds and short reads, cancellation, piece-range mapping, file path confinement, descriptor validation, and the wrapper patcher.

A green simulator workflow does not prove real-world torrent playback on a physical iPhone. Before claiming end-to-end playback success, test a known legal/public-domain torrent on-device, including metadata acquisition, startup buffering, seeking, cancellation, and cleanup. The XITRIX wrapper repository currently has no GitHub license declaration; resolve its redistribution terms before publicly distributing an app that bundles the dependency. The generated CI IPA is unsigned and must be signed before installation.


## SceneBox-inspired playback deadlines

CineNex assigns libtorrent deadlines to the exact piece range required by each byte-range read. Pieces are scheduled in ascending playback order at 80 ms intervals, capped at 60 seconds for unusually large ranges. When a later read moves the playback window, deadlines for pieces no longer in the requested range are cleared. This supplements piece priorities: priorities guide general selection, while deadlines make the currently requested bytes urgent. Deadlines are relative to the moment they are scheduled and are best-effort targets; a slow or unavailable swarm can still miss them. The pure `TorrentPieceDeadlinePlan` validates ranges and delay bounds and is covered by unit tests. The native bridge is applied by the CI patcher and is built for both device and simulator targets before app tests run.

Validation-only branch marker: the playback-deadline Swift selector fix is being checked by the repository's iOS CI workflow.
