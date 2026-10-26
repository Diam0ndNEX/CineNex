# Tracking Integrations

## Stremio-compatible playback add-ons

CineNex queries configured Stremio-compatible add-on manifest URLs for direct media streams and torrent descriptors. The Watch Hub defaults to Torrentio with the configured `qualityfilter=unknown,other,cam,scr` exclusions and the MediaFusion Midnight instance. Add-on URLs are stored in the iOS Keychain with device-only accessibility and can be edited in the Watch Hub; enter one HTTPS manifest URL per line. Existing URLs stored in UserDefaults are migrated to the Keychain when possible. To use a personalized MediaFusion configuration, paste its generated manifest URL into the Watch Hub on your device; CineNex does not ship that unique URL in the public repository. The URL editor is marked privacy-sensitive to reduce exposure in system snapshots.

For custom Torrentio filters or debrid settings, open [Torrentio Configure](https://torrentio.strem.fun/configure), configure the options you want, and use the configured add-on's manifest URL in CineNex instead of the default manifest. For MediaFusion Direct P2P or other personalized settings, use the configured manifest URL provided by the instance you trust and save it locally in CineNex. The bundled Midnight URL is the generic instance manifest; users can replace it with their configured URL. Personalized configuration URLs remain in local app preferences and should not be committed to the public repository. Never paste credentials into a URL unless you understand that the full URL may contain private configuration.

CineNex resolves TMDB catalog entries to IMDb identifiers before querying add-ons that use IMDb IDs. A manifest must advertise support for the requested movie or series stream resource. Returned direct URLs are candidates, not guarantees: providers may be offline, require authentication, return unsupported formats, or reject playback in iOS. Torrent descriptors are distinct from direct URLs and require the native torrent engine to prepare the selected media file.

Only configure add-ons you trust. Add-ons receive the media identifier for the title or episode being searched, and their operator may observe requests. CineNex does not bypass DRM, authentication, or provider access controls.

## Trakt

CineNex supports Trakt device authorization and movie scrobbling. A user supplies the Client ID from their own Trakt API application, authorizes in Trakt's browser page, and can enable automatic scrobbling. OAuth tokens are stored in iOS Keychain and refreshed using the rotating refresh token. CineNex never asks for the user's Trakt password.

The current demo catalog does not contain verified external IDs and has no real episodic metadata. Movie scrobbling sends the movie title and release year for Trakt matching; series scrobbling remains disabled until a catalog provider supplies season and episode identifiers. API errors are shown as status and do not interrupt playback.

Developer setup: create an API application at https://trakt.tv/oauth/applications and paste its Client ID into CineNex's Tracking tab.

## Letterboxd

Letterboxd publishes API documentation, but API access is request-only. Its current access page says personal/private projects are not being granted API access. CineNex therefore does not ask users for Letterboxd passwords, scrape the website, or pretend direct account synchronization is active.

The Tracking tab supports importing individual CSV files from the user's official Letterboxd export, including diary, watched, ratings, and watchlist files. Import is local, preserves film titles, years, ratings, dates, rewatch flags, tags, and reviews when those columns exist, and merges duplicate rows by a stable record key. The app can export its imported diary records as a Letterboxd-shaped `diary.csv` file. This is a file-based bridge, not live account sync; it does not write directly to a Letterboxd account.

To use it, export data from Letterboxd, extract the ZIP, and import the relevant CSV files in CineNex's Tracking tab. Export the diary CSV from CineNex when you want to take that diary data back to a service that accepts Letterboxd CSV imports.

## Local tracking

Playback progress and CineNex favorites continue to work without external accounts. Trakt sync is optional and can be disconnected independently. Letterboxd CSV data is stored locally on the device. Local playback progress is not automatically converted into a watched diary entry because reaching a saved position does not prove a complete watch.

Trakt scrobbling includes a TMDB identifier only when the selected movie was returned by TMDB and has a positive numeric TMDB ID. Local/demo entries continue to use title and year matching; CineNex does not guess external identifiers.

## Embedded playback cleaner

CineNex's embedded WebKit player includes an on-device Playback Cleaner. When enabled, it compiles a small native WebKit content-blocking rule set for selected third-party advertising domains, rejects top-level navigation to those domains, and refuses to create pop-up web views. It does not inspect or rewrite video streams, remove ads mixed into video, inject page scripts, or promise to eliminate every ad. Filtering can be disabled globally or for an individual provider when a player stops working. Only HTTPS navigation is allowed, and the filter is deliberately conservative to reduce compatibility risk.

The initial domain list is bundled with the app; no browsing history or URLs are uploaded to a filtering service. Domain coverage is intentionally limited and should be expanded only with evidence that the additional rules do not break supported players.

## SceneBox playback port

The Watch Hub VLC player ports SceneBox's `ChromeVisibility`, `PlaybackFormatting.trackLabel`, and the network-cache, stall-monitoring, and progress concepts from `PlaybackScreen` (source: `Diam0ndNEX/scenebox`, under `WatchBox/Features/Player`). The controls hide after four seconds of active playback, remain visible while paused or buffering, and defer hiding while settings or seeking are in use. The video surface toggles the controls.

VLC uses an eight-second cache for local torrent HTTP streams and a 1.5-second cache with HTTP reconnect for remote streams. Frozen playback shows a buffering indicator after three half-second samples. Retry ends the previous lock-screen controller before registering new commands and resets subtitle discovery.

Movie progress is saved every five seconds and on close using CineNex's existing local progress store; resume waits for a seekable stream with a known duration. Series playback deliberately does not store episode positions under the series-level movie-progress key. Episode-aware resume and next-episode autoplay need a separate episode progress contract before being ported. These changes require simulator CI and real-device playback verification; static inspection is not evidence of working provider playback.

## Native startup diagnostics v2

Repeated attempts stopping at `Creating libtorrent session` narrow the failure to the native initializer. The pinned XITRIX settings initializer leaves interface NSString values unset; settings conversion passed their null UTF-8 pointers to libtorrent's `std::string` parameter. CineNex now supplies explicit outgoing/listening interfaces and patches every settings string conversion through a null-safe helper. Native constructor exceptions return a recoverable initialization failure; this cannot recover from OS termination or arbitrary memory faults.

Both build workflows apply `Scripts/patch_xitrix_session_startup.py` before compilation, and its hash invalidates old native caches. The native initializer appends bounded JSON-lines checkpoints, synchronously flushed at each step, covering settings conversion, session construction, persistence restoration and the alerts thread. Records include attempt ID, uptime, thread and resident memory. Swift diagnostics add attempt-relative timing, errors, metadata peer/rate snapshots, selected-file size/type and piece wait ranges. No source URL, manifest configuration path, movie title, credentials or magnet hash is intentionally recorded; URL-shaped values in error details are redacted. The report is local and shared only through the user's Share action.

Provider diagnostics distinguish manifest and stream requests, HTTP status/bytes/timing, parsed hash/direct counts and final displayed counts per provider. Legacy generic ElfHosted-only configurations also query Midnight; custom configured MediaFusion paths are preserved. App version/build are included so a report identifies its installed artifact.
