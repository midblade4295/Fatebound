package org.fatebound.notify;

import android.Manifest;
import android.app.Activity;
import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;


import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.HashSet;
import java.util.Set;

/**
 * 0.31.119 (Kevin: "Do all" -- chest-ready notifications): local notifications at a time the game picks.
 * The game (scripts/meta/notify.gd) schedules one per unlocking chest when it goes to the background and cancels them
 * all when it comes back. AlarmManager.setAndAllowWhileIdle: inexact (a few minutes late at most under Doze), no
 * exact-alarm permission. Nothing leaves the phone.
 */
public class FateboundNotify extends GodotPlugin {
    static final String PREFS = "fatebound_notify";
    static final String KEY_IDS = "ids";
    static final int PERMISSION_REQUEST = 7419;

    public FateboundNotify(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "FateboundNotify";
    }

    private Context ctx() {
        Activity a = getActivity();
        return a != null ? a.getApplicationContext() : null;
    }

    /** True when the game may post notifications (always below Android 13). */
    @UsedByGodot
    public boolean hasPermission() {
        Context c = ctx();
        if (c == null) return false;
        if (Build.VERSION.SDK_INT < 33) return true;
        return c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED;
    }

    /** Android 13+: the system's "Allow notifications?" (shown at most twice by Android, then never again). */
    @UsedByGodot
    public void requestPermission() {
        Activity a = getActivity();
        if (a == null || Build.VERSION.SDK_INT < 33 || hasPermission()) return;
        a.runOnUiThread(() -> a.requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, PERMISSION_REQUEST));
    }

    /** A notification in delaySeconds (replacing any with the same id). */
    @UsedByGodot
    public void schedule(int id, String title, String body, int delaySeconds) {
        Context c = ctx();
        if (c == null) return;
        AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
        if (am == null) return;
        long at = System.currentTimeMillis() + Math.max(1, delaySeconds) * 1000L;
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending(c, id, title, body));
        SharedPreferences sp = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        Set<String> ids = new HashSet<>(sp.getStringSet(KEY_IDS, new HashSet<>()));
        ids.add(Integer.toString(id));
        sp.edit().putStringSet(KEY_IDS, ids).apply();
    }

    /** Every scheduled one off, and any already showing. */
    @UsedByGodot
    public void cancelAll() {
        Context c = ctx();
        if (c == null) return;
        AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
        SharedPreferences sp = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        for (String s : sp.getStringSet(KEY_IDS, new HashSet<>())) {
            try {
                int id = Integer.parseInt(s);
                if (am != null) am.cancel(pending(c, id, "", ""));
            } catch (NumberFormatException ignored) {
            }
        }
        sp.edit().remove(KEY_IDS).apply();
        android.app.NotificationManager nm = (android.app.NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null) nm.cancelAll();
    }

    static PendingIntent pending(Context c, int id, String title, String body) {
        Intent i = new Intent(c, NotifyReceiver.class);
        i.putExtra("id", id);
        i.putExtra("title", title);
        i.putExtra("body", body);
        return PendingIntent.getBroadcast(c, id, i, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }
}
