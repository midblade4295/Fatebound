// Fatebound engine services (Unity port): Godot's FileAccess, DirAccess and ProjectSettings over System.IO with the
// engine's semantics (core/io/file_access.cpp, drivers/unix/*_unix.cpp):
//  - paths: "user://" -> PlatformHost.Host.UserDataDir (created on first use, as Godot does at startup); "res://" is the
//    game's data, read-only, through ResourceLoader.Host.ReadFile; anything else is a file-system path as is.
//  - open errors as fopen gives them (ERR_FILE_NOT_FOUND for a missing file or folder, ERR_FILE_CANT_OPEN otherwise),
//    eof_reached() only after a read ran past the end (a seek or get_length() clears it), get_line() / get_as_text()
//    decoding as Godot does (BOM skipped, NUL ends the text, "\r\n" lines).
//  - writes go straight to the OS (no user-space buffer): Godot closes a file when its last reference goes, the port
//    can't know when that is, so nothing may wait in a buffer for a close that never comes.
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using Fatebound.Sim;
using IOFileAccess = System.IO.FileAccess;

namespace Fatebound.GUI
{
    public sealed partial class FileAccess : IDisposable
    {
        public const int READ = 1, WRITE = 2, READ_WRITE = 3, WRITE_READ = 7;
        public const int COMPRESSION_FASTLZ = 0, COMPRESSION_DEFLATE = 1, COMPRESSION_ZSTD = 2, COMPRESSION_GZIP = 3, COMPRESSION_BROTLI = 4;

        [ThreadStatic] static int _lastOpenError;

        Stream _f;
        string _path = "", _abs = "";
        bool _eof;
        int _lastError;
        int _flags;

        /// <summary>big_endian: get_16/32/64 and store_16/32/64 swap bytes.</summary>
        public bool BigEndian;

        FileAccess() { }

        // ------------------------------------------------------------------ paths
        static bool _userDirMade;

        /// <summary>A file-system path for a user:// or plain path (res:// stays as it is: it isn't on the file system).</summary>
        internal static string Fix(string path)
        {
            if (path == null) return "";
            string p = path.Replace('\\', '/');
            if (p.StartsWith("user://", StringComparison.Ordinal))
            {
                string dir = PlatformHost.Host.UserDataDir;
                if (!string.IsNullOrEmpty(dir))
                {
                    if (!_userDirMade)
                    {
                        _userDirMade = true;
                        try { Directory.CreateDirectory(dir); } catch (Exception) { }
                    }
                    return dir.TrimEnd('/') + "/" + p.Substring(7);
                }
                return p.Substring(7);
            }
            return p;
        }

        internal static bool IsRes(string path) => path != null && path.StartsWith("res://", StringComparison.Ordinal);

        // ------------------------------------------------------------------ static API
        /// <summary>FileAccess.open(path, flags): the file, or null (get_open_error() says why).</summary>
        public static FileAccess Open(string path, int flags)
        {
            var fa = new FileAccess();
            int err = fa.OpenInternal(path, flags);
            _lastOpenError = err;
            return err == GD.OK ? fa : null;
        }

        public static int GetOpenError() => _lastOpenError;

        public static bool FileExists(string path)
        {
            if (IsRes(path)) return ResourceLoader.Host != null && ResourceLoader.Host.FileExists(path);
            return File.Exists(Fix(path));
        }

        /// <summary>get_file_as_bytes(path): the whole file (empty on error; get_open_error() says why).</summary>
        public static byte[] GetFileAsBytes(string path)
        {
            var f = Open(path, READ);
            if (f == null) return Array.Empty<byte>();
            using (f)
            {
                var data = new byte[f.GetLength()];
                int n = f.ReadInto(data, 0, data.Length);
                if (n < data.Length) Array.Resize(ref data, n);
                return data;
            }
        }

        /// <summary>get_file_as_string(path): the whole file as UTF-8 ("" on error).</summary>
        public static string GetFileAsString(string path)
        {
            var b = GetFileAsBytes(path);
            if (_lastOpenError != GD.OK) return "";
            return GMarshal.Utf8(b, 0, b.Length, out _);
        }

