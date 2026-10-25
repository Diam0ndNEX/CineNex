# Tracking Integrations

## Stremio-compatible playback add-ons

CineNex queries configured Stremio-compatible add-on manifest URLs for direct media streams and torrent descriptors. The Watch Hub defaults to Torrentio with the configured `qualityfilter=unknown,other,cam,scr` exclusions and the MediaFusion Midnight instance. Add-on URLs are stored locally in iOS app preferences and can be edited in the Watch Hub; enter one HTTPS manifest URL per line. To use a personalized MediaFusion configuration, paste its generated manifest URL into the Watch Hub on your device instead of committing that unique URL to the public repository.

For custom Torrentio filters or debrid settings, open [Torrentio Configure](https://torrentio.strem.fun/configure), configure the options you want, and use the configured add-on's manifest URL in CineNex instead of the default manifest. For MediaFusion Direct P2P or other personalized settings, use the configured manifest URL provided by the instance you trust and save it locally in CineNex. The bundled Midnight URL is the generic instance manifest; users can replace it with their configured URL. Never paste credentials into a URL unless you understand that the full URL may contain private configuration.

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
