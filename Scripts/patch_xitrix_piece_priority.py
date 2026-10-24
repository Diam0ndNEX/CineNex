from __future__ import annotations

import argparse
from pathlib import Path


HEADER_METHOD = "- (BOOL)setPiecePriority:(NSInteger)priority at:(NSInteger)pieceIndex;"
IMPLEMENTATION_METHOD = "- (BOOL)setPiecePriority:(NSInteger)priority at:(NSInteger)pieceIndex {"

IMPLEMENTATION = """- (BOOL)setPiecePriority:(NSInteger)priority at:(NSInteger)pieceIndex {
    if (pieceIndex < 0 || priority < 0 || priority > 7) {
        return NO;
    }

    __block BOOL didSetPriority = NO;
    [self performOperation:@"setPiecePriority" action:^(lt::torrent_handle const &handle) {
        auto torrentInfo = handle.torrent_file();
        if (torrentInfo == nullptr || pieceIndex >= torrentInfo->num_pieces()) {
            return;
        }

        handle.piece_priority(
            lt::piece_index_t(static_cast<int>(pieceIndex)),
            lt::download_priority_t(static_cast<int>(priority))
        );
        didSetPriority = YES;
    }];
    return didSetPriority;
}

"""


class PatchError(RuntimeError):
    pass


def patch_wrapper(wrapper_root: Path) -> bool:
    header_path = wrapper_root / "LibTorrent/Core/TorrentHandle/TorrentHandle.h"
    implementation_path = wrapper_root / "LibTorrent/Core/TorrentHandle/TorrentHandle.mm"
    if not header_path.is_file() or not implementation_path.is_file():
        raise PatchError("The checked-out XITRIX wrapper does not contain the expected TorrentHandle files.")

    header = header_path.read_text(encoding="utf-8")
    implementation = implementation_path.read_text(encoding="utf-8")
    header_present = HEADER_METHOD in header
    implementation_present = IMPLEMENTATION_METHOD in implementation

    if header_present and implementation_present:
        return False
    if header_present or implementation_present:
        raise PatchError("The wrapper contains only part of the piece-priority bridge; refusing to patch an inconsistent checkout.")

    header_anchor = "- (void)setFilePriority:(FilePriority)priority at:(NSInteger)fileIndex;"
    implementation_anchor = "- (void)setFilePriority:(FilePriority)priority at:(NSInteger)fileIndex {"
    if header.count(header_anchor) != 1:
        raise PatchError("Expected exactly one public file-priority declaration in TorrentHandle.h.")
    if implementation.count(implementation_anchor) != 1:
        raise PatchError("Expected exactly one file-priority implementation in TorrentHandle.mm.")
    if "handle.prioritize_pieces(piecePriorities);" not in implementation:
        raise PatchError("The wrapper's existing piece-priority implementation changed; refusing to patch an unknown API.")

    updated_header = header.replace(header_anchor, HEADER_METHOD + "\n" + header_anchor, 1)
    updated_implementation = implementation.replace(implementation_anchor, IMPLEMENTATION + implementation_anchor, 1)
    header_path.write_text(updated_header, encoding="utf-8")
    implementation_path.write_text(updated_implementation, encoding="utf-8")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply CineNex's narrow piece-priority bridge to a pinned XITRIX LibTorrent-Swift checkout.")
    parser.add_argument("wrapper_root", type=Path)
    args = parser.parse_args()
    try:
        changed = patch_wrapper(args.wrapper_root)
    except (OSError, PatchError) as error:
        parser.exit(1, f"XITRIX piece-priority patch failed: {error}\n")
    print("Applied XITRIX piece-priority bridge." if changed else "XITRIX piece-priority bridge is already applied.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
