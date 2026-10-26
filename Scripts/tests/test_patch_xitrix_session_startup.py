import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from patch_xitrix_session_startup import patched_sources, patch_wrapper, PatchError

FIXTURES = Path(__file__).parent / 'fixtures' / 'xitrix_session'


class NativeStartupPatchTests(unittest.TestCase):
    def sources(self):
        return tuple((FIXTURES / name).read_text() for name in ['SessionSettings.mm', 'Session.mm', 'Session.h'])

    def test_every_native_string_conversion_is_null_safe(self):
        settings, session, header = patched_sources(*self.sources())
        for field in ['agentName', 'peerFingerprint', 'outgoingInterfaces', 'listenInterfaces', 'proxyHostname', 'proxyUsername', 'proxyPassword']:
            self.assertNotIn(f'[_{field} UTF8String]', settings)
            self.assertIn(f'CineNexSafeUTF8(_{field})', settings)
        self.assertIn('return text != nullptr ? text : "";', settings)
        self.assertIn('_listenInterfaces = @"0.0.0.0:0,[::]:0";', settings)
        self.assertIn('_outgoingInterfaces = @"";', settings)
        self.assertIn('nullable instancetype)initWith:', header)
        self.assertIn('catch (std::exception const &exception)', session)

    def test_native_checkpoints_surround_settings_and_session_calls(self):
        _, session, _ = patched_sources(*self.sources())
        self.assertLess(session.index('@"settings.convert.begin"'), session.index('lt::session_params(_settings.settingsPack)'))
        self.assertLess(session.index('lt::session_params(_settings.settingsPack)'), session.index('@"settings.convert.end"'))
        self.assertLess(session.index('@"session.construct.begin"'), session.index('new lt::session'))
        self.assertLess(session.index('new lt::session'), session.index('@"session.construct.end"'))
        self.assertIn('resident_bytes', session)
        self.assertIn('fsync(descriptor)', session)
        self.assertIn('@"persistence.restore.begin"', session)
        self.assertIn('@"alerts.thread.start"', session)

    def test_scene_box_peer_profile_is_adapted(self):
        settings, _, _ = patched_sources(*self.sources())
        self.assertIn('settings_pack::connections_limit, 150', settings)
        self.assertIn('settings_pack::dht_bootstrap_nodes', settings)
        self.assertIn('router.bittorrent.com:6881', settings)
        self.assertIn('settings_pack::enable_outgoing_tcp, true', settings)
        self.assertIn('settings_pack::announce_to_all_trackers, true', settings)

    def test_native_alert_thread_can_be_stopped(self):
        _, session, header = patched_sources(*self.sources())
        self.assertIn('- (void)shutdown;', header)
        self.assertIn('[_eventsThread cancel];', session)
        self.assertNotIn('while (YES)', session)
        self.assertIn('while (![[NSThread currentThread] isCancelled])', session)

    def test_patch_is_idempotent(self):
        result = patched_sources(*self.sources())
        self.assertIsNone(patched_sources(*result))

    def test_partial_patch_is_rejected(self):
        original = self.sources()
        changed = patched_sources(*original)
        with self.assertRaises(PatchError):
            patched_sources(changed[0], original[1], original[2])

    def test_unknown_wrapper_is_not_modified(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            paths = ['LibTorrent/Core/SessionSettings/SessionSettings.mm', 'LibTorrent/Core/Session/Session.mm', 'LibTorrent/Core/Session/Session.h']
            for path, content in zip(paths, self.sources()):
                file = root / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(content)
            target = root / paths[0]
            target.write_text(target.read_text().replace('[_listenInterfaces UTF8String]', 'unknown_expression'))
            before = [p.read_bytes() for p in (root / path for path in paths)]
            with self.assertRaises(PatchError):
                patch_wrapper(root)
            after = [p.read_bytes() for p in (root / path for path in paths)]
            self.assertEqual(before, after)


if __name__ == '__main__':
    unittest.main()
