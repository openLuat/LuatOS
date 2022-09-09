#ifndef __EPD_1IN54_V3_H_
#define __EPD_1IN54_V3_H_

#include "DEV_Config.h"

// Display resolution
#define EPD_1IN54_V3_WIDTH       200
#define EPD_1IN54_V3_HEIGHT      200

void EPD_1IN54_V3_Init(UBYTE mode);
void EPD_1IN54_V3_Clear(void);
void EPD_1IN54_V3_Display(UBYTE *Image, UBYTE *Image2);
void EPD_1IN54_V3_DisplayPartBaseImage(UBYTE *Image);
void EPD_1IN54_V3_DisplayPart(UBYTE *Image);
void EPD_1IN54_V3_Sleep(void);

#endif
