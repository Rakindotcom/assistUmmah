package com.rakindotcom.ummah_assist.release_harness;

import static org.junit.Assert.*;
import static com.rakindotcom.ummah_assist.release_harness.SignedReleaseAuditTest.required;

import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
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
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

/** Controlled UI actions against disposable fixture accounts only. */
public final class SignedInReleaseAuditTest {
    private static final String APP = "com.rakindotcom.ummah_assist";
    private final JSONObject report = new JSONObject();
    private UiDevice device;
    private Context context;
    private File output;
    private String stage = "initialization";
    private boolean reminderNoticeDismissed;

    @Test
    public void signedInIsolationAndPermissions() throws Exception {
        Bundle args = InstrumentationRegistry.getArguments();
        context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
        Configurator.getInstance().setWaitForIdleTimeout(300);
        output = new File(context.getExternalFilesDir(null), "release-audit");
        assertTrue(output.mkdirs() || output.isDirectory());
        try {
            stage = "artifact identity";
            String hash = SignedReleaseAuditTest.sha256(new File(context.getPackageManager().getApplicationInfo(APP, 0).sourceDir));
            assertEquals(required(args, "expectedApkSha256"), hash);
            report.put("installedApkSha256", hash);
            report.put("pageSize", Os.sysconf(OsConstants._SC_PAGESIZE));
            assertEquals(Long.parseLong(required(args, "expectedPageSize")), Os.sysconf(OsConstants._SC_PAGESIZE));
            Intent launch = context.getPackageManager().getLaunchIntentForPackage(APP);
            assertNotNull(launch);
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
            context.startActivity(launch);

            stage = "fixture A sign-in";
            signIn(required(args, "accountAEmail"), required(args, "accountAPassword"));
            report.put("nativePasswordSignIn", true);
            capture("03-home");

            stage = "fixture A task read";
            nav("কাজ");
            reveal(required(args, "accountATask"));
            report.put("accountATaskVisible", true);
            capture("04-tasks");

            stage = "task save";
            reveal("কাজ যোগ").click();
            waitLabel("নতুন কাজ যোগ করুন", 10000);
            List<UiObject2> editors = editors();
            assertFalse(editors.isEmpty());
            editors.get(0).setText("Native audit saved task");
            dismissKeyboardIfShown();
            click("যোগ করুন");
            waitAbsent("নতুন কাজ যোগ করুন", 30000);
            reveal("Native audit saved task");
            report.put("nativeTaskSaveVisible", true);

            stage = "core navigation";
            nav("নামাজ"); waitLabel("নামাজ ট্র্যাকিং", 30000); capture("05-prayer");
            nav("গ্রোথ"); waitLabel("গ্রোথ চেকলিস্ট", 30000); capture("06-growth");
            nav("আরও"); reveal("কুরআন রিডিং"); capture("07-more");
            stage = "Quran navigation";
            reveal("কুরআন রিডিং").click(); waitLabel("কুরআন রিডিং", 20000); capture("08-quran");
            nav("আরও"); reveal("যিকিরের লক্ষ্য").click();
            stage = "tasbih navigation";
            waitContains("যিকিরসমূহ", 20000); capture("09-dhikr");
            report.put("coreNavigationOpened", true);

            stage = "native permission denial";
            nav("আরও"); reveal("সেটিংস ও রিপোর্ট").click();
            UiObject2 reminders = reveal("দৈনিক রিমাইন্ডার");
            assertEquals(PackageManager.PERMISSION_DENIED,
                    context.getPackageManager().checkPermission("android.permission.POST_NOTIFICATIONS", APP));
            reminders.click();
            long deadline = SystemClock.uptimeMillis() + 15000;
            UiObject2 deny = null;
            while (deny == null && SystemClock.uptimeMillis() < deadline) {
                deny = device.findObject(By.res(Pattern.compile(".*:id/permission_deny_button")));
                SystemClock.sleep(200);
            }
            assertNotNull("Expected Android notification permission dialog", deny);
            deny.click();
            waitContains("রিমাইন্ডার চালু করতে নোটিফিকেশন অনুমতি দিন", 10000);
            assertEquals(PackageManager.PERMISSION_DENIED,
                    context.getPackageManager().checkPermission("android.permission.POST_NOTIFICATIONS", APP));
            report.put("notificationDenialHandled", true);

            stage = "fixture A sign-out";
            signOut();
            report.put("nativeSignOut", true);
            stage = "fixture B sign-in and isolation";
            signIn(required(args, "accountBEmail"), required(args, "accountBPassword"));
            nav("কাজ");
            reveal(required(args, "accountBTask"));
            assertNull(find(required(args, "accountATask"), true));
            assertNull(find("Native audit saved task", true));
            report.put("secondAccountOwnDataVisible", true);
            report.put("previousAccountDataAbsent", true);
            capture("10-other-account-tasks");
            stage = "fixture B sign-out";
            nav("আরও"); reveal("সেটিংস ও রিপোর্ট").click(); signOut();
            report.put("secondAccountSignOut", true);
            report.put("success", true);
            save();
        } catch (Throwable failure) {
            report.put("success", false); report.put("failedStage", stage);
            report.put("failureType", failure.getClass().getSimpleName()); save();
            try {capture("failure-private");} catch (Throwable ignored) { }
            throw new AssertionError("Native flow audit failed at " + stage + " (" + failure.getClass().getSimpleName() + "). Inspect private artifacts.");
        }
    }

