
#include "DEV_Config.h"

#define UBYTE uint8_t
void EPD_2IN9FF_Init(UBYTE mode);
void EPD_2IN9FF_Clear(void);
void EPD_2IN9FF_Display(UBYTE *Image, UBYTE *Image2);
void EPD_2IN9FF_Sleep(void);

#define EPD_2IN9FF_WIDTH       128
#define EPD_2IN9FF_HEIGHT      296
