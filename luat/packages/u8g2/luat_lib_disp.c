/*
@module  disp
@summary 显示屏控制
@version 1.0
@date    2020.03.30
*/
#include "luat_base.h"
#include "luat_malloc.h"

#include "luat_disp.h"
#include "luat_gpio.h"
#include "luat_timer.h"
#include "luat_i2c.h"

#include "u8g2.h"
#include "u8g2_luat_fonts.h"

#define LUAT_LOG_TAG "disp"
#include "luat_log.h"

static u8g2_t* u8g2;
static int u8g2_lua_ref;
static uint8_t i2c_id;
//static uint8_t i2c_addr = 0x3C;
//static uint8_t spi_id;

/*
显示屏初始化
@api disp.init(conf)
@table 配置信息
@return int 正常初始化1,已经初始化过2,内存不够3,初始化失败返回4
@usage
-- 初始化模拟i2c的ssd1306
if disp.init({mode="i2c_sw", pin0=17, pin1=18}) == 1 then
    log.info("disp", "disp init complete")
end
-- 初始化硬件i2c0的ssd1306
i2c.setup(0, i2c.FAST)
if disp.init({mode="i2c_hw", i2c_id=0}) == 1 then
    log.info("disp", "disp init complete")
end
*/
static int l_disp_init(lua_State *L) {
    if (u8g2 != NULL) {
        LLOGW("disp is aready inited");
        lua_pushinteger(L, 2);
        return 1;
    }
    u8g2 = (u8g2_t*)lua_newuserdata(L, sizeof(u8g2_t));
    if (u8g2 == NULL) {
        LLOGE("lua_newuserdata return NULL, out of memory ?!");
        lua_pushinteger(L, 3);
        return 1;
    }
    // TODO: 暂时只支持SSD1306 12864, I2C接口-> i2c1soft, 软件模拟
    luat_disp_conf_t conf = {0};
    conf.pinType = 2; // I2C 硬件(或者是个假硬件)
    conf.ptr = u8g2;
    if (lua_istable(L, 1)) {
        // 参数解析
        lua_pushliteral(L, "mode");
        lua_gettable(L, 1);
        if (lua_isstring(L, -1)) {
            const char* mode = luaL_checkstring(L, -1);
            LLOGD("mode = [%s]", mode);
            if (strcmp("i2c_sw", mode) == 0) {
                LLOGD("using i2c_sw");
                conf.pinType = 1;
            }
            else if (strcmp("i2c_hw", mode) == 0) {
                LLOGD("using i2c_hw");
                conf.pinType = 2;
            }
            else if (strcmp("spi_sw_3pin", mode) == 0) {
                LLOGD("using spi_sw_3pin");
                conf.pinType = 3;
            }
            else if (strcmp("spi_sw_4pin", mode) == 0) {
                LLOGD("using spi_sw_4pin");
                conf.pinType = 4;
            }
            else if (strcmp("spi_hw_4pin", mode) == 0) {
                LLOGD("using spi_hw_4pin");
                conf.pinType = 5;
            }
        }
        lua_pop(L, 1);

        // 解析pin0 ~ pin7
        lua_pushliteral(L, "pin0");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.pin0 = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        
        lua_pushliteral(L, "pin1");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.pin1 = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        
        lua_pushliteral(L, "pin2");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.pin2 = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        
        lua_pushliteral(L, "pin3");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.pin3 = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);

        lua_pushliteral(L, "i2c_id");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            i2c_id = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);

        // lua_pushliteral(L, "i2c_addr");
        // lua_gettable(L, 1);
        // if (lua_isinteger(L, -1)) {
        //     i2c_addr = luaL_checkinteger(L, -1);
        // }
        // lua_pop(L, 1);

        // lua_pushliteral(L, "spi_id");
        // lua_gettable(L, 1);
        // if (lua_isinteger(L, -1)) {
        //     spi_id = luaL_checkinteger(L, -1);
        // }
        // lua_pop(L, 1);

        // pin4 ~ pin7暂时用不到,先不设置了
    }
    LLOGD("pinType=%d", conf.pinType);
    if (luat_disp_setup(&conf)) {
        u8g2 = NULL;
        LLOGW("disp init fail");
        lua_pushinteger(L, 4);
        return 1; // 初始化失败
    }
    
    u8g2_lua_ref = luaL_ref(L, LUA_REGISTRYINDEX);

    u8g2_SetFont(u8g2, u8g2_font_ncenB08_tr); // 设置默认字体
    
    lua_pushinteger(L, 1);
    return 1;
}

