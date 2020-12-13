/*
@module  eink
@summary eink操作库
@version 1.0
@date    2020.11.14
*/
#include "luat_base.h"
#include "luat_log.h"
#include "luat_sys.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_malloc.h"
#include "luat_spi.h"

#include "luat_gpio.h"

#include "epd1in54.h"
// #include "epd2in9.h"

#include "epdif.h"
#include "epdpaint.h"
#include "imagedata.h"
#include "qrcode.h"

#include <stdlib.h>

#define Pin_BUSY        (18)
#define Pin_RES         (7)
#define Pin_DC          (9)
#define Pin_CS          (16)

#define SPI_ID          (0)

#define COLORED      0
#define UNCOLORED    1

#define LUAT_LOG_TAG "luat.eink"


static EPD epd; 
static Paint paint;
static unsigned char* frame_buffer;

/**
设置并启用SPI
@api eink.setup(bandrate, cs, CPHA, CPOL, dataw, id, bitdict, ms, mode)
@int SPI号,例如0
@int CS 片选脚,暂不可用,请填nil
@int CPHA 默认0,可选0/1
@int CPOL 默认0,可选0/1
@int 数据宽度,默认8bit
@int 波特率,默认2M=2000000
@int 大小端, 默认spi.MSB, 可选spi.LSB
@int 主从设置, 默认主1, 可选从机0. 通常只支持主机模式
@int 工作模式, 全双工1, 半双工0, 默认全双工
@int 刷新模式 0：局刷partial, 1：全刷full。默认全刷
@return int 成功返回0,否则返回其他值
*/
static int l_eink_setup(lua_State *L) {
    luat_spi_t spi_config = {0};
    int spi_id = luaL_optinteger(L, 1, 0);
    luat_spi_close(spi_id);

    spi_config.bandrate = 2000000U;//luaL_optinteger(L, 1, 2000000U); // 2000000U
    spi_config.id = spi_id;
    spi_config.cs = 255; // 默认无
    spi_config.CPHA = 0; // CPHA0
    spi_config.CPOL = 0; // CPOL0
    spi_config.dataw = 8; // 8bit
    spi_config.bit_dict = 1; // MSB=1, LSB=0
    spi_config.master = 1; // master=1,slave=0
    spi_config.mode = 1; // FULL=1, half=0

    luat_gpio_mode(luaL_optinteger(L, 2, Pin_BUSY), Luat_GPIO_INPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);
    luat_gpio_mode(luaL_optinteger(L, 3, Pin_RES), Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);
    luat_gpio_mode(luaL_optinteger(L, 4, Pin_DC), Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);
    luat_gpio_mode(luaL_optinteger(L, 5, Pin_CS), Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);

    int status = luat_spi_setup(&spi_config);
    if(status == 0)
    {
        int num = luaL_optinteger(L, 1, 1);
        if(num)
            status = EPD_Init(&epd, lut_full_update);
        else
            status = EPD_Init(&epd, lut_partial_update);

        if (status != 0) {
            LLOGD("e-Paper init failed");
            return 0;
        } 
        frame_buffer = (unsigned char*)malloc(EPD_WIDTH * EPD_HEIGHT / 8);
        //   Paint paint;
        Paint_Init(&paint, frame_buffer, epd.width, epd.height);
        Paint_Clear(&paint, UNCOLORED);
    }
      
    lua_pushboolean(L, 1);
    return 1;
}


/**
清除缓冲区
@api eink.clear()

*/
static int l_eink_clear(lua_State *L)
{
    int colored = luaL_optinteger(L, 1, 1);
    Paint_Clear(&paint, colored);
    return 0;
}

/**
设置窗口
@api eink.setWin(width, height, rotate)
@int width  宽度
@int height 高度
@int rotate 显示方向
*/
static int l_eink_setWin(lua_State *L)
{
    int width = luaL_checkinteger(L, 1);
    int height = luaL_checkinteger(L, 2);
    int rotate = luaL_checkinteger(L, 3);

    Paint_SetWidth(&paint, width);
    Paint_SetHeight(&paint, height);
    Paint_SetRotate(&paint, rotate);
    return 0;
}