    @Test
    public void remindersConsentAndNativeCaptures() throws Exception {
        Bundle args = InstrumentationRegistry.getArguments();
        context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
        Configurator.getInstance().setWaitForIdleTimeout(300);
        output = new File(context.getExternalFilesDir(null), "release-audit");
        assertTrue(output.mkdirs() || output.isDirectory());
        try {
            stage = "artifact identity";
            String hash = SignedReleaseAuditTest.sha256(new File(context.getPackageManager().getApplicationInfo(APP, 0).sourceDir));
            assertEquals(required(args, "expectedApkSha256"), hash); report.put("installedApkSha256", hash);
            // Request a real device viewport with the store's supported 16:9 aspect ratio.
            device.executeShellCommand("wm size 720x1280"); device.executeShellCommand("wm density 320");
            Intent launch = context.getPackageManager().getLaunchIntentForPackage(APP);
            assertNotNull(launch); launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
            context.startActivity(launch);
            stage = "native captures";
            signIn(required(args, "accountAEmail"), required(args, "accountAPassword")); capture("store-01-home");
            nav("নামাজ"); waitLabel("নামাজ ট্র্যাকিং", 30000); capture("store-02-prayer");
            nav("গ্রোথ"); waitLabel("গ্রোথ চেকলিস্ট", 30000); capture("store-03-growth");
            nav("আরও"); reveal("কুরআন রিডিং").click(); waitLabel("কুরআন রিডিং", 20000); capture("store-04-quran");
            nav("আরও"); reveal("যিকিরের লক্ষ্য").click(); waitContains("যিকিরসমূহ", 20000); capture("store-05-dhikr");
            report.put("nativeStoreViewport", "720x1280 at density 320; original screenshots without cropping");
            nav("আরও"); reveal("সেটিংস ও রিপোর্ট").click();
            stage = "daily reminder permission and alarms";
            assertFalse("Unexpected baseline alarm", appAlarmPresent());
            reveal("দৈনিক রিমাইন্ডার").click();
            long deadline = SystemClock.uptimeMillis() + 15000; UiObject2 allow = null;
            while (allow == null && SystemClock.uptimeMillis() < deadline) {
                allow = device.findObject(By.res(Pattern.compile(".*:id/permission_allow_button"))); SystemClock.sleep(200);
            }
            assertNotNull("Expected Android notification permission dialog", allow); allow.click();
            deadline = SystemClock.uptimeMillis() + 20000;
            while (!appAlarmPresent() && SystemClock.uptimeMillis() < deadline) SystemClock.sleep(200);
            assertTrue("No native daily alarm after permission grant", appAlarmPresent());
            assertEquals(PackageManager.PERMISSION_GRANTED, context.getPackageManager().checkPermission("android.permission.POST_NOTIFICATIONS", APP));
            report.put("nativeNotificationPermissionAllowed", true); report.put("nativeDailyAlarmScheduled", true);
            stage = "optional diagnostics off on off";
            UiObject2 diagnostics = reveal("সমস্যার রিপোর্ট পাঠান");
            assertFalse("Diagnostics must default off", diagnostics.isChecked()); diagnostics.click();
            waitChecked("সমস্যার রিপোর্ট পাঠান", true); report.put("diagnosticsEnabledByExplicitToggle", true);
            device.executeShellCommand("am force-stop " + APP); context.startActivity(launch);
            waitLabel("আসসালামু আলাইকুম", 60000); nav("আরও"); reveal("সেটিংস ও রিপোর্ট").click();
            reveal("সমস্যার রিপোর্ট পাঠান");
            waitChecked("সমস্যার রিপোর্ট পাঠান", true); report.put("diagnosticsConsentSurvivesRestart", true);
            reveal("সমস্যার রিপোর্ট পাঠান").click(); waitChecked("সমস্যার রিপোর্ট পাঠান", false);
            report.put("diagnosticsDisabledAgain", true);
            stage = "sign-out cancels native alarms";
            signOut(); deadline = SystemClock.uptimeMillis() + 15000;
            while (appAlarmPresent() && SystemClock.uptimeMillis() < deadline) SystemClock.sleep(200);
            assertFalse("Account alarms remained after sign-out", appAlarmPresent());
            report.put("nativeSignOutCancelsAlarms", true);
            report.put("success", true); save();
        } catch (Throwable failure) {
            report.put("success", false); report.put("failedStage", stage);
            report.put("failureType", failure.getClass().getSimpleName()); save();
            try {capture("failure-private");} catch (Throwable ignored) { }
            throw new AssertionError("Native reminders audit failed at " + stage + " (" + failure.getClass().getSimpleName() + "). Inspect private artifacts.");
        } finally {device.executeShellCommand("wm size reset"); device.executeShellCommand("wm density reset");}
    }

