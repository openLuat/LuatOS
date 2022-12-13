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
#include "luat_rtos.h"

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

static int32_t l_eink_callback(lua_State *L, void* ptr){
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    luat_release_rtos_timer(econf.readbusy_timer);
    luat_cbcwait(L, econf.idp, 1);
    return 0;
}

static LUAT_RT_RET_TYPE readbusy_timer_cb(LUAT_RT_CB_PARAM){
    rtos_msg_t msg = {
		.handler = l_eink_callback,
	};
    if (econf.timer_count++ > 300){//30s
        luat_cbcwait_noarg(econf.idp);
        luat_stop_rtos_timer(econf.readbusy_timer);
        luat_msgbus_put(&msg, 0);
        return;
    }
    eink_async_t* async_cmd = (eink_async_t *)param;
    if (async_cmd->level){
        if(DEV_Digital_Read(EPD_BUSY_PIN)) {
            if (async_cmd->send_cmd){
                DEV_Digital_Write(EPD_DC_PIN, 0);
                DEV_Digital_Write(EPD_CS_PIN, 0);
                DEV_SPI_WriteByte(0x71);
                DEV_Digital_Write(EPD_CS_PIN, 1);
            }
            luat_cbcwait_noarg(econf.idp);
            luat_stop_rtos_timer(econf.readbusy_timer);
            luat_msgbus_put(&msg, 0);
        }
    }else{
        if(DEV_Digital_Read(EPD_BUSY_PIN)==0) {
            luat_cbcwait_noarg(econf.idp);
            luat_stop_rtos_timer(econf.readbusy_timer);
            luat_msgbus_put(&msg, 0);
        }
    }
}

void EPD_Busy_WaitUntil(uint8_t level,uint8_t send_cmd){
    uint16_t count = 200;//20s
    econf.async_cmd.level = level;
    econf.async_cmd.send_cmd = send_cmd;
    if (econf.async){
        econf.readbusy_timer = luat_create_rtos_timer(readbusy_timer_cb, &econf.async_cmd, NULL);
        luat_start_rtos_timer(econf.readbusy_timer, 100, 1);
    }else{
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
}

