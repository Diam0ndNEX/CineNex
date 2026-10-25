from __future__ import annotations

import argparse
from pathlib import Path


HEADER_METHOD = "- (BOOL)setPiecePriority:(NSInteger)priority at:(NSInteger)pieceIndex;"
IMPLEMENTATION_METHOD = "- (BOOL)setPiecePriority:(NSInteger)priority at:(NSInteger)pieceIndex {"
DEADLINE_METHOD = "- (BOOL)setPieceDeadline:(NSInteger)milliseconds at:(NSInteger)pieceIndex;"
DEADLINE_IMPLEMENTATION_METHOD = "- (BOOL)setPieceDeadline:(NSInteger)milliseconds at:(NSInteger)pieceIndex {"
CLEAR_DEADLINE_METHOD = "- (BOOL)clearPieceDeadlineAt:(NSInteger)pieceIndex;"
CLEAR_DEADLINE_IMPLEMENTATION_METHOD = "- (BOOL)clearPieceDeadlineAt:(NSInteger)pieceIndex {"
CLEAR_DEADLINE_IMPLEMENTATION = """- (BOOL)setPieceDeadline:(NSInteger)milliseconds at:(NSInteger)pieceIndex {
    if (pieceIndex < 0 || milliseconds < 0 || milliseconds > 60000) {
        return NO;
    }

    __block BOOL didSetDeadline = NO;
    [self performOperation:@"setPieceDeadline" action:^(lt::torrent_handle const &handle) {
        auto torrentInfo = handle.torrent_file();
        if (torrentInfo == nullptr || pieceIndex >= torrentInfo->num_pieces()) {
            return;
        }

        handle.set_piece_deadline(
            lt::piece_index_t(static_cast<int>(pieceIndex)),
            static_cast<int>(milliseconds)
        );
        didSetDeadline = YES;
    }];
    return didSetDeadline;
}

"""

CLEAR_DEADLINE_IMPLEMENTATION = """- (BOOL)clearPieceDeadlineAt:(NSInteger)pieceIndex {
    if (pieceIndex < 0) {
        return NO;
    }

    __block BOOL didClearDeadline = NO;
    [self performOperation:@"clearPieceDeadline" action:^(lt::torrent_handle const &handle) {
        auto torrentInfo = handle.torrent_file();
        if (torrentInfo == nullptr || pieceIndex >= torrentInfo->num_pieces()) {
            return;
        }

        handle.reset_piece_deadline(lt::piece_index_t(static_cast<int>(pieceIndex)));
        didClearDeadline = YES;
    }];
    return didClearDeadline;
}

"""


class PatchError(RuntimeError):
    pass


