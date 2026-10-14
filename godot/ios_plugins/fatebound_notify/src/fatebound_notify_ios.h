// Fatebound: chest-ready local notifications on iOS (IOS_PORT_SPEC_FOR_CLAUDE.md §6, status row 7).
// The iOS twin of the FateboundNotify Android plugin (godot/android_plugins/fatebound_notify): the same four calls with
// the same names, so scripts/meta/notify.gd drives either one unchanged.
//   hasPermission()                          may the game post notifications (UNAuthorizationStatus, cached)
//   requestPermission()                      iOS's "Allow notifications?" (shown once by iOS; then Settings)
//   schedule(id, title, body, delaySeconds)  one notification in delaySeconds, replacing one with the same id
//   cancelAll()                              every scheduled one off, and any already showing
// A GDExtension (godot-cpp), built on the macOS CI into a static xcframework (build_ios.sh). Off Apple platforms the
// same class builds with a stand-in that only records the calls, for checking the binding on Linux.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class FateboundNotifyIOS : public RefCounted {
	GDCLASS(FateboundNotifyIOS, RefCounted);

protected:
	static void _bind_methods();

public:
	FateboundNotifyIOS();

	bool hasPermission();
	void requestPermission();
	void schedule(int64_t id, const String &title, const String &body, int64_t delay_seconds);
	void cancelAll();
	void refresh();

	// What was asked (the stand-in records every call; on iOS it stays empty). For tests.
	PackedStringArray calls() const;
};

} // namespace godot
