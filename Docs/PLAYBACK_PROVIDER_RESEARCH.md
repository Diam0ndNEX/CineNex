# Playback provider integration research

## Stremio-compatible add-ons

CineNex now has a protocol client foundation in `StremioAddonClient.swift`. It fetches an add-on manifest, checks declared stream capabilities and media-ID prefixes, requests a movie or specific series episode, and decodes both direct stream entries and torrent descriptors.

The protocol uses `/manifest.json` and `/stream/{type}/{videoID}.json`. Series episode IDs are represented as `{seriesID}:{season}:{episode}` for the stream request. Manifest resource objects may narrow supported types and ID prefixes beyond the top-level declarations; the client enforces those restrictions.

### Current limitations

- The protocol client is now wired into Watch Hub's source search and playback coordinator through an explicit user action. The optional manifest list is locally persisted; there are still no bundled default add-ons.
- A real add-on still needs an appropriate media identifier. TMDB IDs and IMDb IDs are not interchangeable; CineNex needs an explicit external-ID lookup before querying add-ons that require IMDb IDs.
- A returned URL is only a candidate. CineNex must validate redirects, headers, content type, codec/format support, access requirements, and real playback before labelling a source playable.
- Torrent entries commonly contain an info hash and optional file index rather than a directly playable URL. They are retained as descriptors, not falsely treated as direct streams.
- The protocol allows both HTTP and HTTPS stream URLs in responses, but manifest and API requests are restricted to HTTPS. HTTP media candidates must be reviewed separately before use.
- No add-on is bundled by this change. Provider selection and licensing review are separate from protocol compatibility.

## Torrent playback feasibility

A native torrent path would need a maintained BitTorrent engine that builds for iOS, supports piece prioritization or sequential download for seeking, exposes readable media bytes or a local loopback HTTP stream, and can cancel and clean up reliably when playback ends. CineNex must test memory use, battery, network changes, seeking, subtitle selection, and app suspension on real hardware.

The existence of an iOS torrent downloader is not sufficient evidence that it supports playback-grade streaming. The engine also needs a compatible license, reproducible dependency builds, and an implementation that does not bypass DRM or provider access controls. Start with public-domain or otherwise authorized test torrents and do not ship a torrent source as production-ready until end-to-end playback is demonstrated.

## Validation sequence

1. Add protocol unit tests for manifests, resource capability restrictions, HTTP failures, direct stream entries, torrent descriptors, malformed URLs, and movie/episode path construction.
2. Add an explicit IMDb/external-ID resolver using the existing metadata integration where available.
3. Integrate the protocol client into the playback coordinator with provider-specific timeouts and result normalization.
4. Test a documented, authorized add-on with public-domain content end to end.
5. Separately prototype the torrent engine behind an interface and test authorized media before connecting it to source discovery.
6. Only after real-device validation, add curated no-setup defaults and keep any unavoidable user configuration optional.


## Current implementation status

The provider adapter is now connected to the Watch Hub through an explicit source-search action. Users can optionally store one HTTPS manifest URL per line; those URLs are saved locally using app preferences. Search resolves the selected TMDB item to an IMDb ID, queries the configured add-ons concurrently, and lists returned direct media URLs. Direct URLs with common native media extensions use AVPlayer; other returned URLs open in the embedded web player.

This is an advanced/manual fallback, not the desired zero-setup default. It is intentionally not preloaded with unverified community add-ons. The next no-setup step is to establish a maintained registry of providers whose source behavior, authorization, privacy practices, and availability can be reviewed. That registry must not silently install an arbitrary add-on supplied by a remote list.

## Torrent implementation decision

The first native engine candidate to investigate is libtorrent 2.x through an iOS-compatible XCFramework. Its streaming documentation distinguishes sequential downloading from time-critical piece scheduling; sequential mode alone is not the ideal playback scheduler. A small Swift-only torrent implementation was not selected because the available project evidence describes it as incomplete and lacking important performance optimizations.

