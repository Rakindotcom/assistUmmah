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
            'bundleSha256': 'old', 'nativeRuntimeTested': True, 'universalApkSha256': 'apk',
            'signedReleaseStartupSmokePassed': True,
        })
        self.smoke = {
            'sourceBundleSha256': 'old', 'currentBundleVerified': True, 'universalApkSha256': 'apk',
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
        self.assertEqual(
            read_json(self.docs / 'signed-release-smoke.json')['supersededByBundleSha256'],
            'new',
        )
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
        self.assertNotIn('supersededByBundleSha256',
                         read_json(self.docs / 'signed-release-smoke.json'))
        environment = read_json(self.docs / 'android-emulator-environment.json')
        self.assertEqual(environment['productionRuntimeBundleSha256'], 'new')
        self.assertTrue(read_json(self.docs / 'verification-summary.json')['signedReleaseStartupSmokePassed'])

    def test_incomplete_smoke_cannot_confirm_runtime(self):
        self.smoke['sourceBundleSha256'] = 'new'
        self.smoke['firebaseCrashlyticsInitialized'] = False
        write_json(self.docs / 'signed-release-smoke.json', self.smoke)
        self.assertFalse(reconcile_runtime_evidence(self.docs, 'new'))

    def test_cloud_startup_is_scoped_and_cannot_unlock_direct_packet_gate(self):
        summary = read_json(self.docs / 'verification-summary.json')
        summary['universalApkSha256'] = 'uploaded'
        write_json(self.docs / 'verification-summary.json', summary)
        cloud = {
            'sourceBundleSha256': 'new', 'uploadedApkSha256': 'uploaded',
            'uploadMd5VerifiedByGoogleCloudStorage': True,
            'matrixId': 'matrix-recorded', 'matrixState': 'FINISHED',
            'outcome': 'SUCCESS', 'roboMode': 'ROBO_VERSION_1',
            'pageSizeByCatalogModel': 16384, 'loginScreenVisuallyVerified': True,
            'firebaseInitialized': True, 'firebaseCrashlyticsInitialized': True,
            'firebaseRegistrarErrorsAbsent': True,
            'fatalExceptionsAbsentInRunLog': True,
        }
        write_json(self.docs / 'current-testlab-startup.json', cloud)
        self.assertFalse(reconcile_runtime_evidence(self.docs, 'new'))
        summary = read_json(self.docs / 'verification-summary.json')
        self.assertTrue(summary['nativeRuntimeTested'])
        self.assertTrue(summary['cloudSignedApkStartupVerified'])
        self.assertFalse(summary['signedReleaseStartupSmokePassed'])
        bundle = read_json(self.docs / 'bundle-verification.json')
        self.assertTrue(bundle['cloudRuntime16KbStartupVerified'])
        self.assertFalse(bundle['runtime16KbVerified'])

        cloud['uploadedApkSha256'] = 'different-apk'
        write_json(self.docs / 'current-testlab-startup.json', cloud)
        self.assertFalse(reconcile_runtime_evidence(self.docs, 'new'))
        self.assertFalse(read_json(self.docs / 'verification-summary.json')[
            'cloudSignedApkStartupVerified'])
        cloud['uploadedApkSha256'] = 'uploaded'
        write_json(self.docs / 'current-testlab-startup.json', cloud)

        # New APKs may not inherit a previous cloud run's startup claim.
        write_json(self.docs / 'bundle-verification.json', {'sha256': 'later'})
        self.assertFalse(reconcile_runtime_evidence(self.docs, 'later'))
        summary = read_json(self.docs / 'verification-summary.json')
        self.assertFalse(summary['nativeRuntimeTested'])
        self.assertFalse(summary['cloudSignedApkStartupVerified'])

    def test_resigning_cloud_mode_cannot_prove_signed_candidate_startup(self):
        summary = read_json(self.docs / 'verification-summary.json')
        summary['universalApkSha256'] = 'uploaded'
        write_json(self.docs / 'verification-summary.json', summary)
        write_json(self.docs / 'current-testlab-startup.json', {
            'sourceBundleSha256': 'new', 'uploadedApkSha256': 'uploaded',
            'uploadMd5VerifiedByGoogleCloudStorage': True,
            'matrixId': 'matrix-recorded', 'matrixState': 'FINISHED',
            'outcome': 'SUCCESS', 'roboMode': 'ROBO_VERSION_2',
            'pageSizeByCatalogModel': 16384, 'loginScreenVisuallyVerified': True,
            'firebaseInitialized': True, 'firebaseCrashlyticsInitialized': True,
            'firebaseRegistrarErrorsAbsent': True,
            'fatalExceptionsAbsentInRunLog': True,
        })
        self.assertFalse(reconcile_runtime_evidence(self.docs, 'new'))
        self.assertFalse(read_json(self.docs / 'verification-summary.json')[
            'cloudSignedApkStartupVerified'])

    def test_same_bundle_with_different_apk_invalidates_startup(self):
        self.smoke['sourceBundleSha256'] = 'new'
        write_json(self.docs / 'signed-release-smoke.json', self.smoke)
        summary = read_json(self.docs / 'verification-summary.json')
        summary['universalApkSha256'] = 'replacement'
        write_json(self.docs / 'verification-summary.json', summary)
        self.assertFalse(reconcile_runtime_evidence(self.docs, 'new'))
        self.assertFalse(read_json(self.docs / 'verification-summary.json')['signedReleaseStartupSmokePassed'])

    def test_functional_flags_cannot_survive_changed_bundle_or_apk(self):
        record = {'sourceBundleSha256': 'new', 'installedApkSha256': 'apk',
                  'success': True, 'matrixOutcome': 'SUCCESS', 'physicalDevice': True,
                  'nativePasswordSignIn': True, 'coreNavigationOpened': True,
                  'secondAccountOwnDataVisible': True, 'previousAccountDataAbsent': True,
                  'serverVerification': [{'nativeSavedTaskOnServer': True}]}
        path = self.docs / 'current-native-physical-flows.json'
        write_json(path, record)
        reconcile_runtime_evidence(self.docs, 'new')
        self.assertTrue(read_json(self.docs / 'verification-summary.json')['physicalNativeTaskPersistenceVerified'])
        for key in ['sourceBundleSha256', 'installedApkSha256', 'matrixOutcome']:
            with self.subTest(changed=key):
                changed = {**record, key: 'different'}
                write_json(path, changed)
                reconcile_runtime_evidence(self.docs, 'new')
                summary = read_json(self.docs / 'verification-summary.json')
                self.assertFalse(summary['physicalNativeTaskPersistenceVerified'])
                self.assertFalse(summary['physicalDeviceTested'])

    def test_expected_crash_needs_passing_junit_and_received_report(self):
        record = {'sourceBundleSha256': 'new', 'installedApkSha256': 'apk',
                  'success': True, 'matrixOutcome': 'FAILURE',
                  'matrixFailureExpectedFromControlledCrash': True,
                  'junitTestsPassed': 1, 'junitFailures': 0,
                  'explicitDiagnosticsOptInBeforeCrash': True,
                  'postCrashRestartSucceeded': True, 'diagnosticsDisabledAfterTest': True,
                  'serverReportVerification': {'receivedByCrashlytics': True}}
        path = self.docs / 'current-native-location-diagnostics.json'
        write_json(path, record)
        reconcile_runtime_evidence(self.docs, 'new')
        self.assertTrue(read_json(self.docs / 'verification-summary.json')['controlledCrashlyticsServerReceiptVerified'])
        for changed in [{**record, 'junitFailures': 1},
                        {**record, 'serverReportVerification': {'receivedByCrashlytics': False}}]:
            write_json(path, changed)
            reconcile_runtime_evidence(self.docs, 'new')
            self.assertFalse(read_json(self.docs / 'verification-summary.json')['controlledCrashlyticsServerReceiptVerified'])


if __name__ == '__main__':
    unittest.main()
