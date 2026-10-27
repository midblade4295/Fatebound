/* fxcrun: compile one HLSL file with D3DCompiler_47.dll (FXC, the compiler Unity runs first for its Vulkan, GLES and
 * Metal shaders: its bytecode then goes through HLSLcc) -- built with MinGW, run under Wine by check.py (FBFXC=1).
 *   fxcrun <file.hlsl> <entry> <target> [-I dir]... [-D NAME=VALUE]...
 * Prints FXC's errors and warnings; exit code 0 when it compiled. */
#define COBJMACROS
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { const char *Name; const char *Definition; } MACRO;
typedef struct ID3DBlobVtbl {
    HRESULT (WINAPI *QueryInterface)(void *, REFIID, void **);
    ULONG (WINAPI *AddRef)(void *);
    ULONG (WINAPI *Release)(void *);
    LPVOID (WINAPI *GetBufferPointer)(void *);
    SIZE_T (WINAPI *GetBufferSize)(void *);
} ID3DBlobVtbl;
typedef struct { ID3DBlobVtbl *lpVtbl; } ID3DBlob;

typedef struct ID3DIncludeVtbl {
    HRESULT (WINAPI *Open)(void *self, int type, const char *name, const void *parent, const void **data, UINT *bytes);
    HRESULT (WINAPI *Close)(void *self, const void *data);
} ID3DIncludeVtbl;
typedef struct { ID3DIncludeVtbl *lpVtbl; } ID3DInclude;

typedef HRESULT (WINAPI *PD3DCompile)(const void *, SIZE_T, const char *, const MACRO *, ID3DInclude *, const char *,
    const char *, UINT, UINT, ID3DBlob **, ID3DBlob **);

static char *dirs[64];
static int ndirs = 0;
static char cur_dir[4096];

static char *read_file(const char *path, UINT *len)
{
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *b = malloc(n + 1);
    fread(b, 1, n, f);
    b[n] = 0;
    fclose(f);
    *len = (UINT)n;
    return b;
}

/* each opened file's folder, by its data pointer: an include is looked for next to the file that includes it first */
static const void *open_data[4096];
static char *open_dir[4096];
static int nopen = 0;

static char *dir_of(const char *path)
{
    char *d = strdup(path);
    char *slash = strrchr(d, '/');
    if (slash) *slash = 0; else strcpy(d, ".");
    return d;
}

static HRESULT WINAPI inc_open(void *self, int type, const char *name, const void *parent, const void **data, UINT *bytes)
{
    char path[8192];
    char *b = NULL;
    const char *pdir = cur_dir;
    for (int i = 0; i < nopen; i++) if (open_data[i] == parent) { pdir = open_dir[i]; break; }
    snprintf(path, sizeof path, "%s/%s", pdir, name);
    b = read_file(path, bytes);
    if (!b) { snprintf(path, sizeof path, "%s/%s", cur_dir, name); b = read_file(path, bytes); }
    for (int i = 0; !b && i < ndirs; i++) {
        snprintf(path, sizeof path, "%s/%s", dirs[i], name);
        b = read_file(path, bytes);
    }
    if (!b) { strncpy(path, name, sizeof path - 1); b = read_file(name, bytes); }
    if (!b) return E_FAIL;
    if (nopen < 4096) { open_data[nopen] = b; open_dir[nopen] = dir_of(path); nopen++; }
    *data = b;
    return S_OK;
}

static HRESULT WINAPI inc_close(void *self, const void *data) { free((void *)data); return S_OK; }

/* fxcrun @<jobs file>: one "<file>\t<entry>\t<target>" per line, each compiled in turn in this one process (Wine starts
 * once); prints "### <n> rc=<0|1>" after each job's messages */
