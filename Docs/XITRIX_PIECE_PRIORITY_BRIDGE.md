# XITRIX piece-priority bridge

CineNex's byte-range planner calculates exact global torrent-piece ranges for startup and seeks. The public XITRIX TorrentHandle API currently exposes file priorities, sequential download, and first/last-piece priority, but not an arbitrary piece-priority setter. The pinned wrapper implementation already calls libtorrent's prioritize_pieces internally, so the patch adds one narrow, bounds-checked setPiecePriority method for the adapter. It also exposes each file's global byte offset from libtorrent's file layout, which is needed to map file-relative AVPlayer ranges to global piece indices when files share a piece.

The patcher is intentionally external to the wrapper source. It applies only when the expected header and implementation anchors are present, refuses partially patched or changed upstream layouts, and is idempotent. CI tests it against synthetic wrapper fixtures; the native wrapper still requires a real Xcode build after submodule integration.

The wrapper repository has no GitHub license declaration. This bridge does not copy wrapper source into CineNex, but that absence remains a release-readiness risk before bundling or distributing the dependency.
