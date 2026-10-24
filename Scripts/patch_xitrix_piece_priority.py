from __future__ import annotations

import argparse
from pathlib import Path


HEADER_METHOD = "- (BOOL)setPiecePriority:(NSInteger)priority at:(NSInteger)pieceIndex;"
IMPLEMENTATION_METHOD = "- (BOOL)setPiecePriority:(NSInteger)priority at:(NSInteger)pieceIndex {"
FILE_ENTRY_METHOD = "@property (readonly, nonatomic) uint64_t fileOffset;"
FILE_ENTRY_INTERNAL_METHOD = "@property (readwrite, nonatomic) uint64_t fileOffset;"
FILE_OFFSET_ASSIGNMENT = "fileEntry.fileOffset = static_cast<uint64_t>(layout.file_offset(fileIndex));"

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
    file_entry_path = wrapper_root / "LibTorrent/Core/FileEntry/FileEntry.h"
    file_entry_internal_path = wrapper_root / "LibTorrent/Core/FileEntry/FileEntry_Internal.h"
    snapshot_path = wrapper_root / "LibTorrent/Core/TorrentHandleSnapshot/TorrentHandleSnapshot.mm"
    paths = [header_path, implementation_path, file_entry_path, file_entry_internal_path, snapshot_path]
    if not all(path.is_file() for path in paths):
        raise PatchError("The checked-out XITRIX wrapper does not contain the expected torrent metadata files.")

    header = header_path.read_text(encoding="utf-8")
    implementation = implementation_path.read_text(encoding="utf-8")
    file_entry = file_entry_path.read_text(encoding="utf-8")
    file_entry_internal = file_entry_internal_path.read_text(encoding="utf-8")
    snapshot = snapshot_path.read_text(encoding="utf-8")
    present = [
        HEADER_METHOD in header,
        IMPLEMENTATION_METHOD in implementation,
        FILE_ENTRY_METHOD in file_entry,
        FILE_ENTRY_INTERNAL_METHOD in file_entry_internal,
        FILE_OFFSET_ASSIGNMENT in snapshot,
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
    anchors = [
        (header.count(header_anchor), "public file-priority declaration in TorrentHandle.h"),
        (implementation.count(implementation_anchor), "file-priority implementation in TorrentHandle.mm"),
        (file_entry.count(file_entry_anchor), "begin_idx declaration in FileEntry.h"),
        (file_entry_internal.count(file_entry_internal_anchor), "begin_idx declaration in FileEntry_Internal.h"),
        (snapshot.count(snapshot_anchor), "begin_idx assignment in TorrentHandleSnapshot.mm"),
    ]
    for count, description in anchors:
        if count != 1:
            raise PatchError(f"Expected exactly one {description}.")
    if "handle.prioritize_pieces(piecePriorities);" not in implementation:
        raise PatchError("The wrapper's existing piece-priority implementation changed; refusing to patch an unknown API.")

    updated_header = header.replace(header_anchor, HEADER_METHOD + "\n" + header_anchor, 1)
    updated_implementation = implementation.replace(implementation_anchor, IMPLEMENTATION + implementation_anchor, 1)
    updated_file_entry = file_entry.replace(file_entry_anchor, FILE_ENTRY_METHOD + "\n" + file_entry_anchor, 1)
    updated_file_entry_internal = file_entry_internal.replace(file_entry_internal_anchor, FILE_ENTRY_INTERNAL_METHOD + "\n" + file_entry_internal_anchor, 1)
    updated_snapshot = snapshot.replace(snapshot_anchor, "                " + FILE_OFFSET_ASSIGNMENT + "\n" + snapshot_anchor, 1)
    header_path.write_text(updated_header, encoding="utf-8")
    implementation_path.write_text(updated_implementation, encoding="utf-8")
    file_entry_path.write_text(updated_file_entry, encoding="utf-8")
    file_entry_internal_path.write_text(updated_file_entry_internal, encoding="utf-8")
    snapshot_path.write_text(updated_snapshot, encoding="utf-8")
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
