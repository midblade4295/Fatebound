#!/usr/bin/env python3
"""Godot 4 .pck files (format 2-4, unencrypted), for the content packs (0.31.95).
  list  FILE.pck [--sum]             path and size of every file
  strip IN.pck OUT.pck PREFIX...     a copy without the files whose path starts with a PREFIX (Godot puts the project
                                     settings, the uid cache and the autoload scripts into every pack; a content pack
                                     must hold data only: no code to run, nothing that could shadow a newer build's)"""
import struct
import sys

HEADER = 4 + 5 * 4 + 8 + 8 + 16 * 4      # magic, version + engine major/minor/patch + flags, file base, dir offset, reserved
ALIGN = 16


def read(path):
    with open(path, "rb") as f:
        if f.read(4) != b"GDPC":
            raise SystemExit("%s: not a pck" % path)
        version, major, minor, patch, flags = struct.unpack("<5I", f.read(20))
        file_base = struct.unpack("<Q", f.read(8))[0]
        if version >= 3:
            dir_offset = struct.unpack("<Q", f.read(8))[0]
            f.seek(dir_offset)
        else:
            f.read(16 * 4)
        if flags & 1:
            raise SystemExit("%s: encrypted directory" % path)
        rel = bool(flags & 2)
        count = struct.unpack("<I", f.read(4))[0]
        out = []
        for _ in range(count):
            n = struct.unpack("<I", f.read(4))[0]
            name = f.read(n).rstrip(b"\0").decode()
            off, size = struct.unpack("<QQ", f.read(16))
            md5 = f.read(16)
            fl = struct.unpack("<I", f.read(4))[0]
            out.append({"path": name, "size": size, "at": off + (file_base if rel else 0), "md5": md5, "flags": fl})
        return {"version": version, "engine": (major, minor, patch), "flags": flags}, out


def entries(path):
    return [(e["path"], e["size"], e["at"]) for e in read(path)[1]]


def _pad(n):
    return (ALIGN - n % ALIGN) % ALIGN


def strip(src, dst, prefixes):
    head, es = read(src)
    if head["version"] < 3:
        raise SystemExit("format %d: only 3+ is written" % head["version"])
    keep = [e for e in es if not any(e["path"].startswith(p) for p in prefixes)]
    file_base = HEADER + _pad(HEADER)
    with open(src, "rb") as fi, open(dst, "wb") as fo:
        fo.write(b"\0" * file_base)
        pos = 0
        for e in keep:
            fi.seek(e["at"])
            fo.write(fi.read(e["size"]))
            e["new"] = pos
            pos += e["size"]
            fo.write(b"\0" * _pad(pos))
            pos += _pad(pos)
        dir_offset = file_base + pos
        fo.write(struct.pack("<I", len(keep)))
        for e in keep:
            name = e["path"].encode()
            name += b"\0" * ((4 - len(name) % 4) % 4)
            fo.write(struct.pack("<I", len(name)) + name + struct.pack("<QQ", e["new"], e["size"]) + e["md5"] +
                     struct.pack("<I", e["flags"]))
        fo.seek(0)
        fo.write(b"GDPC" + struct.pack("<5I", head["version"], *head["engine"], head["flags"] | 2) +
                 struct.pack("<QQ", file_base, dir_offset))
    return len(es) - len(keep)


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "list":
        es = entries(sys.argv[2])
        if "--sum" in sys.argv:
            print(len(es), "files", sum(e[1] for e in es), "bytes")
        else:
            for name, size, _ in es:
                print(size, name)
    elif cmd == "strip":
        print("removed", strip(sys.argv[2], sys.argv[3], sys.argv[4:]))
    else:
        raise SystemExit(__doc__)
