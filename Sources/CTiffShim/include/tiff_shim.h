#ifndef DSK_TIFF_SHIM_H
#define DSK_TIFF_SHIM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Charge libtiff dynamiquement (dlopen). Renvoie 1 si disponible. */
int dsk_tiff_available(void);

void *dsk_tiff_open(const char *path, const char *mode);
void dsk_tiff_close(void *tif);

/* Wrappers non variadiques de TIFFSetField (appel variadique via pointeur). */
int dsk_tiff_set_field_u32(void *tif, int tag, uint32_t value);
int dsk_tiff_set_field_f64(void *tif, int tag, double value);

int dsk_tiff_write_scanline(void *tif, void *buf, uint32_t row, uint16_t sample);
int dsk_tiff_write_directory(void *tif);
uint32_t dsk_tiff_default_strip_size(void *tif);

/* Chaîne de version de libtiff (ou NULL). */
const char *dsk_tiff_version(void);

#ifdef __cplusplus
}
#endif

#endif /* DSK_TIFF_SHIM_H */
