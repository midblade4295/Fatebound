// Ported from godot/scripts/meta/apple_token.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;

namespace Fatebound.Game
{
    // 0.31.130 (the iOS port, IOS_PORT_SPEC_FOR_CLAUDE.md §3): the appAccountToken an App Store purchase carries -- which
    // Fatebound account bought it. A UUID version 5 (RFC 9562: SHA-1 of a namespace and a name) of the server account's id,
    // so the phone (scripts/meta/billing_ios.gd) and the server (server/iap_verify_apple.gd) each work it out alone and the
    // server refuses a purchase whose token isn't the account's. Nothing secret: it only binds a purchase to an account.
    //   python3 -c "import uuid; print(uuid.uuid5(uuid.UUID('14e4328b-9f9f-5cb3-932f-4b0af036d9b0'), '<account id>'))"
    // NAMESPACE is uuid5(NAMESPACE_DNS, "account.fatebound.game"); never change it (old purchases carry tokens made with it).
    public static class AppleToken
    {
        public const string NAMESPACE = "14e4328b-9f9f-5cb3-932f-4b0af036d9b0";

        public static string ForAccount(string acct)
        {
            if (acct == "")
                return "";
            return Uuid5(NAMESPACE, acct);
        }

        public static string Uuid5(string ns, string name)
        {
            var hc = new HashingContext();
            hc.Start(HashingContext.HASH_SHA1);
            hc.Update(ns.Replace("-", "").HexDecode());
            hc.Update(name.ToUtf8Buffer());
            var b = hc.Finish().Slice(0, 16);
            b[6] = (byte)((b[6] & 0x0f) | 0x50);                  // version 5
            b[8] = (byte)((b[8] & 0x3f) | 0x80);                  // the RFC variant
            var h = b.HexEncode();
            return GD.Fmt("%s-%s-%s-%s-%s", h.Substr(0, 8), h.Substr(8, 4), h.Substr(12, 4), h.Substr(16, 4), h.Substr(20, 12));
        }
    }
}
