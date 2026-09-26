# Native Play testing bundle: versionCode22 / 1.1.0

Prepared in response to the explicit request for a Play Store upload file.
Package: com.fatebound.game. Existing upload key is reused by the existing CI
signing stage. The separate native preview retains its package/certificate.
No Play Console upload, rollout, main merge or server change is performed.

Upload to internal testing first. Old WebView progression and its guest identity
are not automatically imported; back up the older save before updating.
Native Settings & Saves accepts progression JSON and the legacy cloud code.
The WebView data is not deleted by this build, but native code does not read it.

No physical-phone test has been performed. The generated release bundle is
checked for its signature, existing upload certificate, package/version, SDK,
packaged native assets and native-library alignment before delivery.
