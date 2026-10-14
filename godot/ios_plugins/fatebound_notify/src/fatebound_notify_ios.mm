// Fatebound: chest-ready local notifications on iOS -- the UNUserNotificationCenter side. See fatebound_notify_ios.h.
#include "fatebound_notify_ios.h"

#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>

#include <atomic>

using namespace godot;

namespace {

// -1 not known yet, 0 no, 1 yes. Written from UserNotifications' completion handlers (any thread), read by the game.
std::atomic<int> g_allowed(-1);

NSString *ns(const String &s) {
	NSString *out = [NSString stringWithUTF8String:s.utf8().get_data()];
	return out != nil ? out : @"";
}

bool allowed_status(UNAuthorizationStatus st) {
	if (st == UNAuthorizationStatusAuthorized || st == UNAuthorizationStatusProvisional) {
		return true;
	}
	if (@available(iOS 14.0, *)) {
		return st == UNAuthorizationStatusEphemeral;
	}
	return false;
}

} // namespace

FateboundNotifyIOS::FateboundNotifyIOS() {
	refresh();
}

void FateboundNotifyIOS::refresh() {
	[[UNUserNotificationCenter currentNotificationCenter] getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
		g_allowed.store(allowed_status(settings.authorizationStatus) ? 1 : 0);
	}];
}

bool FateboundNotifyIOS::hasPermission() {
	refresh(); // (the player may have changed it in iOS Settings: the next ask sees it)
	return g_allowed.load() == 1;
}

void FateboundNotifyIOS::requestPermission() {
	UNAuthorizationOptions opts = UNAuthorizationOptionAlert | UNAuthorizationOptionSound;
	[[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:opts
																		completionHandler:^(BOOL granted, NSError *error) {
																			g_allowed.store(granted ? 1 : 0);
																		}];
}

void FateboundNotifyIOS::schedule(int64_t id, const String &title, const String &body, int64_t delay_seconds) {
	UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
	content.title = ns(title);
	content.body = ns(body);
	content.sound = [UNNotificationSound defaultSound];
	NSTimeInterval at = (NSTimeInterval)(delay_seconds < 1 ? 1 : delay_seconds);
	UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:at repeats:NO];
	NSString *ident = [NSString stringWithFormat:@"fatebound.chest.%lld", (long long)id];
	UNNotificationRequest *req = [UNNotificationRequest requestWithIdentifier:ident content:content trigger:trigger];
	[[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:req withCompletionHandler:nil];
}

void FateboundNotifyIOS::cancelAll() {
	UNUserNotificationCenter *c = [UNUserNotificationCenter currentNotificationCenter];
	[c removeAllPendingNotificationRequests];
	[c removeAllDeliveredNotifications];
}

PackedStringArray FateboundNotifyIOS::calls() const {
	return PackedStringArray();
}