/*
关闭显示屏
@api disp.close() 
@usage
-- 关闭disp,再次使用disp相关API的话,需要重新初始化
disp.close()
*/
static int l_disp_close(lua_State *L) {
    if (u8g2_lua_ref != 0) {
        lua_geti(L, LUA_REGISTRYINDEX, u8g2_lua_ref);
        if (lua_isuserdata(L, -1)) {
            luaL_unref(L, LUA_REGISTRYINDEX, u8g2_lua_ref);
        }
        u8g2_lua_ref = 0;
    }
    lua_gc(L, LUA_GCCOLLECT, 0);
    u8g2 = NULL;
    return 0;
}
/*
@api disp.clear() 清屏
@usage
-- 清屏
disp.clear()
*/
static int l_disp_clear(lua_State *L) {
    if (u8g2 == NULL) return 0;
    u8g2_ClearBuffer(u8g2);
    return 0;
}

/*
把显示数据更新到屏幕
@api disp.update()
@usage
-- 把显示数据更新到屏幕
disp.update()
*/
static int l_disp_update(lua_State *L) {
    if (u8g2 == NULL) return 0;
    u8g2_SendBuffer(u8g2);
    return 0;
}


/*
在显示屏上画一段文字,要调用disp.update才会更新到屏幕
@api disp.drawStr(content, x, y) 
@string 文件内容
@int 横坐标
@int 竖坐标
@usage
disp.drawStr("wifi is ready", 10, 20)
*/
static int l_disp_draw_text(lua_State *L) {
    if (u8g2 == NULL) {
        LLOGW("disp not init yet!!!");
        return 0;
    }
    size_t len;
    size_t x, y;
    const char* str = luaL_checklstring(L, 1, &len);
    x = luaL_checkinteger(L, 2);
    y = luaL_checkinteger(L, 3);
    
    u8g2_DrawUTF8(u8g2, x, y, str);
    return 0;
}

/*
设置字体
@api disp.setFont(fontId) 
@int 字体id, 默认0,纯英文8x8字节. 如果支持中文支持, 那么1代表12x12的中文字体.
@usage
-- 设置为中文字体,对之后的drawStr有效
disp.setFont(1)
*/
static int l_disp_set_font(lua_State *L) {
    if (u8g2 == NULL) {
        LLOGI("disp not init yet!!!");
        lua_pushboolean(L, 0);
        return 1;
    }
    int font_id = luaL_checkinteger(L, 1);
    if (font_id < 0) {
        lua_pushboolean(L, 0);
    }
    else {
        switch (font_id)
        {
        case 0:
            u8g2_SetFont(u8g2, u8g2_font_ncenB08_tr);
            lua_pushboolean(L, 1);
            break;
        #if defined USE_U8G2_OPPOSANSM12_CHINESE
        case 1:
            u8g2_SetFont(u8g2, u8g2_font_opposansm12_chinese);
            lua_pushboolean(L, 1);
            break;
        #endif
        default:
            lua_pushboolean(L, 0);
            break;
        }
    }

    return 1;
}

#include "rotable.h"
static const rotable_Reg reg_disp[] =
{
    { "init",       l_disp_init,        0},
    { "close",      l_disp_close,       0},
    { "clear",      l_disp_clear,       0},
    { "update",     l_disp_update,      0},
    { "drawStr",    l_disp_draw_text,   0},
    { "setFont",    l_disp_set_font,    0},
	{ NULL, NULL, 0}
};

