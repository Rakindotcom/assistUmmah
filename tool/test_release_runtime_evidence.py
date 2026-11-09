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

    def test_timezone_claims_require_current_successful_native_receipt(self):
        record = {'sourceBundleSha256': 'new', 'installedApkSha256': 'apk',
                  'success': True, 'matrixOutcome': 'SUCCESS',
                  'dailyZoneIsolatedFromPrayerDatabase': True,
                  'deviceTimezoneRefreshWithoutProcessRestart': True}
        path = self.docs / 'current-native-timezone.json'
        write_json(path, record)
        reconcile_runtime_evidence(self.docs, 'new')
        summary = read_json(self.docs / 'verification-summary.json')
        self.assertTrue(summary['nativeDailyTimezoneIsolationVerified'])
        self.assertTrue(summary['nativeDailyTimezoneRefreshVerified'])
        for key in ['sourceBundleSha256', 'installedApkSha256', 'matrixOutcome',
                    'deviceTimezoneRefreshWithoutProcessRestart']:
            with self.subTest(changed=key):
                write_json(path, {**record, key: False})
                reconcile_runtime_evidence(self.docs, 'new')
                self.assertFalse(read_json(self.docs / 'verification-summary.json')[
                    'nativeDailyTimezoneRefreshVerified'])

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


    def test_natural_delivery_requires_observed_alarm_and_unchanged_clock(self):
        record = {'sourceBundleSha256': 'new', 'installedApkSha256': 'apk',
                  'success': True, 'matrixOutcome': 'SUCCESS', 'junitTestsPassed': 1,
                  'junitFailures': 0, 'junitErrors': 0,
                  'dailyNativeAlarmRegistered': True, 'naturalClockNotificationPosted': True,
                  'wallClockAdvanceAbsent': True, 'notificationOrBroadcastInjectionAbsent': True,
                  'forcedDeepDozeConfirmed': True, 'deepDozeStateAtObservation': 'IDLE',
                  'registeredDailyDueEpochMillis': 100000, 'observationAtEpochMillis': 112000,
                  'observedDelayAfterDueMillis': 12000}
        path = self.docs / 'current-native-lifecycle.json'
        write_json(path, record)
        reconcile_runtime_evidence(self.docs, 'new')
        summary = read_json(self.docs / 'verification-summary.json')
        self.assertTrue(summary['nativeNaturalClockDailyDeliveryVerified'])
        self.assertTrue(summary['nativeForcedDozeDeliveryVerified'])
        for key, value in [('naturalClockNotificationPosted', False),
                           ('wallClockAdvanceAbsent', False), ('junitFailures', 1),
                           ('installedApkSha256', 'other'), ('observedDelayAfterDueMillis', 0),
                           ('observationAtEpochMillis', 90000)]:
            with self.subTest(changed=key):
                write_json(path, {**record, key: value})
                reconcile_runtime_evidence(self.docs, 'new')
                summary = read_json(self.docs / 'verification-summary.json')
                self.assertFalse(summary['nativeNaturalClockDailyDeliveryVerified'])
                self.assertFalse(summary['nativeForcedDozeDeliveryVerified'])
        # A notification after the device left Doze proves only the natural-clock case.
        write_json(path, {**record, 'deepDozeStateAtObservation': 'ACTIVE'})
        reconcile_runtime_evidence(self.docs, 'new')
        summary = read_json(self.docs / 'verification-summary.json')
        self.assertTrue(summary['nativeNaturalClockDailyDeliveryVerified'])
        self.assertFalse(summary['nativeForcedDozeDeliveryVerified'])

    def test_prayer_permission_flags_require_registered_alarm_window_counts(self):
        record = {'sourceBundleSha256': 'new', 'installedApkSha256': 'apk',
                  'success': True, 'matrixOutcome': 'SUCCESS', 'junitTestsPassed': 1,
                  'junitFailures': 0, 'junitErrors': 0,
                  'nativeExactAccessRequestRefused': True,
                  'nativePrayerInexactFallbackRegistered': True,
                  'nativeExactAccessGrantedThroughOs': True,
                  'nativePrayerExactSchedulingAfterGrant': True,
                  'nativeExactAccessRevokedThroughOs': True,
                  'nativePrayerInexactFallbackAfterRevocation': True,
                  'nativePrayerOptOutCancelsAlarms': True,
                  'deniedNativeAlarmCount': 48, 'deniedExactNativeAlarmCount': 0,
                  'grantedNativeAlarmCount': 48, 'grantedExactNativeAlarmCount': 47,
                  'revokedNativeAlarmCount': 48, 'revokedExactNativeAlarmCount': 0}
        path = self.docs / 'current-native-prayer-permissions.json'
        write_json(path, record)
        reconcile_runtime_evidence(self.docs, 'new')
        summary = read_json(self.docs / 'verification-summary.json')
        self.assertTrue(summary['nativePrayerInexactDenialFallbackVerified'])
        self.assertTrue(summary['nativePrayerExactGrantVerified'])
        self.assertTrue(summary['nativePrayerExactRevocationRecoveryVerified'])
        for key, flag, value in [
            ('deniedExactNativeAlarmCount', 'nativePrayerInexactDenialFallbackVerified', 1),
            ('grantedExactNativeAlarmCount', 'nativePrayerExactGrantVerified', 0),
            ('revokedExactNativeAlarmCount', 'nativePrayerExactRevocationRecoveryVerified', 1),
            ('deniedNativeAlarmCount', 'nativePrayerInexactDenialFallbackVerified', 0),
            ('grantedExactNativeAlarmCount', 'nativePrayerExactGrantVerified', True),
        ]:
            with self.subTest(changed=key):
                write_json(path, {**record, key: value})
                reconcile_runtime_evidence(self.docs, 'new')
                self.assertFalse(read_json(self.docs / 'verification-summary.json')[flag])


    def test_complete_suite_requires_new_permission_case_and_current_binary(self):
        record = {'sourceBundleSha256': 'new', 'installedApkSha256': 'apk',
                  'success': True, 'matrixOutcome': 'SUCCESS',
                  **{name: True for name in ['full', 'reminders', 'location',
                      'delivery', 'timezone', 'prayerpermissions', 'deletion']}}
        path = self.docs / 'current-native-suite.json'
        write_json(path, record)
        reconcile_runtime_evidence(self.docs, 'new')
        self.assertTrue(read_json(self.docs / 'verification-summary.json')['currentNativeReleaseSuitePassed'])
        for key, value in [('prayerpermissions', False), ('installedApkSha256', 'old'),
                           ('sourceBundleSha256', 'old'), ('matrixOutcome', 'FAILURE')]:
            with self.subTest(changed=key):
                write_json(path, {**record, key: value})
                reconcile_runtime_evidence(self.docs, 'new')
                self.assertFalse(read_json(self.docs / 'verification-summary.json')['currentNativeReleaseSuitePassed'])


if __name__ == '__main__':
    unittest.main()