        public static long GetModifiedTime(string path)
        {
            if (IsRes(path)) return 0;
            string p = Fix(path);
            try { return File.Exists(p) || Directory.Exists(p) ? (long)(File.GetLastWriteTimeUtc(p) - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalSeconds : 0; }
            catch (Exception) { return 0; }
        }

        public static long GetSize(string path)
        {
            if (IsRes(path))
            {
                var b = ResourceLoader.Host?.ReadFile(path);
                return b != null ? b.Length : -1;
            }
            try { return new FileInfo(Fix(path)).Length; }
            catch (Exception) { GD.PushError("Failed to get size for: " + path); return -1; }
        }

        public static string GetMd5(string path)
        {
            var f = Open(path, READ);
            if (f == null) return "";
            using (f)
            using (var h = System.Security.Cryptography.MD5.Create())
                return h.ComputeHash(f._f).HexEncode();
        }

        public static string GetSha256(string path)
        {
            var f = Open(path, READ);
            if (f == null) return "";
            using (f)
            using (var h = System.Security.Cryptography.SHA256.Create())
                return h.ComputeHash(f._f).HexEncode();
        }

        // ------------------------------------------------------------------ open / close
        int OpenInternal(string path, int flags)
        {
            _path = path ?? "";
            if (flags != READ && flags != WRITE && flags != READ_WRITE && flags != WRITE_READ) return GD.ERR_INVALID_PARAMETER;
            if (IsRes(_path))
            {
                _abs = _path;
                if (flags != READ) return GD.ERR_FILE_CANT_OPEN;
                var data = ResourceLoader.Host?.ReadFile(_path);
                if (data == null) return GD.ERR_FILE_NOT_FOUND;
                _f = new MemoryStream(data, false);
                _flags = flags;
                return GD.OK;
            }
            _abs = Fix(_path);
            if (Directory.Exists(_abs)) return GD.ERR_FILE_CANT_OPEN;
            try
            {
                FileMode mode = flags == READ || flags == READ_WRITE ? FileMode.Open : FileMode.Create;
                IOFileAccess access = flags == READ ? IOFileAccess.Read : flags == WRITE ? IOFileAccess.Write : IOFileAccess.ReadWrite;
                // writes unbuffered (see the header); reads buffered
                _f = new FileStream(_abs, mode, access, FileShare.ReadWrite | FileShare.Delete, flags == READ ? 4096 : 1);
                _flags = flags;
                _lastError = GD.OK;
                return GD.OK;
            }
            catch (FileNotFoundException) { return GD.ERR_FILE_NOT_FOUND; }
            catch (DirectoryNotFoundException) { return GD.ERR_FILE_NOT_FOUND; }
            catch (Exception) { return GD.ERR_FILE_CANT_OPEN; }
        }

        public void Close()
        {
            if (_f == null) return;
            try { _f.Dispose(); } catch (Exception) { }
            _f = null;
        }

        public void Dispose() => Close();
        public bool IsOpen() => _f != null;
        public string GetPath() => _path;
        public string GetPathAbsolute() => _abs;
        public int GetError() => _lastError;

        bool Check()
        {
            if (_f != null) return true;
            GD.PushError("File must be opened before use.");
            return false;
        }

        public void Flush()
        {
            if (Check()) _f.Flush();
        }

        public void Seek(long position)
        {
            if (!Check()) return;
            try { _f.Seek(position, SeekOrigin.Begin); _eof = false; }
            catch (Exception) { _lastError = GD.ERR_FILE_CANT_READ; }
        }

        public void SeekEnd(long position = 0)
        {
            if (!Check()) return;
            try { _f.Seek(position, SeekOrigin.End); _eof = false; }
            catch (Exception) { _lastError = GD.ERR_FILE_CANT_READ; }
        }

        public long GetPosition() => Check() ? _f.Position : 0;

        /// <summary>get_length() (as Godot's: seeking to the end and back, which clears eof_reached()).</summary>
        public long GetLength()
        {
            if (!Check()) return 0;
            _eof = false;
            return _f.Length;
        }

        public bool EofReached() => _eof;

        public int Resize(long length)
        {
            if (!Check()) return GD.FAILED;
            try { _f.SetLength(length); return GD.OK; }
            catch (Exception) { return GD.FAILED; }
        }

        // ------------------------------------------------------------------ reading
        int ReadInto(byte[] dst, int off, int len)
        {
            if (!Check()) return 0;
            if ((_flags & READ) == 0) { _lastError = GD.ERR_FILE_CANT_READ; return 0; }
            int total = 0;
            try
            {
                while (total < len)
                {
                    int n = _f.Read(dst, off + total, len - total);
                    if (n <= 0) break;
                    total += n;
                }
            }
            catch (Exception) { _lastError = GD.ERR_FILE_CANT_READ; return total; }
            if (total < len) _eof = true;
            _lastError = _eof ? GD.ERR_FILE_EOF : GD.OK;
            return total;
        }

        readonly byte[] _tmp = new byte[8];

        ulong ReadLE(int n)
        {
            Array.Clear(_tmp, 0, 8);
            ReadInto(_tmp, 0, n);
            if (BigEndian) Array.Reverse(_tmp, 0, n);
            ulong v = 0;
            for (int i = n - 1; i >= 0; i--) v = (v << 8) | _tmp[i];
            return v;
        }

        public long Get8() => (long)ReadLE(1);
        public long Get16() => (long)ReadLE(2);
        public long Get32() => (long)ReadLE(4);
        public long Get64() => unchecked((long)ReadLE(8));
        public double GetHalf() => PackedBytes.HalfToFloat((ushort)ReadLE(2));
        public double GetFloat() => BitConverter.Int32BitsToSingle(unchecked((int)(uint)ReadLE(4)));
        public double GetDouble() => BitConverter.Int64BitsToDouble(unchecked((long)ReadLE(8)));
        public double GetReal() => GetFloat();

        /// <summary>get_buffer(length): up to length bytes (fewer at the end of the file).</summary>
        public byte[] GetBuffer(long length)
        {
            if (length < 0) { GD.PushError("Length of buffer cannot be smaller than 0."); return Array.Empty<byte>(); }
            if (length == 0) return Array.Empty<byte>();
            var data = new byte[length];
            int n = ReadInto(data, 0, data.Length);
            if (n < data.Length) Array.Resize(ref data, n);
            return data;
        }

        /// <summary>get_line(): up to "\n", "\r\n", "\r" or a NUL (not included).</summary>
        public string GetLine()
        {
            var line = new List<byte>();
            byte c = (byte)Get8();
            while (!_eof)
            {
                if (c == '\r' || c == '\n' || c == 0 || _lastError != GD.OK)
                {
                    if (c == '\r')
                    {
                        long prev = GetPosition() - 1;
                        if ((byte)Get8() != '\n')
                        {
                            Seek(prev);
                            Get8();
                        }
                    }
                    break;
                }
                line.Add(c);
                c = (byte)Get8();
            }
            var arr = line.ToArray();
            return GMarshal.Utf8(arr, 0, arr.Length, out _);
        }

        /// <summary>get_csv_line(delim): one CSV record (quoted fields may span lines).</summary>
        public string[] GetCsvLine(string delim = ",")
        {
            if (delim.Length != 1) { GD.PushError("Only single character delimiters are supported to parse CSV lines."); return Array.Empty<string>(); }
            string line = "";
            int qc;
            do
            {
                if (_eof) break;
                line += GetLine() + "\n";
                qc = 0;
                foreach (char ch in line) if (ch == '"') qc++;
            } while (qc % 2 != 0);
            if (line.Length > 0) line = line.Substring(0, line.Length - 1);
            var strings = new List<string>();
            bool inQuote = false;
            var cur = new StringBuilder();
            for (int i = 0; i < line.Length; i++)
            {
                char ch = line[i];
                if (!inQuote && ch == delim[0])
                {
                    strings.Add(cur.ToString());
                    cur.Clear();
                }
                else if (ch == '"')
                {
                    if (i + 1 < line.Length && line[i + 1] == '"' && inQuote) { cur.Append('"'); i++; }
                    else inQuote = !inQuote;
                }
                else cur.Append(ch);
            }
            strings.Add(cur.ToString());
            return strings.ToArray();
        }

        /// <summary>get_as_text(): the whole file as UTF-8, whatever the position (which is kept).</summary>
        public string GetAsText(bool skipCr = false)
        {
            if (!Check()) return "";
            long pos = GetPosition();
            Seek(0);
            long len = GetLength();
            var b = new byte[len];
            int n = ReadInto(b, 0, b.Length);
            Seek(pos);
            if (n != len) { GD.PushError("Condition \"r != len\" is true. Returning: String()"); return ""; }
            string s = GMarshal.Utf8(b, 0, b.Length, out _);
            return skipCr ? s.Replace("\r\n", "\n") : s;
        }

        public string GetPascalString()
        {
            long n = Get32();
            var b = GetBuffer(n);
            return GMarshal.Utf8(b, 0, b.Length, out _);
        }

        /// <summary>get_var(allow_objects): a 32-bit length then var_to_bytes data.</summary>
        public Var GetVar(bool allowObjects = false)
        {
            long len = Get32();
            var b = GetBuffer(len);
            if (b.LongLength != len) { GD.PushError("Condition \"buff.size() != len\" is true. Returning: Variant()"); return Var.Nil; }
            return GMarshal.BytesToVar(b, allowObjects);
        }

        // ------------------------------------------------------------------ writing
        bool Write(byte[] b, int off, int len)
        {
            if (!Check()) return false;
            if ((_flags & WRITE) == 0 && _flags != READ_WRITE) { _lastError = GD.ERR_FILE_CANT_WRITE; return false; }
            try
            {
                _f.Write(b, off, len);
                _lastError = GD.OK;
                return true;
            }
            catch (Exception)
            {
                _lastError = GD.ERR_FILE_CANT_WRITE;
                return false;
            }
        }

        bool WriteLE(ulong v, int n)
        {
            var b = new byte[n];
            for (int i = 0; i < n; i++) b[i] = (byte)(v >> (8 * i));
            if (BigEndian) Array.Reverse(b);
            return Write(b, 0, n);
        }

        public bool Store8(long v) => WriteLE(unchecked((ulong)v), 1);
        public bool Store16(long v) => WriteLE(unchecked((ulong)v), 2);
        public bool Store32(long v) => WriteLE(unchecked((ulong)v), 4);
        public bool Store64(long v) => WriteLE(unchecked((ulong)v), 8);
        public bool StoreHalf(double v) => WriteLE(PackedBytes.MakeHalf((float)v), 2);
        public bool StoreFloat(double v) => WriteLE(unchecked((uint)BitConverter.SingleToInt32Bits((float)v)), 4);
        public bool StoreDouble(double v) => WriteLE(unchecked((ulong)BitConverter.DoubleToInt64Bits(v)), 8);
        public bool StoreReal(double v) => StoreFloat(v);

        public bool StoreBuffer(byte[] b)
        {
            if (b == null || b.Length == 0) return true;
            return Write(b, 0, b.Length);
        }

        public bool StoreString(string s)
        {
            if (string.IsNullOrEmpty(s)) return true;
            var b = Encoding.UTF8.GetBytes(s);
            return Write(b, 0, b.Length);
        }

        public bool StoreLine(string s)
        {
            var b = Encoding.UTF8.GetBytes((s ?? "") + "\n");
            return Write(b, 0, b.Length);
        }

        public bool StorePascalString(string s)
        {
            var b = Encoding.UTF8.GetBytes(s ?? "");
            return Store32(b.Length) && StoreBuffer(b);
        }

        public bool StoreCsvLine(string[] values, string delim = ",")
        {
            if (delim.Length != 1) { GD.PushError("Condition \"p_delim.length() != 1\" is true. Returning: false"); return false; }
            var sb = new StringBuilder();
            for (int i = 0; i < values.Length; i++)
            {
                string v = values[i] ?? "";
                if (v.Contains("\"") || v.Contains(delim) || v.Contains("\n")) v = "\"" + v.Replace("\"", "\"\"") + "\"";
                if (i < values.Length - 1) v += delim;
                sb.Append(v);
            }
            return StoreLine(sb.ToString());
        }

        /// <summary>store_var(value, full_objects): a 32-bit length then var_to_bytes data.</summary>
        public bool StoreVar(Var v, bool fullObjects = false)
        {
            var b = GMarshal.VarToBytes(v, fullObjects);
            if (b.Length == 0) { GD.PushError("Error when trying to encode Variant."); return false; }
            return Store32(b.Length) && StoreBuffer(b);
        }
    }

