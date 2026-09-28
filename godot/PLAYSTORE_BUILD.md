# Fatebound Siege Play testing bundle: versionCode24 / 1.2.0-siege-online

Prepared in response to the explicit request for a Play Store upload file.
Package: `com.fatebound.game`. All four Android ABIs are enabled: arm32, arm64, x86, x86_64.
The Play upload certificate matches the previous native Play bundle. The separate Siege
preview (`com.fatebound.kaykitrebuild`) retains its own package and signing identity.
No Play Console upload, rollout, main merge or server change is performed.

Upload to **internal testing first**. Confirm that versionCode 24 is unused in Play Console;
the repo proves that versionCode 23 existed, but cannot prove which codes Play has consumed.
This is a whole-game conversion to Siege, including online play backed by the existing
`fatebound-siege.service` at `wss://136-113-125-3.sslip.io/fatebound/siege/ws`.
Old WebView progression and its guest identity are not automatically imported; back up
the older save before updating.
Native Settings & Saves accepts progression JSON and the legacy cloud code.
The WebView data is not deleted by this build, but native code does not read it.

No physical-phone test has been performed. The generated release bundle is
checked for its signature, existing upload certificate, package/version, SDK,
packaged Siege assets, Vulkan mobile rendering settings and native-library alignment
before delivery. The public repository currently exposes the Play upload keystore and
password; request an upload-key reset in Play Console and move future signing to secrets.
Do not paste credentials into an AI handoff or Play notes.
