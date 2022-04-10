/*----------------------------------------------------------------------------/
/ TJpgDec - Tiny JPEG Decompressor include file               (C)ChaN, 2020
/----------------------------------------------------------------------------*/
#ifndef LUAT_TJPGD
#define LUAT_TJPGD

#ifdef __cplusplus
extern "C" {
#endif


typedef struct {
    uint16_t width;
	uint16_t height;
    uint8_t *fbuf;
} luat_tjpgd_data_t;

luat_tjpgd_data_t * luat_tjpgd(const char* input_file);

#ifdef __cplusplus
}
#endif

#endif /* _TJPGDEC */
