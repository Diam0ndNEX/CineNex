# Screenshot-reference correction

The supplied references define the black canvas, single floating four-button dock, large single headings, compact grouped Settings rows, tall detail artwork fading to black, a white Play pill, separate secondary actions, cast portraits and metadata hierarchy.

Root navigation now uses an explicit selected page, not a hidden native TabView plus a custom dock. Home/Search/Library/Profile are the sole dock buttons. Discover remains under Search. There is no native root navigation title or branded toolbar bubble. Pushed settings pages retain a back control.

Genre buttons and movie/series collections own paged queries. TMDB uses real movie/TV genre IDs; token-free Cinemeta uses genre and skip cursors. Independent cursors, raw response counts, deduplication and a persistent visible sentinel handle short pages. Empty duplicate scans are bounded. Local saved lists are finite. Missing provider metadata is not invented.

Cold discovery has two independently testable fixes: synchronous Security IPC runs off MainActor behind a cancellable timed waiter; HTTP callers complete at a wall-clock deadline without waiting for a delayed URLSession completion queue. Built-in providers remain usable if secure storage stalls. Request IDs and secure-read elapsed diagnostics explain each stage without logging URLs, tokens or codes. These mechanisms do not establish the only cause of a user's device-specific stall.

The UI smoke test launches a DEBUG-only deterministic demo catalog. It checks one dock/no native tab bar and navigates Settings, a preference page, Library, a title and its genre. Its screenshots verify layout/routing, not production provider availability. Full regression builds export screenshots/results; IPA-only builds keep skipping simulator tests.

Movie ratings shown by the five-star row are explicitly local device feedback, not remote tracker writes. Artwork and cast portraits use real supplied URLs; absent certification, logos, comments and tracker metadata are not fabricated. Native-device layout, Dynamic Type and cold discovery still require acceptance with the signed IPA.