/**
获取窗口信息
@api eink.getWin()
@return int width, height, rotate
*/
static int l_eink_getWin(lua_State *L)
{
    int width =  Paint_GetWidth(&paint);
    int height = Paint_GetHeight(&paint);
    int rotate = Paint_GetRotate(&paint);

    lua_pushinteger(L, width);
    lua_pushinteger(L, height);
    lua_pushinteger(L, rotate);
    return 3;
}

/**
打印字符串
@api eink.print(x, y, *str, colored, font)
@return int width, height, rotate
*/
static int l_eink_print(lua_State *L)
{
    size_t len;
    int x           = luaL_checkinteger(L, 1);
    int y           = luaL_checkinteger(L, 2);
    const char *str = luaL_checklstring(L, 3, &len);
    int colored     = luaL_optinteger(L, 4, 0);    
    int font        = luaL_optinteger(L, 5, 16);


    switch (font)
    {
        case 8:
            Paint_DrawStringAt(&paint, x, y, str, &Font8, colored);
            break;
        case 12:
            Paint_DrawStringAt(&paint, x, y, str, &Font12, colored);
            break;
        case 16:
            Paint_DrawStringAt(&paint, x, y, str, &Font16, colored);
            break;
        case 20:
            Paint_DrawStringAt(&paint, x, y, str, &Font20, colored);
            break;
        case 24:
            Paint_DrawStringAt(&paint, x, y, str, &Font24, colored);
            break;    
        default:
            break;
    }
    return 0;
}

/**
缓冲区绘制中文
@api eink.printcn(x, y, *str, font, colored)
@return int width, height, rotate
*/
static int l_eink_printcn(lua_State *L)
{
    size_t len;
    int x           = luaL_checkinteger(L, 1);
    int y           = luaL_checkinteger(L, 2);
    const char *str = luaL_checklstring(L, 3, &len);
    int colored     = luaL_optinteger(L, 4, 0);    
    int font        = luaL_optinteger(L, 5, 12);


    
    switch (font)
    {
        case 12:
            Paint_DrawStringCN(&paint, x, y, str, &Font12CN, colored);
            break;
        case 24:
            Paint_DrawStringCN(&paint, x, y, str, &Font24CN, colored);
            break;   
        default:
            break;
    }
    return 0;
}

/**
显示缓冲区信息
@api eink.show(x, y)
@int x 
@int y
*/
static int l_eink_show(lua_State *L)
{
    int x     = luaL_optinteger(L, 1, 0);
    int y     = luaL_optinteger(L, 2, 0);
    /* Display the frame_buffer */
    EPD_SetFrameMemory(&epd, frame_buffer, x, y, Paint_GetWidth(&paint), Paint_GetHeight(&paint));
    EPD_DisplayFrame(&epd);
    return 0;
}


/**
缓冲区绘制线
@api eink.line(x, y, x2, y2, colored)
@user
    eink.line(0, 0, 10, 20, 0)
*/
static int l_eink_line(lua_State *L)
{
    int x       = luaL_checkinteger(L, 1);
    int y       = luaL_checkinteger(L, 2);
    int x2      = luaL_checkinteger(L, 3);
    int y2      = luaL_checkinteger(L, 4);
    int colored = luaL_optinteger(L, 5, 0);

    Paint_DrawLine(&paint, x, y, x2, y2, colored);
    return 0;
}

/**
缓冲区绘制矩形
@api eink.rect(x, y, x2, y2, colored, fill)
@usage
    eink.rect(0, 0, 10, 20)
or
    eink.rect(0, 0, 10, 20, 1) -- Filled
*/
static int l_eink_rect(lua_State *L)
{
    int x      = luaL_checkinteger(L, 1);
    int y      = luaL_checkinteger(L, 2);
    int x2      = luaL_checkinteger(L, 3);
    int y2      = luaL_checkinteger(L, 4);
    int colored = luaL_optinteger(L, 5, 0);
    int fill    = luaL_optinteger(L, 6, 0);

    if(fill)
        Paint_DrawFilledRectangle(&paint, x, y, x2, y2, colored);
    else
        Paint_DrawRectangle(&paint, x, y, x2, y2, colored);
    return 0;
}

