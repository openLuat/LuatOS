/**
 *  @filename   :   epd1in54b.c
 *  @brief      :   Implements for e-paper library
 *  @author     :   Yehui from Waveshare
 *
 *  Copyright (C) Waveshare     September 12 2017
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documnetation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to  whom the Software is
 * furished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS OR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */
#include  <stdlib.h>
#include "epd1in54.h"
#include "epdif.h"

#define LUAT_LOG_TAG "luat.epaper"
#include "luat_log.h"

//#define CONFIG_LV_DISPLAY_ORIENTATION_PORTRAIT_INVERTED 0
#define CONFIG_LV_DISPLAY_ORIENTATION_PORTRAIT 0
#define EPD_1IN54F_WIDTH           200
#define EPD_1IN54F_HEIGHT          200
#define EPD_1IN54F_ROW_LEN         (EPD_1IN54F_HEIGHT / 8u)
#define EPD_1IN54F_PARTIAL_CNT     5;

static uint8_t partial_counter = 0;
static const uint8_t lut_vcom_dc1[] = {
    0x01, 0x04, 0x04, 0x03, 0x01, 0x01, 0x01,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};


static const uint8_t lut_ww1[] = {
    0x01, 0x04, 0x04, 0x03, 0x01, 0x01, 0x01,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};


static const uint8_t lut_bw1[] = {
    0x01, 0x84, 0x84, 0x83, 0x01, 0x01, 0x01,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};


static const uint8_t lut_wb1[] = {
    0x01, 0x44, 0x44, 0x43, 0x01, 0x01, 0x01,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};


static const uint8_t lut_bb1[] = {
    0x01, 0x04, 0x04, 0x03, 0x01, 0x01, 0x01,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};



static void EPD_1IN54F_load_partial_lut(EPD* epd)
{
    EPD_1IN54F_SendCommand(epd,0x20); // LUT VCOM register
    for (int i = 0; i < 56; i++)
      EPD_1IN54F_SendData(epd, lut_vcom_dc1[i]);
  //  EPD_1IN54F_SendData((uint8_t *)lut_vcom_dc1, sizeof(lut_vcom_dc1));

    EPD_1IN54F_SendCommand(epd,0x21); // LUT White-to-White
    for (int i = 0; i < 56; i++)
      EPD_1IN54F_SendData(epd, lut_ww1[i]);
  //  EPD_1IN54F_SendData((uint8_t *)lut_ww1, sizeof(lut_ww1));

    EPD_1IN54F_SendCommand(epd,0x22); // LUT Black-to-White
    //EPD_1IN54F_SendData((uint8_t *)lut_bw1, sizeof(lut_bw1));
    for (int i = 0; i < 56; i++)
      EPD_1IN54F_SendData(epd, lut_bw1[i]);

    EPD_1IN54F_SendCommand(epd,0x23); // LUT White-to-Black
    //EPD_1IN54F_SendData((uint8_t *)lut_wb1,sizeof(lut_wb1));
    for (int i = 0; i < 56; i++)
      EPD_1IN54F_SendData(epd, lut_wb1[i]);

    EPD_1IN54F_SendCommand(epd,0x24); // LUT Black-to-Black
    //EPD_1IN54F_SendData((uint8_t *)lut_bb1, sizeof(lut_bb1));
    for (int i = 0; i < 56; i++)
      EPD_1IN54F_SendData(epd, lut_bb1[i]);
}
static void EPD_1IN54F_partial_in(EPD* epd)
{
//    ESP_LOGD(TAG, "Partial in!");

    // Panel setting: accept LUT from registers instead of OTP
#if defined (CONFIG_LV_DISPLAY_ORIENTATION_PORTRAIT_INVERTED)
    uint8_t pst_use_reg_lut[] = { 0xf3, 0x0e };
#elif defined(CONFIG_LV_DISPLAY_ORIENTATION_PORTRAIT)
    uint8_t pst_use_reg_lut[] = { 0xff, 0x0e };
#else
#//error "Unsupported orientation - only portrait modes are supported for now"
#endif
    EPD_1IN54F_SendCommand(epd,0x00);
   // EPD_1IN54F_SendData(pst_use_reg_lut, sizeof(pst_use_reg_lut));
    for (int i = 0; i < 2; i++)
      EPD_1IN54F_SendData(epd, pst_use_reg_lut[i]);

    // WORKAROUND: need to ignore OLD framebuffer or otherwise partial refresh won't work
    uint8_t vcom = 0xb7;
    EPD_1IN54F_SendCommand(epd,0x50);
    EPD_1IN54F_SendData(epd, vcom);

    // Dump LUT in
    EPD_1IN54F_load_partial_lut(epd);

    // Go partial!
    EPD_1IN54F_SendCommand(epd,0x91);
}

