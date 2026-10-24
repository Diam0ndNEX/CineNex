import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from patch_xitrix_piece_priority import (
    FILE_ENTRY_INTERNAL_METHOD,
    FILE_ENTRY_METHOD,
    FILE_OFFSET_ASSIGNMENT,
    IMPLEMENTATION_METHOD,
    PIECE_LENGTH_GETTER,
    PIECE_LENGTH_METHOD,
    HEADER_METHOD,
    PatchError,
    patch_wrapper,
)


class PatchXitrixPiecePriorityTests(unittest.TestCase):
    def create_wrapper(self, root: Path) -> tuple[Path, Path]:
        header = root / "LibTorrent/Core/TorrentHandle/TorrentHandle.h"
        implementation = root / "LibTorrent/Core/TorrentHandle/TorrentHandle.mm"
        file_entry = root / "LibTorrent/Core/FileEntry/FileEntry.h"
        file_entry_internal = root / "LibTorrent/Core/FileEntry/FileEntry_Internal.h"
        snapshot = root / "LibTorrent/Core/TorrentHandleSnapshot/TorrentHandleSnapshot.mm"
        snapshot_header = root / "LibTorrent/Core/TorrentHandleSnapshot/TorrentHandleSnapshot.h"
        header.parent.mkdir(parents=True)
        implementation.parent.mkdir(parents=True, exist_ok=True)
        file_entry.parent.mkdir(parents=True, exist_ok=True)
        snapshot.parent.mkdir(parents=True, exist_ok=True)
        header.write_text(
            "#import <Foundation/Foundation.h>\n"
            "@interface TorrentHandle : NSObject\n"
            "- (void)setFilePriority:(FilePriority)priority at:(NSInteger)fileIndex;\n"
            "@end\n",
            encoding="utf-8",
        )
        implementation.write_text(
            "#import \"TorrentHandle.h\"\n"
            "@implementation TorrentHandle\n"
            "- (void)applyPriorityConfigurationToHandle:(lt::torrent_handle const &)handle {\n"
            "    handle.prioritize_pieces(piecePriorities);\n"
            "}\n"
            "- (void)setFilePriority:(FilePriority)priority at:(NSInteger)fileIndex {\n"
            "}\n"
            "@end\n",
            encoding="utf-8",
        )
        file_entry.write_text(
            "@interface FileEntry : NSObject\n"
            "@property (readonly, nonatomic) uint64_t begin_idx;\n"
            "@end\n",
            encoding="utf-8",
        )
        file_entry_internal.write_text(
            "@interface FileEntry ()\n"
            "@property (readwrite, nonatomic) uint64_t begin_idx;\n"
            "@end\n",
            encoding="utf-8",
        )
        snapshot.write_text(
            "- (BOOL)isValid {\n"
            "                fileEntry.begin_idx = static_cast<uint64_t>(beginIndex);\n",
            encoding="utf-8",
        )
        snapshot_header.write_text(
            "@interface TorrentHandleSnapshot : NSObject\n"
            "@property (readonly) uint64_t total;\n"
            "@end\n",
            encoding="utf-8",
        )
        return header, implementation

    def test_adds_checked_piece_priority_bridge(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            header, implementation = self.create_wrapper(root)
            file_entry = root / "LibTorrent/Core/FileEntry/FileEntry.h"
            file_entry_internal = root / "LibTorrent/Core/FileEntry/FileEntry_Internal.h"
            snapshot = root / "LibTorrent/Core/TorrentHandleSnapshot/TorrentHandleSnapshot.mm"
            snapshot_header = root / "LibTorrent/Core/TorrentHandleSnapshot/TorrentHandleSnapshot.h"

            self.assertTrue(patch_wrapper(root))
            header_text = header.read_text(encoding="utf-8")
            implementation_text = implementation.read_text(encoding="utf-8")
            self.assertIn(HEADER_METHOD, header_text)
            self.assertIn(IMPLEMENTATION_METHOD, implementation_text)
            self.assertIn("priority > 7", implementation_text)
            self.assertIn("pieceIndex >= torrentInfo->num_pieces()", implementation_text)
            self.assertIn("handle.piece_priority(", implementation_text)
            self.assertIn(FILE_ENTRY_METHOD, file_entry.read_text(encoding="utf-8"))
            self.assertIn(FILE_ENTRY_INTERNAL_METHOD, file_entry_internal.read_text(encoding="utf-8"))
            self.assertIn(FILE_OFFSET_ASSIGNMENT, snapshot.read_text(encoding="utf-8"))
            self.assertIn(PIECE_LENGTH_GETTER, snapshot.read_text(encoding="utf-8"))
            self.assertIn(PIECE_LENGTH_METHOD, snapshot_header.read_text(encoding="utf-8"))

    def test_patch_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            header, implementation = self.create_wrapper(root)

            self.assertTrue(patch_wrapper(root))
            patched_header = header.read_text(encoding="utf-8")
            patched_implementation = implementation.read_text(encoding="utf-8")
            self.assertFalse(patch_wrapper(root))
            self.assertEqual(header.read_text(encoding="utf-8"), patched_header)
            self.assertEqual(implementation.read_text(encoding="utf-8"), patched_implementation)

    def test_unknown_upstream_layout_fails_without_mutating_files(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            header, implementation = self.create_wrapper(root)
            header.write_text(header.read_text(encoding="utf-8").replace("setFilePriority", "setFilesPriority"), encoding="utf-8")
            original_header = header.read_text(encoding="utf-8")
            original_implementation = implementation.read_text(encoding="utf-8")

            with self.assertRaises(PatchError):
                patch_wrapper(root)

            self.assertEqual(header.read_text(encoding="utf-8"), original_header)
            self.assertEqual(implementation.read_text(encoding="utf-8"), original_implementation)

    def test_partial_patch_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            header, implementation = self.create_wrapper(root)
            header.write_text(header.read_text(encoding="utf-8") + HEADER_METHOD + "\n", encoding="utf-8")

            with self.assertRaises(PatchError):
                patch_wrapper(root)

            self.assertNotIn(IMPLEMENTATION_METHOD, implementation.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