A concrete reference implementation exists in [XITRIX/iTorrent_Framework](https://github.com/XITRIX/iTorrent_Framework): its README identifies libtorrent, Boost, and OpenSSL, and its build script archives device and simulator frameworks into an XCFramework. It is a native Xcode project with a libtorrent submodule rather than a drop-in Swift Package, so CineNex still needs a reproducible build and a license/dependency audit before adopting it. Apple requires separate platform slices in an XCFramework; simulator arm64 and device arm64 are not interchangeable. Before selecting libtorrent, verify its current iOS build recipe, package/license compatibility, supported architectures, and integration cost. Prototype a playback adapter with a local HTTP byte-range server or file-backed AVPlayer path, explicit piece prioritization, bounded disk cache, and deterministic cleanup. Do not add the binary dependency until a reproducible CI build and authorized public-domain end-to-end test pass.

### Candidate audit — 2026-10-24

- **`libtorrent_flutter`** demonstrates the desired technical shape: libtorrent, time-critical piece scheduling, and a loopback HTTP byte-range server. However, its published package is GPL-3.0 licensed ([package and license](https://pub.dev/packages/libtorrent_flutter)). CineNex must not adopt it unless the project deliberately accepts GPL-3.0 obligations; this integration does not make that licensing decision.
- **`warppipe/swift-torrent`** is a pure-Swift iOS 17+ package, but the repository currently has no recognized license metadata or LICENSE file despite the README's MIT label. Its current source also concatenates untrusted torrent path components in [TorrentInfo.swift](https://github.com/warppipe/swift-torrent/blob/main/Sources/SwiftTorrent/Torrent/TorrentInfo.swift), then appends those paths to the download root in [DiskIO.swift](https://github.com/warppipe/swift-torrent/blob/main/Sources/SwiftTorrent/Storage/DiskIO.swift). Its piece picker is rarest-first and does not expose playback-priority scheduling. Do not vendor or feed it untrusted torrent metadata as-is.
- **`XITRIX/iTorrent_Framework`** is a useful reference for an iOS libtorrent bridge, but the framework repository does not declare an explicit license and relies on a native Xcode build with a libtorrent submodule. Do not copy its bridge source or treat it as a redistributable dependency without an explicit license.
- **Official libtorrent 2.x** is the preferred technical direction because the upstream project publishes a BSD license ([official project and license](https://www.libtorrent.org/)). CineNex should own the small C/Objective-C++ bridge and build a reproducible XCFramework for device and simulator architectures, rather than inheriting a GPL bridge or an unlicensed wrapper.

### Required implementation gates

1. Pin the exact libtorrent, Boost, and OpenSSL revisions and build options; produce device and simulator slices in CI, and preserve every upstream license notice.
2. Expose a narrow Swift-safe API for magnet/torrent ingestion, metadata, file selection, progress, cancellation, piece deadlines, and bounded cache control. Do not expose raw native pointers to UI code.
3. Serve media only through a loopback-bound byte-range server with a per-session unguessable path token, correct `200`, `206`, and `416` responses, request cancellation, and strict byte-range limits.
4. Validate torrent names and path components before filesystem access, keep all writes inside a unique cache directory, cap concurrent downloads and cache size, and clean up on cancellation, dismissal, and app termination.
5. Add deterministic unit tests for metadata/path traversal, range parsing, priority windows, and cleanup. Add an end-to-end test using a licensed test asset distributed directly by its rights holder.
6. Connect torrent results to Watch Hub only after the engine builds reproducibly and the range server passes authorized playback tests. Until then, Stremio torrent descriptors remain non-playable metadata, not a source CineNex claims it can play.


### Native iOS reuse investigation — 2026-10-24

The fact that `libtorrent_flutter` lists iOS is valid evidence that its Flutter plugin can build into an iOS Flutter app. It does **not** make the Dart/Flutter package a drop-in dependency for CineNex's native SwiftUI target. Its CocoaPods integration downloads or builds the plugin's native libraries, while its public API and lifecycle are exposed through Flutter FFI. A native-only adoption would need a separately maintained Objective-C/Objective-C++ facade over the underlying libtorrent code and the streaming server, or a move to Flutter (not recommended just for this feature). The package's advertised `set_piece_deadline` and HTTP byte-range behavior make it a strong behavioral reference, but its GPL-3.0 license remains a deliberate distribution decision.

A better native reference surfaced in the investigation: [XITRIX/iTorrent](https://github.com/XITRIX/iTorrent) is a native iOS app under an MIT license and uses libtorrent, with sequential playback through VLC and a GCDWebServer dependency. It points to [XITRIX/LibTorrent-Swift](https://github.com/XITRIX/LibTorrent-Swift), an Objective-C++ wrapper around the official libtorrent submodule. This is closer to CineNex's architecture than the Flutter plugin. However, the wrapper repository currently has no declared license metadata or license file, so its code should not be copied or redistributed until the maintainer clarifies licensing. The app's MIT license applies to the app's licensed source, not automatically to every submodule or third-party library. The separate [iTorrent_Framework](https://github.com/XITRIX/iTorrent_Framework) also lacks explicit repository license metadata, so it is useful as a build/reference example rather than a dependency to vendor without permission.

The pure-Swift [warppipe/swift-torrent](https://github.com/warppipe/swift-torrent) does declare MIT in its README but has no GitHub-recognized license or LICENSE file. More importantly, its README describes a download pipeline and rarest-first piece selection, not a playback-oriented range server with seek-aware piece deadlines. It is not the best fit for CineNex's requirement to stream and seek without reinventing the scheduling layer.

**Updated recommendation:** first ask whether XITRIX's maintainer is willing to clarify the license of `LibTorrent-Swift` and whether its wrapper exposes the piece-priority and file-reading primitives CineNex needs. In parallel, keep the official libtorrent 2.x source as the fallback, building our own narrow native bridge if necessary. Keep `libtorrent_flutter` as the streaming-behavior reference and an option only if the project knowingly accepts GPL-3.0 and the native extraction cost is justified. No torrent engine is integrated by this investigation.


### XITRIX wrapper API audit — 2026-10-24

The public Objective-C headers confirm that `XITRIX/LibTorrent-Swift` already exposes a useful native surface:

- `Session` owns the libtorrent session, restores state, adds/removes `Downloadable` items, and reports torrent lifecycle updates through `SessionDelegate`.
- `TorrentHandle` exposes snapshots, pause/resume, file priorities, sequential download, and first/last-piece priority. `TorrentHandle.Snapshot` reports metadata, per-file entries, progress, transfer rates, and piece completion state.
- `FileEntry` exposes each file's index, relative path, size, downloaded byte count, and piece range.
- The wrapper's `make.sh` configures libtorrent with Xcode and an iOS 15 deployment target. This is evidence of an iOS-oriented native build recipe, not yet evidence that the current wrapper builds reproducibly with CineNex's Xcode/CI toolchain or that all required device/simulator slices are available.
- The inspected public API does **not** expose a playback-specific per-piece deadline API or a built-in HTTP byte-range server. Sequential and first/last-piece prioritization are available, but seek-aware streaming would still need additional native work or a separately audited range-serving layer. Do not assume sequential download alone gives reliable seeking.

**Integration decision:** keep this wrapper as the selected candidate, subject to a licensing gate. The wrapper repository has no visible license file or declared license metadata, and the iTorrent app's MIT license does not automatically grant rights to the wrapper or its submodules. Before adding the wrapper as a submodule, copying it, or shipping it in CineNex, obtain explicit reuse terms from the maintainer. After that, prototype the dependency in an isolated branch, verify the Xcode project and submodule revisions, and build both iPhone device and simulator targets in CI. Keep torrent playback disabled until range requests can wait for requested pieces safely, prioritize seek windows, enforce strict cache/path limits, and pass authorized-content end-to-end tests.
