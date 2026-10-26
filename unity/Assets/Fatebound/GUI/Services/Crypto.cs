// Fatebound engine services (Unity port): Godot's HashingContext (MD5 / SHA-1 / SHA-256 in steps), Crypto (random
// bytes, HMAC, constant-time compare; key generation, signing and encryption are not available), X509Certificate (PEM
// certificate chains, for TLSOptions), CryptoKey (a stub) and TLSOptions (what WebSocketPeer / HTTPRequest verify a
// server against).
using System;
using System.Collections.Generic;
using System.Net.Security;
using System.Security.Cryptography;
using System.Text;
using Fatebound.Sim;
using SysCert = System.Security.Cryptography.X509Certificates.X509Certificate2;
using SysChain = System.Security.Cryptography.X509Certificates.X509Chain;

namespace Fatebound.GUI
{
    public sealed class HashingContext
    {
        public const int HASH_MD5 = 0, HASH_SHA1 = 1, HASH_SHA256 = 2;

        IncrementalHash _ctx;

        /// <summary>start(type): OK, or ERR_ALREADY_IN_USE while a hash is running.</summary>
        public int Start(int type)
        {
            if (_ctx != null) { GD.PushError("Condition \"ctx != nullptr\" is true. Returning: ERR_ALREADY_IN_USE"); return GD.ERR_ALREADY_IN_USE; }
            switch (type)
            {
                case HASH_MD5: _ctx = IncrementalHash.CreateHash(HashAlgorithmName.MD5); break;
                case HASH_SHA1: _ctx = IncrementalHash.CreateHash(HashAlgorithmName.SHA1); break;
                case HASH_SHA256: _ctx = IncrementalHash.CreateHash(HashAlgorithmName.SHA256); break;
                default: return GD.ERR_UNAVAILABLE;
            }
            return GD.OK;
        }

        /// <summary>update(chunk): ERR_UNCONFIGURED before start(), FAILED for an empty chunk (as Godot).</summary>
        public int Update(byte[] chunk)
        {
            if (_ctx == null) { GD.PushError("Parameter \"ctx\" is null."); return GD.ERR_UNCONFIGURED; }
            if (chunk == null || chunk.Length == 0) { GD.PushError("Condition \"len == 0\" is true. Returning: FAILED"); return GD.FAILED; }
            _ctx.AppendData(chunk);
            return GD.OK;
        }

        /// <summary>finish(): the digest; the context can start() again.</summary>
        public byte[] Finish()
        {
            if (_ctx == null) { GD.PushError("Parameter \"ctx\" is null."); return Array.Empty<byte>(); }
            var r = _ctx.GetHashAndReset();
            _ctx.Dispose();
            _ctx = null;
            return r;
        }
    }

    public sealed class Crypto
    {
        static readonly RandomNumberGenerator Rng = RandomNumberGenerator.Create();

        public byte[] GenerateRandomBytes(int size)
        {
            if (size < 0) { GD.PushError("Condition \"p_bytes < 0\" is true."); return Array.Empty<byte>(); }
            var b = new byte[size];
            lock (Rng) Rng.GetBytes(b);
            return b;
        }

        /// <summary>hmac_digest(hash_type, key, msg).</summary>
        public byte[] HmacDigest(int hashType, byte[] key, byte[] msg)
        {
            HMAC h;
            switch (hashType)
            {
                case HashingContext.HASH_MD5: h = new HMACMD5(key); break;
                case HashingContext.HASH_SHA1: h = new HMACSHA1(key); break;
                case HashingContext.HASH_SHA256: h = new HMACSHA256(key); break;
                default: GD.PushError("Unsupported hash type."); return Array.Empty<byte>();
            }
            using (h) return h.ComputeHash(msg ?? Array.Empty<byte>());
        }

        public bool ConstantTimeCompare(byte[] a, byte[] b)
        {
            if (a == null || b == null || a.Length != b.Length) return false;
            int d = 0;
            for (int i = 0; i < a.Length; i++) d |= a[i] ^ b[i];
            return d == 0;
        }

        // Not available in the port (the game doesn't use them): each says so and returns nothing.
        public CryptoKey GenerateRsa(int size) { Unavailable("generate_rsa"); return null; }
        public X509Certificate GenerateSelfSignedCertificate(CryptoKey key, string issuer = "", string notBefore = "", string notAfter = "") { Unavailable("generate_self_signed_certificate"); return null; }
        public byte[] Sign(int hashType, byte[] hash, CryptoKey key) { Unavailable("sign"); return Array.Empty<byte>(); }
        public bool Verify(int hashType, byte[] hash, byte[] signature, CryptoKey key) { Unavailable("verify"); return false; }
        public byte[] Encrypt(CryptoKey key, byte[] plaintext) { Unavailable("encrypt"); return Array.Empty<byte>(); }
        public byte[] Decrypt(CryptoKey key, byte[] ciphertext) { Unavailable("decrypt"); return Array.Empty<byte>(); }

        static void Unavailable(string what) => GD.PushError("Crypto." + what + "() is not available in the port.");
    }

