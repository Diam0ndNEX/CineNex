# CineNex account login build configuration

Consumer screens no longer request a Trakt API Client ID. They use system browser sign-in. AniList and MyAnimeList account cards authenticate and read profiles/anime lists; these lists are read-only and are not silently merged into local episode progress. MAL currently loads the first 100 list entries. These capabilities are not advertised as full two-way sync.

## Required developer registration (not configured in this repository)

- `CINENEX_ANILIST_CLIENT_ID`: AniList OAuth application client ID. Register exactly `cinenex://oauth/aniList` as its redirect.
- `CINENEX_MAL_CLIENT_ID`: MyAnimeList native OAuth application client ID. Register exactly `cinenex://oauth/myAnimeList` as its redirect. Native PKCE sends a fresh 256-bit random verifier/challenge with the service's plain method, and verifies state and callback identity.
- `CINENEX_TRAKT_CLIENT_ID`: CineNex's Trakt OAuth app ID, registered redirect `cinenex://oauth/trakt`.
- `CINENEX_TRAKT_TOKEN_BROKER_URL`: developer-controlled HTTPS endpoint that exchanges Trakt authorization codes and refresh tokens using the registered application's server-side secret. No client secret is embedded in CineNex. The repository does not deploy this endpoint.

Supply these values as Xcode build settings to both validation and IPA workflows when registration is complete. They map into Info.plist; the cinenex callback scheme is registered by XcodeGen. Missing configuration shows an explicit unavailable-build message and disabled login action. Do not substitute another application's IDs or secrets from public source.

The Trakt exchange endpoint accepts JSON `{grant_type: authorization_code, code, redirect_uri}` or `{grant_type: refresh_token, refresh_token}`. It must pin its own registered client/redirect, protect abuse, avoid logging credentials, and return standard Trakt JSON fields `access_token`, `refresh_token`, `expires_in`, `created_at`. Token exchange endpoint implementation, hosting and provider registration are prerequisites, not completed features. Existing saved Trakt tokens/client configuration remain readable for migration; legacy device-flow methods remain but are no longer the consumer sign-in action.

## Storage and validation

Tokens use device-only, unlocked Keychain storage. Sign-out removes local credentials/list state, not the provider account or remote list. Credential-bearing API calls refuse redirects. Callback validation rejects mismatched state, host/scheme/path/port and duplicate parameters. OAuth callback URLs/tokens are never sent to playback diagnostics.

AniList official docs support native-client implicit login at https://github.com/AniList/docs/blob/master/docs/guide/auth/implicit.md. Trakt official OAuth requirements are at https://trakt.docs.apiary.io/. MyAnimeList official authorization/API documentation is at https://myanimelist.net/apiconfig/references/authorization and https://myanimelist.net/apiconfig/references/api/v2; retrieval was unavailable in this editing environment. Its native PKCE/token/profile/list implementation requires verification against registered credentials.

Local Python checks and whitespace pass. Swift/iOS compilation, end-to-end provider login, token refresh, provider callback acceptance, large-account list behavior and profile/list error recovery remain unverified. Do not call these account integrations enabled until registered clients are configured and device sign-in succeeds.
