#ifndef __EPD_1IN54R_H_
#define __EPD_1IN54R_H_

#include "DEV_Config.h"

// Display resolution
#define EPD_1IN54R_WIDTH       152
#define EPD_1IN54R_HEIGHT      152

void EPD_1IN54R_Init(UBYTE mode);
void EPD_1IN54R_Clear(void);
void EPD_1IN54R_Display(const UBYTE *blackimage, const UBYTE *ryimage);
void EPD_1IN54R_Sleep(void);

#endif
