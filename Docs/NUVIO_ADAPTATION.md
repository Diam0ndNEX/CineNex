# Nuvio reference adaptation

The owner supplied `Nuvio.zip` as a design and behavior reference. Its README identifies NuvioMedia/NuvioMobile and the luqmanfadlli/NuvioMobile-Enhanced fork and states GPLv3. The archive does not include the linked LICENSE file. This pass implements original SwiftUI equivalents of the interaction patterns below; it does not import Nuvio's Kotlin runtime, player bridges, branding, assets, application credentials, or verbatim implementation.

Reference points:

| Nuvio reference | CineNex adaptation |
| --- | --- |
| `HomeHeroSection.kt` | Manually paged featured titles and a selectable hero presentation |
| `HomeContinueWatchingSection.kt`, `HomeCatalogSection.kt` | Resume presentation and configurable catalog shelves |
| `NuvioGlassTabBar.swift`, `Theme.kt` | Floating native glass, readable system type and optional navigation feedback/canvas choices |
| `DetailEpisodeNavigator.kt` | Search, sorting, numeric episode jump and local watched marks |
| `ProviderFilterRow.kt`, `PinnedStreamSourcesRepository.kt` | Live provider-count chips, persistent pins and explicit per-release pin actions |
| `StreamCard.kt`, `StreamBadgePresentation.kt` | Release card density and concise codec/HDR/audio hints |

Preserve CineNex's progressive source discovery, MediaFusion/Torrentio adapters, startup readiness, cancellation, verified-byte HTTP streaming, cache budgets, native icon and account configuration. Provider pins affect presentation only, not playback selection. Technical badges are hints in the release name, not proof of decoder compatibility. Missing sizes and seed counts remain unknown.

Episode watched marks are manual and local. CineNex does not currently record automatic per-episode playback fractions, so this pass does not claim automatic episode progress or account synchronization. No trailer autoplays or background hero timers are introduced.

Validation must include a fresh iOS build and regression run after integration. Swift compilation is unavailable on the Linux editing host. Physical-device layout, VoiceOver, Dynamic Type, pagination, playback and energy acceptance remain necessary; passing unit tests is not visual acceptance.