    /// <summary>Godot's DirAccess: listing a folder and the static file operations.</summary>
    public sealed partial class DirAccess
    {
        [ThreadStatic] static int _lastOpenError;

        string _dir;                // file-system path (or res:// path)
        string _shown;              // as the game gave it
        List<(string name, bool dir)> _list;
        int _listPos;
        bool _curDir;
        string _cur = "";

        /// <summary>include_navigational: list "." and ".." too. include_hidden: list names starting with ".".</summary>
        public bool IncludeNavigational, IncludeHidden;

        DirAccess() { }

        /// <summary>DirAccess.open(path): the folder, or null (get_open_error() says why).</summary>
        public static DirAccess Open(string path)
        {
            var d = new DirAccess();
            int e = d.ChangeDir(path);
            _lastOpenError = e;
            return e == GD.OK ? d : null;
        }

        public static int GetOpenError() => _lastOpenError;

        public int ChangeDir(string path)
        {
            if (FileAccess.IsRes(path)) { _dir = path.TrimEnd('/'); _shown = path; return GD.OK; }
            string p = path;
            if (_dir != null && !path.StartsWith("/", StringComparison.Ordinal) && !path.Contains("://")) p = _shown.PathJoin(path);
            string fs = FileAccess.Fix(p);
            if (!Directory.Exists(fs)) return GD.ERR_INVALID_PARAMETER;
            _dir = Path.GetFullPath(fs);
            _shown = p;
            return GD.OK;
        }