LUAMOD_API int luaopen_disp( lua_State *L ) {
    u8g2_lua_ref = 0;
    u8g2 = NULL;
    luat_newlib(L, reg_disp);
    return 1;
}

//-----------------------------
// 往下是一些U8G2方法的默认实现

uint8_t luat_u8x8_gpio_and_delay(u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr);
uint8_t luat_u8x8_byte_hw_i2c(u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr);

LUAT_WEAK int luat_disp_setup(luat_disp_conf_t *conf) {
    if (conf->pinType == 1) {
        u8g2_t* u8g2 = (u8g2_t*)conf->ptr;
        u8g2_Setup_ssd1306_i2c_128x64_noname_f( u8g2, U8G2_R0, u8x8_byte_sw_i2c, luat_u8x8_gpio_and_delay);
        u8g2->u8x8.pins[U8X8_PIN_I2C_CLOCK] = conf->pin0;
        u8g2->u8x8.pins[U8X8_PIN_I2C_DATA] = conf->pin1;
        LLOGD("setup disp i2c.sw SCL=%ld SDA=%ld", conf->pin0, conf->pin1);
        u8g2_InitDisplay(u8g2);
        u8g2_SetPowerSave(u8g2, 0);
        return 0;
    }
    else if (conf->pinType == 2) {
        u8g2_t* u8g2 = (u8g2_t*)conf->ptr;
        u8g2_Setup_ssd1306_i2c_128x64_noname_f( u8g2, U8G2_R0, luat_u8x8_byte_hw_i2c, luat_u8x8_gpio_and_delay);
        LLOGD("setup disp i2c.hw");
        u8g2_InitDisplay(u8g2);
        u8g2_SetPowerSave(u8g2, 0);
        return 0;
    }
    LLOGI("only i2c sw mode is support, by default impl");
    return -1;
}

LUAT_WEAK int luat_disp_close(luat_disp_conf_t *conf) {
    return 0;
}

LUAT_WEAK uint8_t luat_u8x8_byte_hw_i2c(u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr) {
  static uint8_t buffer[32];		/* u8g2/u8x8 will never send more than 32 bytes */
  static uint8_t buf_idx;
  uint8_t *data;
 
  switch(msg)
  {
    case U8X8_MSG_BYTE_SEND:
      data = (uint8_t *)arg_ptr;      
      while( arg_int > 0 )
      {
	buffer[buf_idx++] = *data;
	data++;
	arg_int--;
      }      
      break;
    case U8X8_MSG_BYTE_INIT:
      //i2c_init(u8x8);			/* init i2c communication */
      break;
    case U8X8_MSG_BYTE_SET_DC:
      /* ignored for i2c */
      break;
    case U8X8_MSG_BYTE_START_TRANSFER:
      buf_idx = 0;
      break;
    case U8X8_MSG_BYTE_END_TRANSFER:
      luat_i2c_send(i2c_id, u8x8_GetI2CAddress(u8x8) >> 1, buffer, buf_idx);
      break;
    default:
      return 0;
  }
  return 1;
}

