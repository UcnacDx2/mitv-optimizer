package com.ucnacdx2.mitvhomebridge;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.IBinder;
import android.os.Parcel;
import android.util.Log;
import android.widget.Toast;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

public class MainActivity extends Activity {
    private static final String TAG = "MiTVHomeBridge";

    private static final String HOME_PERMISSION = "com.mitv.tvhome.permission.HOME_STATE";
    private static final String TVHOME_PACKAGE = "com.mitv.tvhome";
    private static final String TVHOME_ACTIVITY = "com.mitv.tvhome.MainActivityUserMode";
    private static final String FALLBACK_PACKAGE = "com.xiaomi.mitv.settings";
    private static final String FALLBACK_ACTIVITY = "com.xiaomi.mitv.settings.entry.FallbackHome";

    private static final ComponentName TVHOME_COMPONENT =
        new ComponentName(TVHOME_PACKAGE, TVHOME_ACTIVITY);
    private static final ComponentName FALLBACK_COMPONENT =
        new ComponentName(FALLBACK_PACKAGE, FALLBACK_ACTIVITY);

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);

        final boolean fromTvHome = isLaunchedFromTvHome();
        Log.i(TAG, "entry=" + (fromTvHome ? "tvhome" : "external")
            + " referrer=" + safeReferrer());

        new Thread(() -> {
            if (fromTvHome) {
                switchAwayFromTvHome();
            } else {
                openTvHome();
            }
        }, "MiTvHomeBridge").start();
    }

    /**
     * TVHome's app grid launches third-party apps with itself as the activity referrer.
     * getCallingPackage() only covers startActivityForResult(), so use both signals.
     */
    private boolean isLaunchedFromTvHome() {
        if (TVHOME_PACKAGE.equals(getCallingPackage())) {
            return true;
        }

        Uri referrer = getReferrer();
        if (isTvHomeReferrer(referrer)) {
            return true;
        }

        Intent intent = getIntent();
        if (intent == null) {
            return false;
        }

        try {
            Uri explicit = intent.getParcelableExtra(Intent.EXTRA_REFERRER);
            if (isTvHomeReferrer(explicit)) {
                return true;
            }
        } catch (RuntimeException error) {
            Log.w(TAG, "failed to read EXTRA_REFERRER", error);
        }

        String referrerName = intent.getStringExtra(Intent.EXTRA_REFERRER_NAME);
        if (referrerName != null) {
            try {
                return isTvHomeReferrer(Uri.parse(referrerName));
            } catch (RuntimeException error) {
                Log.w(TAG, "bad EXTRA_REFERRER_NAME=" + referrerName, error);
            }
        }
        return false;
    }

    private boolean isTvHomeReferrer(Uri referrer) {
        if (referrer == null) {
            return false;
        }
        if ("android-app".equals(referrer.getScheme())) {
            return TVHOME_PACKAGE.equals(referrer.getHost());
        }
        return TVHOME_PACKAGE.equals(referrer.getHost())
            || referrer.toString().contains(TVHOME_PACKAGE);
    }

    private String safeReferrer() {
        try {
            Uri referrer = getReferrer();
            return referrer == null ? "null" : referrer.toString();
        } catch (RuntimeException error) {
            return "error:" + error.getClass().getSimpleName();
        }
    }

    /**
     * Entry from the Xiaomi launcher means "leave the factory launcher".
     * First try the PackageManager Binder service without root. If the ROM rejects
     * the call, request Magisk root once and apply both component changes atomically.
     */
    private void switchAwayFromTvHome() {
        int oldTvHome = getComponentState(TVHOME_COMPONENT);
        int oldFallback = getComponentState(FALLBACK_COMPONENT);

        boolean tvHomeDisabled = setComponentViaPackageService(
            TVHOME_COMPONENT, PackageManager.COMPONENT_ENABLED_STATE_DISABLED);
        boolean fallbackDisabled = setComponentViaPackageService(
            FALLBACK_COMPONENT, PackageManager.COMPONENT_ENABLED_STATE_DISABLED);

        if (!(tvHomeDisabled && fallbackDisabled)) {
            Log.i(TAG, "package service call incomplete; requesting root fallback");
            String command = "pm disable-user --user 0 " + shellQuote(TVHOME_COMPONENT.flattenToString())
                + " && pm disable-user --user 0 " + shellQuote(FALLBACK_COMPONENT.flattenToString());
            boolean rootOk = runRoot(command);
            tvHomeDisabled = rootOk && isComponentDisabled(TVHOME_COMPONENT);
            fallbackDisabled = rootOk && isComponentDisabled(FALLBACK_COMPONENT);
        }

        if (tvHomeDisabled && fallbackDisabled) {
            Log.i(TAG, "factory Home components disabled");
            finishOnUi(null);
            return;
        }

        // Avoid leaving the Home stack half-changed if only one Binder call succeeded.
        restoreViaPackageService(TVHOME_COMPONENT, oldTvHome);
        restoreViaPackageService(FALLBACK_COMPONENT, oldFallback);
        Log.e(TAG, "failed to disable factory Home components");
        finishOnUi("切换失败：service call 和 Root 都不可用");
    }

    /**
     * Entry from any launcher other than TVHome means "open the factory launcher".
     * Re-enable MainActivityUserMode, keep FallbackHome untouched, then launch TVHome.
     */
    private void openTvHome() {
        boolean enabled = setComponentViaPackageService(
            TVHOME_COMPONENT, PackageManager.COMPONENT_ENABLED_STATE_ENABLED);
        boolean rootWasUsed = false;

        if (!enabled) {
            Log.i(TAG, "package service call could not enable TVHome; requesting root fallback");
            rootWasUsed = runRoot(
                "pm enable --user 0 " + shellQuote(TVHOME_COMPONENT.flattenToString()));
            enabled = rootWasUsed && isComponentState(
                TVHOME_COMPONENT, PackageManager.COMPONENT_ENABLED_STATE_ENABLED);
        }

        if (!enabled) {
            Log.e(TAG, "failed to enable " + TVHOME_COMPONENT.flattenToString());
            finishOnUi("无法启用小米桌面");
            return;
        }

        if (launchTvHomeDirect()) {
            finishOnUi(null);
            return;
        }

        // HOME_STATE is signature-only on the target ROM. If direct launch fails,
        // use root just for the protected activity start.
        boolean launched = runRoot(
            "am start -a com.mitv.tvhome.HOME_PAGE -n "
                + shellQuote(TVHOME_COMPONENT.flattenToString()));
        if (!launched) {
            Log.e(TAG, "root launch failed (enableRoot=" + rootWasUsed + ")");
            finishOnUi("Root 启动小米桌面失败");
            return;
        }
        finishOnUi(null);
    }

    private boolean launchTvHomeDirect() {
        if (checkSelfPermission(HOME_PERMISSION) != PackageManager.PERMISSION_GRANTED) {
            Log.i(TAG, "HOME_STATE not granted; direct launch skipped");
            return false;
        }
        try {
            Intent intent = new Intent("com.mitv.tvhome.HOME_PAGE");
            intent.setComponent(TVHOME_COMPONENT);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
            Log.i(TAG, "TVHome launched directly");
            return true;
        } catch (RuntimeException error) {
            Log.w(TAG, "direct TVHome launch failed", error);
            return false;
        }
    }

    /**
     * Equivalent to a version-aware `service call package <transaction> ...`, but
     * uses Binder directly so the transaction number comes from the ROM's own Stub
     * instead of being hard-coded. Permission errors are expected and trigger root.
     */
    private boolean setComponentViaPackageService(ComponentName component, int newState) {
        Parcel data = null;
        Parcel reply = null;
        try {
            Class<?> serviceManager = Class.forName("android.os.ServiceManager");
            Method getService = serviceManager.getDeclaredMethod("getService", String.class);
            getService.setAccessible(true);
            IBinder packageBinder = (IBinder) getService.invoke(null, "package");
            if (packageBinder == null) {
                Log.w(TAG, "package Binder service not found");
                return false;
            }

            Class<?> packageStub = Class.forName("android.content.pm.IPackageManager$Stub");
            Field transaction = packageStub.getDeclaredField(
                "TRANSACTION_setComponentEnabledSetting");
            transaction.setAccessible(true);
            int transactionCode = transaction.getInt(null);

            data = Parcel.obtain();
            reply = Parcel.obtain();
            data.writeInterfaceToken("android.content.pm.IPackageManager");
            data.writeInt(1); // non-null ComponentName for writeTypedObject/writeParcelable
            component.writeToParcel(data, 0);
            data.writeInt(newState);
            // Let PackageManager kill the target package when disabling it. This
            // is important when the bridge was opened from TVHome: after this
            // activity finishes we must not fall back into a still-running TVHome.
            data.writeInt(0);
            data.writeInt(0); // user 0

            // Android 14+ added callingPackage to this AIDL method.
            if (Build.VERSION.SDK_INT >= 34) {
                data.writeString(getPackageName());
            }

            boolean transacted = packageBinder.transact(transactionCode, data, reply, 0);
            if (!transacted) {
                Log.w(TAG, "package service transact returned false for " + component);
                return false;
            }
            reply.readException();

            boolean verified = isComponentState(component, newState);
            Log.i(TAG, "package service call " + component.flattenToShortString()
                + " -> " + stateName(newState) + " verified=" + verified
                + " tx=" + transactionCode);
            return verified;
        } catch (Throwable error) {
            Log.w(TAG, "package service call rejected for " + component.flattenToShortString(), error);
            return false;
        } finally {
            if (reply != null) {
                reply.recycle();
            }
            if (data != null) {
                data.recycle();
            }
        }
    }

    private void restoreViaPackageService(ComponentName component, int state) {
        if (state < PackageManager.COMPONENT_ENABLED_STATE_DEFAULT
            || state > PackageManager.COMPONENT_ENABLED_STATE_DISABLED_UNTIL_USED) {
            return;
        }
        setComponentViaPackageService(component, state);
    }

    private int getComponentState(ComponentName component) {
        try {
            return getPackageManager().getComponentEnabledSetting(component);
        } catch (RuntimeException error) {
            Log.w(TAG, "cannot read component state " + component.flattenToShortString(), error);
            return -1;
        }
    }

    private boolean isComponentState(ComponentName component, int expected) {
        return getComponentState(component) == expected;
    }

    private boolean isComponentDisabled(ComponentName component) {
        int state = getComponentState(component);
        return state == PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            || state == PackageManager.COMPONENT_ENABLED_STATE_DISABLED_USER
            || state == PackageManager.COMPONENT_ENABLED_STATE_DISABLED_UNTIL_USED;
    }

    private boolean runRoot(String command) {
        Process process = null;
        try {
            Log.i(TAG, "su -c <component operation>");
            process = new ProcessBuilder("su", "-c", command)
                .redirectErrorStream(true)
                .start();

            StringBuilder output = new StringBuilder();
            try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(process.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    if (output.length() < 4096) {
                        output.append(line).append('\n');
                    }
                }
            }

            int exit = process.waitFor();
            Log.i(TAG, "root command exit=" + exit + " output=" + output.toString().trim());
            return exit == 0;
        } catch (Exception error) {
            Log.e(TAG, "root command failed", error);
            return false;
        } finally {
            if (process != null) {
                process.destroy();
            }
        }
    }

    private static String shellQuote(String value) {
        return "'" + value.replace("'", "'\\''") + "'";
    }

    private static String stateName(int state) {
        switch (state) {
            case PackageManager.COMPONENT_ENABLED_STATE_DEFAULT:
                return "default";
            case PackageManager.COMPONENT_ENABLED_STATE_ENABLED:
                return "enabled";
            case PackageManager.COMPONENT_ENABLED_STATE_DISABLED:
                return "disabled";
            case PackageManager.COMPONENT_ENABLED_STATE_DISABLED_USER:
                return "disabled-user";
            case PackageManager.COMPONENT_ENABLED_STATE_DISABLED_UNTIL_USED:
                return "disabled-until-used";
            default:
                return "state-" + state;
        }
    }

    private void finishOnUi(String message) {
        runOnUiThread(() -> {
            if (message != null) {
                Toast.makeText(this, message, Toast.LENGTH_LONG).show();
            }
            finish();
        });
    }
}
