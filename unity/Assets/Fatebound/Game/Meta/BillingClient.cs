// Ported from godot/addons/GodotGooglePlayBilling/BillingClient.gd (the Google Play Billing plugin's GDScript wrapper,
// which scripts/meta/billing.gd loads and instantiates; Fatebound 0.31.222). The plugin itself is the Engine singleton
// "GodotGooglePlayBilling" (a stand-in the Unity client registers); its Java methods (initPlugin, startConnection,
// queryProductDetails, purchase...) and signals are reached by name (GObject, GUI/Missing/Meta_Object.cs).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;

namespace Fatebound.Game
{
    // class_name BillingClient
    public class BillingClient : Node
    {
        public event Action Connected;
        public event Action Disconnected;
        public event Action<int, string> ConnectError;
        public event Action<GDict> QueryProductDetailsResponse;
        public event Action<GDict> QueryPurchasesResponse;
        public event Action<GDict> OnPurchaseUpdated;
        public event Action<GDict> ConsumePurchaseResponse;
        public event Action<GDict> AcknowledgePurchaseResponse;

        public enum BillingResponseCode
        {
            OK = 0, // Success.
            USER_CANCELED = 1, // User cancelled the purchase flow
            SERVICE_UNAVAILABLE = 2, // Network error or no connection
            BILLING_UNAVAILABLE = 3, // A user billing error occurred during processing.
            ITEM_UNAVAILABLE = 4, // The requested product is not available for purchase.
            DEVELOPER_ERROR = 5, // Error resulting from incorrect usage of the API.
            ERROR = 6, // Fatal error during the API action.
            ITEM_ALREADY_OWNED = 7, // The purchase failed because the item is already owned.
            ITEM_NOT_OWNED = 8, // Requested action on the item failed since it is not owned by the user.
            NETWORK_ERROR = 12, // A network error occurred during the operation.
            SERVICE_DISCONNECTED = -1, // The app is not connected to the Play Store service via the Google Play Billing Library.
            FEATURE_NOT_SUPPORTED = -2, // The requested feature is not supported by the Play Store on the current device.
            SERVICE_TIMEOUT = -3 // Request timed out. It's deprecated, SERVICE_UNAVAILABLE which will be used instead of this code.
        }

        public enum ConnectionState
        {
            DISCONNECTED, // This client was not yet connected to billing service or was already closed.
            CONNECTING, // This client is currently in process of connecting to billing service.
            CONNECTED, // This client is currently connected to billing service.
            CLOSED // This client was already closed and shouldn't be used again.
        }

        public enum ProductType
        {
            INAPP, // A Product type for Android apps in-app products.
            SUBS // A Product type for Android apps subscriptions.
        }

        public enum PurchaseState
        {
            UNSPECIFIED_STATE, // Purchase with unknown state.
            PURCHASED, // Purchase is completed.
            PENDING, // Purchase is pending and not yet completed to be processed by your app.
        }

        public enum ReplacementMode
        {
            // Unknown...
            UNKNOWN_REPLACEMENT_MODE = 0,
            // The new plan takes effect immediately, and the remaining time will be prorated and credited to the user.
            // Note: This is the default behavior.
            WITH_TIME_PRORATION = 1,
            // The new plan takes effect immediately, and the billing cycle remains the same.
            CHARGE_PRORATED_PRICE = 2,
            // The new plan takes effect immediately, and the new price will be charged on next recurrence time.
            WITHOUT_PRORATION = 3,
            // Replacement takes effect immediately, and the user is charged full price of new plan and
            // is given a full billing cycle of subscription, plus remaining prorated time from the old plan.
            CHARGE_FULL_PRICE = 4,
            // The new purchase takes effect immediately, the new plan will take effect when the old item expires.
            DEFERRED = 5,
            // Indicates that this plan should remain unchanged in the new purchase.
            KEEP_EXISTING = 6
        }

        public object _plugin_singleton;              // (JNISingleton)
        public string _plugin_name = "GodotGooglePlayBilling";

        public BillingClient()
        {
            if (Engine.HasSingleton(_plugin_name))
            {
                _plugin_singleton = Engine.GetSingleton(_plugin_name);
                GObject.Call(_plugin_singleton, "initPlugin");
                _ConnectSignals();
            }
            else if (OS.HasFeature("template"))
                GD.PrintErr(_plugin_name, " singleton not found!");
        }

