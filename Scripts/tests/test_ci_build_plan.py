import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('ci_build_plan', Path(__file__).resolve().parents[1] / 'ci_build_plan.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class BuildPlanTests(unittest.TestCase):
    def test_ipa_only_skips_every_test_even_for_behavior_changes(self):
        result = module.plan(['CineNex/Features/Player/PlayerView.swift'], full=True, ipa=True, ipa_only=True)
        self.assertEqual(result, dict(build=True, tests=False, native_tests=False, ipa=True, ipa_only=True))

    def test_docs_skip_macos(self):
        self.assertFalse(module.plan(['Docs/ARCHITECTURE.md'])['build'])

    def test_player_and_unknown_changes_keep_tests(self):
        for path in ['CineNex/Features/Player/PlayerView.swift', 'CineNex/Features/Home/ContentView.swift', 'unknown.config']:
            self.assertTrue(module.plan([path])['tests'])

    def test_presentation_only_builds_without_tests_or_ipa(self):
        self.assertEqual(module.plan(['CineNex/Features/Home/AppearanceSettingsView.swift']),
                         dict(build=True, tests=False, native_tests=False, ipa=False, ipa_only=False))

    def test_mixed_changes_do_not_hide_behavior_tests(self):
        self.assertTrue(module.plan(['CineNex/Features/Home/AppearanceSettingsView.swift', 'CineNex/Services/SceneBoxTorrentSearch.swift'])['tests'])

    def test_native_changes_keep_wrapper_checks(self):
        self.assertTrue(module.plan(['Thirdparty/LibTorrent-Swift'])['native_tests'])

    def test_full_ipa_runs_everything_even_for_docs(self):
        result = module.plan(['README.md'], full=True, ipa=True)
        self.assertTrue(all(result[key] for key in ['build', 'tests', 'native_tests', 'ipa']))


if __name__ == '__main__':
    unittest.main()