LUAT_WEAK uint8_t luat_u8x8_gpio_and_delay(u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr)
{
    switch(msg)
    {
        case U8X8_MSG_DELAY_NANO:            // delay arg_int * 1 nano second
            __asm__ volatile("nop");
            break;
        
        case U8X8_MSG_DELAY_100NANO:        // delay arg_int * 100 nano seconds
            __asm__ volatile("nop");
            break;
        
        case U8X8_MSG_DELAY_10MICRO:        // delay arg_int * 10 micro seconds
            for (uint16_t n = 0; n < 320; n++)
            {
                __asm__ volatile("nop");
            }
        break;
        
        case U8X8_MSG_DELAY_MILLI:            // delay arg_int * 1 milli second
            luat_timer_mdelay(arg_int);
            break;
        
        case U8X8_MSG_GPIO_AND_DELAY_INIT:  
            // Function which implements a delay, arg_int contains the amount of ms  
            
            // set spi pin mode 
            if (u8x8->pins[U8X8_PIN_SPI_CLOCK] != 255) {
                luat_gpio_mode(u8x8->pins[U8X8_PIN_SPI_CLOCK],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);//d0 a5 15 d1 a7 17 res b0 18 dc b1 19 cs a4 14  
                luat_gpio_mode(u8x8->pins[U8X8_PIN_SPI_DATA],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
                luat_gpio_mode(u8x8->pins[U8X8_PIN_RESET],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
                luat_gpio_mode(u8x8->pins[U8X8_PIN_DC],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
                luat_gpio_mode(u8x8->pins[U8X8_PIN_CS],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
            }
            
            // set i2c pin mode
            if (u8x8->pins[U8X8_PIN_I2C_DATA] != 255) {
                luat_gpio_mode(u8x8->pins[U8X8_PIN_I2C_DATA],Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_HIGH);
                luat_gpio_mode(u8x8->pins[U8X8_PIN_I2C_CLOCK],Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_HIGH);
            }
            
            // 反正还没支持,先注释掉吧
            // set 8080 pin mode
            // if (u8x8->pins[U8X8_PIN_D0] != 255) {
            //     luat_gpio_mode(u8x8->pins[U8X8_PIN_D0],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
            //     luat_gpio_mode(u8x8->pins[U8X8_PIN_D1],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
            //     luat_gpio_mode(u8x8->pins[U8X8_PIN_D2],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
            //     luat_gpio_mode(u8x8->pins[U8X8_PIN_D3],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
            //     luat_gpio_mode(u8x8->pins[U8X8_PIN_D4],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
            //     luat_gpio_mode(u8x8->pins[U8X8_PIN_D5],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
            //     luat_gpio_mode(u8x8->pins[U8X8_PIN_D6],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
            //     luat_gpio_mode(u8x8->pins[U8X8_PIN_D7],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
            //     luat_gpio_mode(u8x8->pins[U8X8_PIN_E],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
            //     luat_gpio_mode(u8x8->pins[U8X8_PIN_DC],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
            //     luat_gpio_mode(u8x8->pins[U8X8_PIN_RESET],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
            // }
            
            // set value
            //luat_gpio_set(u8x8->pins[U8X8_PIN_SPI_CLOCK],1);
            //luat_gpio_set(u8x8->pins[U8X8_PIN_SPI_DATA],1);
            //luat_gpio_set(u8x8->pins[U8X8_PIN_RESET],1);
            //luat_gpio_set(u8x8->pins[U8X8_PIN_DC],1);
            //luat_gpio_set(u8x8->pins[U8X8_PIN_CS],1);
            break;
        
        case U8X8_MSG_DELAY_I2C:
            // arg_int is the I2C speed in 100KHz, e.g. 4 = 400 KHz
            // arg_int=1: delay by 5us, arg_int = 4: delay by 1.25us
            for (uint16_t n = 0; n < (arg_int<=2?160:40); n++)
            {
                __asm__ volatile("nop");
            }
            break;

        //case U8X8_MSG_GPIO_D0:                // D0 or SPI clock pin: Output level in arg_int
        //case U8X8_MSG_GPIO_SPI_CLOCK:

        //case U8X8_MSG_GPIO_D1:                // D1 or SPI data pin: Output level in arg_int
        //case U8X8_MSG_GPIO_SPI_DATA:

        case U8X8_MSG_GPIO_D2:                // D2 pin: Output level in arg_int
            if (arg_int) luat_gpio_set(u8x8->pins[U8X8_PIN_D2],1);  
            else luat_gpio_set(u8x8->pins[U8X8_PIN_D2],0);
            break;

        case U8X8_MSG_GPIO_D3:                // D3 pin: Output level in arg_int
            if (arg_int) luat_gpio_set(u8x8->pins[U8X8_PIN_D3],1);  
            else luat_gpio_set(u8x8->pins[U8X8_PIN_D3],0);
            break;

        case U8X8_MSG_GPIO_D4:                // D4 pin: Output level in arg_int
            if (arg_int) luat_gpio_set(u8x8->pins[U8X8_PIN_D4],1);  
            else luat_gpio_set(u8x8->pins[U8X8_PIN_D4],0);
            break;

        case U8X8_MSG_GPIO_D5:                // D5 pin: Output level in arg_int
            if (arg_int) luat_gpio_set(u8x8->pins[U8X8_PIN_D5],1);  
            else luat_gpio_set(u8x8->pins[U8X8_PIN_D5],0);
            break;

        case U8X8_MSG_GPIO_D6:                // D6 pin: Output level in arg_int
            if (arg_int) luat_gpio_set(u8x8->pins[U8X8_PIN_D6],1);  
            else luat_gpio_set(u8x8->pins[U8X8_PIN_D6],0);
            break;

        case U8X8_MSG_GPIO_D7:                // D7 pin: Output level in arg_int
            if (arg_int) luat_gpio_set(u8x8->pins[U8X8_PIN_D7],1);  
            else luat_gpio_set(u8x8->pins[U8X8_PIN_D7],0);
            break;

        case U8X8_MSG_GPIO_E:                // E/WR pin: Output level in arg_int
            if (arg_int) luat_gpio_set(u8x8->pins[U8X8_PIN_E],1);  
            else luat_gpio_set(u8x8->pins[U8X8_PIN_E],0);
            break;

        case U8X8_MSG_GPIO_I2C_CLOCK:
            // arg_int=0: Output low at I2C clock pin
            // arg_int=1: Input dir with pullup high for I2C clock pin
            if (arg_int) luat_gpio_set(u8x8->pins[U8X8_PIN_I2C_CLOCK],1);  
            else luat_gpio_set(u8x8->pins[U8X8_PIN_I2C_CLOCK],0);  
            break;

        case U8X8_MSG_GPIO_I2C_DATA:
            // arg_int=0: Output low at I2C data pin
            // arg_int=1: Input dir with pullup high for I2C data pin
            if (arg_int) luat_gpio_set(u8x8->pins[U8X8_PIN_I2C_DATA],1);  
            else luat_gpio_set(u8x8->pins[U8X8_PIN_I2C_DATA],0);              
      break;

        case U8X8_MSG_GPIO_SPI_CLOCK:  
            //Function to define the logic level of the clockline  
            if (arg_int) luat_gpio_set(u8x8->pins[U8X8_PIN_SPI_CLOCK],1);  
            else luat_gpio_set(u8x8->pins[U8X8_PIN_SPI_CLOCK],0);
            break;

        case U8X8_MSG_GPIO_SPI_DATA:
            //Function to define the logic level of the data line to the display  
            if (arg_int) luat_gpio_set(u8x8->pins[U8X8_PIN_SPI_DATA],1);  
            else luat_gpio_set(u8x8->pins[U8X8_PIN_SPI_DATA],0);  
            break;

        case U8X8_MSG_GPIO_CS:
            // Function to define the logic level of the CS line  
            if(arg_int) luat_gpio_set(u8x8->pins[U8X8_PIN_CS],1);
            else luat_gpio_set(u8x8->pins[U8X8_PIN_CS],0);
            break;

        case U8X8_MSG_GPIO_DC:
            //Function to define the logic level of the Data/ Command line  
            if(arg_int) luat_gpio_set(u8x8->pins[U8X8_PIN_DC],1);
            else luat_gpio_set(u8x8->pins[U8X8_PIN_DC],0);
            break;

        case U8X8_MSG_GPIO_RESET:
            //Function to define the logic level of the RESET line
            if (arg_int) luat_gpio_set(u8x8->pins[U8X8_PIN_RESET],1);
            else luat_gpio_set(u8x8->pins[U8X8_PIN_RESET],0);
            break;

        default:
            //A message was received which is not implemented, return 0 to indicate an error 
            return 0; 
    }
    return 1;
}
