"""Regression checks for release evidence bound to a specific bundle."""
from pathlib import Path
import tempfile
import unittest

from release_runtime_evidence import read_json, reconcile_runtime_evidence, write_json


class ReleaseRuntimeEvidenceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.docs = Path(self.temp.name)
        write_json(self.docs / 'bundle-verification.json', {'sha256': 'new', 'runtime16KbVerified': False})
        write_json(self.docs / 'android-emulator-environment.json', {
            'productionAppRuntimeVerified': True,
            'productionRuntimeBundleSha256': 'old',
        })
        write_json(self.docs / 'verification-summary.json', {
            'bundleSha256': 'old', 'nativeRuntimeTested': True,
            'signedReleaseStartupSmokePassed': True,
        })
        self.smoke = {
            'sourceBundleSha256': 'old', 'currentBundleVerified': True,
            'productionReleaseBinary': True, 'installedApkHashMatches': True,
            'loginScreenVisibleInAccessibilityTree': True, 'firebaseInitialized': True,
            'firebaseCrashlyticsInitialized': True,
            'firebaseRegistrarErrorsAbsent': True, 'pageSize': 16384,
        }
        write_json(self.docs / 'signed-release-smoke.json', self.smoke)

    def test_new_bundle_invalidates_all_runtime_claims(self):
        self.assertFalse(reconcile_runtime_evidence(self.docs, 'new'))
        self.assertFalse(read_json(self.docs / 'bundle-verification.json')['runtime16KbVerified'])
        self.assertFalse(read_json(self.docs / 'signed-release-smoke.json')['currentBundleVerified'])
        environment = read_json(self.docs / 'android-emulator-environment.json')
        self.assertFalse(environment['productionAppRuntimeVerified'])
        self.assertIsNone(environment['productionRuntimeBundleSha256'])
        summary = read_json(self.docs / 'verification-summary.json')
        self.assertEqual(summary['bundleSha256'], 'new')
        self.assertFalse(summary['nativeRuntimeTested'])
        self.assertFalse(summary['signedReleaseStartupSmokePassed'])

    def test_matching_complete_smoke_confirms_current_bundle(self):
        self.smoke['sourceBundleSha256'] = 'new'
        write_json(self.docs / 'signed-release-smoke.json', self.smoke)
        self.assertTrue(reconcile_runtime_evidence(self.docs, 'new'))
        self.assertTrue(read_json(self.docs / 'bundle-verification.json')['runtime16KbVerified'])
        environment = read_json(self.docs / 'android-emulator-environment.json')
        self.assertEqual(environment['productionRuntimeBundleSha256'], 'new')
        self.assertTrue(read_json(self.docs / 'verification-summary.json')['signedReleaseStartupSmokePassed'])

    def test_incomplete_smoke_cannot_confirm_runtime(self):
        self.smoke['sourceBundleSha256'] = 'new'
        self.smoke['firebaseCrashlyticsInitialized'] = False
        write_json(self.docs / 'signed-release-smoke.json', self.smoke)
        self.assertFalse(reconcile_runtime_evidence(self.docs, 'new'))


if __name__ == '__main__':
    unittest.main()
