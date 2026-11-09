"""Keep bundle, emulator and release-smoke claims tied to the same binary."""
import json
import os
from pathlib import Path
import tempfile


def read_json(path: Path) -> dict:
    return json.loads(path.read_text())


def write_json(path: Path, value: dict) -> None:
    """Replace one evidence file atomically; packet creation checks all files agree."""
    with tempfile.NamedTemporaryFile('w', encoding='utf-8', dir=path.parent,
                                     prefix=f'.{path.name}.', delete=False) as stream:
        temp = Path(stream.name)
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    try:
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


# Each flag has a named, scoped device receipt. Missing or stale evidence is false.
SCOPED_CLAIMS = {
    'current-controlled-startup.json': {
        'independentDeviceApkHashVerified': ('installedApkHashMatches',),
        'bundledPrivacyNativeVerified': ('bundledPrivacyVisible',),
        'nativeSystemBackVerified': ('systemBackFromPrivacy',),
    },
    'current-native-flows.json': {
        'nativeLoginFormSubmitted': ('nativePasswordSignIn',),
        'nativePasswordLoginVerified': ('nativePasswordSignIn',),
        'nativeTaskPersistenceVerified': ('serverVerification.0.nativeSavedTaskOnServer',),
        'nativeAccountSwitchIsolationVerified': ('secondAccountOwnDataVisible', 'previousAccountDataAbsent'),
        'nativeNotificationDenialVerified': ('notificationDenialHandled',),
    },
    'current-native-deletion.json': {
        'nativeDeletionRecoveryVerified': ('nativeDeletionReturnsToLogin', 'coldRestartOtherAccountUnaffected'),
        'nativeDeletionRouteRevocationVerified': ('remoteDeletionClosesPrivateDialog', 'backCannotRestorePrivateHome'),
        'nativeDeletionServerCleanupVerified': ('serverVerification.deletedAuthIdentityAbsent', 'serverVerification.legacyActivitiesAbsent'),
    },
    'current-native-legacy.json': {
        'android8StartupVerified': ('installedApkHashMatches', 'loginScreenVisible', 'bundledPrivacyVisible', 'systemBackFromPrivacy'),
    },
    'current-native-physical.json': {
        'physicalStartupVerified': ('physicalDevice', 'installedApkHashMatches', 'loginScreenVisible'),
    },
    'current-native-physical-flows.json': {
        'physicalNativePasswordSignInVerified': ('physicalDevice', 'nativePasswordSignIn'),
        'physicalNativeTaskPersistenceVerified': ('physicalDevice', 'serverVerification.0.nativeSavedTaskOnServer'),
        'physicalNativeAccountIsolationVerified': ('physicalDevice', 'secondAccountOwnDataVisible', 'previousAccountDataAbsent'),
        'physicalCoreNavigationVerified': ('physicalDevice', 'coreNavigationOpened'),
    },
    'current-native-reminders.json': {
        'nativeNotificationPermissionGrantVerified': ('nativeNotificationPermissionAllowed',),
        'nativeDailyAlarmRegistrationVerified': ('nativeDailyAlarmScheduled',),
        'nativeSignOutAlarmCancellationVerified': ('nativeSignOutCancelsAlarms',),
        'nativeDiagnosticsConsentPersistenceVerified': ('diagnosticsEnabledByExplicitToggle', 'diagnosticsConsentSurvivesRestart', 'diagnosticsDisabledAgain'),
    },
    'current-native-timezone.json': {
        'nativeDailyTimezoneIsolationVerified': ('dailyZoneIsolatedFromPrayerDatabase',),
        'nativeDailyTimezoneRefreshVerified': ('deviceTimezoneRefreshWithoutProcessRestart',),
    },
    'current-native-delivery.json': {
        'controlledClockNativeNotificationDeliveryVerified': ('nativeNotificationShadeDelivery', 'wallClockAdvancedPastInexactWindow'),
        'nativeNotificationOsRevocationVerified': ('notificationPermissionRevokedThroughOs', 'optOutAfterOsRevocationCancelsAlarms'),
    },
    'current-native-location-diagnostics.json': {
        'nativeLocationDenialVerified': ('locationPermissionDenialHandled',),
        'nativeManualLocationFallbackVerified': ('manualLocationSavedWithoutPermission',),
        'controlledCrashlyticsServerReceiptVerified': ('serverReportVerification.receivedByCrashlytics', 'explicitDiagnosticsOptInBeforeCrash', 'diagnosticsDisabledAfterTest'),
        'nativePostCrashRestartVerified': ('postCrashRestartSucceeded',),
    },
}