/**
缓冲区绘制圆形
@api eink.circle(x, y, radius, colored, fill)
@user
    eink.circle(0, 0, 10)
or
    eink.circle(0, 0, 10, 1, 1) -- Filled
*/
static int l_eink_circle(lua_State *L)
{
    int x       = luaL_checkinteger(L, 1);
    int y       = luaL_checkinteger(L, 2);
    int radius  = luaL_checkinteger(L, 3);
    int colored = luaL_optinteger(L, 4, 0);
    int fill    = luaL_optinteger(L, 5, 0);

    if(fill)
        Paint_DrawFilledCircle(&paint, x, y, radius, colored);
    else
        Paint_DrawCircle(&paint, x, y, radius, colored);
    return 0;
}

/**
缓冲区绘制QRCode
@api eink.qrcode(x, y, *str, version)
@int x
@int y
@char str
@int version :1 ~40
*/
static int l_eink_qrcode(lua_State *L)
{
    size_t len;
    int x           = luaL_checkinteger(L, 1);
    int y           = luaL_checkinteger(L, 2);
    const char* str = luaL_checklstring(L, 3, &len);
    int version     = luaL_checkinteger(L, 4);
    // Create the QR code
    QRCode qrcode;
    uint8_t qrcodeData[qrcode_getBufferSize(version)];
    qrcode_initText(&qrcode, qrcodeData, version, 0, str);   

    for(int i = 0; i < qrcode.size; i++)
    {
        for (int j = 0; j < qrcode.size; j++)
        {
            qrcode_getModule(&qrcode, j, i) ? Paint_DrawPixel(&paint, x+j, y+i, COLORED) : Paint_DrawPixel(&paint, x+j, y+i, UNCOLORED);
        }
    }
    return 0;
}

/**
缓冲区绘制电池
@api eink.line(x, y, bat)
@int x
@int y
@int bat 电池电压
*/
static int l_eink_bat(lua_State *L)
{
    int x           = luaL_checkinteger(L, 1);
    int y           = luaL_checkinteger(L, 2);
    int bat         = luaL_checkinteger(L, 3);
    int batnum      = 0;
        // eink.rect(0, 3, 2, 6)
        // eink.rect(2, 0, 20, 9)
        // eink.rect(9, 1, 19, 8, 0, 1)
    if(bat < 4200 && bat > 4080)batnum = 100;
    if(bat < 4080 && bat > 4000)batnum = 90;
    if(bat < 4000 && bat > 3930)batnum = 80;
    if(bat < 3930 && bat > 3870)batnum = 70;
    if(bat < 3870 && bat > 3820)batnum = 60;
    if(bat < 3820 && bat > 3790)batnum = 50;
    if(bat < 3790 && bat > 3770)batnum = 40;
    if(bat < 3770 && bat > 3730)batnum = 30;
    if(bat < 3730 && bat > 3700)batnum = 20;
    if(bat < 3700 && bat > 3680)batnum = 15;
    if(bat < 3680 && bat > 3500)batnum = 10;
    if(bat < 3500 && bat > 2500)batnum = 5;
    batnum = 20 - (int)(batnum / 5) + 3;
    // w外框
    Paint_DrawRectangle(&paint, x+0, y+3, x+2, y+6, COLORED);
    Paint_DrawRectangle(&paint, x+2, y+0, x+23, y+9, COLORED);
    // 3 ~21   100 / 5
    Paint_DrawFilledRectangle(&paint, x+batnum, y+1, x+22, y+8, COLORED);

    return 0;
}

