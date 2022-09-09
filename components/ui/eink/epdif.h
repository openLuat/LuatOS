/**
 *  @filename   :   epdif.h
 *  @brief      :   Header file of epdif.c providing EPD interface functions
 *                  Users have to implement all the functions in epdif.cpp
 *  @author     :   Yehui from Waveshare
 *
 *  Copyright (C) Waveshare     July 7 2017
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

#ifndef EPDIF_H
#define EPDIF_H


// Pin definition
#define CS_PIN           0
#define RST_PIN          1
#define DC_PIN           2
#define BUSY_PIN         3

#ifndef uint8_t
typedef unsigned char      uint8_t;
#endif 
#ifndef uint16_t
typedef unsigned short     uint16_t;
#endif 

typedef struct eink_conf {
    uint8_t spi_id;
    uint8_t busy_pin;
    uint8_t res_pin;
    uint8_t dc_pin;
    uint8_t cs_pin;
    uint8_t full_mode;
    uint8_t port;
    void* userdata;
}eink_conf_t;

extern eink_conf_t econf;

/**
 * e-Paper GPIO
**/
#define EPD_RST_PIN     (econf.res_pin)
#define EPD_DC_PIN      (econf.dc_pin)
#define EPD_CS_PIN      (econf.cs_pin)
#define EPD_BUSY_PIN    (econf.busy_pin)
#define EPD_SPI_ID      (econf.spi_id)

// Pin level definition
#define LOW             0
#define HIGH            1

typedef struct {
//  GPIO_TypeDef* port;
  uint8_t port;
} EPD_Pin;

int  EpdInitCallback(void);
void EpdDigitalWriteCallback(int pin, int value);
int  EpdDigitalReadCallback(int pin);
void EpdDelayMsCallback(unsigned int delaytime);
void EpdSpiTransferCallback(unsigned char data);

#endif /* EPDIF_H */
