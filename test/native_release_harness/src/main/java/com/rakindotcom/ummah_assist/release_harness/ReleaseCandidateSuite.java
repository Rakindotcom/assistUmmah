package com.rakindotcom.ummah_assist.release_harness;

import static org.junit.Assert.*;
import android.content.Context;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.UiDevice;
import org.json.JSONObject;
import org.junit.Test;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

/** One device allocation, with fresh app data per case and deletion last. */
public final class ReleaseCandidateSuite {
    private static final String APP="com.rakindotcom.ummah_assist";
    private File output;
    private final JSONObject report=new JSONObject();
    private String stage="startup";
    @Test public void verifyCurrentRelease() throws Exception {
        Context context=InstrumentationRegistry.getInstrumentation().getTargetContext();
        output=new File(context.getExternalFilesDir(null),"release-audit");
        assertTrue(output.mkdirs()||output.isDirectory());
        try {
            new SignedReleaseAuditTest().auditOriginalSignedApk();
            run("full",()->new SignedInReleaseAuditTest().signedInIsolationAndPermissions());
            run("reminders",()->new SignedInReleaseAuditTest().remindersConsentAndNativeCaptures());
            run("location",()->new SignedInReleaseAuditTest().locationFallbackOnly());
            run("delivery",()->new SignedInReleaseAuditTest().scheduledDeliveryAndOsRevocation());
            run("timezone",()->new SignedInReleaseAuditTest().timezoneRefreshWithoutRestart());
            run("deletion",()->new SignedInReleaseAuditTest().deletionRecoveryAndRouteRevocation());
            report.put("success",true);save();
        }catch(Throwable failure){
            report.put("success",false);report.put("failedStage",stage);save();
            throw new AssertionError("Release suite stopped at "+stage+". Inspect private case receipts.");
        }
    }
    private interface Case {void run()throws Exception;}
    private void run(String name,Case action)throws Exception {
        stage=name;
        UiDevice device=UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
        assertTrue("Fresh app-data reset failed",device.executeShellCommand("pm clear "+APP).contains("Success"));
        for(String permission:new String[]{"POST_NOTIFICATIONS","ACCESS_FINE_LOCATION","ACCESS_COARSE_LOCATION"}){
            device.executeShellCommand("pm revoke "+APP+" android.permission."+permission);
            device.executeShellCommand("pm clear-permission-flags "+APP+" android.permission."+permission+" user-set user-fixed");
        }
        new SignedInReleaseAuditTest().resetFixtureReminderPreferences();
        action.run();
        File raw=new File(output,"flows-receipt.json");
        assertTrue("Missing case receipt",raw.isFile());
        assertTrue("Cannot preserve case receipt",raw.renameTo(new File(output,name+"-receipt.json")));
        report.put(name,true);save();
    }
    private void save()throws Exception {
        try(FileOutputStream stream=new FileOutputStream(new File(output,"suite-receipt.json"))){
            stream.write((report.toString(2)+"\n").getBytes(StandardCharsets.UTF_8));
        }
    }
}
