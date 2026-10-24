# Playback provider integration research

## Stremio-compatible add-ons

CineNex now has a protocol client foundation in `StremioAddonClient.swift`. It fetches an add-on manifest, checks declared stream capabilities and media-ID prefixes, requests a movie or specific series episode, and decodes both direct stream entries and torrent descriptors.

The protocol uses `/manifest.json` and `/stream/{type}/{videoID}.json`. Series episode IDs are represented as `{seriesID}:{season}:{episode}` for the stream request. Manifest resource objects may narrow supported types and ID prefixes beyond the top-level declarations; the client enforces those restrictions.

### Current limitations

- The protocol client is not yet wired into Watch Hub's source search or the playback coordinator.
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

Before selecting libtorrent, verify its current iOS build recipe, package/license compatibility, supported architectures, and integration cost. Prototype a playback adapter with a local HTTP byte-range server or file-backed AVPlayer path, explicit piece prioritization, bounded disk cache, and deterministic cleanup. Do not add the binary dependency until a reproducible CI build and authorized public-domain end-to-end test pass.
