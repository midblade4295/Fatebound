# War alerts on a closed phone (push notifications) -- what Kevin sets up first

0.31.151. The "your chest is ready" notifications (scripts/meta/notify.gd) are scheduled **on the phone** -- nothing
leaves it, and the server can't wake a closed phone with them. "Your land is under attack" / "your clan is attacking
X -- join!" (today: war_alarm / war_call, shown only while the app is open) need real push notifications: Firebase
Cloud Messaging (FCM) for Android, and Apple's push service (APNs, through FCM) for iPhone. Those need a Firebase
project and keys that only Kevin can create. Nothing below goes in the repo: keys stay on the server and on Kevin's
machine.

## 1. Firebase project (console.firebase.google.com)
1. Add project -> pick the **existing Google Cloud project** the Play service account lives in (the one used for
   purchase checks, server/iap_verify.gd), so one project holds both. Analytics: off (the game has its own).
2. Add app -> Android -> package **com.fatebound.game** (the Play build). Optionally a second Android app for the
   preview package **com.fatebound.kaykitrebuild**, so the preview APK can test it.
3. Download **google-services.json** for each. Keep them out of the repo; hand them over the way the other build
   files are (the build script will copy them in at build time, like the upload keystore).
4. iPhone (later, with the iOS build): Add app -> iOS -> bundle id **com.fatebound.game**; download
   **GoogleService-Info.plist**; Project settings -> Cloud Messaging -> upload an **APNs auth key (.p8)** from the
   Apple developer account (Certificates, Identifiers & Profiles -> Keys -> new key with "Apple Push Notifications
   service"). This is a different key from the App Store purchase key.

## 2. The server's sending key
1. Google Cloud console -> APIs & Services -> enable **Firebase Cloud Messaging API** (the V1 one).
2. IAM -> the service account the server already uses for purchase checks -> add the role **Firebase Cloud Messaging
   API Admin** (or make a new service account just for this and download its JSON key).
3. On the server: `/etc/fatebound-siege/fcm-service-account.json` (root-only, like the Play key); the installer will
   hand it to the service with LoadCredential, the same way as play-service-account.json.

## 3. Then I build
- An Android plugin (godot/android_plugins, like FateboundNotify) with firebase-messaging: it registers the phone and
  shows the alert when the app is closed.
- The phone sends its FCM token to the server on the social socket (only while Settings > NOTIFICATIONS is on).
- server: a token per account; war_alarm (your clan's land attacked) and war_call (your clan attacking -- JOIN) also go
  out by FCM to members who are offline, at most one every few minutes each; sent with the service account's OAuth
  token (server/iap_verify.gd already does that dance for Google Play).
- Settings > NOTIFICATIONS gets a "War alerts" switch beside "Chest ready".

Tell me when 1 and 2 are done (and where the files are) and I'll wire it up and test it on the preview APK.
