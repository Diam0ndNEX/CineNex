import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('account_config', Path(__file__).parents[1] / 'configure_account_logins.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class AccountConfigurationTests(unittest.TestCase):
    def test_https_callback_produces_associated_domain_and_safe_xcconfig(self):
        text, entitlements = module.build_configuration({'CINENEX_TRAKT_CLIENT_ID': 'public-id', module.REDIRECT_KEY: 'https://login.example.test/oauth/trakt'})
        self.assertIn('https:/$()/login.example.test/oauth/trakt', text)
        self.assertEqual(entitlements['com.apple.developer.associated-domains'], ['applinks:login.example.test'])
    def test_empty_config_does_not_invent_credentials_or_domains(self):
        text, entitlements = module.build_configuration({})
        self.assertEqual(entitlements['com.apple.developer.associated-domains'], [])
        self.assertNotIn('client_secret', text)
    def test_invalid_settings_cannot_inject_build_configuration(self):
        for values in [{'CINENEX_MAL_CLIENT_ID': 'id\nCODE_SIGNING_ALLOWED=NO'},
                       {module.REDIRECT_KEY: 'http://example.test/callback'},
                       {module.REDIRECT_KEY: 'https://user:pass@example.test/callback'},
                       {module.REDIRECT_KEY: 'https://example.test/callback?token=private'}]:
            with self.subTest(values=values), self.assertRaises(ValueError):
                module.build_configuration(values)
