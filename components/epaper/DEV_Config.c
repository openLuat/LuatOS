/*****************************************************************************
* | File      	:   DEV_Config.c
* | Author      :   Waveshare team
* | Function    :   Hardware underlying interface
* | Info        :
*                Used to shield the underlying layers of each master
*                and enhance portability
*----------------
* |	This version:   V2.0
* | Date        :   2018-10-30
* | Info        :
# ******************************************************************************
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
#include "DEV_Config.h"


void DEV_SPI_WriteByte(UBYTE value)
{
    if (econf.port == LUAT_EINK_SPI_DEVICE){
      luat_spi_device_send((luat_spi_device_t*)(econf.eink_spi_device), (const char *)&value, 1);
    }else{
        luat_spi_send(econf.port, (const char*)&value, 1);
    }
    
}

int DEV_Digital_Write(int pin, int level){
    if (pin == EPD_CS_PIN && econf.port == LUAT_EINK_SPI_DEVICE){
        return 0;
    }
    return luat_gpio_set(pin, level);
}

void EPD_Busy_WaitUntil(uint8_t level,uint8_t send_cmd){
    uint16_t count = 300;//30s
    while(1){
        if (level){
            if (send_cmd){
                DEV_Digital_Write(EPD_DC_PIN, 0);
                DEV_Digital_Write(EPD_CS_PIN, 0);
                DEV_SPI_WriteByte(0x71);
                DEV_Digital_Write(EPD_CS_PIN, 1);
            }
            if(DEV_Digital_Read(EPD_BUSY_PIN)) 
                break;
        }else{
            if(DEV_Digital_Read(EPD_BUSY_PIN)==0) 
                break;
        }
        if(!(count--)){
            Debug("error: e-Paper busy timeout!!!\r\n");
            return;
        }
        else
            DEV_Delay_ms(100);
    }
    DEV_Delay_ms(100);
}

