# CineNex architecture

CineNex is an iPhone media catalog and playback client. Catalog metadata and playable sources remain separate. The deployment target is iOS18; native glass is gated to newer systems with accessible fallbacks.

## Navigation and catalog

`ContentView` owns Home, Discover, Search, Library and Settings navigation, Cinema/Anime selection, title routes and paginated catalog state. A solid compact dock replaces the native blurred tab strip. `CatalogPresentation` contains artwork, collection and discovery components; `CatalogFilterState` applies only metadata actually supplied by a provider. `AppearanceSettingsView` persists working layout, shelf, density, motion and navigation choices.

TMDB and Cinemeta supply movie/series metadata; AniList supplies anime metadata. `CatalogCacheStore` restores catalog snapshots, while `ArtworkDiskCache` coalesces artwork requests and bounds memory/disk storage. Library snapshots, favorites and movie/anime playback progress remain local and retain their existing storage keys.

## Source discovery

`WatchHubView` owns cancellable, generation-guarded source search and independent provider-result updates. `AutomaticExternalIDResolver` accepts existing IMDb IDs immediately and coalesces missing-ID resolution through `SourceIdentifierCache`. `SourceDiscoveryNetworking` applies cancellable wall-clock HTTP deadlines. `SourceDiscoveryCache` keeps bounded private metadata on disk and short-lived stream responses only in memory; explicit refresh clears stream responses.

`SceneBoxTorrentSearch` staggers Torrentio fallbacks. `StremioAddonPlaybackProvider` bounds add-on concurrency and emits each completed client independently. `StremioAddonClient` validates manifests, stream requests, responses and HTTPS redirects. Discovery starts no torrent transfers.

## Selection and playback

`SmartPlaybackSelection` ranks distinct release/file candidates, applies preferences, checks readiness sequentially and bounds attempts. Direct-link HEAD checks establish a media response only; torrent preparation waits for verified opening and index pieces. These checks do not guarantee decoder compatibility or the availability of all later movie data. Manual source selection remains available.

`XITRIXTorrentPlaybackEngine` owns the patched libtorrent bridge, selected-file priority, bounded byte lookahead and piece deadlines. `TorrentPlaybackProvider` serves verified local bytes through a loopback HTTP server. `TorrentPlaybackSessionRegistry` owns prepared providers until playback closes or preparation is discarded. `TorrentCacheMaintenance` protects active roots and bounds retained inactive transfers.

`TorrentPlaybackMonitor` publishes real rates, peers, seeds and required/available buffer pieces, guarded by attempt ownership. `TorrentBufferingStatusView` displays those values without inventing a download percentage. `SceneBoxStreamPlaybackView` provides VLC playback, floating controls, buffer state, subtitles and playback preferences. `PlayerView` retains offline/direct Apple/VLC playback. Native synchronous status and shutdown calls cannot be interrupted mid-call; surrounding time budgets are checked immediately after they return.

## Accounts and validation

Trakt uses device authorization with a bundled registered public Client ID, Keychain storage, refresh and optional movie scrobbling. Optional native PKCE remains disabled without a correctly associated callback. AniList/MAL browser login code and read-only profile/list adapters require their registered public IDs; see `Docs/ACCOUNT_LOGIN.md` for current setup status. Anime lists are not full two-way local-progress sync.

Build settings and package pins live in `project.yml`. `Scripts/ci_build_plan.py` and `.github/workflows/ios-build.yml` are authoritative for change-aware validation; preserve them. Run `python3 -m unittest discover -s Scripts/tests -v`, then the selected Xcode simulator checks. Fast IPA packaging is separate from full regression validation. `Docs/EXPERIENCE_3.md` lists the physical-device and visual checks that Linux cannot execute.