def _proved(record: dict, path: str) -> bool:
    value = record
    for part in path.split('.'):
        if isinstance(value, dict):
            value = value.get(part)
        elif isinstance(value, list) and part.isdigit() and int(part) < len(value):
            value = value[int(part)]
        else:
            return False
    return value is True


def reconcile_functional_evidence(docs: Path, bundle_sha256: str, summary: dict) -> None:
    apk_sha256 = summary.get('universalApkSha256')
    evidence = {}
    for filename, claims in SCOPED_CLAIMS.items():
        path = docs / filename
        record = read_json(path) if path.exists() else {}
        passed = record.get('matrixOutcome') == 'SUCCESS'
        if filename == 'current-native-location-diagnostics.json':
            # A deliberate app crash fails the provider matrix, while JUnit and
            # an independently received, correlated report establish this case.
            passed = passed or bool(
                record.get('matrixOutcome') == 'FAILURE'
                and record.get('matrixFailureExpectedFromControlledCrash') is True
                and record.get('junitTestsPassed', 0) >= 1
                and record.get('junitFailures') == 0
                and _proved(record, 'explicitDiagnosticsOptInBeforeCrash')
                and _proved(record, 'postCrashRestartSucceeded')
                and _proved(record, 'diagnosticsDisabledAfterTest')
                and _proved(record, 'serverReportVerification.receivedByCrashlytics'))
        current = bool(apk_sha256 and record.get('sourceBundleSha256') == bundle_sha256
                       and record.get('installedApkSha256') == apk_sha256
                       and record.get('success') is True and passed)
        evidence[filename] = {'current': current, 'scope': record.get('scope') if current else None}
        for flag, fields in claims.items():
            summary[flag] = current and all(_proved(record, field) for field in fields)
    controlled = evidence['current-controlled-startup.json']['current']
    record = read_json(docs / 'current-controlled-startup.json') if controlled else {}
    summary['devicePageSizeSyscallVerified'] = bool(controlled and record.get('pageSize') == 16384
                                                  and record.get('measurementProcess') == 'com.rakindotcom.ummah_assist.release_harness')
    summary['physicalDeviceTested'] = bool(summary['physicalStartupVerified']
                                         or summary['physicalCoreNavigationVerified'])
    summary['nativeFunctionalEvidence'] = evidence
    inventory_path = docs / 'current-store-captures/export-verification.json'
    inventory = read_json(inventory_path) if inventory_path.exists() else {}
    summary['currentStorePhoneScreenshots'] = (
        len(inventory.get('screens', [])) if apk_sha256
        and inventory.get('sourceBundleSha256') == bundle_sha256
        and inventory.get('sourceApkSha256') == apk_sha256 else 0)


