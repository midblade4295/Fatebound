# FateboundNotify (0.31.119)

The Android side of the chest-ready notifications: a Godot v2 plugin (`org.godotengine.plugin.v2.FateboundNotify`)
with `hasPermission()`, `requestPermission()`, `schedule(id, title, body, delaySeconds)`, `cancelAll()`.
The game uses it through `scripts/meta/notify.gd` only.

Build (Java 17+, Android SDK 36, Gradle 8.14):

    cd godot/android_plugins/fatebound_notify
    ANDROID_HOME=/root/android-sdk gradle assembleDebug assembleRelease
    cp build/outputs/aar/fatebound_notify-debug.aar   ../../addons/FateboundNotify/bin/debug/FateboundNotify-debug.aar
    cp build/outputs/aar/fatebound_notify-release.aar ../../addons/FateboundNotify/bin/release/FateboundNotify-release.aar

Like the billing and Play Games plugins it goes only into Gradle exports (the Play Store preset); the sideloaded
preview APK has no notifications.