def patch_wrapper(wrapper_root: Path) -> bool:
    header_path = wrapper_root / "LibTorrent/Core/TorrentHandle/TorrentHandle.h"
    implementation_path = wrapper_root / "LibTorrent/Core/TorrentHandle/TorrentHandle.mm"
    file_entry_path = wrapper_root / "LibTorrent/Core/FileEntry/FileEntry.h"
    file_entry_internal_path = wrapper_root / "LibTorrent/Core/FileEntry/FileEntry_Internal.h"
    snapshot_path = wrapper_root / "LibTorrent/Core/TorrentHandleSnapshot/TorrentHandleSnapshot.mm"
    snapshot_header_path = wrapper_root / "LibTorrent/Core/TorrentHandleSnapshot/TorrentHandleSnapshot.h"
    paths = [header_path, implementation_path, file_entry_path, file_entry_internal_path, snapshot_path, snapshot_header_path]
    if not all(path.is_file() for path in paths):
        raise PatchError("The checked-out XITRIX wrapper does not contain the expected torrent metadata files.")

    header = header_path.read_text(encoding="utf-8")
    implementation = implementation_path.read_text(encoding="utf-8")
    file_entry = file_entry_path.read_text(encoding="utf-8")
    file_entry_internal = file_entry_internal_path.read_text(encoding="utf-8")
    snapshot = snapshot_path.read_text(encoding="utf-8")
    snapshot_header = snapshot_header_path.read_text(encoding="utf-8")
    present = [
        HEADER_METHOD in header,
        IMPLEMENTATION_METHOD in implementation,
        DEADLINE_METHOD in header,
        DEADLINE_IMPLEMENTATION_METHOD in implementation,
        CLEAR_DEADLINE_METHOD in header,
        CLEAR_DEADLINE_IMPLEMENTATION_METHOD in implementation,
        FILE_ENTRY_METHOD in file_entry,
        FILE_ENTRY_INTERNAL_METHOD in file_entry_internal,
        FILE_OFFSET_ASSIGNMENT in snapshot,
        PIECE_LENGTH_METHOD in snapshot_header,
        PIECE_LENGTH_GETTER in snapshot,
    ]
    if all(present):
        return False
    if any(present):
        raise PatchError("The wrapper contains only part of the torrent range bridge; refusing to patch an inconsistent checkout.")

    header_anchor = "- (void)setFilePriority:(FilePriority)priority at:(NSInteger)fileIndex;"
    implementation_anchor = "- (void)setFilePriority:(FilePriority)priority at:(NSInteger)fileIndex {"
    file_entry_anchor = "@property (readonly, nonatomic) uint64_t begin_idx;"
    file_entry_internal_anchor = "@property (readwrite, nonatomic) uint64_t begin_idx;"
    snapshot_anchor = "                fileEntry.begin_idx = static_cast<uint64_t>(beginIndex);"
    snapshot_validity_anchor = "- (BOOL)isValid {"
    snapshot_header_anchor = "@property (readonly) uint64_t total;"
    anchors = [
        (header.count(header_anchor), "public file-priority declaration in TorrentHandle.h"),
        (implementation.count(implementation_anchor), "file-priority implementation in TorrentHandle.mm"),
        (file_entry.count(file_entry_anchor), "begin_idx declaration in FileEntry.h"),
        (file_entry_internal.count(file_entry_internal_anchor), "begin_idx declaration in FileEntry_Internal.h"),
        (snapshot.count(snapshot_anchor), "begin_idx assignment in TorrentHandleSnapshot.mm"),
        (snapshot.count(snapshot_validity_anchor), "isValid getter in TorrentHandleSnapshot.mm"),
        (snapshot_header.count(snapshot_header_anchor), "total declaration in TorrentHandleSnapshot.h"),
    ]
    for count, description in anchors:
        if count != 1:
            raise PatchError(f"Expected exactly one {description}.")
    if "handle.prioritize_pieces(piecePriorities);" not in implementation:
        raise PatchError("The wrapper's existing piece-priority implementation changed; refusing to patch an unknown API.")

    updated_header = header.replace(
        header_anchor,
        HEADER_METHOD + "\n" + DEADLINE_METHOD + "\n" + CLEAR_DEADLINE_METHOD + "\n" + header_anchor,
        1,
    )
    updated_implementation = implementation.replace(
        implementation_anchor,
        IMPLEMENTATION + DEADLINE_IMPLEMENTATION + implementation_anchor,
        1,
    )
    updated_implementation = updated_implementation.replace(
        implementation_anchor,
        CLEAR_DEADLINE_IMPLEMENTATION + implementation_anchor,
        1,
    )
    updated_file_entry = file_entry.replace(file_entry_anchor, FILE_ENTRY_METHOD + "\n" + file_entry_anchor, 1)
    updated_file_entry_internal = file_entry_internal.replace(file_entry_internal_anchor, FILE_ENTRY_INTERNAL_METHOD + "\n" + file_entry_internal_anchor, 1)
    updated_snapshot = snapshot.replace(snapshot_anchor, "                " + FILE_OFFSET_ASSIGNMENT + "\n" + snapshot_anchor, 1)
    piece_length_getter = """- (uint32_t)pieceLength {
    auto info = _torrentInfo;
    if (info == nullptr) {
        return 0;
    }
    const int length = info->piece_length();
    return length > 0 ? static_cast<uint32_t>(length) : 0;
}

"""
    updated_snapshot = updated_snapshot.replace(snapshot_validity_anchor, piece_length_getter + snapshot_validity_anchor, 1)
    updated_snapshot_header = snapshot_header.replace(snapshot_header_anchor, PIECE_LENGTH_METHOD + "\n" + snapshot_header_anchor, 1)
    header_path.write_text(updated_header, encoding="utf-8")
    implementation_path.write_text(updated_implementation, encoding="utf-8")
    file_entry_path.write_text(updated_file_entry, encoding="utf-8")
    file_entry_internal_path.write_text(updated_file_entry_internal, encoding="utf-8")
    snapshot_path.write_text(updated_snapshot, encoding="utf-8")
    snapshot_header_path.write_text(updated_snapshot_header, encoding="utf-8")
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