static void EPD_1IN54F_partial_out(EPD* epd)
{
//    ESP_LOGD(TAG, "Partial out!");

    // Panel setting: use LUT from OTP
#if defined (CONFIG_LV_DISPLAY_ORIENTATION_PORTRAIT_INVERTED)
    uint8_t pst_use_otp_lut[] = { 0xd3, 0x0e };
#elif defined(CONFIG_LV_DISPLAY_ORIENTATION_PORTRAIT)
    uint8_t pst_use_otp_lut[] = { 0xdf, 0x0e };
#else
//#error "Unsupported orientation - only portrait modes are supported for now"
#endif
    EPD_1IN54F_SendCommand(epd,0x00);
    //EPD_1IN54F_SendData(pst_use_otp_lut, sizeof(pst_use_otp_lut));
    for (int i = 0; i < 2; i++)
      EPD_1IN54F_SendData(epd, pst_use_otp_lut[i]);

    // WORKAROUND: re-enable OLD framebuffer to get a better full refresh
    uint8_t vcom = 0x97;
    EPD_1IN54F_SendCommand(epd,0x50);
    EPD_1IN54F_SendData(epd, vcom);

    // Out from partial!
    EPD_1IN54F_SendCommand(epd,0x92);
}

int EPD_1IN54F_Init(EPD* epd, const unsigned char* lut) {
  epd->reset_pin = EPD_RST_PIN;
  epd->dc_pin = EPD_DC_PIN;
  epd->cs_pin = EPD_CS_PIN;
  epd->busy_pin = EPD_BUSY_PIN;
  epd->width = EPD_1IN54F_WIDTH;
  epd->height = EPD_1IN54F_HEIGHT;
  /* this calls the peripheral hardware interface, see epdif */
  if (EpdInitCallback() != 0) {
    return -1;
  }
  /* EPD hardware init start */
  EPD_1IN54F_Reset(epd);
  /*
  EPD_1IN54F_SendCommand(epd, DRIVER_OUTPUT_CONTROL);
  EPD_1IN54F_SendData(epd, (EPD_1IN54F_HEIGHT - 1) & 0xFF);
  EPD_1IN54F_SendData(epd, ((EPD_1IN54F_HEIGHT - 1) >> 8) & 0xFF);
  EPD_1IN54F_SendData(epd, 0x00);                     // GD = 0; SM = 0; TB = 0;
  EPD_1IN54F_SendCommand(epd, BOOSTER_SOFT_START_CONTROL);
  EPD_1IN54F_SendData(epd, 0xD7);
  EPD_1IN54F_SendData(epd, 0xD6);
  EPD_1IN54F_SendData(epd, 0x9D);
  EPD_1IN54F_SendCommand(epd, WRITE_VCOM_REGISTER);
  EPD_1IN54F_SendData(epd, 0xA8);                     // VCOM 7C
  EPD_1IN54F_SendCommand(epd, SET_DUMMY_LINE_PERIOD);
  EPD_1IN54F_SendData(epd, 0x1A);                     // 4 dummy lines per gate
  EPD_1IN54F_SendCommand(epd, SET_GATE_TIME);
  EPD_1IN54F_SendData(epd, 0x08);                     // 2us per line
  EPD_1IN54F_SendCommand(epd, DATA_ENTRY_MODE_SETTING);
  EPD_1IN54F_SendData(epd, 0x03);                     // X increment; Y increment
  EPD_1IN54F_SetLut(epd, epd->lut);
  */
///*
  EPD_1IN54F_SendCommand(epd,0x00); // panel setting
  EPD_1IN54F_SendData (epd,0xdf);
  EPD_1IN54F_SendData (epd,0x0e);

  EPD_1IN54F_SendCommand(epd,0x01); // power setting
  EPD_1IN54F_SendData(epd,0x03);
  EPD_1IN54F_SendData(epd,0x06); // 16V
  EPD_1IN54F_SendData(epd,0x2A);//
  EPD_1IN54F_SendData(epd,0x2A);//

  EPD_1IN54F_SendCommand(epd,0x4D); // FITIinternal code
  EPD_1IN54F_SendData (epd,0x55);

  EPD_1IN54F_SendCommand(epd,0xaa);
  EPD_1IN54F_SendData (epd,0x0f);

  EPD_1IN54F_SendCommand(epd,0xE9);
  EPD_1IN54F_SendData (epd,0x02);

  EPD_1IN54F_SendCommand(epd,0xb6);
  EPD_1IN54F_SendData (epd,0x11);

  EPD_1IN54F_SendCommand(epd,0xF3);
  EPD_1IN54F_SendData (epd,0x0a);

  EPD_1IN54F_SendCommand(epd,0x06); // boost soft start
  EPD_1IN54F_SendData (epd,0xc7);
  EPD_1IN54F_SendData (epd,0x0c);
  EPD_1IN54F_SendData (epd,0x0c);

  EPD_1IN54F_SendCommand(epd,0x61); // resolution setting
  EPD_1IN54F_SendData (epd,0xc8); // 200
  EPD_1IN54F_SendData (epd,0x00);
  EPD_1IN54F_SendData (epd,0xc8); // 200

  EPD_1IN54F_SendCommand(epd,0x60); // Tcon setting
  EPD_1IN54F_SendData (epd,0x00);

  EPD_1IN54F_SendCommand(epd,0x82); // VCOM DC setting
  EPD_1IN54F_SendData (epd,0x12);

  EPD_1IN54F_SendCommand(epd,0x30); // PLL control
  EPD_1IN54F_SendData (epd,0x3C);   // default 50Hz

  EPD_1IN54F_SendCommand(epd,0X50); // VCOM and data interval
  EPD_1IN54F_SendData(epd,0x97);//

  EPD_1IN54F_SendCommand(epd,0XE3); // power saving register
  EPD_1IN54F_SendData(epd,0x00); // default

  EPD_1IN54F_SendCommand(epd,0X04);
//*/

/*  esp32 lib
  EPD_1IN54F_SendCommand(epd,0x00); // panel setting
  EPD_1IN54F_SendData (epd,0xdf);
  EPD_1IN54F_SendData (epd,0x0e);

  EPD_1IN54F_SendCommand(epd,0x4d); // panel setting
  EPD_1IN54F_SendData (epd,0x55);

  EPD_1IN54F_SendCommand(epd,0xaa); // panel setting
  EPD_1IN54F_SendData (epd,0x0f);

  EPD_1IN54F_SendCommand(epd,0xe9); // panel setting
  EPD_1IN54F_SendData (epd,0x02);

  EPD_1IN54F_SendCommand(epd,0xb6); // panel setting
  EPD_1IN54F_SendData (epd,0x11);

  EPD_1IN54F_SendCommand(epd,0xf3); // panel setting
  EPD_1IN54F_SendData (epd,0x0a);

  EPD_1IN54F_SendCommand(epd,0x61); // resolution setting
  EPD_1IN54F_SendData (epd,0xc8); // 200
  EPD_1IN54F_SendData (epd,0x00);
  EPD_1IN54F_SendData (epd,0xc8); // 200

  EPD_1IN54F_SendCommand(epd,0x60); // panel setting
  EPD_1IN54F_SendData (epd,0x00);

  EPD_1IN54F_SendCommand(epd,0x50); // panel setting
  EPD_1IN54F_SendData (epd,0x97);

  EPD_1IN54F_SendCommand(epd,0xe3); // panel setting
  EPD_1IN54F_SendData (epd,0x00);
*/
  EPD_1IN54F_DelayMs(epd, 100);
  EPD_1IN54F_WaitUntilIdle(epd);

  /* EPD hardware init end */
  return 0;
}

