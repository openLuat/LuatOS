#ifndef __EPD_3in7_U_H_
#define __EPD_3in7_U_H_

#include "DEV_Config.h"

// Display resolution
#define EPD_3in7_U_WIDTH       240
#define EPD_3in7_U_HEIGHT      416 

#define LUTGC_TEST          //
#define LUTDU_TEST          //

#define EPD_3in7_U_WHITE                         0xFF  // 
#define EPD_3in7_U_BLACK                         0x00  //
#define EPD_3in7_U_Source_Line                   0xAA  //
#define EPD_3in7_U_Gate_Line                     0x55  //
#define EPD_3in7_U_UP_BLACK_DOWN_WHITE           0xF0  //
#define EPD_3in7_U_LEFT_BLACK_RIGHT_WHITE        0x0F  //
#define EPD_3in7_U_Frame                         0x01  // 
#define EPD_3in7_U_Crosstalk                     0x02  //
#define EPD_3in7_U_Chessboard                    0x03  //
#define EPD_3in7_U_Image                         0x04  //


extern unsigned char EPD_3in7_U_Flag;

void EPD_3in7_U_SendCommand(UBYTE Reg);
void EPD_3in7_U_SendData(UBYTE Data);
void EPD_3in7_U_refresh(void);
void EPD_3in7_U_lut_GC(void);
void EPD_3in7_U_lut_DU(void);
void EPD_3in7_U_Init(UBYTE mode);
void EPD_3in7_U_display(UBYTE *Image, UBYTE *Image2);
void EPD_3in7_U_display_NUM(UBYTE NUM);
void EPD_3in7_U_Clear(void);
void EPD_3in7_U_sleep(void);



#endif
