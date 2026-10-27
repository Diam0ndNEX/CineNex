import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('verify_app', Path(__file__).parents[1] / 'verify_built_app.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class BuiltAppConfigurationTests(unittest.TestCase):
    def info(self):
        return {
            'CINENEX_TRAKT_CLIENT_ID': 'registered-app',
            'CFBundleURLTypes': [{'CFBundleURLSchemes': ['cinenex']}],
            'CFBundleIcons': {'CFBundlePrimaryIcon': {
                'CFBundleIconName': 'AppIcon', 'CFBundleIconFiles': ['AppIcon60x60']}},
        }

    def test_processed_app_with_registered_id_and_icon_is_accepted(self):
        module.verify_info(self.info(), {'CINENEX_TRAKT_CLIENT_ID': 'registered-app',
                                        'CINENEX_MAL_CLIENT_ID': ''})

    def test_missing_unexpanded_or_wrong_public_id_rejects_package(self):
        for value in (None, '', '$(CINENEX_TRAKT_CLIENT_ID)', 'another-app'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                info = self.info()
                info['CINENEX_TRAKT_CLIENT_ID'] = value
                module.verify_info(info, {'CINENEX_TRAKT_CLIENT_ID': 'registered-app'})

    def test_missing_callback_scheme_or_icon_rejects_package(self):
        for key in ('CFBundleURLTypes', 'CFBundleIcons'):
            with self.subTest(key=key), self.assertRaises(ValueError):
                info = self.info()
                del info[key]
                module.verify_info(info, {})


if __name__ == '__main__':
    unittest.main()
