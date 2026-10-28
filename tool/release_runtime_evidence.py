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
    write_json(bundle_path, bundle)

    environment_path = docs / 'android-emulator-environment.json'
    environment = read_json(environment_path)
    environment['productionAppRuntimeVerified'] = current
    environment['productionRuntimeBundleSha256'] = bundle_sha256 if current else None
    environment['productionRuntimeScope'] = (
        'Fresh signed universal APK startup and login accessibility tree on the dedicated 16 KB emulator.'
        if current else 'Current signed bundle has no successful native runtime smoke.')
    write_json(environment_path, environment)

    summary_path = docs / 'verification-summary.json'
    summary = read_json(summary_path)
    summary['bundleSha256'] = bundle_sha256
    summary['nativeRuntimeTested'] = current
    summary['signedReleaseStartupSmokePassed'] = current
    summary['signedReleaseLoginVisible'] = current
    summary['firebaseRegistrarErrorsAbsent'] = current
    summary['priorRuntimeEvidenceAvailable'] = smoke is not None
    if not current:
        summary['nativeEvidenceScope'] = (
            'Profile audit and captures belong to a prior app build; '
            'the current signed bundle runtime is unverified.')
    else:
        summary['nativeEvidenceScope'] = (
            'Current signed bundle startup/login passed on the dedicated 16 KB emulator; '
            'profile audit and captures belong to a prior app build.')
    write_json(summary_path, summary)
    return current