/**
 *  @brief: this calls the corresponding function from epdif.h
 *          usually there is no need to change this function
 */
void EPD_1IN54F_DigitalWrite(EPD* epd, int pin, int value) {
  EpdDigitalWriteCallback(pin, value);
}

/**
 *  @brief: this calls the corresponding function from epdif.h
 *          usually there is no need to change this function
 */
int EPD_1IN54F_DigitalRead(EPD* epd, int pin) {
  return EpdDigitalReadCallback(pin);
}

/**
 *  @brief: this calls the corresponding function from epdif.h
 *          usually there is no need to change this function
 */
void EPD_1IN54F_DelayMs(EPD* epd, unsigned int delaytime) {  // 1ms
  EpdDelayMsCallback(delaytime);
}

/**
 *  @brief: basic function for sending commands
 */
void EPD_1IN54F_SendCommand(EPD* epd, unsigned char command) {
  EPD_1IN54F_DigitalWrite(epd, epd->dc_pin, LOW);
  EpdSpiTransferCallback(command);
}

/**
 *  @brief: basic function for sending data
 */
void EPD_1IN54F_SendData(EPD* epd, unsigned char data) {
  EPD_1IN54F_DigitalWrite(epd, epd->dc_pin, HIGH);
  EpdSpiTransferCallback(data);
}