        public void _ConnectSignals()
        {
            GObject.Connect(_plugin_singleton, "connected", (Action)(() => Connected?.Invoke()));
            GObject.Connect(_plugin_singleton, "disconnected", (Action)(() => Disconnected?.Invoke()));
            GObject.Connect(_plugin_singleton, "connect_error", (Action<int, string>)((c, m) => ConnectError?.Invoke(c, m)));
            GObject.Connect(_plugin_singleton, "query_product_details_response", (Action<GDict>)(r => QueryProductDetailsResponse?.Invoke(r)));
            GObject.Connect(_plugin_singleton, "query_purchases_response", (Action<GDict>)(r => QueryPurchasesResponse?.Invoke(r)));
            GObject.Connect(_plugin_singleton, "on_purchase_updated", (Action<GDict>)(r => OnPurchaseUpdated?.Invoke(r)));
            GObject.Connect(_plugin_singleton, "consume_purchase_response", (Action<GDict>)(r => ConsumePurchaseResponse?.Invoke(r)));
            GObject.Connect(_plugin_singleton, "acknowledge_purchase_response", (Action<GDict>)(r => AcknowledgePurchaseResponse?.Invoke(r)));
        }

        bool HasPlugin => GD.IsInstanceValid(_plugin_singleton);     // (`if _plugin_singleton:`)

        public void StartConnection()
        {
            if (HasPlugin)
                GObject.Call(_plugin_singleton, "startConnection");
        }

        public void EndConnection()
        {
            if (HasPlugin)
                GObject.Call(_plugin_singleton, "endConnection");
        }

        public bool IsReady()
        {
            if (HasPlugin)
                return (bool)GObject.Call(_plugin_singleton, "isReady");
            return false;
        }

        public int GetConnectionState()
        {
            if (HasPlugin)
                return (int)GObject.Call(_plugin_singleton, "getConnectionState");
            return (int)ConnectionState.DISCONNECTED;
        }

        public void QueryProductDetails(string[] product_list, ProductType product_type)
        {
            var product_type_str = "inapp";
            if (product_type == ProductType.SUBS)
                product_type_str = "subs";

            if (HasPlugin)
                GObject.Call(_plugin_singleton, "queryProductDetails", Var.Of(product_list), product_type_str);
        }

        public void QueryPurchases(ProductType product_type, bool include_suspended_subs = false)
        {
            var product_type_str = "inapp";
            if (product_type == ProductType.SUBS)
                product_type_str = "subs";

            if (HasPlugin)
                GObject.Call(_plugin_singleton, "queryPurchases", product_type_str, include_suspended_subs);
        }

        static GDict Dict(Var r) => r.IsDict ? r.D : new GDict();

        public GDict Purchase(string product_id, string purchase_option_id = "", string offer_id = "", bool is_offer_personalized = false)
        {
            if (HasPlugin)
                return Dict(GObject.Call(_plugin_singleton, "purchase", product_id, purchase_option_id, offer_id, is_offer_personalized));
            return new GDict();
        }

        public GDict PurchaseSubscription(string product_id, string base_plan_id, string offer_id = "", bool is_offer_personalized = false)
        {
            if (HasPlugin)
                return Dict(GObject.Call(_plugin_singleton, "purchaseSubscription", product_id, base_plan_id, offer_id, is_offer_personalized));
            return new GDict();
        }

        public GDict UpdateSubscription(string old_product_id, string old_purchase_token, ReplacementMode replacement_mode, string new_product_id, string base_plan_id, string offer_id = "", bool is_offer_personalized = false)
        {
            if (HasPlugin)
                return Dict(GObject.Call(_plugin_singleton, "updateSubscription", old_product_id, old_purchase_token, (int)replacement_mode, new_product_id, base_plan_id, offer_id, is_offer_personalized));
            return new GDict();
        }

        public void ConsumePurchase(string purchase_token)
        {
            if (HasPlugin)
                GObject.Call(_plugin_singleton, "consumePurchase", purchase_token);
        }

        public void AcknowledgePurchase(string purchase_token)
        {
            if (HasPlugin)
                GObject.Call(_plugin_singleton, "acknowledgePurchase", purchase_token);
        }

        public void SetObfuscatedAccountId(string account_id)
        {
            if (HasPlugin)
                GObject.Call(_plugin_singleton, "setObfuscatedAccountId", account_id);
        }

        public void SetObfuscatedProfileId(string profile_id)
        {
            if (HasPlugin)
                GObject.Call(_plugin_singleton, "setObfuscatedProfileId", profile_id);
        }

        public void OpenSubscriptionsPage(string product_id = "")
        {
            if (HasPlugin)
                GObject.Call(_plugin_singleton, "openSubscriptions", product_id);
        }
    }
}
