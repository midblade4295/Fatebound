// Fatebound engine services (Unity port): Godot's WebSocketPeer (modules/websocket/wsl_peer.cpp) over
// System.Net.WebSockets.ClientWebSocket, and the HTTPRequest node over System.Net.Http.
//
// WebSocketPeer keeps Godot's polling model: a background task connects and receives into a queue, and only poll()
// moves the state (CONNECTING -> OPEN -> CLOSING -> CLOSED) and makes packets readable, so game code sees changes
// exactly where it calls poll(). As in Godot, packets are readable only while OPEN and are dropped when the peer
// closes; a close frame that arrives right behind messages is applied at the next poll(), so those messages can be
// read first (in Godot that depends on how the bytes arrived). A dropped connection closes with code -1; a clean
// close gives the peer's code and reason. put_packet / send queue in order behind each other.
//
// HTTPRequest is a Node: request() starts the transfer in the background; request_completed is emitted on the main
// thread from _Process (the node must be in the tree, as in Godot).
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Security.Authentication;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public sealed partial class WebSocketPeer
    {
        public const int STATE_CONNECTING = 0, STATE_OPEN = 1, STATE_CLOSING = 2, STATE_CLOSED = 3;
        public const int WRITE_MODE_TEXT = 0, WRITE_MODE_BINARY = 1;

        /// <summary>(Godot's buffer limits: inbound is not enforced; outbound refuses a send that would queue more.)</summary>
        public int InboundBufferSize = 65535;
        public int OutboundBufferSize = 65535;
        public int MaxQueuedPackets = 4096;
        /// <summary>Seconds between keep-alive frames (0: none).</summary>
        public double HeartbeatInterval;
        public string[] SupportedProtocols = Array.Empty<string>();
        /// <summary>Extra handshake headers, "Name: value".</summary>
        public string[] HandshakeHeaders = Array.Empty<string>();

        enum Ev { Open, Data, Close, Error }

        sealed class Event
        {
            public int Gen;
            public Ev Kind;
            public byte[] Data;
            public bool Text;
            public int Code;
            public string Reason;
        }

        int _state = STATE_CLOSED;
        int _closeCode = -1;
        string _closeReason = "";
        string _url = "", _protocol = "";
        int _gen;
        ClientWebSocket _ws;
        CancellationTokenSource _cts;
        Task _sendChain = Task.CompletedTask;
        long _queuedBytes;
        int _queuedCount;
        readonly ConcurrentQueue<Event> _events = new ConcurrentQueue<Event>();
        readonly Queue<(byte[] data, bool text)> _in = new Queue<(byte[], bool)>();
        bool _wasString;
        int _packetError;

        static readonly byte[] Empty = Array.Empty<byte>();

        // ------------------------------------------------------------------ connecting
        /// <summary>connect_to_url(url, tls_client_options): OK and STATE_CONNECTING; poll() to progress.</summary>
        public int ConnectToUrl(string url, TLSOptions tlsClientOptions = null)
        {
            if (string.IsNullOrEmpty(url)) { GD.PushError("Condition \"p_url.is_empty()\" is true. Returning: ERR_INVALID_PARAMETER"); return GD.ERR_INVALID_PARAMETER; }
            if (tlsClientOptions != null && tlsClientOptions.IsServer()) return GD.ERR_INVALID_PARAMETER;
            if (_state != STATE_CLOSED && _state != STATE_CLOSING) { GD.PushError("Condition \"ready_state != STATE_CLOSED && ready_state != STATE_CLOSING\" is true. Returning: ERR_ALREADY_IN_USE"); return GD.ERR_ALREADY_IN_USE; }
            Reset();
            string u = url.Contains("://") ? url : "ws://" + url;
            if (!u.StartsWith("ws://", StringComparison.OrdinalIgnoreCase) && !u.StartsWith("wss://", StringComparison.OrdinalIgnoreCase))
            {
                GD.PushError("Invalid protocol: \"" + u.Substring(0, u.IndexOf("://", StringComparison.Ordinal) + 3) + "\" (must be either \"ws://\" or \"wss://\").");
                return GD.ERR_INVALID_PARAMETER;
            }
            if (!Uri.TryCreate(u, UriKind.Absolute, out Uri uri)) { GD.PushError("Invalid URL: " + url); return GD.ERR_INVALID_PARAMETER; }

            var ws = new ClientWebSocket();
            try
            {
                foreach (var p in SupportedProtocols) ws.Options.AddSubProtocol(p);
                foreach (var h in HandshakeHeaders)
                {
                    int c = h.IndexOf(':');
                    if (c > 0) ws.Options.SetRequestHeader(h.Substring(0, c).Trim(), h.Substring(c + 1).Trim());
                }
                if (HeartbeatInterval > 0) ws.Options.KeepAliveInterval = TimeSpan.FromSeconds(HeartbeatInterval);
            }
            catch (Exception e)
            {
                GD.PushError("WebSocketPeer: " + e.Message);
                ws.Dispose();
                return GD.ERR_INVALID_PARAMETER;
            }
            if (tlsClientOptions != null && (tlsClientOptions.IsUnsafeClient() || tlsClientOptions.GetTrustedCaChain() != null || tlsClientOptions.GetCommonNameOverride().Length > 0))
            {
                // (a runtime without per-socket certificate checks keeps the system's: a warning, not a failure)
                try { ws.Options.RemoteCertificateValidationCallback = tlsClientOptions.Validate; }
                catch (Exception e) { GD.PushWarning("WebSocketPeer: custom TLS options not supported here (" + e.GetType().Name + ")."); }
            }
            _ws = ws;
            _cts = new CancellationTokenSource();
            _url = url;
            _state = STATE_CONNECTING;
            int gen = _gen;
            var ct = _cts.Token;
            _sendChain = Task.CompletedTask;
            Task.Run(() => Run(ws, uri, gen, ct));
            return GD.OK;
        }

        void Post(int gen, Ev kind, byte[] data = null, bool text = false, int code = -1, string reason = "") =>
            _events.Enqueue(new Event { Gen = gen, Kind = kind, Data = data, Text = text, Code = code, Reason = reason });

        async Task Run(ClientWebSocket ws, Uri uri, int gen, CancellationToken ct)
        {
            try { await ws.ConnectAsync(uri, ct).ConfigureAwait(false); }
            catch (Exception) { Post(gen, Ev.Error); return; }
            Post(gen, Ev.Open, reason: ws.SubProtocol ?? "");
            var buf = new byte[65536];
            var msg = new MemoryStream();
            try
            {
                while (true)
                {
                    var r = await ws.ReceiveAsync(new ArraySegment<byte>(buf), ct).ConfigureAwait(false);
                    if (r.MessageType == WebSocketMessageType.Close)
                    {
                        var status = r.CloseStatus ?? WebSocketCloseStatus.Empty;
                        // answer the close as wslay does (the same code), unless this side started it
                        if (ws.State == WebSocketState.CloseReceived)
                        {
                            try { await ws.CloseOutputAsync(status, "", CancellationToken.None).ConfigureAwait(false); }
                            catch (Exception) { }
                        }
                        Post(gen, Ev.Close, code: (int)status, reason: r.CloseStatusDescription ?? "");
                        return;
                    }
                    msg.Write(buf, 0, r.Count);
                    if (r.EndOfMessage)
                    {
                        Post(gen, Ev.Data, msg.ToArray(), r.MessageType == WebSocketMessageType.Text);
                        msg.SetLength(0);
                    }
                }
            }
            catch (Exception) { Post(gen, Ev.Error); }
        }

        void Reset()
        {
            _gen++;
            _closeCode = -1;
            _closeReason = "";
            _url = "";
            _protocol = "";
            _wasString = false;
            _in.Clear();
            Interlocked.Exchange(ref _queuedBytes, 0);
            Interlocked.Exchange(ref _queuedCount, 0);
            Drop();
        }

        void Drop()
        {
            var ws = _ws;
            var cts = _cts;
            _ws = null;
            _cts = null;
            if (cts != null) { try { cts.Cancel(); } catch (Exception) { } }
            if (ws != null)
            {
                try { ws.Abort(); } catch (Exception) { }
                try { ws.Dispose(); } catch (Exception) { }
            }
        }

        void ToClosed()
        {
            _state = STATE_CLOSED;
            _in.Clear();
            Drop();
        }

        /// <summary>poll(): applies what happened since the last poll (open, messages, close).</summary>
        public void Poll()
        {
            bool delivered = false;
            while (_events.TryPeek(out var e))
            {
                if (e.Gen != _gen || _state == STATE_CLOSED) { _events.TryDequeue(out _); continue; }
                if (e.Kind == Ev.Close && delivered && _state == STATE_OPEN) break;     // the messages first
                _events.TryDequeue(out _);
                switch (e.Kind)
                {
                    case Ev.Open:
                        if (_state == STATE_CONNECTING) { _state = STATE_OPEN; _protocol = e.Reason; }
                        break;
                    case Ev.Data:
                        if (_state == STATE_OPEN && _in.Count < MaxQueuedPackets) { _in.Enqueue((e.Data, e.Text)); delivered = true; }
                        break;
                    case Ev.Close:
                        _closeCode = e.Code;
                        _closeReason = e.Reason;
                        ToClosed();
                        break;
                    case Ev.Error:
                        ToClosed();
                        break;
                }
            }
        }

        public int GetReadyState() => _state;
        public int GetCloseCode() => _closeCode;
        public string GetCloseReason() => _closeReason;
        public string GetRequestedUrl() => _url;
        public string GetSelectedProtocol() => _protocol;
        public void SetNoDelay(bool enabled) { }
        public int GetCurrentOutboundBufferedAmount() => _state == STATE_OPEN ? (int)Interlocked.Read(ref _queuedBytes) : 0;
        public int AcceptStream(object stream) { GD.PushError("WebSocketPeer.accept_stream() is not available in the port."); return GD.ERR_UNAVAILABLE; }

        // ------------------------------------------------------------------ sending
        /// <summary>send(message, write_mode): OK, FAILED when not open, ERR_OUT_OF_MEMORY past the outbound buffer.</summary>
        public int Send(byte[] message, int writeMode = WRITE_MODE_BINARY)
        {
            if (_state != STATE_OPEN) { GD.PushError("Condition \"ready_state != STATE_OPEN\" is true. Returning: FAILED"); return GD.FAILED; }
            message = message ?? Empty;
            if (Interlocked.CompareExchange(ref _queuedCount, 0, 0) >= MaxQueuedPackets) return GD.ERR_OUT_OF_MEMORY;
            if (OutboundBufferSize > 0 && Interlocked.Read(ref _queuedBytes) + message.Length > OutboundBufferSize)
            {
                GD.PushError("Condition \"outbound_buffer_size > 0 && (queued + size > outbound_buffer_size)\" is true. Returning: ERR_OUT_OF_MEMORY");
                return GD.ERR_OUT_OF_MEMORY;
            }
            var ws = _ws;
            int gen = _gen;
            var type = writeMode == WRITE_MODE_TEXT ? WebSocketMessageType.Text : WebSocketMessageType.Binary;
            Interlocked.Add(ref _queuedBytes, message.Length);
            Interlocked.Increment(ref _queuedCount);
            var data = message;
            _sendChain = _sendChain.ContinueWith(async _ =>
            {
                try { await ws.SendAsync(new ArraySegment<byte>(data), type, true, CancellationToken.None).ConfigureAwait(false); }
                catch (Exception) { Post(gen, Ev.Error); }
                finally
                {
                    Interlocked.Add(ref _queuedBytes, -data.Length);
                    Interlocked.Decrement(ref _queuedCount);
                }
            }, TaskScheduler.Default).Unwrap();
            return GD.OK;
        }

        public int PutPacket(byte[] buffer) => Send(buffer, WRITE_MODE_BINARY);
        public int SendText(string message) => Send(Encoding.UTF8.GetBytes(message ?? ""), WRITE_MODE_TEXT);
        public int PutVar(Var v, bool fullObjects = false) => PutPacket(GMarshal.VarToBytes(v, fullObjects));

        // ------------------------------------------------------------------ receiving
        public int GetAvailablePacketCount() => _state == STATE_OPEN ? _in.Count : 0;

        /// <summary>get_packet(): the next packet (empty, with get_packet_error() set, when there is none).</summary>
        public byte[] GetPacket()
        {
            if (_state != STATE_OPEN) { GD.PushError("Condition \"ready_state != STATE_OPEN\" is true. Returning: FAILED"); _packetError = GD.FAILED; return Empty; }
            if (_in.Count == 0) { _packetError = GD.ERR_UNAVAILABLE; return Empty; }
            var (data, text) = _in.Dequeue();
            _wasString = text;
            _packetError = GD.OK;
            return data;
        }

        public int GetPacketError() => _packetError;
        public bool WasStringPacket() => _wasString;
        public Var GetVar(bool allowObjects = false) => GMarshal.BytesToVar(GetPacket(), allowObjects);

        // ------------------------------------------------------------------ closing
        /// <summary>close(code, reason): a clean close (STATE_CLOSING until the peer answers); code -1 drops the
        /// connection at once.</summary>
        public void Close(int code = 1000, string reason = "")
        {
            if (code < 0) { _state = STATE_CLOSED; _in.Clear(); Drop(); return; }
            if (_state == STATE_OPEN)
            {
                var ws = _ws;
                int gen = _gen;
                _sendChain = _sendChain.ContinueWith(async _ =>
                {
                    try { await ws.CloseOutputAsync((WebSocketCloseStatus)code, reason ?? "", CancellationToken.None).ConfigureAwait(false); }
                    catch (Exception) { Post(gen, Ev.Error); }
                }, TaskScheduler.Default).Unwrap();
                _state = STATE_CLOSING;
            }
            else if (_state == STATE_CONNECTING || _state == STATE_CLOSED)
            {
                _state = STATE_CLOSED;
                _in.Clear();
                Drop();
            }
        }
    }

    /// <summary>Godot's HTTPClient constants (the HTTPRequest node does the requests).</summary>
    public sealed partial class HTTPClient
    {
        public const int METHOD_GET = 0, METHOD_HEAD = 1, METHOD_POST = 2, METHOD_PUT = 3, METHOD_DELETE = 4, METHOD_OPTIONS = 5,
            METHOD_TRACE = 6, METHOD_CONNECT = 7, METHOD_PATCH = 8;
        public const int STATUS_DISCONNECTED = 0, STATUS_RESOLVING = 1, STATUS_CANT_RESOLVE = 2, STATUS_CONNECTING = 3,
            STATUS_CANT_CONNECT = 4, STATUS_CONNECTED = 5, STATUS_REQUESTING = 6, STATUS_BODY = 7, STATUS_CONNECTION_ERROR = 8,
            STATUS_TLS_HANDSHAKE_ERROR = 9;
        public const int RESPONSE_OK = 200, RESPONSE_PARTIAL_CONTENT = 206, RESPONSE_NOT_FOUND = 404;

        static readonly string[] MethodNames = { "GET", "HEAD", "POST", "PUT", "DELETE", "OPTIONS", "TRACE", "CONNECT", "PATCH" };
        internal static string MethodName(int m) => m >= 0 && m < MethodNames.Length ? MethodNames[m] : "GET";

        /// <summary>query_string_from_dict(fields): "a=1&b=x%20y" (a null value: the key alone; an array: the key repeated).</summary>
        public static string QueryStringFromDict(GDict fields)
        {
            var parts = new List<string>();
            foreach (var kv in fields.Pairs())
            {
                string k = GFormat.Str(kv.Key).UriEncode();
                if (kv.Value.IsNil) parts.Add(k);
                else if (kv.Value.IsArr) foreach (var x in kv.Value.AsArr().List) parts.Add(x.IsNil ? k : k + "=" + GFormat.Str(x).UriEncode());
                else parts.Add(k + "=" + GFormat.Str(kv.Value).UriEncode());
            }
            return string.Join("&", parts);
        }
    }

    /// <summary>Godot's HTTPRequest node over HttpClient.</summary>
    public partial class HTTPRequest : Node
    {
        public const int RESULT_SUCCESS = 0, RESULT_CHUNKED_BODY_SIZE_MISMATCH = 1, RESULT_CANT_CONNECT = 2, RESULT_CANT_RESOLVE = 3,
            RESULT_CONNECTION_ERROR = 4, RESULT_TLS_HANDSHAKE_ERROR = 5, RESULT_NO_RESPONSE = 6, RESULT_BODY_SIZE_LIMIT_EXCEEDED = 7,
            RESULT_BODY_DECOMPRESS_FAILED = 8, RESULT_REQUEST_FAILED = 9, RESULT_DOWNLOAD_FILE_CANT_OPEN = 10,
            RESULT_DOWNLOAD_FILE_WRITE_ERROR = 11, RESULT_REDIRECT_LIMIT_REACHED = 12, RESULT_TIMEOUT = 13;

        /// <summary>request_completed(result, response_code, headers, body).</summary>
        public event Action<int, int, string[], byte[]> RequestCompleted;

        public bool AcceptGzip = true;
        public bool UseThreads;
        /// <summary>Seconds before RESULT_TIMEOUT (0: none).</summary>
        public double Timeout;
        public int BodySizeLimit = -1;
        public int MaxRedirects = 8;
        public string DownloadFile = "";
        public int DownloadChunkSize = 65536;

        string _httpProxyHost = "", _httpsProxyHost = "";
        int _httpProxyPort = -1, _httpsProxyPort = -1;
        TLSOptions _tls;

        sealed class Job
        {
            public CancellationTokenSource Cts;
            public long Downloaded;
            public long BodySize = -1;
            public volatile int Status = HTTPClient.STATUS_RESOLVING;
            public volatile bool Done;
            public int Result, Code;
            public string[] Headers = Array.Empty<string>();
            public byte[] Body = Array.Empty<byte>();
            public long StartUsec;
        }

        Job _job;

        public void SetHttpProxy(string host, int port) { _httpProxyHost = host ?? ""; _httpProxyPort = port; }
        public void SetHttpsProxy(string host, int port) { _httpsProxyHost = host ?? ""; _httpsProxyPort = port; }
        public void SetTlsOptions(TLSOptions options) => _tls = options;

        public int GetHttpClientStatus() => _job == null ? HTTPClient.STATUS_DISCONNECTED : _job.Status;
        public int GetDownloadedBytes() => _job == null ? 0 : (int)Interlocked.Read(ref _job.Downloaded);
        public int GetBodySize() => _job == null ? -1 : (int)_job.BodySize;

        /// <summary>request(url, custom_headers, method, request_data): OK, or why it couldn't start.</summary>
        public int Request(string url, string[] customHeaders = null, int method = HTTPClient.METHOD_GET, string requestData = "") =>
            RequestRaw(url, customHeaders, method, string.IsNullOrEmpty(requestData) ? Array.Empty<byte>() : Encoding.UTF8.GetBytes(requestData));

        public int RequestRaw(string url, string[] customHeaders, int method, byte[] requestDataRaw)
        {
            if (!IsInsideTree()) { GD.PushError("Condition \"!is_inside_tree()\" is true. Returning: ERR_UNCONFIGURED"); return GD.ERR_UNCONFIGURED; }
            if (_job != null) { GD.PushError("HTTPRequest is processing a request. Wait for completion or cancel it before attempting a new one."); return GD.ERR_BUSY; }
            if (!Uri.TryCreate(url, UriKind.Absolute, out Uri uri) || (uri.Scheme != "http" && uri.Scheme != "https"))
            {
                GD.PushError("Invalid URL: " + url);
                return GD.ERR_INVALID_PARAMETER;
            }
            var headers = new List<string>(customHeaders ?? Array.Empty<string>());
            if (AcceptGzip && !HasHeader(headers, "Accept-Encoding")) headers.Add("Accept-Encoding: gzip, deflate");
            var job = new Job { Cts = new CancellationTokenSource(), StartUsec = Time.GetTicksUsec() };
            _job = job;
            var handler = MakeHandler(uri);
            byte[] data = requestDataRaw ?? Array.Empty<byte>();
            Task.Run(() => Run(job, handler, uri, headers, method, data));
            SetProcess(true);
            return GD.OK;
        }

        static bool HasHeader(List<string> headers, string name)
        {
            foreach (var h in headers) if (h.StartsWith(name + ":", StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        HttpClientHandler MakeHandler(Uri uri)
        {
            var h = new HttpClientHandler
            {
                AllowAutoRedirect = MaxRedirects > 0,
                AutomaticDecompression = AcceptGzip ? DecompressionMethods.GZip | DecompressionMethods.Deflate : DecompressionMethods.None,
            };
            if (MaxRedirects > 0) h.MaxAutomaticRedirections = MaxRedirects;
            bool https = uri.Scheme == "https";
            string ph = https ? _httpsProxyHost : _httpProxyHost;
            int pp = https ? _httpsProxyPort : _httpProxyPort;
            if (ph.Length > 0 && pp > 0)
            {
                h.Proxy = new WebProxy(ph, pp);
                h.UseProxy = true;
            }
            var tls = _tls;
            if (tls != null && (tls.IsUnsafeClient() || tls.GetTrustedCaChain() != null || tls.GetCommonNameOverride().Length > 0))
                h.ServerCertificateCustomValidationCallback = (msg, cert, chain, errors) => tls.Validate(msg, cert, chain, errors);
            return h;
        }

        static readonly HashSet<string> ContentHeaders = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "Content-Type", "Content-Length", "Content-Encoding", "Content-Language", "Content-Location", "Content-MD5",
            "Content-Range", "Content-Disposition", "Expires", "Last-Modified", "Allow",
        };

        async Task Run(Job job, HttpClientHandler handler, Uri uri, List<string> headers, int method, byte[] data)
        {
            var ct = job.Cts.Token;
            Stream file = null;
            try
            {
                using (var client = new HttpClient(handler) { Timeout = System.Threading.Timeout.InfiniteTimeSpan })
                using (var req = new HttpRequestMessage(new HttpMethod(HTTPClient.MethodName(method)), uri))
                {
                    var contentHeaders = new List<(string, string)>();
                    bool ua = false, accept = false;
                    foreach (var line in headers)
                    {
                        int c = line.IndexOf(':');
                        if (c <= 0) continue;
                        string k = line.Substring(0, c).Trim(), v = line.Substring(c + 1).Trim();
                        if (k.Equals("User-Agent", StringComparison.OrdinalIgnoreCase)) ua = true;
                        if (k.Equals("Accept", StringComparison.OrdinalIgnoreCase)) accept = true;
                        if (ContentHeaders.Contains(k)) contentHeaders.Add((k, v));
                        else req.Headers.TryAddWithoutValidation(k, v);
                    }
                    if (!ua) req.Headers.TryAddWithoutValidation("User-Agent", "GodotEngine/4.7.2.stable.official (" + PlatformHost.Host.OSName + ")");
                    if (!accept) req.Headers.TryAddWithoutValidation("Accept", "*/*");
                    if (data.Length > 0 || method == HTTPClient.METHOD_POST || method == HTTPClient.METHOD_PUT || method == HTTPClient.METHOD_PATCH)
                    {
                        req.Content = new ByteArrayContent(data);
                        foreach (var (k, v) in contentHeaders)
                        {
                            if (k.Equals("Content-Length", StringComparison.OrdinalIgnoreCase)) continue;
                            req.Content.Headers.Remove(k);
                            req.Content.Headers.TryAddWithoutValidation(k, v);
                        }
                    }
                    job.Status = HTTPClient.STATUS_REQUESTING;
                    HttpResponseMessage resp;
                    try { resp = await client.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, ct).ConfigureAwait(false); }
                    catch (OperationCanceledException) { return; }
                    catch (Exception e) { Fail(job, ConnectResult(e)); return; }
                    using (resp)
                    {
                        int code = (int)resp.StatusCode;
                        var hl = new List<string>();
                        foreach (var h in resp.Headers) foreach (var v in h.Value) hl.Add(h.Key + ": " + v);
                        foreach (var h in resp.Content.Headers) foreach (var v in h.Value) hl.Add(h.Key + ": " + v);
                        job.Headers = hl.ToArray();
                        job.Code = code;
                        if (MaxRedirects > 0 && code >= 300 && code < 400 && resp.Headers.Location != null)
                        {
                            Finish(job, RESULT_REDIRECT_LIMIT_REACHED);
                            return;
                        }
                        job.BodySize = resp.Content.Headers.ContentLength ?? -1;
                        if (BodySizeLimit >= 0 && job.BodySize > BodySizeLimit) { Finish(job, RESULT_BODY_SIZE_LIMIT_EXCEEDED); return; }
                        if (DownloadFile.Length > 0)
                        {
                            try { file = new FileStream(FileAccess.Fix(DownloadFile), FileMode.Create, System.IO.FileAccess.Write); }
                            catch (Exception) { Finish(job, RESULT_DOWNLOAD_FILE_CANT_OPEN); return; }
                        }
                        job.Status = HTTPClient.STATUS_BODY;
                        var body = new MemoryStream();
                        var buf = new byte[Math.Max(1024, DownloadChunkSize)];
                        try
                        {
                            using (var s = await resp.Content.ReadAsStreamAsync().ConfigureAwait(false))
                            {
                                while (true)
                                {
                                    int n = await s.ReadAsync(buf, 0, buf.Length, ct).ConfigureAwait(false);
                                    if (n <= 0) break;
                                    if (file != null)
                                    {
                                        try { file.Write(buf, 0, n); }
                                        catch (Exception) { Finish(job, RESULT_DOWNLOAD_FILE_WRITE_ERROR); return; }
                                    }
                                    else body.Write(buf, 0, n);
                                    long total = Interlocked.Add(ref job.Downloaded, n);
                                    if (BodySizeLimit >= 0 && total > BodySizeLimit) { Finish(job, RESULT_BODY_SIZE_LIMIT_EXCEEDED); return; }
                                }
                            }
                        }
                        catch (OperationCanceledException) { return; }
                        catch (InvalidDataException) { Finish(job, RESULT_BODY_DECOMPRESS_FAILED); return; }
                        catch (Exception) { Fail(job, RESULT_CONNECTION_ERROR); return; }
                        job.Body = body.ToArray();
                        Finish(job, RESULT_SUCCESS);
                    }
                }
            }
            catch (Exception) { Fail(job, RESULT_REQUEST_FAILED); }
            finally
            {
                if (file != null) { try { file.Dispose(); } catch (Exception) { } }
            }
        }

        /// <summary>A failure before a response (or a broken body): no code, no headers (as Godot's _defer_done).</summary>
        static void Fail(Job job, int result)
        {
            job.Code = 0;
            job.Headers = Array.Empty<string>();
            Finish(job, result);
        }

        static void Finish(Job job, int result)
        {
            job.Result = result;
            job.Status = HTTPClient.STATUS_DISCONNECTED;
            job.Done = true;
        }

        static int ConnectResult(Exception e)
        {
            for (var x = e; x != null; x = x.InnerException)
            {
                if (x is AuthenticationException) return RESULT_TLS_HANDSHAKE_ERROR;
                if (x is SocketException se)
                {
                    switch (se.SocketErrorCode)
                    {
                        case SocketError.HostNotFound:
                        case SocketError.NoData:
                        case SocketError.TryAgain:
                            return RESULT_CANT_RESOLVE;
                        default:
                            return RESULT_CANT_CONNECT;
                    }
                }
            }
            return RESULT_CANT_CONNECT;
        }

        /// <summary>cancel_request(): stops the transfer; request_completed is not emitted.</summary>
        public void CancelRequest()
        {
            var j = _job;
            _job = null;
            if (j != null) { try { j.Cts.Cancel(); } catch (Exception) { } }
            SetProcess(false);
        }

        protected override void _Process(double delta)
        {
            var j = _job;
            if (j == null) { SetProcess(false); return; }
            if (!j.Done && Timeout > 0 && (Time.GetTicksUsec() - j.StartUsec) / 1e6 >= Timeout)
            {
                CancelRequest();
                RequestCompleted?.Invoke(RESULT_TIMEOUT, 0, Array.Empty<string>(), Array.Empty<byte>());
                return;
            }
            if (!j.Done) return;
            _job = null;
            SetProcess(false);
            RequestCompleted?.Invoke(j.Result, j.Code, j.Headers, j.Result == RESULT_SUCCESS ? j.Body : Array.Empty<byte>());
        }

        protected override void _ExitTree()
        {
            if (_job != null) CancelRequest();
            base._ExitTree();
        }
    }
}
