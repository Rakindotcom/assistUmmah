package com.rakindotcom.ummah_assist.release_harness;

import static org.junit.Assert.*;

import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.system.Os;
import android.system.OsConstants;

import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.By;
import androidx.test.uiautomator.Configurator;
import androidx.test.uiautomator.UiDevice;
import androidx.test.uiautomator.UiObject2;

import org.json.JSONObject;
import org.junit.Test;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Locale;

/** Black-box UI checks against the original signed production APK. */
public final class SignedReleaseAuditTest {
    private static final String APP = "com.rakindotcom.ummah_assist";
    private final JSONObject report = new JSONObject();
    private UiDevice device;
    private File output;
    private String stage = "initialization";

    @Test
    public void auditOriginalSignedApk() throws Exception {
        Context target = InstrumentationRegistry.getInstrumentation().getTargetContext();
        Bundle args = InstrumentationRegistry.getArguments();
        output = new File(target.getExternalFilesDir(null), "release-audit");
        assertTrue("Cannot create audit output", output.mkdirs() || output.isDirectory());
        device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
        Configurator.getInstance().setWaitForIdleTimeout(500);
        try {
            stage = "artifact identity";
            assertEquals("Runner must remain outside the production process",
                    APP + ".release_harness", target.getPackageName());
            PackageInfo info = target.getPackageManager().getPackageInfo(APP, 0);
            String expected = required(args, "expectedApkSha256");
            String actual = sha256(new File(target.getPackageManager()
                    .getApplicationInfo(APP, 0).sourceDir));
            report.put("installedApkSha256", actual);
            report.put("expectedApkSha256", expected);
            report.put("package", APP);
            report.put("versionName", info.versionName);
            long versionCode = Build.VERSION.SDK_INT >= 28 ? info.getLongVersionCode() : info.versionCode;
            report.put("versionCode", versionCode);
            report.put("androidApi", Build.VERSION.SDK_INT);
            report.put("architecture", Build.SUPPORTED_ABIS[0]);
            report.put("pageSize", Os.sysconf(OsConstants._SC_PAGESIZE));
            report.put("measurementProcess", target.getPackageName());
            assertEquals("Installed APK bytes differ from the release artifact", expected, actual);
            assertEquals("Unexpected release version", Long.parseLong(required(args, "expectedVersionCode")), versionCode);
            if (args.containsKey("expectedPageSize")) {
                assertEquals("Unexpected native page size", Long.parseLong(args.getString("expectedPageSize")),
                        Os.sysconf(OsConstants._SC_PAGESIZE));
            }
            report.put("installedApkHashMatches", true);
            stage = "signed-out startup";
            Intent launch = target.getPackageManager().getLaunchIntentForPackage(APP);
            assertNotNull("Missing launcher activity", launch);
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
            target.startActivity(launch);
            waitLabel("লগইন", 60000);
            report.put("loginScreenVisible", true);
            capture("01-sign-in");

            stage = "bundled privacy";
            clickLabel("গোপনীয়তা নীতি");
            waitLabel("আমাদের পরিচয় ও যোগাযোগ", 15000);
            report.put("bundledPrivacyVisible", true);
            capture("02-privacy");
            device.pressBack();
            waitLabel("লগইন", 10000);
            report.put("systemBackFromPrivacy", true);
            report.put("success", true);
            writeReport();
        } catch (Throwable failure) {
            report.put("success", false);
            report.put("failedStage", stage);
            report.put("failureType", failure.getClass().getSimpleName());
            writeReport();
            try { capture("failure-private"); } catch (Throwable ignored) { }
            // Do not leak credentials or entered field values through assertions.
            throw new AssertionError("Release audit failed at " + stage + " (" +
                    failure.getClass().getSimpleName() + "). Inspect private artifacts.");
        }
    }

    static String required(Bundle args, String key) {
        String value = args.getString(key);
        assertNotNull("Missing audit argument: " + key, value);
        assertFalse("Empty audit argument: " + key, value.isEmpty());
        return value;
    }

    private UiObject2 waitLabel(String label, long timeout) {
        long deadline = SystemClock.uptimeMillis() + timeout;
        do {
            UiObject2 node = device.findObject(By.text(label));
            if (node == null) node = device.findObject(By.desc(label));
            if (node != null) return node;
            SystemClock.sleep(200);
        } while (SystemClock.uptimeMillis() < deadline);
        throw new AssertionError("Missing required UI label during " + stage);
    }

    private void clickLabel(String label) { waitLabel(label, 10000).click(); }

    private void capture(String name) throws Exception {
        assertTrue("Screenshot capture failed", device.takeScreenshot(new File(output, name + ".png")));
        device.dumpWindowHierarchy(new File(output, name + ".xml"));
    }

    private void writeReport() throws Exception {
        try (FileOutputStream stream = new FileOutputStream(new File(output, "receipt.json"))) {
            stream.write((report.toString(2) + "\n").getBytes(StandardCharsets.UTF_8));
        }
    }

    static String sha256(File path) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (FileInputStream stream = new FileInputStream(path)) {
            byte[] buffer = new byte[65536];
            int count;
            while ((count = stream.read(buffer)) != -1) digest.update(buffer, 0, count);
        }
        StringBuilder hex = new StringBuilder();
        for (byte b : digest.digest()) hex.append(String.format(Locale.ROOT, "%02x", b & 255));
        return hex.toString();
    }
}
