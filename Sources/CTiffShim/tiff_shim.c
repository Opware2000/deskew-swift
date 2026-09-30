/*
 * Shim C pour libtiff : chargement dynamique (dlopen/dlsym), sans dépendance de
 * build. Les appels variadiques (TIFFSetField) sont faits via pointeur de
 * fonction, ce qui est autorisé en C.
 *
 * Travail dérivé de Deskew (MPL 2.0).
 */

#include "tiff_shim.h"
#include <dlfcn.h>
#include <stdarg.h>
#include <stddef.h>

typedef void *TIFF;

static TIFF (*p_TIFFOpen)(const char *, const char *);
static void (*p_TIFFClose)(TIFF);
static int (*p_TIFFSetField)(TIFF, int, ...);
static int (*p_TIFFWriteScanline)(TIFF, void *, uint32_t, uint16_t);
static int (*p_TIFFWriteDirectory)(TIFF);
static uint32_t (*p_TIFFDefaultStripSize)(TIFF, uint32_t);
static const char *(*p_TIFFGetVersion)(void);
static void (*p_TIFFSetWarningHandler)(void (*)(const char *, const char *, va_list));
static void (*p_TIFFSetErrorHandler)(void (*)(const char *, const char *, va_list));

static void *g_handle = NULL;
static int g_tried = 0;

/* Handler silencieux : libtiff écrit sinon ses diagnostics sur stderr, ce qui
 * pollue la sortie console du programme. */
static void dsk_tiff_silent_handler(const char *module, const char *fmt, va_list ap) {
    (void)module;
    (void)fmt;
    (void)ap;
}

static void dsk_tiff_load(void) {
    if (g_tried) return;
    g_tried = 1;

    const char *names[] = {
        "libtiff.dylib",
        "libtiff.6.dylib",
        "libtiff.5.dylib",
        "/opt/homebrew/lib/libtiff.dylib",
        "/usr/local/lib/libtiff.dylib",
        "libtiff.so",
        "libtiff.so.6",
        "libtiff.so.5",
        NULL
    };
    for (int i = 0; names[i] != NULL; i++) {
        void *h = dlopen(names[i], RTLD_NOW | RTLD_LOCAL);
        if (h != NULL) { g_handle = h; break; }
    }
    if (g_handle == NULL) return;

    p_TIFFOpen = (TIFF (*)(const char *, const char *))dlsym(g_handle, "TIFFOpen");
    p_TIFFClose = (void (*)(TIFF))dlsym(g_handle, "TIFFClose");
    p_TIFFSetField = (int (*)(TIFF, int, ...))dlsym(g_handle, "TIFFSetField");
    p_TIFFWriteScanline = (int (*)(TIFF, void *, uint32_t, uint16_t))dlsym(g_handle, "TIFFWriteScanline");
    p_TIFFWriteDirectory = (int (*)(TIFF))dlsym(g_handle, "TIFFWriteDirectory");
    p_TIFFDefaultStripSize = (uint32_t (*)(TIFF, uint32_t))dlsym(g_handle, "TIFFDefaultStripSize");
    p_TIFFGetVersion = (const char *(*)(void))dlsym(g_handle, "TIFFGetVersion");
    p_TIFFSetWarningHandler = (void (*)(void (*)(const char *, const char *, va_list)))dlsym(g_handle, "TIFFSetWarningHandler");
    p_TIFFSetErrorHandler = (void (*)(void (*)(const char *, const char *, va_list)))dlsym(g_handle, "TIFFSetErrorHandler");

    if (p_TIFFOpen == NULL || p_TIFFClose == NULL || p_TIFFSetField == NULL ||
        p_TIFFWriteScanline == NULL || p_TIFFWriteDirectory == NULL) {
        dlclose(g_handle);
        g_handle = NULL;
        return;
    }

    if (p_TIFFSetWarningHandler != NULL) p_TIFFSetWarningHandler(dsk_tiff_silent_handler);
    if (p_TIFFSetErrorHandler != NULL) p_TIFFSetErrorHandler(dsk_tiff_silent_handler);
}

int dsk_tiff_available(void) {
    dsk_tiff_load();
    return g_handle != NULL ? 1 : 0;
}

void *dsk_tiff_open(const char *path, const char *mode) {
    dsk_tiff_load();
    return p_TIFFOpen != NULL ? p_TIFFOpen(path, mode) : NULL;
}

void dsk_tiff_close(void *tif) {
    if (p_TIFFClose != NULL) p_TIFFClose((TIFF)tif);
}

int dsk_tiff_set_field_u32(void *tif, int tag, uint32_t value) {
    return p_TIFFSetField != NULL ? p_TIFFSetField((TIFF)tif, tag, value) : 0;
}

int dsk_tiff_set_field_f64(void *tif, int tag, double value) {
    return p_TIFFSetField != NULL ? p_TIFFSetField((TIFF)tif, tag, value) : 0;
}

int dsk_tiff_write_scanline(void *tif, void *buf, uint32_t row, uint16_t sample) {
    return p_TIFFWriteScanline != NULL ? p_TIFFWriteScanline((TIFF)tif, buf, row, sample) : 0;
}

int dsk_tiff_write_directory(void *tif) {
    return p_TIFFWriteDirectory != NULL ? p_TIFFWriteDirectory((TIFF)tif) : 0;
}

uint32_t dsk_tiff_default_strip_size(void *tif) {
    return p_TIFFDefaultStripSize != NULL ? p_TIFFDefaultStripSize((TIFF)tif, 0) : 0;
}

const char *dsk_tiff_version(void) {
    dsk_tiff_load();
    return p_TIFFGetVersion != NULL ? p_TIFFGetVersion() : NULL;
}
