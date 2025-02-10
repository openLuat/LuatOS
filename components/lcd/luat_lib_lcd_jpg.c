
/*
@module  lcd
@summary lcd驱动模块
@version 1.0
@date    2021.06.16
@demo lcd
@tag LUAT_USE_LCD
*/
#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_mem.h"
#include "luat_zbuff.h"
#include "luat_fs.h"
#include "luat_gpio.h"

#define LUAT_LOG_TAG "lcd"
#include "luat_log.h"

#include "u8g2.h"
#include "u8g2_luat_fonts.h"
#include "luat_u8g2.h"

#include "qrcodegen.h"

int8_t u8g2_font_decode_get_signed_bits(u8g2_font_decode_t *f, uint8_t cnt);
uint8_t u8g2_font_decode_get_unsigned_bits(u8g2_font_decode_t *f, uint8_t cnt);

extern luat_color_t BACK_COLOR , FORE_COLOR ;

extern const luat_lcd_opts_t lcd_opts_custom;
extern luat_lcd_conf_t *lcd_dft_conf;
extern void lcd_auto_flush(luat_lcd_conf_t *conf);

#ifdef LUAT_USE_TJPGD
#include "tjpgd.h"
#include "tjpgdcnf.h"

#define N_BPP (3 - JD_FORMAT)

/* Session identifier for input/output functions (name, members and usage are as user defined) */
typedef struct {
    FILE *fp;               /* Input stream */
    int x;
    int y;
    // int width;
    // int height;
    uint16_t buff[16*16];
} IODEV;

static unsigned int file_in_func (JDEC* jd, uint8_t* buff, unsigned int nbyte){
    IODEV *dev = (IODEV*)jd->device;   /* Device identifier for the session (5th argument of jd_prepare function) */
    if (buff) {
        /* Read bytes from input stream */
        return luat_fs_fread(buff, 1, nbyte, dev->fp);
    } else {
        /* Remove bytes from input stream */
        return luat_fs_fseek(dev->fp, nbyte, SEEK_CUR) ? 0 : nbyte;
    }
}

static int lcd_out_func (JDEC* jd, void* bitmap, JRECT* rect){
    IODEV *dev = (IODEV*)jd->device;
    uint16_t* tmp = (uint16_t*)bitmap;

    // rgb高低位swap
    uint16_t count = (rect->right - rect->left + 1) * (rect->bottom - rect->top + 1);
    for (size_t i = 0; i < count; i++){
        if (lcd_dft_conf->port < LUAT_LCD_HW_ID_0 || lcd_dft_conf->port == LUAT_LCD_SPI_DEVICE)
            dev->buff[i] = ((tmp[i] >> 8) & 0xFF)+ ((tmp[i] << 8) & 0xFF00);
        else
            dev->buff[i] = tmp[i];
    }
    
    // LLOGD("jpeg seg %dx%d %dx%d", rect->left, rect->top, rect->right, rect->bottom);
    // LLOGD("jpeg seg size %d %d %d", rect->right - rect->left + 1, rect->bottom - rect->top + 1, (rect->right - rect->left + 1) * (rect->bottom - rect->top + 1));
    luat_lcd_draw(lcd_dft_conf, dev->x + rect->left, dev->y + rect->top,
                                dev->x + rect->right, dev->y + rect->bottom,
                                dev->buff);
    return 1;    /* Continue to decompress */
}

static int lcd_draw_jpeg(const char* path, int xpos, int ypos) {
    JRESULT res;      /* Result code of TJpgDec API */
    JDEC jdec;        /* Decompression object */
    void *work;       /* Pointer to the decompressor work area */
#if JD_FASTDECODE == 2
    size_t sz_work = 3500 * 3; /* Size of work area */
#else
    size_t sz_work = 3500; /* Size of work area */
#endif
    IODEV devid;      /* User defined device identifier */

    FILE* fd = luat_fs_fopen(path, "r");
    if (fd == NULL) {
        LLOGW("no such file %s", path);
    return -1;
    }

    devid.fp = fd;
    work = luat_heap_malloc(sz_work);
    if (work == NULL) {
        LLOGE("out of memory when malloc jpeg decode workbuff");
        return -3;
    }
    res = jd_prepare(&jdec, file_in_func, work, sz_work, &devid);
    if (res != JDR_OK) {
        luat_heap_free(work);
        luat_fs_fclose(fd);
        LLOGW("jd_prepare file %s error %d", path, res);
        return -2;
    }
    devid.x = xpos;
    devid.y = ypos;
    // devid.width = jdec.width;
    // devid.height = jdec.height;
    res = jd_decomp(&jdec, lcd_out_func, 0);
    luat_heap_free(work);
    luat_fs_fclose(fd);
    if (res != JDR_OK) {
        LLOGW("jd_decomp file %s error %d", path, res);
        return -2;
    }else {
        lcd_auto_flush(lcd_dft_conf);
        return 0;
    }
}

/*
显示图片,当前只支持jpg,jpeg
@api lcd.showImage(x, y, file)
@int X坐标
@int y坐标
@string 文件路径
@usage
lcd.showImage(0,0,"/luadb/logo.jpg")
*/
int l_lcd_showimage(lua_State *L) {
    size_t size = 0;
    int ret = 0;
    int x = luaL_checkinteger(L, 1);
    int y = luaL_checkinteger(L, 2);
    const char* input_file = luaL_checklstring(L, 3, &size);
    if (memcmp(input_file+size-4, ".jpg", 5) == 0 || memcmp(input_file+size-4, ".JPG", 5) == 0 || memcmp(input_file+size-5, ".jpeg", 6) == 0 || memcmp(input_file+size-5, ".JPEG", 6) == 0){
      ret = lcd_draw_jpeg(input_file, x, y);
      lua_pushboolean(L, ret == 0 ? 1 : 0);
    } else{
      LLOGE("input_file not support");
      lua_pushboolean(L, 0);
    }
    return 1;
}
#endif
