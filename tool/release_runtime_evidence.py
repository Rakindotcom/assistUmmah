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


def reconcile_runtime_evidence(docs: Path, bundle_sha256: str) -> bool:
    """Accept runtime proof only if it names this exact verified bundle."""
    smoke_path = docs / 'signed-release-smoke.json'
    smoke = read_json(smoke_path) if smoke_path.exists() else None
    current = bool(smoke and smoke.get('sourceBundleSha256') == bundle_sha256
                   and smoke.get('productionReleaseBinary')
                   and smoke.get('installedApkHashMatches')
                   and smoke.get('loginScreenVisibleInAccessibilityTree')
                   and smoke.get('firebaseInitialized')
                   and smoke.get('firebaseCrashlyticsInitialized')
                   and smoke.get('firebaseRegistrarErrorsAbsent')
                   and smoke.get('pageSize') == 16384)
    cloud_path = docs / 'current-testlab-startup.json'
    cloud = read_json(cloud_path) if cloud_path.exists() else None
    summary_path = docs / 'verification-summary.json'
    summary = read_json(summary_path)
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
    environment['productionRuntimeScope'] = (
        'Fresh signed universal APK startup and login accessibility tree on the dedicated 16 KB emulator.'
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
            'Profile audit and captures belong to a prior app build; '
            'the current signed bundle runtime is unverified.')
    else:
        summary['nativeEvidenceScope'] = (
            'Current signed bundle startup/login passed on the dedicated 16 KB emulator; '
            'profile audit and captures belong to a prior app build.')
    write_json(summary_path, summary)
    return current
