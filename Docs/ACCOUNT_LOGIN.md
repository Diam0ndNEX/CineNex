# CineNex account login build configuration

Consumer screens no longer request a Trakt API Client ID. They use the system authentication browser. AniList and MyAnimeList account cards authenticate and read profiles/anime lists; these lists are read-only and are not silently merged into local episode progress. MAL currently loads the first 100 entries. These capabilities are not advertised as full two-way sync.

## Required developer registration

- `CINENEX_ANILIST_CLIENT_ID`: AniList OAuth app client ID. Register exactly `cinenex://oauth/aniList` as its redirect.
- `CINENEX_MAL_CLIENT_ID`: MyAnimeList native OAuth app client ID. Register exactly `cinenex://oauth/myAnimeList`. Native PKCE sends a fresh 256-bit random verifier/challenge with the service's plain method and verifies state and callback identity.
- `CINENEX_TRAKT_CLIENT_ID`: CineNex's Trakt OAuth app public client ID.
- `CINENEX_TRAKT_REDIRECT_URI`: optional, only for the separate direct PKCE browser method; exact registered HTTPS callback on a domain associated with the app, for example an owned `/callback/trakt` path. This cannot be a `cinenex://` callback or a made-up domain. The domain must serve a correct Apple app-site-association file and match the app's signed Associated Domains entitlement and signing team/app ID. ASWebAuthenticationSession uses Apple's HTTPS callback matcher.

Supply these public values as Xcode build settings in validation and IPA builds. They map into Info.plist; the cinenex scheme is registered for AniList/MAL. Missing configuration shows an explicit unavailable-build message rather than asking consumers to enter API keys. Registered client IDs are not configured by this source change; they must be verified before login can be advertised as enabled. Consumer Trakt sign-in uses device authorization and does not require an HTTPS callback or associated-domain entitlement. Re-signing the IPA with a different team may invalidate its associated-domain relationship.

## Trakt uses direct native PKCE; no token broker or client secret

Consumer sign-in uses Trakt's documented device flow: request a code from `auth.trakt.tv/oauth/device/code`, display the code and validated Trakt activation link, and poll `auth.trakt.tv/oauth/device/token` at the server interval. No client secret, callback server, Universal Link, Apple team ID or domain entitlement is needed for this flow. The user opens Trakt, enters the short one-time code, approves, and returns to CineNex. No API credential entry is shown. This avoids relying on entitlements preserved by KSign, Flarestore, AltStore, SideStore or other IPA signers; those combinations still need device testing.

The single owned sign-in task rejects duplicate starts, has an explicit Cancel, stops when leaving Tracking or disconnecting, and uses a generation check so an old response cannot reconnect after cancellation. Polling handles documented empty HTTP400/pending, HTTP429/increased interval, denial, expiry, invalid/already-used codes, and a monotonic deadline. Verification addresses must be HTTPS Trakt activation URLs. Credential-bearing requests refuse redirects and have bounded timeouts. No code or token is logged.

Trakt's current October 2026 official documentation deprecates client secrets for user sign-in. The optional `signInWithBrowser` method remains available for builds deliberately configured with a correctly associated HTTPS domain. CineNex generates a fresh verifier, sends its SHA-256/base64url challenge with `code_challenge_method=S256`, validates the returned state and redirect, then exchanges the code and original verifier directly at `https://auth.trakt.tv/oauth/token`. It never sends a client secret. OAuth authorization, token exchange, refresh and legacy device routes use `auth.trakt.tv`; data API requests remain on `api.trakt.tv`.

Concurrent API requests share one refresh task because current Trakt refresh tokens are single-use. The new access/refresh pair is stored before completion, and an authentication-generation guard prevents a refresh completing after disconnect from resurrecting the account. An `invalid_grant` refresh clears the invalid local session and asks for a fresh browser sign-in. Legacy saved Trakt tokens remain readable; expired pre-migration refresh tokens may require one reauthorization.

No broker implementation, deployment or secret configuration is required. HTTPS callback hosting/association is distinct from running a token-exchange server.

## Storage and validation

Tokens use device-only, unlocked Keychain storage. Account API sessions are ephemeral and credential-bearing requests refuse redirects. Sign-out removes local credentials/list state, not the provider account or remote list. Callback validation rejects mismatched state, host/scheme/path/port and duplicate parameters. OAuth callback URLs/tokens are never sent to playback diagnostics.

Primary references:
- https://developer.trakt.tv/docs/authentication-oauth
- https://developer.trakt.tv/docs/pkce
- https://github.com/trakt/trakt-api/blob/master/projects/api/src/contracts/oauth/index.ts
- https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/callback/https(host:path:)
- https://github.com/AniList/docs/blob/master/docs/guide/auth/implicit.md
- https://myanimelist.net/apiconfig/references/authorization
- https://myanimelist.net/apiconfig/references/api/v2

The MyAnimeList documentation endpoint was unavailable during editing; native PKCE/token/profile/list behavior still needs a registered-client replay. Local Python checks, YAML parsing and whitespace pass. Swift/iOS compilation, provider login, refresh and callback/domain acceptance, large-account lists and profile/list error recovery remain unverified until fresh CI and device testing. Unit tests cover the RFC7636 S256 vector, fixed Trakt auth host, HTTPS redirect policy, secret-free exchange payloads, callback-state rejection and secure random verifier format.


## Build wiring and owned HTTPS callback

Public IDs live in Config/AccountApplications.json or repository Actions variables with the same CINENEX_* names. Both validation and Fast IPA workflows run Scripts/configure_account_logins.py, then use Generated/OAuth.xcconfig for every app build/test. No secret is put in the app. The script validates IDs and HTTPS redirects, generates the associated-domain entitlement, and can produce an apple-app-site-association template when CINENEX_APP_TEAM_ID is provided. Publish that file at /.well-known/apple-app-site-association on the registered callback host, without redirects, and sign CineNex with the matching team and associated-domain entitlement. The callback website needs no token-exchange server.

Provider app registration and acceptance of each provider's developer terms remain account-owner actions. Trakt's GitHub connection is verified as @Diam0ndNEX. Registration is prepared as a Production app so sign-in is not restricted to explicitly added testers. The Production form still requires an HTTPS redirect even for device-only usage. Registration remains blocked until a dedicated callback endpoint exists; automatic review rejected using the GitHub repository page as an unused redirect. No substitute URL is registered or bundled. A future authorization-code flow must register and deploy a real associated HTTPS callback first. The final Create App step accepts Trakt API requirements and is awaiting the owner's approval. No registered Client ID exists yet. Signing/associated-domain capability must survive external IPA re-signing. A generated template does not prove that the domain is deployed or associated with a signed app.

Device authorization regression coverage: empty pending responses, HTTP429 slowdown, denial/expiry/invalid/used outcomes, strict activation-host validation, client-ID-only configuration with no Associated Domains entitlement, and cancellation while waiting for approval. Swift tests are committed for CI; Linux checks do not execute them.
