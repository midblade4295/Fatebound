Godot Google Play Billing 3.3.0 (Play Billing Library 9.1.0), MIT licence (LICENSE).
Built here from github.com/godot-sdk-integrations/godot-google-play-billing commit e494f37
(`./gradlew :godot-google-play-billing:assemble`). Only change: export_plugin.gd hands the AAR and the billing
dependency to Gradle presets only, so the non-Gradle preview builds export as before.
The game talks to it through scripts/meta/billing.gd, never directly.