/**
 *  @brief: Wait until the busy_pin goes LOW
 */
void EPD_1IN54F_WaitUntilIdle(EPD* epd) {
  while(EPD_1IN54F_DigitalRead(epd, epd->busy_pin) == HIGH) {      //0: busy, 1: idle
    EPD_1IN54F_DelayMs(epd, 100);
  }      
}

/**
 *  @brief: module reset.
 *          often used to awaken the module in deep sleep,
 *          see EPD::Sleep();
 */
void EPD_1IN54F_Reset(EPD* epd) {
  EPD_1IN54F_DigitalWrite(epd, epd->reset_pin, LOW);                //module reset    
  EPD_1IN54F_DelayMs(epd, 200);
  EPD_1IN54F_DigitalWrite(epd, epd->reset_pin, HIGH);
  EPD_1IN54F_DelayMs(epd, 200);    
}

/**
 *  @brief: module Power on.
 */
void EPD_1IN54F_power_on(EPD* epd) {
  EPD_1IN54F_SendCommand(epd, 0x50);  
  EPD_1IN54F_SendData(epd,0x97); 

  EPD_1IN54F_SendCommand(epd, 0x04);     
}

/**
 *  @brief: module Power off.
 */
void EPD_1IN54F_power_off(EPD* epd) {
  EPD_1IN54F_SendCommand(epd, 0x50);  
  EPD_1IN54F_SendData(epd,0xf7);  

  EPD_1IN54F_SendCommand(epd, 0x02);
}

/**
 *  @brief: put an image buffer to the frame memory.
 *          this won't update the display.
 */


void EPD_1IN54F_SetFrameMemory(
  EPD* epd,
  const unsigned char* image_buffer,
  int x,
  int y,
  int image_width,
  int image_height
) {
  int x_end;
  int y_end;

  if (
    image_buffer == NULL ||
    x < 0 || image_width < 0 ||
    y < 0 || image_height < 0
  ) {
    return;
  }
  /* x point must be the multiple of 8 or the last 3 bits will be ignored */
  x &= 0xF8;
  image_width &= 0xF8;
  if (x + image_width >= epd->width) {
    x_end = epd->width - 1;
  } else {
    x_end = x + image_width - 1;
  }
  if (y + image_height >= epd->height) {
    y_end = epd->height - 1;
  } else {
    y_end = y + image_height - 1;
  }

  // 局刷还不行
  EPD_1IN54F_SetMemoryArea(epd, x, y, x_end, y_end);
  //EPD_1IN54F_SetMemoryPointer(epd, x, y);
  //EPD_1IN54F_SendCommand(epd, WRITE_RAM);
  EPD_1IN54F_SendCommand(epd, 0x10);
  /* send the image data */
  for (int j = 0; j < y_end - y + 1; j++) {
    for (int i = 0; i < (x_end - x + 1) / 8; i++) {
      EPD_1IN54F_SendData(epd, image_buffer[i + j * (image_width / 8)]);
    }
  }

    EPD_1IN54F_SendCommand(epd, 0x13);
  /* send the image data */
  for (int j = 0; j < y_end - y + 1; j++) {
    for (int i = 0; i < (x_end - x + 1) / 8; i++) {
      EPD_1IN54F_SendData(epd, image_buffer[i + j * (image_width / 8)]);
    }
  }
}

