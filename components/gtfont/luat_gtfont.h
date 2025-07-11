
#ifndef _LUAT_GTFONT_H_
#define _LUAT_GTFONT_H_

#include "luat_base.h"
#include "luat_spi.h"
#include "GT5SLCD2E_1A.h"

extern luat_spi_device_t* gt_spi_dev;

unsigned int gtfont_draw_w(unsigned char *pBits,unsigned int x,unsigned int y,unsigned int size,unsigned int widt,unsigned int high,int(*point)(void*,uint16_t, uint16_t, uint32_t),void* userdata,int mode);
unsigned int gtfont_draw_gray_hz (unsigned char *data,unsigned short x,unsigned short y,
                unsigned short w ,unsigned short h,unsigned char grade,
                int(*point)(void*,uint16_t, uint16_t, uint32_t),void* userdata,int mode);
unsigned int gtfont_get_width(unsigned char *p,unsigned int zfwidth,unsigned int zfhigh );

uint32_t gt_unicode2gb18030(uint32_t unicode);

#endif

/*--------------------------------------- end of file ---------------------------------------------*/
