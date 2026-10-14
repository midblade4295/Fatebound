// Fatebound: the stand-in for FateboundNotifyIOS off Apple platforms (a Linux build checks the binding and the calls
// notify.gd makes; nothing is ever shown). On iOS fatebound_notify_ios.mm is built instead.
#if !defined(__APPLE__)

#include "fatebound_notify_ios.h"

using namespace godot;

namespace {
bool g_allowed = false;

PackedStringArray &log() {
	// made on first use: a Godot type can't be built while the library loads (godot-cpp isn't set up yet)
	static PackedStringArray *calls = new PackedStringArray();
	return *calls;
}
} // namespace

FateboundNotifyIOS::FateboundNotifyIOS() {
	refresh();
}

void FateboundNotifyIOS::refresh() {
}

bool FateboundNotifyIOS::hasPermission() {
	return g_allowed;
}

void FateboundNotifyIOS::requestPermission() {
	log().push_back("request");
	g_allowed = true;
}

void FateboundNotifyIOS::schedule(int64_t id, const String &title, const String &body, int64_t delay_seconds) {
	log().push_back(String("schedule ") + String::num_int64(id) + " " + title + " | " + body + " | " +
			String::num_int64(delay_seconds < 1 ? 1 : delay_seconds));
}

void FateboundNotifyIOS::cancelAll() {
	log().push_back("cancel");
}

PackedStringArray FateboundNotifyIOS::calls() const {
	return log();
}

#endif