static int batch(const char *list)
{
    HMODULE m = LoadLibraryA("D3DCompiler_47.dll");
    if (!m) { fprintf(stderr, "no D3DCompiler_47.dll\n"); return 2; }
    PD3DCompile compile = (PD3DCompile)GetProcAddress(m, "D3DCompile");
    UINT n;
    char *jobs = read_file(list, &n);
    if (!jobs) return 2;
    static ID3DIncludeVtbl vt = { inc_open, inc_close };
    ID3DInclude inc = { &vt };
    int idx = 0;
    char *save = NULL;
    for (char *line = strtok_r(jobs, "\n", &save); line; line = strtok_r(NULL, "\n", &save), idx++) {
        char *f = line, *e = strchr(f, '\t');
        if (!e) continue;
        *e++ = 0;
        char *t = strchr(e, '\t');
        if (!t) continue;
        *t++ = 0;
        char *cr = strchr(t, '\r'); if (cr) *cr = 0;
        strncpy(cur_dir, f, sizeof cur_dir - 1);
        char *slash = strrchr(cur_dir, '/'); if (slash) *slash = 0; else strcpy(cur_dir, ".");
        UINT len;
        char *src = read_file(f, &len);
        int rc = 1;
        if (!src) printf("error: can't read %s\n", f);
        else {
            ID3DBlob *code = NULL, *errs = NULL;
            fflush(stdout);
            HRESULT hr = compile(src, len, f, NULL, &inc, e, t, (1 << 12), 0, &code, &errs);
            if (errs) fwrite(errs->lpVtbl->GetBufferPointer(errs), 1, errs->lpVtbl->GetBufferSize(errs), stdout);
            if (FAILED(hr) && !errs) printf("error: D3DCompile failed with 0x%08lx and no message\n", (unsigned long)hr);
            rc = FAILED(hr) ? 1 : 0;
            free(src);
        }
        printf("\n### %d rc=%d\n", idx, rc);
        fflush(stdout);
    }
    return 0;
}

int main(int argc, char **argv)
{
    if (argc == 2 && argv[1][0] == '@') return batch(argv[1] + 1);
    if (argc < 4) { fprintf(stderr, "fxcrun <file> <entry> <target> [-I dir] [-D N=V] | fxcrun @jobs\n"); return 2; }
    MACRO defs[256];
    int nd = 0;
    for (int i = 4; i < argc; i++) {
        if (!strcmp(argv[i], "-I") && i + 1 < argc) dirs[ndirs++] = argv[++i];
        else if (!strcmp(argv[i], "-D") && i + 1 < argc) {
            char *d = strdup(argv[++i]);
            char *eq = strchr(d, '=');
            if (eq) { *eq = 0; defs[nd].Definition = eq + 1; } else defs[nd].Definition = "1";
            defs[nd].Name = d;
            nd++;
        }
    }
    defs[nd].Name = NULL; defs[nd].Definition = NULL;
    strncpy(cur_dir, argv[1], sizeof cur_dir - 1);
    char *slash = strrchr(cur_dir, '/');
    if (!slash) slash = strrchr(cur_dir, '\\');
    if (slash) *slash = 0; else strcpy(cur_dir, ".");
    UINT len;
    char *src = read_file(argv[1], &len);
    if (!src) { fprintf(stderr, "can't read %s\n", argv[1]); return 2; }
    HMODULE m = LoadLibraryA("D3DCompiler_47.dll");
    if (!m) { fprintf(stderr, "no D3DCompiler_47.dll\n"); return 2; }
    PD3DCompile compile = (PD3DCompile)GetProcAddress(m, "D3DCompile");
    static ID3DIncludeVtbl vt = { inc_open, inc_close };
    ID3DInclude inc = { &vt };
    ID3DBlob *code = NULL, *errs = NULL;
    /* D3DCOMPILE_ENABLE_BACKWARDS_COMPATIBILITY (1<<12) | optimization level 1 (0) */
    fprintf(stderr, "compiling %s %s\n", argv[2], argv[3]); fflush(stderr);
    HRESULT hr = compile(src, len, argv[1], defs, &inc, argv[2], argv[3], (1 << 12), 0, &code, &errs);
    if (errs) fwrite(errs->lpVtbl->GetBufferPointer(errs), 1, errs->lpVtbl->GetBufferSize(errs), stdout);
    if (FAILED(hr) && !errs) printf("error: D3DCompile failed with 0x%08lx and no message\n", (unsigned long)hr);
    fprintf(stderr, "hr=0x%08lx\n", (unsigned long)hr); fflush(stdout); fflush(stderr);
    return FAILED(hr) ? 1 : 0;
}