/**
*  @brief: clear the frame memory with the specified color.
*          this won't update the display.
*/
void EPD_1IN54F_ClearFrameMemory(EPD* epd, unsigned char color) {
  EPD_1IN54F_SetMemoryArea(epd, 0, 0, epd->width - 1, epd->height - 1);
  EPD_1IN54F_SetMemoryPointer(epd, 0, 0);
  EPD_1IN54F_SendCommand(epd, WRITE_RAM);
  /* send the color data */
  for (int i = 0; i < epd->width / 8 * epd->height; i++) {
    EPD_1IN54F_SendData(epd, color);
  }
}

/**
*  @brief: update the display
*          there are 2 memory areas embedded in the e-paper display
*          but once this function is called,
*          the the next action of SetFrameMemory or ClearFrame will 
*          set the other memory area.
*/
void EPD_1IN54F_DisplayFrame(EPD* epd) {
  // EPD_1IN54F_SendCommand(epd, DISPLAY_UPDATE_CONTROL_2);
  // EPD_1IN54F_SendData(epd, 0xC4);
  // EPD_1IN54F_SendCommand(epd, MASTER_ACTIVATION);
  // EPD_1IN54F_SendCommand(epd, TERMINATE_FRAME_READ_WRITE);


  EPD_1IN54F_SendCommand(epd, 0x12);
  EPD_1IN54F_WaitUntilIdle(epd);
}

/**
 *  @brief: After this command is transmitted, the chip would enter the 
 *          deep-sleep mode to save power. 
 *          The deep sleep mode would return to standby by hardware reset. 
 *          You can use EPD_1IN54F_Init() to awaken
 */
void EPD_1IN54F_Sleep(EPD* epd) {
  EPD_1IN54F_SendCommand(epd, DEEP_SLEEP_MODE);
  EPD_1IN54F_WaitUntilIdle(epd);
}

/**
 *  @brief: set the look-up tables
 */
static void EPD_1IN54F_SetLut(EPD* epd, const unsigned char* lut) {
  epd->lut = lut;
  EPD_1IN54F_SendCommand(epd, WRITE_LUT_REGISTER);
  /* the length of look-up table is 30 bytes */
  for (int i = 0; i < 30; i++) {
    EPD_1IN54F_SendData(epd, epd->lut[i]);
  } 
}




/**
 *  @brief: private function to specify the memory area for data R/W
 */
static void EPD_1IN54F_SetMemoryArea(EPD* epd, int x_start, int y_start, int x_end, int y_end) {
  // EPD_1IN54F_SendCommand(epd, SET_RAM_X_ADDRESS_START_END_POSITION);
  // /* x point must be the multiple of 8 or the last 3 bits will be ignored */
  // EPD_1IN54F_SendData(epd, (x_start >> 3) & 0xFF);
  // EPD_1IN54F_SendData(epd, (x_end >> 3) & 0xFF);
  // EPD_1IN54F_SendCommand(epd, SET_RAM_Y_ADDRESS_START_END_POSITION);
  // EPD_1IN54F_SendData(epd, y_start & 0xFF);
  // EPD_1IN54F_SendData(epd, (y_start >> 8) & 0xFF);
  // EPD_1IN54F_SendData(epd, y_end & 0xFF);
  // EPD_1IN54F_SendData(epd, (y_end >> 8) & 0xFF);

  uint16_t xe = (x_start + x_end - 1) | 0x0007; // byte boundary inclusive (last byte)
  uint16_t ye = y_start + y_end - 1;
  x_start &= 0xFFF8; // byte boundary
  EPD_1IN54F_SendCommand(epd,0x90); // partial window
  //_writeData(x / 256);
  EPD_1IN54F_SendData(epd,x_start % 256);
  //_writeData(xe / 256);
  EPD_1IN54F_SendData(epd,xe % 256);
  EPD_1IN54F_SendData(epd,y_start / 256);
  EPD_1IN54F_SendData(epd,y_start % 256);
  EPD_1IN54F_SendData(epd,ye / 256);
  EPD_1IN54F_SendData(epd,ye % 256);
  EPD_1IN54F_SendData(epd,0x01); // don't see any difference
  //_writeData(0x00); // don't see any difference
}