def reconcile_runtime_evidence(docs: Path, bundle_sha256: str) -> bool:
    """Accept runtime proof only if it names this exact verified bundle."""
    smoke_path = docs / 'signed-release-smoke.json'
    smoke = read_json(smoke_path) if smoke_path.exists() else None
    summary_path = docs / 'verification-summary.json'
    summary = read_json(summary_path)
    current = bool(smoke and summary.get('universalApkSha256')
                   and smoke.get('universalApkSha256') == summary.get('universalApkSha256')
                   and smoke.get('sourceBundleSha256') == bundle_sha256
                   and smoke.get('productionReleaseBinary')
                   and smoke.get('installedApkHashMatches')
                   and smoke.get('loginScreenVisibleInAccessibilityTree')
                   and smoke.get('firebaseInitialized')
                   and smoke.get('firebaseCrashlyticsInitialized')
                   and smoke.get('firebaseRegistrarErrorsAbsent')
                   and smoke.get('pageSize') == 16384)
    cloud_path = docs / 'current-testlab-startup.json'
    cloud = read_json(cloud_path) if cloud_path.exists() else None
    cloud_current = bool(
        cloud and cloud.get('sourceBundleSha256') == bundle_sha256
        and cloud.get('uploadedApkSha256')
        and cloud.get('uploadedApkSha256') == summary.get('universalApkSha256')
        and cloud.get('uploadMd5VerifiedByGoogleCloudStorage')
        and cloud.get('matrixId') and cloud.get('matrixState') == 'FINISHED'
        and cloud.get('outcome') == 'SUCCESS'
        and cloud.get('roboMode') == 'ROBO_VERSION_1'
        and cloud.get('pageSizeByCatalogModel') == 16384
        and cloud.get('loginScreenVisuallyVerified')
        and cloud.get('firebaseInitialized')
        and cloud.get('firebaseCrashlyticsInitialized')
        and cloud.get('firebaseRegistrarErrorsAbsent')
        and cloud.get('fatalExceptionsAbsentInRunLog'))
    if smoke is not None:
        smoke['currentBundleVerified'] = current
        if current:
            smoke.pop('supersededByBundleSha256', None)
        else:
            smoke['supersededByBundleSha256'] = bundle_sha256
        write_json(smoke_path, smoke)

    bundle_path = docs / 'bundle-verification.json'
    bundle = read_json(bundle_path)
    assert bundle['sha256'] == bundle_sha256, 'Bundle evidence changed during reconciliation'
    bundle['runtime16KbVerified'] = current
    bundle['cloudRuntime16KbStartupVerified'] = cloud_current
    write_json(bundle_path, bundle)

    environment_path = docs / 'android-emulator-environment.json'
    environment = read_json(environment_path)
    environment['productionAppRuntimeVerified'] = current
    environment['cloudProductionStartupVerified'] = cloud_current
    environment['productionRuntimeBundleSha256'] = bundle_sha256 if current else None
    environment['productionRuntimeEnvironment'] = ({
        'provider': smoke.get('provider', 'local Android emulator'),
        'architecture': smoke.get('architecture'),
        'androidApi': smoke.get('androidApi'),
        'pageSize': smoke.get('pageSize'),
    } if current else None)
    environment['productionRuntimeScope'] = (
        smoke.get('scope', 'Fresh signed universal APK startup and login accessibility tree on the dedicated 16 KB emulator.')
        if current else (
            'Current candidate startup passed in Firebase Test Lab; independent '
            'installed-hash and page-size-syscall proof remains absent.'
            if cloud_current else 'Current signed bundle has no successful native runtime smoke.'))
    write_json(environment_path, environment)

    summary['bundleSha256'] = bundle_sha256
    summary['nativeRuntimeTested'] = current or cloud_current
    summary['cloudSignedApkStartupVerified'] = cloud_current
    summary['signedReleaseStartupSmokePassed'] = current
    summary['signedReleaseLoginVisible'] = current
    summary['firebaseRegistrarErrorsAbsent'] = current
    summary['priorRuntimeEvidenceAvailable'] = smoke is not None
    if cloud_current and not current:
        summary['nativeEvidenceScope'] = (
            'Current signed APK startup/login visually verified in ARM64 / 16 KB '
            'Firebase Test Lab using upload checksum and no-resigning mode. '
            'Independent installed APK hash and page-size syscall were not read; '
            'the stricter direct runtime receipt and full signed-in flows remain open.')
    elif not current:
        summary['nativeEvidenceScope'] = (
            'The current signed bundle has no matching 16 KB startup proof. '
            'Other device passes are tracked separately in nativeFunctionalEvidence.')
    else:
        summary['nativeEvidenceScope'] = (
            smoke.get('scope',
                      'Current signed bundle startup/login passed on the dedicated 16 KB emulator; '
                      'profile audit and captures belong to a prior app build.'))
    summary['nativeStartupEvidenceScope'] = summary['nativeEvidenceScope']
    reconcile_functional_evidence(docs, bundle_sha256, summary)
    startup_folder = docs / 'current-native-startup'
    capture_names = (['device-details.png', 'sign-in.png'] if cloud_current else [])
    if summary['nativeFunctionalEvidence']['current-controlled-startup.json']['current']:
        capture_names += ['controlled-01-sign-in.png', 'controlled-02-privacy.png']
    summary['currentNativeStartupCaptureCount'] = sum((startup_folder / name).is_file() for name in capture_names)
    matching = [name for name, proof in summary['nativeFunctionalEvidence'].items() if proof['current']]
    if matching:
        summary['nativeRuntimeTested'] = True
        summary['nativeEvidenceScope'] = (
            ('Matching startup/16 KB proof and scoped native functional receipts are available. '
             if current else 'Scoped native functional receipts match this candidate; the stronger startup/16 KB gate remains open. ')
            + 'See nativeFunctionalEvidence for per-run scope and limits: ' + ', '.join(matching) + '.')
    write_json(summary_path, summary)
    return current
