# CineNex 2 experience

This redesign builds on the playback and responsiveness fixes in PR 121. Existing catalogs, saved titles, playback history, provider configuration and account connections keep their storage identities.

## Product changes

- Home: explicit Cinema/Anime switch, six discovery lanes, rotating curated picks and a Surprise Me action using actual catalog items.
- Search: persistent recent submitted searches with replay and clear actions; existing remote catalog search, media filters and paging preserved.
- Library: status totals, media-kind filtering and sorting, progress-aware playback and existing removal actions.
- Title details: editorial poster header, sharing, cast panels, season cards, existing metadata and episode playback.
- Sources: provider and resolution filters, release ordering, expandable release metadata, provider statuses and explicit provider configuration save/refresh; native playback path unchanged.
- Anime and offline: split poster presentation, expandable synopsis, episode tracking actions and clear external-provider destinations; download storage dashboard, status counters and bulk transfer management.
- Studio: three canvases, six accents, compact/comfortable poster density, optional ratings and reduced decorative motion.
- Control room: movie-resume preference, starting playback speed, skip intervals, subtitle language and adjustable torrent transfer ceilings. These apply when opening the next relevant player/session.
- VLC player: sleep timer (15/30/60 minutes), configurable skipping, remaining-time display, accent transport controls and clearer catalog/episode identity. System Reduce Motion is respected in control transitions.

Transfer ceilings are bytes per second. Balanced caps downloads at 12 MiB/s and uploads at 256 KiB/s; Economy uses 4 MiB/s and the same upload ceiling; Unlimited is explicitly unbounded. A ceiling is not a battery-life guarantee and may cause buffering on unusually high-bitrate releases.

## Validation before release

The Linux editing environment cannot execute SwiftUI. Existing Python CI/patcher checks and whitespace checks are run locally; iOS build/unit tests are required on GitHub. New unit coverage checks persisted playback preference fallbacks and transfer ceilings, alongside source-policy tests.

Device acceptance: visit every tab; switch Cinema/Anime on Home and Search; change every Studio preference; open a title from a lane, search and Library; play an episode from its season; filter/sort sources; cancel preparation; verify both Torrentio and MediaFusion playback; seek with each skip interval; enable/cancel a sleep timer; confirm saved titles and accounts survive restart; check large Dynamic Type and Reduce Motion. Inspect warmth and transfers under the same release/workload before comparing efficiency.

Native visual QA and measured energy improvement remain unverified until device replay. This work does not replace the torrent wrapper or introduce background animation loops.


## Completion pass before merging

The original redesign commit passed iOS CI. Review still found that Home was constrained to one initial catalog response, and the season episode screen retained its older list. Follow-up work adds manual paginated movie/TV discovery for configured TMDB connections (documented discover endpoints), duplicate suppression, first-page-only caching, explicit refresh cancellation and stale-response guards. Token-free Cinemeta discovery stays unchanged; collection screens show the loaded catalog snapshot until reopened. Search re-entry and rapid anime query replacement are also handled.

The episode picker now uses real episode/season metadata in the new layout. No fabricated viewing completion or transfer percentage is shown. Follow-up Swift validation and device layout checks remain required; the PR stays unmerged.


## Source responsiveness, glass, browsing and account follow-up

Source discovery now has an explicit cancellable task, immediate Close/Cancel state invalidation, off-main result mapping and cached off-main filtered releases. Parsed descriptor identities and metadata are reused. Add-on requests are bounded to four concurrent clients and their statuses are counted per client. MediaFusion size/peer data is retained from all returned text/structured fields; unavailable metadata stays unknown.

Search now contains query/results/history. Browse carries the live movie/series catalog with media-kind, genre and release-year filters and provider/popularity, newest, rating and title ordering. Home/Browse/search pagination uses one automatic request per footer visibility entry, retains error Retry, and avoids an auto-fetch loop when filtered results do not move the footer.

Liquid Glass uses native iOS26 controls, grouped sampling and a narrow player timeline with separate transport circles. Older iOS and Reduce Transparency have fallbacks. Solid cards remain appropriate for readable content.

Artwork has hashed URL keys, request coalescing, a 256 MiB disk budget, 7-day expiry and memory reuse. Clear cancels pending downloads and invalidates their write generations. Corrupt decoded entries are removed. Partial torrent bytes can be retained under a 2 GiB inactive-cache budget and 7-day expiry; active roots are reference-count protected. Native metadata removal means these bytes may require metadata fetching and hash rechecking next time. This is not guaranteed instant fast-resume or a complete offline copy. iOS may purge caches. Movie playback position and saved catalog snapshots continue using their existing stores.

Account code is present but not enabled: CineNex's provider app registrations/public IDs are absent, and Trakt's registered HTTPS callback and app/domain association are not configured. See ACCOUNT_LOGIN.md. AniList/MAL list access is currently read-only (MAL first100 entries), not two-way episode sync. Do not advertise successful live login until configuration and device sign-in are verified.

The first-start touch-block symptom and energy effects still require a device replay. New regression coverage covers metadata preservation, bounded add-on fan-out, same-host provider counts, disk-cache persistence/expiry, active partial-cache deletion protection and OAuth callback validation.


## Current Trakt authentication correction

Trakt's October2026 official guidance supports direct native PKCE with S256 and no client secret or token broker. CineNex now uses auth.trakt.tv for authorization/token exchange and serialized refresh, with registered HTTPS callback matching. Earlier broker requirements in conversation were based on outdated documentation and are superseded. Registration/public IDs, verified callback domain and matching signing association remain external setup prerequisites.