        public string GetCurrentDir(bool includeDrive = true) => _shown;

        // ------------------------------------------------------------------ listing
        public int ListDirBegin()
        {
            _list = new List<(string, bool)>();
            _listPos = 0;
            if (FileAccess.IsRes(_dir))
            {
                // res:// listing is not available through the resource host
                return GD.OK;
            }
            try
            {
                _list.Add((".", true));
                _list.Add(("..", true));
                foreach (var e in new DirectoryInfo(_dir).EnumerateFileSystemInfos())
                    _list.Add((e.Name, (e.Attributes & FileAttributes.Directory) != 0));
            }
            catch (Exception) { return GD.ERR_CANT_OPEN; }
            return GD.OK;
        }

        /// <summary>get_next(): the next name ("" at the end), skipping "." / ".." and hidden names unless included.</summary>
        public string GetNext()
        {
            while (true)
            {
                if (_list == null || _listPos >= _list.Count) { _cur = ""; _curDir = false; return ""; }
                var e = _list[_listPos++];
                _cur = e.name;
                _curDir = e.dir;
                bool nav = e.name == "." || e.name == "..";
                if (nav && !IncludeNavigational) continue;
                if (!nav && !IncludeHidden && CurrentIsHidden()) continue;
                return e.name;
            }
        }

