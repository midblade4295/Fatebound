// Ported from godot/scripts/meta/platform.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;

namespace Fatebound.Game
{
    // 0.31.130 (the iOS port, IOS_PORT_SPEC_FOR_CLAUDE.md §1): which phone and which store the game is on. Everything that
    // differs between Android (Google Play) and iOS (the App Store) asks here instead of OS.get_name(), so on Android every
    // answer is exactly what the old checks gave.
    //   store()          "play" on Android, "appstore" on iOS, "none" elsewhere (desktop, tests)
    //   store_url()      the game's page in that store (the update screen's UPDATE)
    //   has_iap()        the store's purchase plugin is in this build
    //   has_cloud_save() the store keeps a copy of the progress (Play Games; iOS v1 has none -- the server account)
    //   has_achievements() the store's achievements service is in this build
    // Tests pretend to be a platform with Platform.forced = "ios" (or "android"); "" is the real one.
    public static class Platform
    {
        public const string PACKAGE = "com.fatebound.game";                 // Play package and iOS bundle id (the same string)
        public const string PLAY_MARKET_URL = "market://details?id=" + PACKAGE;
        public const string PLAY_WEB_URL = "https://play.google.com/store/apps/details?id=" + PACKAGE;
        // The App Store's numeric Apple ID of the app (App Store Connect > App Information): "Fatebound Siege" (0.31.133)
        public const string APPLE_APP_ID = "6822556363";
        public const string APP_STORE_SEARCH_URL = "https://apps.apple.com/us/search?term=Fatebound";

        public const string PLAY_BILLING = "GodotGooglePlayBilling";        // Engine singletons of the Android plugins
        public const string PLAY_GAMES = "GodotPlayGameServices";
        public const string STOREKIT_CLASS = "StoreKitManager";             // GodotApplePlugins' classes (a GDExtension, in the iOS build only)
        public const string GAMECENTER_CLASS = "GameCenterManager";

        public static string forced = "";                               // tests: "android" | "ios" | "" (the real platform)

        public static string OsName()
        {
            switch (forced)
            {
                case "android":
                    return "Android";
                case "ios":
                    return "iOS";
            }
            return OS.GetName();
        }

        public static bool IsAndroid()
        {
            return OsName() == "Android";
        }

        public static bool IsIos()
        {
            return OsName() == "iOS";
        }

        public static string Store()
        {
            if (IsAndroid())
                return "play";
            if (IsIos())
                return "appstore";
            return "none";
        }

        public static string AppStoreUrl()
        {
            return APPLE_APP_ID != "" ? "https://apps.apple.com/app/id" + APPLE_APP_ID : APP_STORE_SEARCH_URL;
        }

        public static string StoreUrl()
        {
            return IsIos() ? AppStoreUrl() : PLAY_WEB_URL;
        }

        public static GArray StoreUrls()
        {
            // what UPDATE tries, in order: the store app first, then its web page
            if (IsIos())
                return GArray.Of(AppStoreUrl());
            if (IsAndroid())
                return GArray.Of(PLAY_MARKET_URL, PLAY_WEB_URL);
            return GArray.Of(PLAY_WEB_URL);
        }

        public static string StoreName()
        {
            return IsIos() ? "the App Store" : "Google Play";
        }

        public static string StoreShort()
        {
            // the shop's line ("Google Play  ·  gems never change damage", "in the Google Play version")
            return IsIos() ? "App Store" : "Google Play";
        }

        public static string StoreButton()
        {
            // a gem pack's button where the store's plugin isn't in the build
            return IsIos() ? "APP STORE" : "PLAY STORE";
        }

        public static bool HasClass(string cls)
        {
            return ClassDB.ClassExists(cls) && ClassDB.CanInstantiate(cls);
        }

        public static bool HasIap()
        {
            if (IsIos())
                return HasClass(STOREKIT_CLASS);
            return Engine.HasSingleton(PLAY_BILLING);
        }

        public static bool HasCloudSave()
        {
            if (IsIos())
                return false;                                  // v1: the server account (transfer code / Game Center link)
            return Engine.HasSingleton(PLAY_GAMES);
        }

        public static bool HasAchievements()
        {
            if (IsIos())
                return HasClass(GAMECENTER_CLASS);
            return Engine.HasSingleton(PLAY_GAMES);
        }

        public static string Plat()
        {
            // 0.31.132: usage statistics' session_start "plat" (the reports split players by phone)
            if (IsIos())
                return "ios";
            return IsAndroid() ? "android" : "desktop";
        }

        public static bool TracksBoot()
        {
            // BootGuard's crash tracking (a phone, not the desktop)
            return IsAndroid() || IsIos();
        }
    }
}