/**
缓冲区绘制天气图标
@api eink.weather_icon(x, y, code)
@int x
@int y
@int code 天气代号
*/
static int l_eink_weather_icon(lua_State *L)
{
    size_t len;
    int x           = luaL_checkinteger(L, 1);
    int y           = luaL_checkinteger(L, 2);
    int code        = luaL_checkinteger(L, 3);
    const char* str = luaL_optlstring(L, 4, "nil", &len);
    const unsigned char * icon = gImage_999;  

    if (strcmp(str, "xue")      == 0)code = 401;
    if (strcmp(str, "lei")      == 0)code = 302;
    if (strcmp(str, "shachen")  == 0)code = 503;
    if (strcmp(str, "wu")       == 0)code = 501;
    if (strcmp(str, "bingbao")  == 0)code = 504;
    if (strcmp(str, "yun")      == 0)code = 103;
    if (strcmp(str, "yu")       == 0)code = 306;
    if (strcmp(str, "yin")      == 0)code = 101;
    if (strcmp(str, "qing")     == 0)code = 100;

    // xue、lei、shachen、wu、bingbao、yun、yu、yin、qing

    //if(code == 64)
    // for(int i = 0; i < 64; i++)
    // {
    //     for (int j = 0; j < 8; j++)
    //     {
    //         for (int k = 0; k < 8; k++)
    //             (gImage_103[i*8+j] << k )& 0x80 ? Paint_DrawPixel(&paint, x+j*8+k, y+i, COLORED) : Paint_DrawPixel(&paint, x+j*8+k, y+i, UNCOLORED);
    //     }
    // }
    
    switch (code)
    {
        case 100:icon = gImage_100;break;
        case 101:icon = gImage_101;break;
        case 102:icon = gImage_102;break;
        case 103:icon = gImage_103;break;
        case 104:icon = gImage_104;break;
        case 200:icon = gImage_200;break;
        case 201:icon = gImage_201;break;
        case 205:icon = gImage_205;break;
        case 208:icon = gImage_208;break;

        case 301:icon = gImage_301;break;
        case 302:icon = gImage_302;break;
        case 303:icon = gImage_303;break;
        case 304:icon = gImage_304;break;
        case 305:icon = gImage_305;break;
        case 306:icon = gImage_306;break;
        case 307:icon = gImage_307;break;
        case 308:icon = gImage_308;break;
        case 309:icon = gImage_309;break;
        case 310:icon = gImage_310;break;
        case 311:icon = gImage_311;break;
        case 312:icon = gImage_312;break;
        case 313:icon = gImage_313;break;

        case 400:icon = gImage_400;break;
        case 401:icon = gImage_401;break;
        case 402:icon = gImage_402;break;
        case 403:icon = gImage_403;break;
        case 404:icon = gImage_404;break;
        case 405:icon = gImage_405;break;
        case 406:icon = gImage_406;break;
        case 407:icon = gImage_407;break;

        case 500:icon = gImage_500;break;
        case 501:icon = gImage_501;break;
        case 502:icon = gImage_502;break;
        case 503:icon = gImage_503;break;
        case 504:icon = gImage_504;break;
        case 507:icon = gImage_507;break;
        case 508:icon = gImage_508;break;
        case 900:icon = gImage_900;break;
        case 901:icon = gImage_901;break;
        case 999:icon = gImage_999;break;

        default:
            break;
    }
    for(int i = 0; i < 48; i++)
    {
        for (int j = 0; j < 6; j++)
        {
            for (int k = 0; k < 8; k++)
                (icon[i*6+j] << k )& 0x80 ? Paint_DrawPixel(&paint, x+j*8+k, y+i, COLORED) : Paint_DrawPixel(&paint, x+j*8+k, y+i, UNCOLORED);
        }
    }


    return 0;
}

#include "rotable.h"
static const rotable_Reg reg_eink[] =
{
    { "setup",          l_eink_setup,           0},
    { "clear",          l_eink_clear,           0},
    { "setWin",         l_eink_setWin,          0},
    { "getWin",         l_eink_getWin,          0},
    { "print",          l_eink_print,           0},
    { "printcn",        l_eink_printcn,         0},
    { "show",           l_eink_show,            0},
    { "rect",           l_eink_rect,            0},
    { "circle",         l_eink_circle,          0},
    { "circle",         l_eink_line,            0},

    { "qrcode",         l_eink_qrcode,          0},   
    { "bat",            l_eink_bat,             0},      
    { "weather_icon",   l_eink_weather_icon,    0},    

    

    //{ "init",           l_eink_init,            0},   
	{ NULL,             NULL,                   0}
};

LUAMOD_API int luaopen_eink( lua_State *L ){
    rotable_newlib(L, reg_eink);
    return 1;
}