/**
 *  @brief: private function to specify the start point for data R/W
 */
static void EPD_1IN54F_SetMemoryPointer(EPD* epd, int x, int y) {
  EPD_1IN54F_SendCommand(epd, SET_RAM_X_ADDRESS_COUNTER);
  /* x point must be the multiple of 8 or the last 3 bits will be ignored */
  EPD_1IN54F_SendData(epd, (x >> 3) & 0xFF);
  EPD_1IN54F_SendCommand(epd, SET_RAM_Y_ADDRESS_COUNTER);
  EPD_1IN54F_SendData(epd, y & 0xFF);
  EPD_1IN54F_SendData(epd, (y >> 8) & 0xFF);
  EPD_1IN54F_WaitUntilIdle(epd);
}



static const unsigned char lut_full_update[] =
{
    0x02, 0x02, 0x01, 0x11, 0x12, 0x12, 0x22, 0x22, 
    0x66, 0x69, 0x69, 0x59, 0x58, 0x99, 0x99, 0x88, 
    0x00, 0x00, 0x00, 0x00, 0xF8, 0xB4, 0x13, 0x51, 
    0x35, 0x51, 0x51, 0x19, 0x01, 0x00
};

// static const unsigned char lut_partial_update[] =
// {
//     0x10, 0x18, 0x18, 0x08, 0x18, 0x18, 0x08, 0x00, 
//     0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 
//     0x00, 0x00, 0x00, 0x00, 0x13, 0x14, 0x44, 0x12, 
//     0x00, 0x00, 0x00, 0x00, 0x00, 0x00
// };

static void EPD_1IN54F_update_partial(EPD* epd,uint8_t x1, uint8_t y1, uint8_t x2, uint8_t y2, uint8_t *data)
{
  EPD_1IN54F_power_on(epd);
  EPD_1IN54F_partial_in(epd);

  // Set partial window
  uint8_t ptl_setting[8] = { x1, x2, 0, y1, 0, y2, 0x01 };
  //uint8_t ptl_setting[8] = { x1, x1+x2, 0, y1, 0, y1+y2, 0x01 };
  //EPD_1IN54F_SendCommand(epd,0X90); // power saving register
  EPD_1IN54F_SendCommand(epd,0x90);
  for (int i = 0; i < 7; i++)
    EPD_1IN54F_SendData(epd, ptl_setting[i]);

  //uint8_t *data_ptr = (uint8_t *)data;

  EPD_1IN54F_SendCommand(epd,0x13);
  for (size_t h_idx = 0; h_idx < y2; h_idx++) {
    //EPD_1IN54F_SendData(data_ptr, EPD_1IN54F_ROW_LEN);
    for (int i = 0; i < x2/8; i++)
      EPD_1IN54F_SendData(epd, data[i]);
    data += x2/8;
 //   len -= EPD_1IN54F_ROW_LEN;
  }



//  ESP_LOGD(TAG, "Partial wait start");

  EPD_1IN54F_SendCommand(epd,0x12);
  EPD_1IN54F_WaitUntilIdle(epd);

//  ESP_LOGD(TAG, "Partial updated");
  EPD_1IN54F_partial_out(epd);
  EPD_1IN54F_power_off(epd);

}

