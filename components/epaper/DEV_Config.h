/*****************************************************************************
* | File      	:   DEV_Config.h
* | Author      :   Waveshare team
* | Function    :   Hardware underlying interface
* | Info        :
*                Used to shield the underlying layers of each master 
*                and enhance portability
*----------------
* |	This version:   V2.0
* | Date        :   2018-10-30
* | Info        :
* 1.add:
*   UBYTE\UWORD\UDOUBLE
* 2.Change:
*   EPD_RST -> EPD_RST_PIN
*   EPD_DC -> EPD_pin_dc
*   EPD_CS -> EPD_CS_PIN
*   EPD_BUSY -> EPD_BUSY_PIN
* 3.Remote:
*   EPD_RST_1\EPD_RST_0
*   EPD_DC_1\EPD_DC_0
*   EPD_CS_1\EPD_CS_0
*   EPD_BUSY_1\EPD_BUSY_0
* 3.add:
*   #define DEV_Digital_Write(_pin, _value) bcm2835_gpio_write(_pin, _value)
*   #define DEV_Digital_Read(_pin) bcm2835_gpio_lev(_pin)
*   #define DEV_SPI_WriteByte(__value) bcm2835_spi_transfer(__value)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documnetation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to  whom the Software is
# furished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS OR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
******************************************************************************/
#ifndef _DEV_CONFIG_H_
#define _DEV_CONFIG_H_

#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_spi.h"
#include "luat_timer.h"
#include "luat_rtos.h"

#include "u8g2.h"
#include "Debug.h"

/**
 * data
**/
#define UBYTE   uint8_t
#define UWORD   uint16_t
#define UDOUBLE uint32_t

#define LUAT_EINK_SPI_DEVICE 255

#define EPD_SHOW        (1<<0)
#define EPD_DRAW        (1<<1)
#define EPD_CLEAR       (1<<2)


#include "epdpaint.h"
typedef struct eink_ctx{
    uint32_t str_color;
    Paint paint;
    uint8_t fb[];
}eink_ctx_t;
typedef struct eink_conf {
    uint8_t full_mode;
    uint8_t port;
    uint8_t pin_rst;
    uint8_t pin_dc;
    uint8_t pin_cs;
    uint8_t pin_busy;
    uint8_t async;
    uint64_t idp;
    uint32_t ctx_index;
    eink_ctx_t *ctxs[2]; // 暂时只支持2种颜色, 有需要的话后续继续
    u8g2_t luat_eink_u8g2;
    luat_spi_device_t* eink_spi_device;
    int eink_spi_ref;
    luat_rtos_queue_t eink_queue_handle;
    luat_rtos_task_handle eink_task_handle;
    void* userdata;
}eink_conf_t;

extern eink_conf_t econf;

/**
 * e-Paper GPIO
**/
#define EPD_RST_PIN     (econf.pin_rst)
#define EPD_DC_PIN      (econf.pin_dc)
#define EPD_CS_PIN      (econf.pin_cs)
#define EPD_BUSY_PIN    (econf.pin_busy)

/**
 * GPIO read and write
**/
int DEV_Digital_Write(int pin, int level);
#define DEV_Digital_Read luat_gpio_get

/**
 * delay x ms
**/
#define DEV_Delay_ms(__xms) luat_timer_mdelay(__xms);

void DEV_SPI_WriteByte(UBYTE value);
void EPD_Busy_WaitUntil(uint8_t level,uint8_t send_cmd);

#endif