    /** Uses the platform alarm queue and notification shade; never sends a synthetic app broadcast. */
    @Test
    public void scheduledDeliveryAndOsRevocation() throws Exception {
        Bundle args = InstrumentationRegistry.getArguments();
        context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
        Configurator.getInstance().setWaitForIdleTimeout(300);
        output = new File(context.getExternalFilesDir(null), "release-audit");
        assertTrue(output.mkdirs() || output.isDirectory());
        long originalWall = System.currentTimeMillis(), originalElapsed = SystemClock.elapsedRealtime();
        String autoTime = device.executeShellCommand("settings get global auto_time").trim();
        boolean clockChanged = false;
        try {
            stage = "artifact identity";
            String hash = SignedReleaseAuditTest.sha256(new File(context.getPackageManager().getApplicationInfo(APP, 0).sourceDir));
            assertEquals(required(args, "expectedApkSha256"), hash); report.put("installedApkSha256", hash);
            Intent launch = context.getPackageManager().getLaunchIntentForPackage(APP);
            assertNotNull(launch); launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK); context.startActivity(launch);
            signIn(required(args, "accountAEmail"), required(args, "accountAPassword"));
            nav("আরও"); reveal("সেটিংস ও রিপোর্ট").click();
            stage = "notification permission grant";
            reveal("দৈনিক রিমাইন্ডার").click();
            long deadline = SystemClock.uptimeMillis() + 15000; UiObject2 allow = null;
            while (allow == null && SystemClock.uptimeMillis() < deadline) {
                allow = device.findObject(By.res(Pattern.compile(".*:id/permission_allow_button"))); SystemClock.sleep(200);
            }
            assertNotNull("Expected native permission dialog", allow); allow.click();
            deadline = SystemClock.uptimeMillis() + 20000;
            while (!appAlarmPresent() && SystemClock.uptimeMillis() < deadline) SystemClock.sleep(200);
            assertTrue("No registered alarm", appAlarmPresent());
            report.put("nativeDailyAlarmRegistered", true);
            stage = "background OS alarm delivery with controlled wall clock";
            java.util.Calendar due = java.util.Calendar.getInstance();
            due.set(java.util.Calendar.HOUR_OF_DAY, 8); due.set(java.util.Calendar.MINUTE, 0);
            due.set(java.util.Calendar.SECOND, 0); due.set(java.util.Calendar.MILLISECOND, 0);
            if (due.getTimeInMillis() <= System.currentTimeMillis()) due.add(java.util.Calendar.DAY_OF_MONTH, 1);
            long advanced = due.getTimeInMillis() + 70L * 60L * 1000L;
            device.pressHome();
            device.executeShellCommand("settings put global auto_time 0");
            device.executeShellCommand("cmd alarm set-time " + advanced);
            clockChanged = Math.abs(System.currentTimeMillis() - advanced) < 10000;
            assertTrue("Provider did not allow a controlled device clock", clockChanged);
            report.put("wallClockAdvancedPastInexactWindow", true);
            device.openNotification();
            device.waitForIdle(1000); SystemClock.sleep(700);
            deadline = SystemClock.uptimeMillis() + 90000;
            UiObject2 notification = null;
            while (notification == null && SystemClock.uptimeMillis() < deadline) {
                dismissNotificationShadeGuideIfPresent();
                notification = device.findObject(By.text("আজকের কাজ").pkg("com.android.systemui"));
                if (notification == null) SystemClock.sleep(300);
            }
            assertNotNull("Registered reminder did not reach the native notification shade", notification);
            report.put("nativeNotificationShadeDelivery", true);
            report.put("deliveryMethod", "Original app pending alarm dispatched by Android after controlled wall-clock advance; no broadcast/notification injected by harness");
            capture("12-native-notification-delivery");
            device.pressBack();
            device.executeShellCommand("cmd alarm set-time " + (originalWall + SystemClock.elapsedRealtime() - originalElapsed));
            clockChanged = false;
            if (autoTime.matches("[01]")) device.executeShellCommand("settings put global auto_time " + autoTime);
            stage = "OS notification permission revocation";
            device.executeShellCommand("pm revoke " + APP + " android.permission.POST_NOTIFICATIONS");
            assertEquals(PackageManager.PERMISSION_DENIED, context.getPackageManager().checkPermission("android.permission.POST_NOTIFICATIONS", APP));
            report.put("notificationPermissionRevokedThroughOs", true);
            context.startActivity(launch); waitLabel("আসসালামু আলাইকুম", 60000);
            nav("আরও"); reveal("সেটিংস ও রিপোর্ট").click();
            // The saved preference may remain on while OS permission is off. Disable it explicitly.
            reveal("দৈনিক রিমাইন্ডার").click();
            deadline = SystemClock.uptimeMillis() + 15000;
            while (appAlarmPresent() && SystemClock.uptimeMillis() < deadline) SystemClock.sleep(200);
            assertFalse("Alarms survived explicit opt-out after OS revocation", appAlarmPresent());
            report.put("optOutAfterOsRevocationCancelsAlarms", true);
            stage = "native tasbih capture";
            nav("আরও"); reveal("যিকিরের লক্ষ্য").click(); waitLabel("যিকিরসমূহ", 20000);
            device.executeShellCommand("wm size 720x1280"); device.executeShellCommand("wm density 320");
            capture("store-05-dhikr");
            nav("আরও"); reveal("সেটিংস ও রিপোর্ট").click(); signOut();
            report.put("success", true); save();
        } catch (Throwable failure) {
            report.put("success", false); report.put("failedStage", stage); report.put("failureType", failure.getClass().getSimpleName()); save();
            try {capture("failure-private");} catch (Throwable ignored) { }
            throw new AssertionError("Native delivery audit failed at " + stage + " (" + failure.getClass().getSimpleName() + "). Inspect private artifacts.");
        } finally {
            if (clockChanged) device.executeShellCommand("cmd alarm set-time " + (originalWall + SystemClock.elapsedRealtime() - originalElapsed));
            if (autoTime.matches("[01]")) device.executeShellCommand("settings put global auto_time " + autoTime);
            device.executeShellCommand("wm size reset"); device.executeShellCommand("wm density reset");
        }
    }

    /** OS exact-alarm permission transitions using the second disposable account. */
    @Test
    public void prayerExactAlarmPermissionTransitions() throws Exception {
        Bundle args=InstrumentationRegistry.getArguments();
        context=InstrumentationRegistry.getInstrumentation().getTargetContext();
        device=UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
        Configurator.getInstance().setWaitForIdleTimeout(300);
        output=new File(context.getExternalFilesDir(null),"release-audit");
        assertTrue(output.mkdirs()||output.isDirectory());
        String original=device.executeShellCommand("cmd appops get "+APP+" SCHEDULE_EXACT_ALARM");
        java.util.regex.Matcher mode=Pattern.compile("SCHEDULE_EXACT_ALARM: (allow|ignore|deny|default|foreground)").matcher(original);
        String originalMode=mode.find()?mode.group(1):"default";
        try {
            stage="artifact identity";
            String hash=SignedReleaseAuditTest.sha256(new File(context.getPackageManager().getApplicationInfo(APP,0).sourceDir));
            assertEquals(required(args,"expectedApkSha256"),hash);report.put("installedApkSha256",hash);
            long pageSize=Os.sysconf(OsConstants._SC_PAGESIZE);report.put("pageSize",pageSize);
            assertEquals(Long.parseLong(required(args,"expectedPageSize")),pageSize);
            device.executeShellCommand("cmd appops set "+APP+" SCHEDULE_EXACT_ALARM deny");
            Intent launch=context.getPackageManager().getLaunchIntentForPackage(APP);
            assertNotNull(launch);launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TASK);
            context.startActivity(launch);
            signIn(required(args,"accountBEmail"),required(args,"accountBPassword"));
            reveal("স্থান সেট করুন").click();waitLabel("শহর থেকে বেছে নিন",15000);
            reveal("ঢাকা").click();waitAbsent("শহর থেকে বেছে নিন",15000);
            nav("নামাজ");waitLabel("নামাজ ট্র্যাকিং",20000);
            stage="prayer notification grant and exact access refusal";
            reveal("নামাজের সময়ের অ্যালার্ট").click();
            long deadline=SystemClock.uptimeMillis()+15000;
            while(device.findObject(By.res(Pattern.compile(".*:id/permission_allow_button")))==null&&SystemClock.uptimeMillis()<deadline)SystemClock.sleep(200);
            assertNotNull("Expected Android notification permission",device.findObject(By.res(Pattern.compile(".*:id/permission_allow_button"))));
            dismissNativePermissionDialog("permission_allow_button");
            stage="exact access system settings request";
            deadline=SystemClock.uptimeMillis()+15000;
            while(!"com.android.settings".equals(device.getCurrentPackageName())&&SystemClock.uptimeMillis()<deadline)SystemClock.sleep(200);
            assertEquals("Exact access request did not open Android Settings","com.android.settings",device.getCurrentPackageName());
            device.pressBack();
            stage="inexact prayer queue after exact refusal";
            reveal("সময় আনুমানিক হতে পারে");waitPrayerAlarmMode(false,"denied");
            assertTrue(device.executeShellCommand("cmd appops get "+APP+" SCHEDULE_EXACT_ALARM").contains("deny"));
            report.put("nativeExactAccessRequestRefused",true);report.put("nativePrayerInexactFallbackRegistered",true);
            capture("prayer-exact-denied");
            stage="OS exact access grant and foreground refresh";
            device.pressHome();device.executeShellCommand("cmd appops set "+APP+" SCHEDULE_EXACT_ALARM allow");
            context.startActivity(launch);waitLabel("আসসালামু আলাইকুম",60000);
            nav("নামাজ");reveal("যথাসময়ে");waitPrayerAlarmMode(true,"granted");
            assertTrue(device.executeShellCommand("cmd appops get "+APP+" SCHEDULE_EXACT_ALARM").contains("allow"));
            report.put("nativeExactAccessGrantedThroughOs",true);report.put("nativePrayerExactSchedulingAfterGrant",true);
            capture("prayer-exact-granted");
            stage="OS exact access revocation and cold recovery";
            device.executeShellCommand("cmd appops set "+APP+" SCHEDULE_EXACT_ALARM deny");
            context.startActivity(launch);waitLabel("আসসালামু আলাইকুম",60000);
            nav("নামাজ");reveal("সময় আনুমানিক হতে পারে");waitPrayerAlarmMode(false,"revoked");
            report.put("nativeExactAccessRevokedThroughOs",true);report.put("nativePrayerInexactFallbackAfterRevocation",true);
            capture("prayer-exact-revoked");
            stage="prayer opt-out clears native queue";
            reveal("নামাজের সময়ের অ্যালার্ট").click();waitChecked("নামাজের সময়ের অ্যালার্ট",false);waitForAppAlarm(false);
            report.put("nativePrayerOptOutCancelsAlarms",true);
            nav("আরও");reveal("সেটিংস ও রিপোর্ট").click();signOut();
            report.put("success",true);save();
        } catch(Throwable failure) {
            report.put("success",false);report.put("failedStage",stage);report.put("failureType",failure.getClass().getSimpleName());save();
            savePrivateText("prayer-permission-failure-alarm-dump.txt",device.executeShellCommand("dumpsys alarm"));
            savePrivateText("prayer-permission-failure-private.txt",String.valueOf(failure.getMessage()));
            try{capture("failure-private");}catch(Throwable ignored){}
            throw new AssertionError("Prayer permission audit failed at "+stage+" ("+failure.getClass().getSimpleName()+"). Inspect private artifacts.",failure);
        } finally {device.executeShellCommand("cmd appops set "+APP+" SCHEDULE_EXACT_ALARM "+originalMode);}
    }

    private void waitPrayerAlarmMode(boolean exactExpected,String name) throws Exception {
        long deadline=SystemClock.uptimeMillis()+25000;
        do {
            String dump=device.executeShellCommand("dumpsys alarm");String[] lines=dump.split("\\n");
            int total=0,exact=0;
            for(int i=0;i<lines.length;i++) {
                if(!lines[i].matches("\\s*RTC_WAKEUP #\\d+:.*")||!lines[i].contains(APP))continue;
                StringBuilder entry=new StringBuilder(lines[i]);
                for(int j=i+1;j<Math.min(i+10,lines.length);j++) {
                    if(lines[j].matches("\\s*(?:RTC|ELAPSED)(?:_WAKEUP)? #\\d+:.*"))break;
                    entry.append(' ').append(lines[j]);
                }
                if(!entry.toString().contains("ScheduledNotificationReceiver"))continue;
                total++;
                if(Pattern.compile("\\bwindow=0\\s").matcher(entry).find())exact++;
            }
            if(total>0&&(exactExpected?exact>0:exact==0)) {
                savePrivateText("prayer-permission-"+name+"-alarm-dump.txt",dump);
                report.put(name+"NativeAlarmCount",total);report.put(name+"ExactNativeAlarmCount",exact);return;
            }
            SystemClock.sleep(300);
        }while(SystemClock.uptimeMillis()<deadline);
        throw new AssertionError("Native alarm queue did not match exact access during "+stage);
    }

    private void waitForAppAlarm(boolean expected) throws Exception {
        long deadline=SystemClock.uptimeMillis()+20000;
        while(appAlarmPresent()!=expected&&SystemClock.uptimeMillis()<deadline)SystemClock.sleep(200);
        assertEquals("Unexpected pending native alarm state during "+stage,expected,appAlarmPresent());
    }

    /** Real elapsed-time delivery in documented forced Doze; no clock advance or injected event. */
    @Test
    public void naturalClockDeliveryInDoze() throws Exception {
        Bundle args = InstrumentationRegistry.getArguments();
        context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
        Configurator.getInstance().setWaitForIdleTimeout(300);
        output = new File(context.getExternalFilesDir(null), "release-audit");
        assertTrue(output.mkdirs() || output.isDirectory());
        String originalZone = device.executeShellCommand("getprop persist.sys.timezone").trim();
        String automaticZone = device.executeShellCommand("settings get global auto_time_zone").trim();
        long initialWall = System.currentTimeMillis(), initialElapsed = SystemClock.elapsedRealtime();
        try {
            stage = "artifact identity";
            String hash = SignedReleaseAuditTest.sha256(new File(context.getPackageManager().getApplicationInfo(APP, 0).sourceDir));
            assertEquals(required(args, "expectedApkSha256"), hash);
            report.put("installedApkSha256", hash);
            report.put("pageSize", Os.sysconf(OsConstants._SC_PAGESIZE));
            Intent launch = context.getPackageManager().getLaunchIntentForPackage(APP);
            assertNotNull(launch); launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
            context.startActivity(launch);
            signIn(required(args,"accountAEmail"),required(args,"accountAPassword"));
            stage = "select real timezone with upcoming daily reminder";
            long now = System.currentTimeMillis(), due = Long.MAX_VALUE;
            String zone = null, title = null;
            for (String id : java.util.TimeZone.getAvailableIDs()) {
                if (!id.contains("/")) continue;
                for (int hour : new int[]{8,20,21}) {
                    java.util.Calendar candidate = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone(id));
                    candidate.setTimeInMillis(now); candidate.set(java.util.Calendar.HOUR_OF_DAY,hour);
                    candidate.set(java.util.Calendar.MINUTE,0); candidate.set(java.util.Calendar.SECOND,0); candidate.set(java.util.Calendar.MILLISECOND,0);
                    if (candidate.getTimeInMillis() < now + 120000) candidate.add(java.util.Calendar.DAY_OF_MONTH,1);
                    if (candidate.getTimeInMillis() < due) {
                        due = candidate.getTimeInMillis(); zone = id;
                        title = hour == 8 ? "আজকের কাজ" : hour == 20 ? "নামাজের হিসাব" : "গ্রোথ চেকলিস্ট";
                    }
                }
            }
            assertNotNull(zone);
            assertTrue("No suitable daily slot within the bounded cloud test", due-now < 30L*60*1000);
            device.pressHome(); device.executeShellCommand("settings put global auto_time_zone 0");
            device.executeShellCommand("cmd alarm set-timezone " + zone);
            context.startActivity(launch); waitLabel("আসসালামু আলাইকুম",60000);
            nav("আরও"); reveal("সেটিংস ও রিপোর্ট").click();
            reveal("দৈনিক রিমাইন্ডার").click();
            long deadline = SystemClock.uptimeMillis()+15000;
            while (device.findObject(By.res(Pattern.compile(".*:id/permission_allow_button"))) == null && SystemClock.uptimeMillis()<deadline) SystemClock.sleep(200);
            dismissNativePermissionDialog("permission_allow_button");
            assertEquals(PackageManager.PERMISSION_GRANTED,context.getPackageManager().checkPermission("android.permission.POST_NOTIFICATIONS",APP));
            waitChecked("দৈনিক রিমাইন্ডার",true); waitAlarmHours(zone,"natural-initial-alarm-dump.txt");
            assertTrue("Slot passed during setup",due-System.currentTimeMillis()>15000);
            String alarmDump=device.executeShellCommand("dumpsys alarm");
            assertTrue("Selected epoch missing from registered native alarms",alarmDump.contains("origWhen "+due));
            savePrivateText("natural-registered-alarm-dump.txt",alarmDump);
            report.put("registeredDailyDueEpochMillis",due);report.put("selectedDeviceTimezone",zone);
            report.put("expectedNativeNotificationTitle",title);report.put("dailyNativeAlarmRegistered",true);save();
            stage = "natural clock delivery while backgrounded in forced Doze";
            device.pressHome();device.sleep();
            device.executeShellCommand("dumpsys battery unplug");
            device.executeShellCommand("dumpsys deviceidle force-idle");
            assertEquals("IDLE",device.executeShellCommand("dumpsys deviceidle get deep").trim());
            report.put("forcedDeepDozeConfirmed",true);save();
            // Daily reminders are explicitly inexact. Observe up to 12 minutes after
            // their due epoch; lack of arrival is inconclusive beyond this window.
            long end = due+12L*60*1000;
            boolean delivered=false;
            while(System.currentTimeMillis()<end) {
                String notifications=device.executeShellCommand("dumpsys notification --noredact");
                String[] records=notifications.split("(?=NotificationRecord\\()");
                for(String record:records) {
                    int lineEnd=record.indexOf('\n');
                    if(lineEnd>0 && record.substring(0,lineEnd).contains("pkg="+APP)
                            && record.contains("android.title=String ("+title+")")) {
                        delivered=true;savePrivateText("natural-delivered-notification-dump.txt",notifications);break;
                    }
                }
                if(delivered)break;
                assertTrue("Device wall clock jumped during observation",Math.abs((System.currentTimeMillis()-initialWall)-(SystemClock.elapsedRealtime()-initialElapsed))<5000);
                SystemClock.sleep(5000);
            }
            report.put("naturalClockNotificationPosted",delivered);
            report.put("deepDozeStateAtObservation",device.executeShellCommand("dumpsys deviceidle get deep").trim());
            report.put("observationAtEpochMillis",System.currentTimeMillis());
            report.put("wallClockAdvanceAbsent",Math.abs((System.currentTimeMillis()-initialWall)-(SystemClock.elapsedRealtime()-initialElapsed))<5000);
            report.put("notificationOrBroadcastInjectionAbsent",true);
            report.put("observationWindowAfterDueMinutes",12);
            if(delivered) {
                assertTrue("Notification preceded registered due epoch",System.currentTimeMillis()>=due-2000);
                report.put("observedDelayAfterDueMillis",System.currentTimeMillis()-due);
            }
            else savePrivateText("natural-no-arrival-notification-dump.txt",device.executeShellCommand("dumpsys notification --noredact"));
            device.executeShellCommand("dumpsys deviceidle unforce");device.executeShellCommand("dumpsys battery reset");device.wakeUp();device.pressMenu();
            context.startActivity(launch);waitLabel("আসসালামু আলাইকুম",60000);
            nav("আরও");reveal("সেটিংস ও রিপোর্ট").click();
            signOut();report.put("success",true);save();
        } catch(Throwable failure) {
            report.put("success",false);report.put("failedStage",stage);report.put("failureType",failure.getClass().getSimpleName());save();
            throw new AssertionError("Natural-clock audit failed at "+stage+" ("+failure.getClass().getSimpleName()+"). Inspect private artifacts.");
        } finally {
            device.executeShellCommand("dumpsys deviceidle unforce");device.executeShellCommand("dumpsys battery reset");device.wakeUp();
            if(!originalZone.isEmpty())device.executeShellCommand("cmd alarm set-timezone "+originalZone);
            if(automaticZone.matches("[01]"))device.executeShellCommand("settings put global auto_time_zone "+automaticZone);
        }
    }

    private void savePrivateText(String name,String value) throws Exception {
        try(FileOutputStream stream=new FileOutputStream(new File(output,name))) {
            stream.write(value.getBytes(StandardCharsets.UTF_8));
        }
    }

    /** Explicit diagnostics opt-in and synthetic crash on a disposable identity only. */
    @Test
    public void locationFallbackAndControlledCrash() throws Exception {
        locationAndDiagnostics(true);
    }

    void locationFallbackOnly() throws Exception { locationAndDiagnostics(false); }

    private void locationAndDiagnostics(boolean withCrash) throws Exception {
        Bundle args = InstrumentationRegistry.getArguments();
        context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
        Configurator.getInstance().setWaitForIdleTimeout(300);
        output = new File(context.getExternalFilesDir(null), "release-audit");
        assertTrue(output.mkdirs() || output.isDirectory());
        try {
            stage = "artifact identity";
            String hash = SignedReleaseAuditTest.sha256(new File(context.getPackageManager().getApplicationInfo(APP, 0).sourceDir));
            assertEquals(required(args, "expectedApkSha256"), hash); report.put("installedApkSha256", hash);
            Intent launch = context.getPackageManager().getLaunchIntentForPackage(APP);
            assertNotNull(launch); launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK); context.startActivity(launch);
            signIn(required(args, "accountAEmail"), required(args, "accountAPassword"));
            stage = "location permission denial";
            reveal("স্থান সেট করুন").click(); waitLabel("শহর থেকে বেছে নিন", 15000);
            reveal("আমার অবস্থান ব্যবহার করুন").click();
            long deadline = SystemClock.uptimeMillis() + 15000; UiObject2 deny = null;
            while (deny == null && SystemClock.uptimeMillis() < deadline) {
                deny = device.findObject(By.res(Pattern.compile(".*:id/permission_deny_button"))); SystemClock.sleep(200);
            }
            assertNotNull("Expected Android location permission dialog", deny);
            dismissNativePermissionDialog("permission_deny_button");
            waitContains("শহর বেছে নিন বা হাতে স্থান লিখুন", 15000);
            assertEquals(PackageManager.PERMISSION_DENIED, context.getPackageManager().checkPermission("android.permission.ACCESS_FINE_LOCATION", APP));
            report.put("locationPermissionDenialHandled", true);
            stage = "manual location fallback";
            reveal("অন্য স্থান বা হিসাবের পদ্ধতি").click(); waitLabel("নামাজের সময় সেট করুন", 15000);
            setField("স্থানের নাম", "ঢাকা"); setField("অক্ষাংশ", "23.8103"); setField("দ্রাঘিমাংশ", "90.4125"); setField("টাইম জোন", "Asia/Dhaka");
            UiObject2 saveLocation = reveal("সময় সংরক্ষণ করুন");
            capture("location-save-before-private");
            assertTrue("Save is obscured by Android navigation", isUsableAction(saveLocation));
            saveLocation.click(); waitAbsent("নামাজের সময় সেট করুন", 20000);
            waitContains("ঢাকা", 15000); report.put("manualLocationSavedWithoutPermission", true);
            device.executeShellCommand("wm size 720x1280"); device.executeShellCommand("wm density 320");
            capture("store-01-home-configured");
            nav("নামাজ"); waitLabel("নামাজ ট্র্যাকিং", 20000); waitContains("ঢাকা", 15000); capture("store-02-prayer-configured");
            nav("আরও"); reveal("যিকিরের লক্ষ্য").click(); waitLabel("যিকিরসমূহ", 20000); capture("store-05-dhikr");
            device.executeShellCommand("wm size reset"); device.executeShellCommand("wm density reset");
            if (!withCrash) {
                nav("আরও"); reveal("সেটিংস ও রিপোর্ট").click(); signOut();
                report.put("controlledCrashSkipped", true); report.put("success", true); save(); return;
            }
            stage = "explicit diagnostic consent";
            nav("আরও"); reveal("সেটিংস ও রিপোর্ট").click(); UiObject2 diagnostics = reveal("সমস্যার রিপোর্ট পাঠান");
            assertFalse("Diagnostics must start disabled", diagnostics.isChecked()); diagnostics.click(); waitChecked("সমস্যার রিপোর্ট পাঠান", true);
            report.put("explicitDiagnosticsOptInBeforeCrash", true);
            stage = "controlled synthetic native crash";
            report.put("controlledCrashAtEpochMillis", System.currentTimeMillis()); save();
            String response = device.executeShellCommand("am crash --user current " + APP);
            assertFalse("Android rejected the controlled crash", response.contains("Error") || response.contains("Unknown"));
            SystemClock.sleep(1500); device.pressBack(); context.startActivity(launch);
            waitLabel("আসসালামু আলাইকুম", 60000); report.put("postCrashRestartSucceeded", true);
            // Give the SDK a bounded foreground interval to enqueue/upload the native report.
            SystemClock.sleep(45000);
            nav("আরও"); reveal("সেটিংস ও রিপোর্ট").click(); reveal("সমস্যার রিপোর্ট পাঠান"); waitChecked("সমস্যার রিপোর্ট পাঠান", true);
            reveal("সমস্যার রিপোর্ট পাঠান").click(); waitChecked("সমস্যার রিপোর্ট পাঠান", false);
            report.put("diagnosticsDisabledAfterTest", true); signOut();
            report.put("success", true); save();
        } catch (Throwable failure) {
            report.put("success", false); report.put("failedStage", stage); report.put("failureType", failure.getClass().getSimpleName()); save();
            try {capture("failure-private");} catch (Throwable ignored) { }
            throw new AssertionError("Native location/diagnostics audit failed at " + stage + " (" + failure.getClass().getSimpleName() + "). Inspect private artifacts.");
        } finally {device.executeShellCommand("wm size reset"); device.executeShellCommand("wm density reset");}
    }

    private void dismissNotificationShadeGuideIfPresent() throws Exception {
        // Samsung's first-use shade guide hides notification nodes from
        // accessibility even when the delivered notification is visible.
        UiObject2 shadeGuide = device.findObject(By.res("com.android.systemui:id/qs_guide_container"));
        if (shadeGuide != null) {
            device.waitForIdle(1000); SystemClock.sleep(700);
            UiObject2 dismissGuide = device.findObject(By.res("com.android.systemui:id/dialog_checked"));
            assertNotNull("Samsung shade guide has no dismiss action", dismissGuide);
            dismissGuide.click();
            long guideDeadline = SystemClock.uptimeMillis() + 10000;
            while (device.findObject(By.res("com.android.systemui:id/qs_guide_container")) != null
                    && SystemClock.uptimeMillis() < guideDeadline) SystemClock.sleep(200);
            assertNull("Samsung shade guide did not close",
                    device.findObject(By.res("com.android.systemui:id/qs_guide_container")));
            report.put("nativeNotificationShadeGuideDismissed", true);
        }
    }

    private void setField(String label, String value) throws Exception {
        reveal(label);
        UiObject2 field=null;
        for(int attempt=0;attempt<3;attempt++){
            device.waitForIdle(1000); SystemClock.sleep(700);
            field=device.findObject(By.clazz("android.widget.EditText").pkg(APP).hintStartsWith(label));
            assertNotNull("Missing native input field",field); field.click();
            device.waitForIdle(1000); SystemClock.sleep(700);
            field=device.findObject(By.clazz("android.widget.EditText").pkg(APP).hintStartsWith(label));
            if(field!=null&&field.isFocused())break;
        }
        assertNotNull("Native input disappeared",field); assertTrue("Native input did not receive focus",field.isFocused());
        field.setText(value); device.waitForIdle(1000); SystemClock.sleep(500);
        dismissKeyboardIfShown(); device.waitForIdle(1000); SystemClock.sleep(700);
    }

    private void dismissKeyboardIfShown() throws Exception {
        device.waitForIdle(1000);
        String state = device.executeShellCommand("dumpsys input_method");
        if (Pattern.compile("(?:mInputShown|mIsInputViewShown|mInputViewShown|isInputViewShown)=true").matcher(state).find()) {
            device.pressBack(); device.waitForIdle(1000); SystemClock.sleep(300);
        }
    }

    private void dismissNativePermissionDialog(String resource) throws Exception {
        Pattern id = Pattern.compile(".*:id/" + Pattern.quote(resource));
        for (int attempt = 0; attempt < 3; attempt++) {
            // A permission node may be published while its opening window is still input-blocked.
            device.waitForIdle(1000); SystemClock.sleep(700);
            UiObject2 button = device.findObject(By.res(id));
            if (button == null) return;
            button.click(); SystemClock.sleep(400);
            if (device.findObject(By.res(id)) == null) return;
        }
        assertNull("Native permission dialog remained after settled input", device.findObject(By.res(id)));
    }

    @Test
    public void timezoneRefreshWithoutRestart() throws Exception {
        Bundle args = InstrumentationRegistry.getArguments();
        context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
        Configurator.getInstance().setWaitForIdleTimeout(300);
        output = new File(context.getExternalFilesDir(null), "release-audit");
        assertTrue(output.mkdirs() || output.isDirectory());
        String originalZone = java.util.TimeZone.getDefault().getID();
        String automaticZone = device.executeShellCommand("settings get global auto_time_zone").trim();
        try {
            stage = "artifact identity";
            String hash = SignedReleaseAuditTest.sha256(new File(context.getPackageManager().getApplicationInfo(APP, 0).sourceDir));
            assertEquals(required(args, "expectedApkSha256"), hash); report.put("installedApkSha256", hash);
            Intent launch = context.getPackageManager().getLaunchIntentForPackage(APP);
            assertNotNull(launch); launch.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            context.startActivity(launch); signIn(required(args,"accountAEmail"),required(args,"accountAPassword"));
            stage = "prayer database initialization before daily scheduling";
            reveal("স্থান সেট করুন").click(); waitLabel("শহর থেকে বেছে নিন",15000); reveal("ঢাকা").click(); waitAbsent("শহর থেকে বেছে নিন",15000);
            nav("আরও"); reveal("সেটিংস ও রিপোর্ট").click(); reveal("দৈনিক রিমাইন্ডার").click();
            long deadline=SystemClock.uptimeMillis()+15000; UiObject2 allow=null;
            while(allow==null && SystemClock.uptimeMillis()<deadline){allow=device.findObject(By.res(Pattern.compile(".*:id/permission_allow_button")));SystemClock.sleep(200);}
            assertNotNull("Expected native notification permission",allow); dismissNativePermissionDialog("permission_allow_button");
            waitChecked("দৈনিক রিমাইন্ডার",true); waitAlarmHours(originalZone,"timezone-initial-alarm-dump.txt");
            report.put("dailyZoneIsolatedFromPrayerDatabase",true);
            String pid=device.executeShellCommand("pidof "+APP).trim(); assertFalse(pid.isEmpty());
            device.executeShellCommand("settings put global auto_time_zone 0");
            for(String zone:new String[]{"America/New_York","Asia/Dhaka"}){
                stage="in-process timezone refresh: "+zone;
                device.pressHome(); device.executeShellCommand("cmd alarm set-timezone "+zone); context.startActivity(launch);
                waitContains("দৈনিক রিমাইন্ডার",20000);
                assertEquals("App process restarted; cannot establish in-process refresh",pid,device.executeShellCommand("pidof "+APP).trim());
                waitAlarmHours(zone,"timezone-"+zone.replace('/','-')+"-alarm-dump.txt");
            }
            report.put("deviceTimezoneRefreshWithoutProcessRestart",true);
            report.put("dailyLocalHoursPreserved", "08:00,20:00,21:00");
            signOut(); report.put("success",true); save();
        } catch(Throwable failure){
            report.put("success",false);report.put("failedStage",stage);report.put("failureType",failure.getClass().getSimpleName());save();
            try{capture("failure-private");}catch(Throwable ignored){}
            throw new AssertionError("Native timezone audit failed at "+stage+" ("+failure.getClass().getSimpleName()+"). Inspect private artifacts.");
        } finally {
            device.executeShellCommand("cmd alarm set-timezone "+originalZone);
            if(automaticZone.matches("[01]"))device.executeShellCommand("settings put global auto_time_zone "+automaticZone);
        }
    }

    private void waitAlarmHours(String zone,String filename) throws Exception {
        long deadline=SystemClock.uptimeMillis()+20000; String dump="";
        java.util.Set<Integer> expected=new java.util.HashSet<>(java.util.Arrays.asList(8,20,21));
        do {
            dump=device.executeShellCommand("dumpsys alarm"); String[] lines=dump.split("\\n");
            java.util.Set<Integer> hours=new java.util.HashSet<>();
            for(int i=0;i<lines.length;i++){
                if(!lines[i].matches("\\s*RTC_WAKEUP #\\d+:.*"))continue;
                StringBuilder entry=new StringBuilder(lines[i]);
                for(int n=i+1;n<Math.min(i+10,lines.length);n++){
                    if(lines[n].matches("\\s*(?:RTC|ELAPSED)(?:_WAKEUP)? #\\d+:.*"))break;
                    entry.append(' ').append(lines[n]);
                }
                if(!entry.toString().contains(APP)||!entry.toString().contains("ScheduledNotificationReceiver"))continue;
                // The Alarm header contains the locale-independent epoch as
                // "origWhen <millis>". The following "origWhen=" field is a
                // localized date (including Bangla digits on this device).
                java.util.regex.Matcher when=Pattern.compile("\\borigWhen\\s+([0-9]+)\\b").matcher(lines[i]);
                if(!when.find())continue;
                java.util.Calendar calendar=java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone(zone));
                calendar.setTimeInMillis(Long.parseLong(when.group(1)));
                if(calendar.get(java.util.Calendar.MINUTE)==0)hours.add(calendar.get(java.util.Calendar.HOUR_OF_DAY));
            }
            if(hours.equals(expected))return;
            SystemClock.sleep(300);
        }while(SystemClock.uptimeMillis()<deadline);
        try(FileOutputStream file=new FileOutputStream(new File(output,filename))){file.write(dump.getBytes(StandardCharsets.UTF_8));}
        throw new AssertionError("Pending alarms did not retain local daily hours during "+stage);
    }

    void resetFixtureReminderPreferences() throws Exception {
        Bundle args=InstrumentationRegistry.getArguments(); String email=required(args,"accountAEmail");
        assertTrue(email.startsWith("teamframecipher+native-"));
        JSONObject login=ownerRequest("https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key="+required(args,"firebaseApiKey"),"POST",
            new JSONObject().put("email",email).put("password",required(args,"accountAPassword")).put("returnSecureToken",true),null);
        assertEquals(required(args,"accountAUid"),login.getString("localId"));
        JSONObject notifications=new JSONObject();for(String key:new String[]{"tasks","prayer","growth"})notifications.put(key,new JSONObject().put("booleanValue",false));
        JSONObject fields=new JSONObject().put("notifications",new JSONObject().put("mapValue",new JSONObject().put("fields",notifications)))
            .put("remindersConfigured",new JSONObject().put("booleanValue",false));
        ownerRequest("https://firestore.googleapis.com/v1/projects/assistummah/databases/(default)/documents/userSettings/"+login.getString("localId")+"?updateMask.fieldPaths=notifications&updateMask.fieldPaths=remindersConfigured",
            "PATCH",new JSONObject().put("fields",fields),login.getString("idToken"));
    }

    private boolean appAlarmPresent() throws Exception {
        String alarms = device.executeShellCommand("dumpsys alarm");
        // Only inspect pending alarm entries; historical Alarm Stats survive cancellation.
        String[] lines = alarms.split("\\n");
        for (int index = 0; index < lines.length; index++) {
            if (!lines[index].matches("\\s*(?:RTC|ELAPSED)(?:_WAKEUP)? #\\d+:.*")) continue;
            StringBuilder entry = new StringBuilder(lines[index]);
            for (int next = index + 1; next < Math.min(index + 10, lines.length); next++) {
                if (lines[next].matches("\\s*(?:RTC|ELAPSED)(?:_WAKEUP)? #\\d+:.*")) break;
                entry.append(lines[next]);
            }
            if (entry.toString().contains(APP) && entry.toString().contains("ScheduledNotificationReceiver")) return true;
        }
        return false;
    }
    private void waitChecked(String label, boolean checked) {
        long deadline = SystemClock.uptimeMillis() + 15000;
        while (SystemClock.uptimeMillis() < deadline) {
            UiObject2 node = find(label, true); if (node != null && node.isChecked() == checked) return;
            SystemClock.sleep(200);
        }
        throw new AssertionError("Consent state did not settle during " + stage);
    }

    /** Simulates an interrupted owner deletion while an unsaved private dialog is open. */
    @Test
    public void deletionRecoveryAndRouteRevocation() throws Exception {
        Bundle args = InstrumentationRegistry.getArguments();
        context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
        Configurator.getInstance().setWaitForIdleTimeout(300);
        output = new File(context.getExternalFilesDir(null), "release-audit");
        assertTrue(output.mkdirs() || output.isDirectory());
        try {
            stage = "artifact identity";
            String hash = SignedReleaseAuditTest.sha256(new File(context.getPackageManager().getApplicationInfo(APP, 0).sourceDir));
            assertEquals(required(args, "expectedApkSha256"), hash);
            report.put("installedApkSha256", hash);
            Intent launch = context.getPackageManager().getLaunchIntentForPackage(APP);
            assertNotNull(launch); launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
            context.startActivity(launch);
            stage = "disposable owner sign-in";
            String email = required(args, "accountAEmail"), password = required(args, "accountAPassword");
            signIn(email, password);
            nav("কাজ"); reveal("কাজ যোগ").click(); waitLabel("নতুন কাজ যোগ করুন", 10000);
            stage = "owner deletion marker";
            JSONObject login = ownerRequest("https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=" + required(args, "firebaseApiKey"),
                "POST", new JSONObject().put("email", email).put("password", password).put("returnSecureToken", true), null);
            assertEquals(required(args, "accountAUid"), login.getString("localId"));
            String token = login.getString("idToken");
            if ("true".equals(args.getString("suiteVerifyPersistedTask"))) {
                JSONObject saved = ownerRequest("https://firestore.googleapis.com/v1/projects/assistummah/databases/(default)/documents/userTasks/" + login.getString("localId"), "GET", null, token);
                assertTrue("Earlier native task save was absent from the server", saved.toString().contains("Native audit saved task"));
                report.put("earlierNativeTaskSaveConfirmedOnServer", true);
            }
            ownerRequest("https://firestore.googleapis.com/v1/projects/assistummah/databases/(default)/documents/accountDeletions/" + login.getString("localId"),
                "PATCH", new JSONObject().put("fields", new JSONObject()), token);
            stage = "private route revocation";
            waitContains("অ্যাকাউন্ট মুছে ফেলা বাকি আছে", 30000);
            assertNull(find("নতুন কাজ যোগ করুন", true));
            report.put("remoteDeletionClosesPrivateDialog", true);
            device.pressBack();
            context.startActivity(launch);
            waitContains("অ্যাকাউন্ট মুছে ফেলা বাকি আছে", 20000);
            assertNull(find("আজকের কাজ", false));
            report.put("backCannotRestorePrivateHome", true);
            capture("11-deletion-recovery");
            stage = "native deletion completion";
            reveal("মুছে ফেলা সম্পন্ন করুন").click();
            waitLabel("অ্যাকাউন্ট মুছে ফেলুন", 15000);
            UiObject2 field = device.findObject(By.clazz("android.widget.EditText").pkg(APP));
            if (field == null) { reveal("বর্তমান পাসওয়ার্ড"); field = editors().get(0); }
            field.click(); field.setText(password); dismissKeyboardIfShown();
            reveal("আমি বুঝেছি, আমার অ্যাকাউন্ট ও সংশ্লিষ্ট তথ্য স্থায়ীভাবে মুছে ফেলা হবে।").click();
            reveal("স্থায়ীভাবে মুছে ফেলার অনুরোধ করুন").click();
            waitLabel("লগইন", 90000);
            report.put("nativeDeletionReturnsToLogin", true);
            // A pre-deletion owner token can still read the empty anti-resurrection marker.
            JSONObject marker = ownerRequest("https://firestore.googleapis.com/v1/projects/assistummah/databases/(default)/documents/accountDeletions/" + login.getString("localId"), "GET", null, token);
            assertTrue(!marker.has("fields") || marker.getJSONObject("fields").length() == 0);
            report.put("emptyDeletionMarkerRetained", true);
            stage = "cold restart and second account";
            device.executeShellCommand("am force-stop " + APP);
            context.startActivity(launch);
            signIn(required(args, "accountBEmail"), required(args, "accountBPassword"));
            nav("কাজ"); reveal(required(args, "accountBTask"));
            assertNull(find(required(args, "accountATask"), true));
            report.put("coldRestartOtherAccountUnaffected", true);
            nav("আরও"); reveal("সেটিংস ও রিপোর্ট").click(); signOut();
            report.put("success", true); save();
        } catch (Throwable failure) {
            report.put("success", false); report.put("failedStage", stage);
            report.put("failureType", failure.getClass().getSimpleName()); save();
            try {capture("failure-private");} catch (Throwable ignored) { }
            throw new AssertionError("Native deletion audit failed at " + stage + " (" + failure.getClass().getSimpleName() + "). Inspect private artifacts.");
        }
    }

    private JSONObject ownerRequest(String url, String method, JSONObject body, String token) throws Exception {
        assertTrue(url.startsWith("https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=") ||
            url.startsWith("https://firestore.googleapis.com/v1/projects/assistummah/databases/(default)/documents/accountDeletions/") ||
            (method.equals("GET") && url.startsWith("https://firestore.googleapis.com/v1/projects/assistummah/databases/(default)/documents/userTasks/")) ||
            (method.equals("PATCH") && url.startsWith("https://firestore.googleapis.com/v1/projects/assistummah/databases/(default)/documents/userSettings/")));
        java.net.HttpURLConnection connection = (java.net.HttpURLConnection) new java.net.URL(url).openConnection();
        connection.setConnectTimeout(15000); connection.setReadTimeout(15000); connection.setRequestMethod(method);
        connection.setRequestProperty("Content-Type", "application/json");
        if (token != null) connection.setRequestProperty("Authorization", "Bearer " + token);
        try {
            if (body != null) {
                connection.setDoOutput(true);
                try (java.io.OutputStream stream = connection.getOutputStream()) {stream.write(body.toString().getBytes(StandardCharsets.UTF_8));}
            }
            int status = connection.getResponseCode();
            assertTrue("Owner request failed during " + stage + " (HTTP " + status + ")", status >= 200 && status < 300);
            try (java.io.InputStream stream = connection.getInputStream(); java.io.ByteArrayOutputStream bytes = new java.io.ByteArrayOutputStream()) {
                byte[] buffer = new byte[4096]; int count;
                while ((count = stream.read(buffer)) != -1) bytes.write(buffer, 0, count);
                return new JSONObject(bytes.toString("UTF-8"));
            }
        } finally {connection.disconnect();}
    }

    private void signIn(String email, String password) throws Exception {
        assertTrue("Only disposable fixture identities are allowed", email.startsWith("teamframecipher+native-"));
        waitLabel("লগইন", 30000);
        setField("ইমেইল ঠিকানা", email);
        setField("পাসওয়ার্ড", password);
        click("লগইন");
        waitLabel("আসসালামু আলাইকুম", 60000);
    }

    private void signOut() {
        reveal("সাইন আউট").click();
        waitContains("আপনি কি সাইন আউট করতে চান?", 10000);
        click("সাইন আউট"); waitLabel("লগইন", 30000);
    }

    private List<UiObject2> editors() {
        return device.findObjects(By.clazz("android.widget.EditText").pkg(APP));
    }

    private UiObject2 find(String label, boolean contains) {
        List<UiObject2> nodes = new ArrayList<>(device.findObjects(contains ? By.textContains(label).pkg(APP) : By.text(label).pkg(APP)));
        nodes.addAll(device.findObjects(contains ? By.descContains(label).pkg(APP) : By.desc(label).pkg(APP)));
        if (android.os.Build.VERSION.SDK_INT >= 26) {
            nodes.addAll(device.findObjects(contains ? By.hintContains(label).pkg(APP) : By.hint(label).pkg(APP)));
        }
        UiObject2 selected = null;
        for (UiObject2 node : nodes) {
            if (selected == null || node.getVisibleBounds().centerY() > selected.getVisibleBounds().centerY()) selected = node;
        }
        return selected;
    }

    private UiObject2 wait(String label, boolean contains, long timeout) {
        long deadline = SystemClock.uptimeMillis() + timeout;
        do { UiObject2 node = find(label, contains); if (node != null) return node; SystemClock.sleep(200); }
        while (SystemClock.uptimeMillis() < deadline);
        throw new AssertionError("Missing required UI during " + stage);
    }
    private UiObject2 waitLabel(String label, long timeout) {return wait(label, false, timeout);}
    private UiObject2 waitContains(String label, long timeout) {return wait(label, true, timeout);}
    private void waitAbsent(String label, long timeout) {
        long deadline = SystemClock.uptimeMillis() + timeout;
        while (find(label, false) != null && SystemClock.uptimeMillis() < deadline) SystemClock.sleep(200);
        assertNull("Pending editor did not finish during " + stage, find(label, false));
    }
    private void click(String label) {waitLabel(label,10000);device.waitForIdle(1000);SystemClock.sleep(700);waitLabel(label,10000).click();}
    private void nav(String label) {waitContains(label, 10000).click();}
    private boolean dismissBlockingReminderNotice(UiObject2 action) {
        if (action == null) return false;
        UiObject2 notice = device.findObject(By.pkg(APP).descStartsWith("রিমাইন্ডার রিফ্রেশ"));
        if (notice == null || !android.graphics.Rect.intersects(
                action.getVisibleBounds(), notice.getVisibleBounds())) return false;
        android.graphics.Rect bounds = notice.getVisibleBounds();
        // A SnackBar with an action stays visible under accessibility. Use its
        // standard downward dismissal before tapping the covered control.
        device.swipe(bounds.centerX(), bounds.centerY(), bounds.centerX(),
                Math.min(device.getDisplayHeight()-1, bounds.bottom+bounds.height()/2), 25);
        device.waitForIdle(1000); SystemClock.sleep(300);
        if (device.findObject(By.pkg(APP).descStartsWith("রিমাইন্ডার রিফ্রেশ")) == null) {
            reminderNoticeDismissed = true;
        }
        return true;
    }
    private boolean isUsableAction(UiObject2 node) {
        if (node == null) return false;
        android.graphics.Rect bounds = node.getVisibleBounds();
        // Flutter can retain an accessibility node clipped to a one-pixel strip
        // at the scroll boundary. Its center is not a usable tap target.
        int minimumVisible = Math.round(12 * context.getResources().getDisplayMetrics().density);
        if (bounds.height() < minimumVisible || bounds.width() < minimumVisible) return false;
        UiObject2 navigation = device.findObject(By.res("com.android.systemui:id/navigation_bar_frame"));
        // Flutter can expose an offscreen scroll child in accessibility before
        // it is actually tappable. Never send that tap to Android Home/Back.
        return navigation == null || bounds.bottom <= navigation.getVisibleBounds().top;
    }
    private UiObject2 reveal(String label) {
        for (int i = 0; i < 7; i++) {
            device.waitForIdle(1000); SystemClock.sleep(700);
            UiObject2 node = find(label, true);
            if (dismissBlockingReminderNotice(node)) continue;
            if (isUsableAction(node)) return node;
            int x = device.getDisplayWidth()/2, h = device.getDisplayHeight();
            device.swipe(x, h*3/4, x, h/3, 25);
        }
        // The destination may be above the current scroll position.
        for (int i = 0; i < 7; i++) {
            device.waitForIdle(1000); SystemClock.sleep(700);
            UiObject2 node = find(label, true);
            if (dismissBlockingReminderNotice(node)) continue;
            if (isUsableAction(node)) return node;
            int x = device.getDisplayWidth()/2, h = device.getDisplayHeight();
            device.swipe(x, h/3, x, h*3/4, 25);
        }
        throw new AssertionError("Required action unavailable during " + stage);
    }
    private void capture(String name) throws Exception {
        device.waitForIdle(1000);
        SystemClock.sleep(700); // Accessibility updates can precede presentation of the Flutter frame.
        assertTrue(device.takeScreenshot(new File(output, name + ".png")));
        device.dumpWindowHierarchy(new File(output, name + ".xml"));
    }
    private void save() throws Exception {
        if (reminderNoticeDismissed) report.put("nativeReminderNoticeDismissedForNavigation", true);
        try (FileOutputStream stream = new FileOutputStream(new File(output, "flows-receipt.json"))) {
            stream.write((report.toString(2) + "\n").getBytes(StandardCharsets.UTF_8));
        }
    }
}
