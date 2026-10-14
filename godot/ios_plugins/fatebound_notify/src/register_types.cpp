// Fatebound: FateboundNotifyIOS's GDExtension entry point (fatebound_notify_ios_init, named in the .gdextension that
// build_ios.sh writes). Godot's iOS export links the static library and registers this symbol itself.
#include "fatebound_notify_ios.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void FateboundNotifyIOS::_bind_methods() {
	ClassDB::bind_method(D_METHOD("hasPermission"), &FateboundNotifyIOS::hasPermission);
	ClassDB::bind_method(D_METHOD("requestPermission"), &FateboundNotifyIOS::requestPermission);
	ClassDB::bind_method(D_METHOD("schedule", "id", "title", "body", "delay_seconds"), &FateboundNotifyIOS::schedule);
	ClassDB::bind_method(D_METHOD("cancelAll"), &FateboundNotifyIOS::cancelAll);
	ClassDB::bind_method(D_METHOD("refresh"), &FateboundNotifyIOS::refresh);
	ClassDB::bind_method(D_METHOD("calls"), &FateboundNotifyIOS::calls);
}

static void initialize_fatebound_notify(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(FateboundNotifyIOS);
}

static void uninitialize_fatebound_notify(ModuleInitializationLevel p_level) {
}

extern "C" {
GDExtensionBool GDE_EXPORT fatebound_notify_ios_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_fatebound_notify);
	init_obj.register_terminator(uninitialize_fatebound_notify);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