        public bool CurrentIsDir() => _curDir;
        public bool CurrentIsHidden() => _cur.Length > 0 && _cur[0] == '.' && _cur != "." && _cur != "..";
        public void ListDirEnd() { _list = null; _listPos = 0; }

        string[] Contents(bool dirs)
        {
            var r = new List<string>();
            ListDirBegin();
            for (string s = GetNext(); s.Length > 0; s = GetNext())
                if (CurrentIsDir() == dirs) r.Add(s);
            ListDirEnd();
            r.Sort(GMarshal.CodePointCompare);
            return r.ToArray();
        }

        public string[] GetFiles() => Contents(false);
        public string[] GetDirectories() => Contents(true);

        public static string[] GetFilesAt(string path)
        {
            var d = Open(path);
            if (d == null) { GD.PushError("Couldn't open directory at path \"" + path + "\"."); return Array.Empty<string>(); }
            return d.GetFiles();
        }

        public static string[] GetDirectoriesAt(string path)
        {
            var d = Open(path);
            if (d == null) { GD.PushError("Couldn't open directory at path \"" + path + "\"."); return Array.Empty<string>(); }
            return d.GetDirectories();
        }

        // ------------------------------------------------------------------ operations relative to this folder
        string Rel(string p)
        {
            if (p.StartsWith("/", StringComparison.Ordinal) || p.Contains("://")) return p;
            return (_shown ?? "").PathJoin(p);
        }