void EPD_1IN54F_fb_full_update(EPD* epd,uint8_t *data, size_t len)
{
  EPD_1IN54F_power_on(epd);
//    ESP_LOGD(TAG, "Performing full update, len: %u", len);

  uint8_t *data_ptr = data;

    // Fill OLD data (maybe not necessary)
  uint8_t old_data[EPD_1IN54F_ROW_LEN] = { 0 };
  EPD_1IN54F_SendCommand(epd,0x10);
  for (size_t idx = 0; idx < EPD_1IN54F_HEIGHT; idx++) {
      //jd79653a_spi_send_data(old_data, EPD_1IN54F_ROW_LEN);
    for (int i = 0; i < EPD_1IN54F_ROW_LEN; i++)
      EPD_1IN54F_SendData(epd, old_data[i]);
  }

  // Fill NEW data
  EPD_1IN54F_SendCommand(epd,0x13);
  for (size_t h_idx = 0; h_idx < EPD_1IN54F_HEIGHT; h_idx++) {
        //jd79653a_spi_send_data(data_ptr, EPD_1IN54F_ROW_LEN);
    for (int i = 0; i < EPD_1IN54F_ROW_LEN; i++)
      EPD_1IN54F_SendData(epd, data_ptr[i]);
    data_ptr += EPD_1IN54F_ROW_LEN;
      //len -= EPD_1IN54F_ROW_LEN;
  }
    //ESP_LOGD(TAG, "Rest len: %u", len);
  EPD_1IN54F_SendCommand(epd,0x12); // Issue refresh command
  EPD_1IN54F_DelayMs(epd, 100);
  EPD_1IN54F_WaitUntilIdle(epd);

  EPD_1IN54F_power_off(epd);
}
//void jd79653a_lv_fb_flush(lv_disp_drv_t *drv, const lv_area_t *area, lv_color_t *color_map)
void jd79653a_lv_fb_flush(
  EPD* epd,
  const unsigned char *color_map,
  int x,
  int y,
  int image_width,
  int image_height
){
//    size_t len = ((area->x2 - area->x1 + 1) * (area->y2 - area->y1 + 1)) / 8;

   // ESP_LOGD(TAG, "x1: 0x%x, x2: 0x%x, y1: 0x%x, y2: 0x%x", area->x1, area->x2, area->y1, area->y2);
 //   ESP_LOGD(TAG, "Writing LVGL fb with len: %u, partial counter: %u", len, partial_counter);

    uint8_t *buf = (uint8_t *) color_map;

    if (partial_counter == 0) {
    //    ESP_LOGD(TAG, "Refreshing in FULL");
        EPD_1IN54F_fb_full_update(epd, buf, ((EPD_1IN54F_HEIGHT * EPD_1IN54F_WIDTH) / 8));
        partial_counter = EPD_1IN54F_PARTIAL_CNT; // Reset partial counter here
    } else {
        EPD_1IN54F_update_partial(epd, x, y, x+image_width-1, y+image_height-1, buf);
        partial_counter -= 1;   // ...or otherwise, decrease 1
    }

 //   lv_disp_flush_ready(drv);
}

#define UBYTE uint8_t
UBYTE EPD_1IN54FF_Init(void);
void EPD_1IN54FF_Clear(void);
void EPD_1IN54FF_Display(UBYTE *Image);
void EPD_1IN54FF_Sleep(void);

#define BUSY_Pin          (18)
#define RST_Pin           (7)
#define DC_Pin            (9)
#define SPI_CS_Pin        (16)

static EPD _epd;
UBYTE EPD_1IN54FF_Init(void) {
  _epd.busy_pin = EPD_BUSY_PIN;
  _epd.reset_pin = EPD_RST_PIN;
  _epd.dc_pin = EPD_DC_PIN;
  _epd.cs_pin = EPD_CS_PIN;
  _epd.width = EPD_1IN54F_WIDTH;
  _epd.height = EPD_1IN54F_HEIGHT;
  LLOGD("EPD_1IN54F_Init");
  EPD_1IN54F_Init(&_epd, lut_full_update);
  return 0;
}
void EPD_1IN54FF_Clear(void) {
  ;
}
void EPD_1IN54FF_Display(UBYTE *Image) {
  EPD_1IN54F_SetFrameMemory(&_epd, Image, 0, 0, EPD_1IN54F_WIDTH, EPD_1IN54F_HEIGHT);
  EPD_1IN54F_DisplayFrame(&_epd);
}
void EPD_1IN54FF_Sleep(void) {
  EPD_1IN54F_Sleep(&_epd);
}

/* END OF FILE */