    /// <summary>A private/public key (not available in the port: load fails).</summary>
    public sealed class CryptoKey
    {
        public int Load(string path, bool publicOnly = false) => GD.ERR_UNAVAILABLE;
        public int LoadFromString(string key, bool publicOnly = false) => GD.ERR_UNAVAILABLE;
        public int Save(string path, bool publicOnly = false) => GD.ERR_UNAVAILABLE;
        public string SaveToString(bool publicOnly = false) => "";
        public bool IsPublicOnly() => false;
    }

    /// <summary>Godot's X509Certificate: a PEM chain of certificates.</summary>
    public sealed class X509Certificate
    {
        internal readonly List<SysCert> Certs = new List<SysCert>();

        /// <summary>load(path): a PEM file with one or more certificates.</summary>
        public int Load(string path)
        {
            var f = FileAccess.Open(path, FileAccess.READ);
            if (f == null) { GD.PushError("Cannot open X509Certificate file '" + path + "'."); return FileAccess.GetOpenError(); }
            string text;
            using (f) text = f.GetAsText();
            return LoadFromString(text);
        }

        public int LoadFromString(string pem)
        {
            Certs.Clear();
            const string Begin = "-----BEGIN CERTIFICATE-----", End = "-----END CERTIFICATE-----";
            int at = 0;
            while (true)
            {
                int b = pem.IndexOf(Begin, at, StringComparison.Ordinal);
                if (b < 0) break;
                int e = pem.IndexOf(End, b, StringComparison.Ordinal);
                if (e < 0) break;
                string body = pem.Substring(b + Begin.Length, e - b - Begin.Length);
                if (!GMarshal.B64Decode(body.Replace("\r", "").Replace("\n", "").Replace(" ", ""), out byte[] der)) return GD.ERR_PARSE_ERROR;
                try { Certs.Add(new SysCert(der)); }
                catch (CryptographicException) { return GD.ERR_PARSE_ERROR; }
                at = e + End.Length;
            }
            if (Certs.Count == 0) { GD.PushError("Error parsing X509 certificates."); return GD.ERR_PARSE_ERROR; }
            return GD.OK;
        }

        public string SaveToString()
        {
            var sb = new StringBuilder();
            foreach (var c in Certs)
            {
                sb.Append("-----BEGIN CERTIFICATE-----\n");
                string b64 = Convert.ToBase64String(c.RawData);
                for (int i = 0; i < b64.Length; i += 64) sb.Append(b64, i, Math.Min(64, b64.Length - i)).Append('\n');
                sb.Append("-----END CERTIFICATE-----\n");
            }
            return sb.ToString();
        }

        public int Save(string path)
        {
            var f = FileAccess.Open(path, FileAccess.WRITE);
            if (f == null) return FileAccess.GetOpenError();
            using (f) f.StoreString(SaveToString());
            return GD.OK;
        }
    }

    /// <summary>Godot's TLSOptions: how a client verifies the server (the system's roots, a given chain, or not at all).</summary>
    public sealed class TLSOptions
    {
        X509Certificate _trusted;
        string _commonName = "";
        bool _unsafe, _server;

        TLSOptions() { }

        /// <summary>TLSOptions.client(trusted_chain, common_name_override): verified against the chain (the system's
        /// roots when null), the host name or common_name_override.</summary>
        public static TLSOptions Client(X509Certificate trustedChain = null, string commonNameOverride = "") =>
            new TLSOptions { _trusted = trustedChain, _commonName = commonNameOverride ?? "" };

        /// <summary>TLSOptions.client_unsafe(trusted_chain): the server isn't verified (tests only).</summary>
        public static TLSOptions ClientUnsafe(X509Certificate trustedChain = null) => new TLSOptions { _trusted = trustedChain, _unsafe = true };

        public static TLSOptions Server(CryptoKey key, X509Certificate certificate) => new TLSOptions { _server = true };

        public bool IsServer() => _server;
        public bool IsUnsafeClient() => _unsafe;
        public string GetCommonNameOverride() => _commonName;
        public X509Certificate GetTrustedCaChain() => _trusted;

        /// <summary>The certificate check for System.Net (RemoteCertificateValidationCallback).</summary>
        internal bool Validate(object sender, System.Security.Cryptography.X509Certificates.X509Certificate cert, SysChain chain, SslPolicyErrors errors)
        {
            if (_unsafe) return true;
            if (_trusted == null || _trusted.Certs.Count == 0)
                return errors == SslPolicyErrors.None || (errors == SslPolicyErrors.RemoteCertificateNameMismatch && _commonName.Length > 0);
            if (cert == null) return false;
            if ((errors & SslPolicyErrors.RemoteCertificateNameMismatch) != 0 && _commonName.Length == 0) return false;
            using (var c = new SysChain())
            {
                c.ChainPolicy.RevocationMode = System.Security.Cryptography.X509Certificates.X509RevocationMode.NoCheck;
                c.ChainPolicy.VerificationFlags = System.Security.Cryptography.X509Certificates.X509VerificationFlags.AllowUnknownCertificateAuthority;
                foreach (var t in _trusted.Certs) c.ChainPolicy.ExtraStore.Add(t);
                var leaf = cert as SysCert ?? new SysCert(cert);
                if (!c.Build(leaf)) return false;
                var root = c.ChainElements[c.ChainElements.Count - 1].Certificate;
                foreach (var t in _trusted.Certs)
                    if (t.Thumbprint == root.Thumbprint) return true;
                return false;
            }
        }
    }
}
