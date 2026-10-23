# Tracking Integrations

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
