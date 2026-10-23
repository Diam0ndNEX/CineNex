# Tracking Integrations

## Trakt

CineNex supports Trakt device authorization and movie scrobbling. A user supplies the Client ID from their own Trakt API application, authorizes in Trakt's browser page, and can enable automatic scrobbling. OAuth tokens are stored in iOS Keychain and refreshed using the rotating refresh token. CineNex never asks for the user's Trakt password.

The current demo catalog does not contain verified external IDs and has no real episodic metadata. Movie scrobbling therefore sends the movie title and release year for Trakt matching; series scrobbling remains disabled until a catalog provider supplies season and episode identifiers. API errors are shown as status and do not interrupt playback.

Developer setup: create an API application at https://trakt.tv/oauth/applications and paste its Client ID into CineNex's Tracking tab.

## Letterboxd

Letterboxd publishes API documentation, but API access is request-only. Its current access page says personal/private projects are not being granted API access. CineNex therefore does not ask users for Letterboxd passwords, scrape the website, or pretend direct synchronization is active.

The planned compatible path is import/export using the user's official Letterboxd data export, with duplicate-safe film matching and a preview before any changes. Direct API sync can be added if Letterboxd grants the project access and provides credentials/licensing that permit the intended use.

## Local tracking

Playback progress and CineNex favorites continue to work without external accounts. Trakt sync is optional and can be disconnected independently. Local playback progress is not automatically converted into a watched diary entry because reaching a saved position does not prove a complete watch.