        public int MakeDir(string path) => MakeDirAbsolute(Rel(path));
        public int MakeDirRecursive(string path) => MakeDirRecursiveAbsolute(Rel(path));
        public bool FileExists(string path) => FileAccess.FileExists(Rel(path));
        public bool DirExists(string path) => DirExistsAbsolute(Rel(path));
        public int Remove(string path) => RemoveAbsolute(Rel(path));
        public int Rename(string from, string to) => RenameAbsolute(Rel(from), Rel(to));
        public int Copy(string from, string to, int chmodFlags = -1) => CopyAbsolute(Rel(from), Rel(to), chmodFlags);

        public long GetSpaceLeft()
        {
            try { return new DriveInfo(Path.GetPathRoot(_dir) ?? "/").AvailableFreeSpace; }
            catch (Exception) { return 0; }
        }

        // ------------------------------------------------------------------ static operations
        public static int MakeDirAbsolute(string path)
        {
            if (FileAccess.IsRes(path)) return GD.ERR_CANT_CREATE;
            string p = FileAccess.Fix(path);
            if (Directory.Exists(p) || File.Exists(p)) return GD.ERR_ALREADY_EXISTS;
            string parent = Path.GetDirectoryName(p.TrimEnd('/'));
            if (!string.IsNullOrEmpty(parent) && !Directory.Exists(parent)) return GD.ERR_CANT_CREATE;
            try { Directory.CreateDirectory(p); return GD.OK; }
            catch (Exception) { return GD.ERR_CANT_CREATE; }
        }

        public static int MakeDirRecursiveAbsolute(string path)
        {
            if (string.IsNullOrEmpty(path)) return GD.OK;
            if (FileAccess.IsRes(path)) return GD.ERR_CANT_CREATE;
            string p = FileAccess.Fix(path);
            if (!p.StartsWith("/", StringComparison.Ordinal) && !(p.Length > 1 && p[1] == ':'))
            {
                GD.PushError("Condition ... Returning: ERR_INVALID_PARAMETER (make_dir_recursive: not an absolute path: " + path + ")");
                return GD.ERR_INVALID_PARAMETER;
            }
            try
            {
                if (File.Exists(p)) { GD.PushError("Could not create directory: '" + path + "'."); return GD.ERR_CANT_CREATE; }
                Directory.CreateDirectory(p);
                return GD.OK;
            }
            catch (Exception)
            {
                GD.PushError("Could not create directory: '" + path + "'.");
                return GD.ERR_CANT_CREATE;
            }
        }

        public static bool DirExistsAbsolute(string path)
        {
            if (FileAccess.IsRes(path)) return false;
            return Directory.Exists(FileAccess.Fix(path));
        }

        /// <summary>remove_absolute(path): a file, or an empty folder. OK or FAILED.</summary>
        public static int RemoveAbsolute(string path)
        {
            if (FileAccess.IsRes(path)) return GD.FAILED;
            string p = FileAccess.Fix(path).TrimEnd('/');
            try
            {
                if (File.Exists(p)) { File.Delete(p); return GD.OK; }
                if (Directory.Exists(p)) { Directory.Delete(p, false); return GD.OK; }
            }
            catch (Exception) { }
            return GD.FAILED;
        }

        /// <summary>rename_absolute(from, to): replaces an existing file at to, as rename(2). OK or FAILED.</summary>
        public static int RenameAbsolute(string from, string to)
        {
            string a = ProjectSettings.GlobalizePath(from).TrimEnd('/'), b = ProjectSettings.GlobalizePath(to).TrimEnd('/');
            if (FileAccess.IsRes(from) || FileAccess.IsRes(to)) return GD.FAILED;
            try
            {
                if (File.Exists(a))
                {
                    if (File.Exists(b)) File.Replace(a, b, null);
                    else File.Move(a, b);
                    return GD.OK;
                }
                if (Directory.Exists(a))
                {
                    if (Directory.Exists(b) && !Directory.EnumerateFileSystemEntries(b).GetEnumerator().MoveNext()) Directory.Delete(b);
                    Directory.Move(a, b);
                    return GD.OK;
                }
            }
            catch (Exception) { }
            return GD.FAILED;
        }

