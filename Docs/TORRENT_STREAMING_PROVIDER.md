# Native Torrent Streaming Provider

## Architecture

CineNex's native torrent provider is split into three boundaries:

- `TorrentPlaybackProvider` adapts a prepared torrent file into a normal `PlaybackSource`.
- `TorrentLoopbackHTTPServer` serves AVPlayer-compatible HTTP responses from loopback only. Each URL carries a random bearer token and an opaque resource identifier.
- `TorrentDiskByteReader` performs bounded random-access reads from the selected on-disk file only after a `TorrentRangeAvailability` implementation confirms that the requested bytes are ready.
- `TorrentPieceRangePlanner` maps a file-relative byte range to the half-open global torrent-piece range, accounting for pieces shared across file boundaries and rejecting overflow.
- `TorrentPlaybackEngine` and `TorrentRangeAvailability` are the integration boundary for the selected libtorrent engine.

The server supports GET, HEAD, single byte ranges, bounded 128 KiB reads, and closes each connection after one response. Request headers are capped at 16 KiB; duplicate headers, request bodies, transfer encodings, control characters, and ambiguous request targets are rejected. Registered resource URLs expire after two hours, and each server limits its active resource registry to 64 entries.

## Engine adapter requirements

A concrete libtorrent adapter must:

1. Add a magnet link or torrent descriptor and wait for metadata.
2. Select the intended playable file using normalized torrent-relative paths, never HTTP-provided filesystem paths.
3. Report the exact file size and a suitable MIME type.
4. Implement `TorrentByteReader.read(offset:length:)` so it validates bounds and returns exactly the requested number of bytes only after those bytes are available, or throws when the torrent fails or the operation is cancelled.
5. Use `TorrentPieceRangePlanner` to map requested file bytes to global piece indices, then prioritize pieces needed for startup and seeks rather than relying only on sequential downloading.
6. Stop torrent sessions and release resources when the playback session is explicitly ended.

The disk reader validates offsets without integer overflow, checks the file size when opened, waits for the exact requested range, checks cancellation before and after the wait, and rejects short reads. The HTTP server deliberately does not fake availability by returning zero-filled or partial data. A reader returning fewer bytes than requested terminates that connection.

## Integration status and licensing

The server, disk reader, and provider boundary are implemented independently of any torrent library. Tests cover loopback HTTP range/HEAD behavior, invalid bearer tokens, exact disk reads, bounds checking, cancellation while waiting, and short-read rejection. This does not yet include a concrete libtorrent adapter, metadata acquisition, piece prioritization, or verified end-to-end torrent playback. The XITRIX wrapper's redistribution terms and reproducible simulator/device build still need resolution before bundling that wrapper into CineNex. No wrapper source is copied here.
