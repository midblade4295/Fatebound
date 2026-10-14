extends RefCounted
# 0.31.130 (the iOS port, IOS_PORT_SPEC_FOR_CLAUDE.md §1): which store's purchases the app uses. Both have one face
# (signals changed / granted / note; prices, busy, ready_; active, price, can_buy, buy, resume; setup(profile)), so the
# shop and the app only ever talk to what this hands back:
#   Android (and the desktop, where nothing is active)  scripts/meta/billing.gd       Google Play, unchanged
#   iOS                                                 scripts/meta/billing_ios.gd   the App Store (StoreKit 2)
# The App Store one also has restore() (RESTORE PURCHASES) and `restoring`.
const Platform = preload("res://scripts/meta/platform.gd")
const Billing = preload("res://scripts/meta/billing.gd")
const BillingIos = preload("res://scripts/meta/billing_ios.gd")

static func script_for(store: String = "") -> Script:
	return BillingIos if (store if store != "" else Platform.store()) == "appstore" else Billing

static func make(store: String = "") -> Node:
	return script_for(store).new()

static func can_restore(b) -> bool:
	# the shop shows RESTORE PURCHASES for a store that has it (the App Store)
	return b != null and b.has_method("restore") and bool(b.active())