        /// <summary>copy_absolute(from, to): from may be res://; to is replaced.</summary>
        public static int CopyAbsolute(string from, string to, int chmodFlags = -1)
        {
            if (from == to) { GD.PushError("Source and destination path are equal."); return GD.ERR_INVALID_PARAMETER; }
            var src = FileAccess.Open(from, FileAccess.READ);
            if (src == null) { int e = FileAccess.GetOpenError(); GD.PushError("Failed to open '" + from + "'."); return e; }
            using (src)
            {
                var dst = FileAccess.Open(to, FileAccess.WRITE);
                if (dst == null) { int e = FileAccess.GetOpenError(); GD.PushError("Failed to open '" + to + "'."); return e; }
                using (dst)
                {
                    long size = src.GetLength();
                    while (size > 0)
                    {
                        var chunk = src.GetBuffer(Math.Min(size, 65536));
                        if (chunk.Length == 0) return GD.FAILED;
                        if (!dst.StoreBuffer(chunk)) return GD.ERR_FILE_CANT_WRITE;
                        size -= chunk.Length;
                    }
                }
            }
            return GD.OK;
        }
    }

    /// <summary>Godot's ProjectSettings: the settings the game reads (from godot/project.godot, plus the engine defaults
    /// it asks for) and the res:// / user:// path conversions.</summary>
    public static partial class ProjectSettings
    {
        /// <summary>Where res:// would be on disk ("" in an exported game: res:// paths then globalize to themselves
        /// without the prefix, as Godot does).</summary>
        public static string ResourcePath = "";

        static readonly GDict _settings = new GDict
        {
            { "application/config/name", "Fatebound" },
            { "application/config/description", "Fatebound native game client — Play testing build." },
            { "application/config/icon", "res://assets/branding/icon.png" },
            { "application/config/version", "" },
            { "application/run/main_scene", "res://scenes/Boot.tscn" },
            { "application/run/max_fps", 0 },
            { "display/window/size/viewport_width", 760 },
            { "display/window/size/viewport_height", 420 },
            { "display/window/size/window_width_override", 1520 },
            { "display/window/size/window_height_override", 840 },
            { "display/window/stretch/mode", "canvas_items" },
            { "display/window/stretch/aspect", "expand" },
            { "display/window/handheld/orientation", 4 },
            { "physics/common/physics_ticks_per_second", 60 },
            { "rendering/renderer/rendering_method", "mobile" },
            { "rendering/renderer/rendering_method.mobile", "mobile" },
            { "gui/common/snap_controls_to_pixels", false },
        };

        public static Var GetSetting(string name, Var defaultValue = default)
        {
            lock (_settings) return _settings.TryGetValue(name, out Var v) ? v : defaultValue;
        }

        public static void SetSetting(string name, Var value)
        {
            lock (_settings)
            {
                if (value.IsNil) _settings.Erase(name);
                else _settings[name] = value;
            }
        }

        public static bool HasSetting(string name)
        {
            lock (_settings) return _settings.Has(name);
        }

        public static string GlobalizePath(string path)
        {
            if (path == null) return "";
            if (path.StartsWith("res://", StringComparison.Ordinal))
                return ResourcePath.Length > 0 ? ResourcePath.TrimEnd('/') + "/" + path.Substring(6) : path.Substring(6);
            if (path.StartsWith("user://", StringComparison.Ordinal)) return FileAccess.Fix(path);
            return path;
        }

        public static string LocalizePath(string path)
        {
            if (path == null) return "";
            if (path.StartsWith("res://", StringComparison.Ordinal) || path.StartsWith("user://", StringComparison.Ordinal)) return path;
            string p = path.Replace('\\', '/');
            if (ResourcePath.Length > 0 && p.StartsWith(ResourcePath.TrimEnd('/') + "/", StringComparison.Ordinal))
                return "res://" + p.Substring(ResourcePath.TrimEnd('/').Length + 1);
            if (!p.StartsWith("/", StringComparison.Ordinal) && !(p.Length > 1 && p[1] == ':')) return "res://" + p;
            return p;
        }

        /// <summary>Resource packs can't be mounted by the port (content arrives as Unity assets): always false.</summary>
        public static bool LoadResourcePack(string pack, bool replaceFiles = true, long offset = 0) => false;
    }
}
