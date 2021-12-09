/*
@module  eink
@summary 墨水屏操作库
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

// #include "epd1in54.h"
// #include "epd2in9.h"

#include "epd.h"
#include "epdpaint.h"
#include "imagedata.h"
#include "../qrcode/qrcode.h"

#include <stdlib.h>

#include "u8g2.h"
#include "u8g2_luat_fonts.h"

int8_t u8g2_font_decode_get_signed_bits(u8g2_font_decode_t *f, uint8_t cnt);
uint8_t u8g2_font_decode_get_unsigned_bits(u8g2_font_decode_t *f, uint8_t cnt);

#define COLORED      0
#define UNCOLORED    1

#define LUAT_LOG_TAG "eink"

enum
{
	font_opposansm8,
	font_opposansm10,
	font_opposansm12,
	font_opposansm16,
	font_opposansm18,
	font_opposansm20,
	font_opposansm22,
	font_opposansm24,
	font_opposansm32,
  font_opposansm12_chinese,
	font_opposansm16_chinese,
  font_opposansm24_chinese,
  font_opposansm32_chinese,
};

static uint32_t eink_str_color;

// static EPD epd;
static Paint paint;
static unsigned char* frame_buffer = NULL;

// #ifdef econf
// #undef econf
// #endif

eink_conf_t econf = {0};

#define Pin_BUSY        (econf.busy_pin)
#define Pin_RES         (econf.res_pin)
#define Pin_DC          (econf.dc_pin)
#define Pin_CS          (econf.cs_pin)

#define SPI_ID          (econf.spi_id)


/**
初始化eink
@api eink.setup(full, spiid)
@int 全屏刷新0,局部刷新1,默认是全屏刷新
@int 所在的spi,默认是0
@int Busy 忙信号管脚
@int Reset 复位管脚
@int DC 数据命令选择管脚
@int CS 使能管脚
@return boolean 成功返回true,否则返回false
*/
static int l_eink_setup(lua_State *L) {
    int status;
    econf.full_mode = luaL_optinteger(L, 1, 1);
    econf.spi_id = luaL_optinteger(L, 2, 0);

    econf.busy_pin = luaL_optinteger(L, 3, 18);
    econf.res_pin  = luaL_optinteger(L, 4, 7);
    econf.dc_pin = luaL_optinteger(L, 5, 9);
    econf.cs_pin = luaL_optinteger(L, 6, 16);

    if (frame_buffer != NULL) {
        lua_pushboolean(L, 1);
        return 0;
    }
    if (lua_type(L, 7) == LUA_TUSERDATA){
        LLOGD("luat_spi_device_send");
        econf.userdata = (luat_spi_device_t*)lua_touserdata(L, 3);
        econf.port = LUAT_EINK_SPI_DEVICE;
        luat_gpio_mode(Pin_BUSY, Luat_GPIO_INPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);
        luat_gpio_mode(Pin_RES, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);
        luat_gpio_mode(Pin_DC, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);
        status = 0;
    }else{
        LLOGD("luat_spi_send");
        luat_spi_t spi_config = {0};
        spi_config.bandrate = 2000000U;//luaL_optinteger(L, 1, 2000000U); // 2000000U
        spi_config.id = SPI_ID;
        spi_config.cs = 255; // 默认无
        spi_config.CPHA = 0; // CPHA0
        spi_config.CPOL = 0; // CPOL0
        spi_config.dataw = 8; // 8bit
        spi_config.bit_dict = 1; // MSB=1, LSB=0
        spi_config.master = 1; // master=1,slave=0
        spi_config.mode = 1; // FULL=1, half=0

        //LLOGD("setup GPIO for epd");
        luat_gpio_mode(Pin_BUSY, Luat_GPIO_INPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);
        luat_gpio_mode(Pin_RES, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);
        luat_gpio_mode(Pin_DC, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);
        luat_gpio_mode(Pin_CS, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);

        status = luat_spi_setup(&spi_config);
    }
    

    size_t epd_w = 0;
    size_t epd_h = 0;
    if(status == 0)
    {
        LLOGD("spi setup complete, now setup epd");
        if(econf.full_mode)
            status = EPD_Init(1, &epd_w, &epd_h);
        else
            status = EPD_Init(0, &epd_w, &epd_h);

        if (status != 0) {
            LLOGD("e-Paper init failed");
            return 0;
        }
        frame_buffer = (unsigned char*)luat_heap_malloc(epd_w * epd_h / 8);
        //   Paint paint;
        Paint_Init(&paint, frame_buffer, epd_w, epd_h);
        Paint_Clear(&paint, UNCOLORED);
    }
    u8g2_SetFontMode(&(paint.luat_eink_u8g2), 0);
    u8g2_SetFontDirection(&(paint.luat_eink_u8g2), 0);
    //LLOGD("epd init complete");
    lua_pushboolean(L, 1);
    return 1;
}

/**
清除绘图缓冲区
@api eink.clear()
@return nil 无返回值,不会马上刷新到设备
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
@int rotate 显示方向,0/1/2/3, 相当于旋转0度/90度/180度/270度
@return nil 无返回值
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
@return int width  宽
@return int height 高
@return int rotate 旋转方向
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

static uint8_t utf8_state;
static uint16_t encoding;
static uint16_t utf8_next(uint8_t b)
{
  if ( b == 0 )  /* '\n' terminates the string to support the string list procedures */
    return 0x0ffff; /* end of string detected, pending UTF8 is discarded */
  if ( utf8_state == 0 )
  {
    if ( b >= 0xfc )  /* 6 byte sequence */
    {
      utf8_state = 5;
      b &= 1;
    }
    else if ( b >= 0xf8 )
    {
      utf8_state = 4;
      b &= 3;
    }
    else if ( b >= 0xf0 )
    {
      utf8_state = 3;
      b &= 7;      
    }
    else if ( b >= 0xe0 )
    {
      utf8_state = 2;
      b &= 15;
    }
    else if ( b >= 0xc0 )
    {
      utf8_state = 1;
      b &= 0x01f;
    }
    else
    {
      /* do nothing, just use the value as encoding */
      return b;
    }
    encoding = b;
    return 0x0fffe;
  }
  else
  {
    utf8_state--;
    /* The case b < 0x080 (an illegal UTF8 encoding) is not checked here. */
    encoding<<=6;
    b &= 0x03f;
    encoding |= b;
    if ( utf8_state != 0 )
      return 0x0fffe; /* nothing to do yet */
  }
  return encoding;
}

static void drawFastHLine(Paint* conf,int16_t x, int16_t y, int16_t len, uint16_t color){
    Paint_DrawHorizontalLine(conf,x, y, len,color);
}
static void drawFastVLine(Paint* conf,int16_t x, int16_t y, int16_t len, uint16_t color){
    Paint_DrawVerticalLine(conf,x, y, len,color);
}

static void u8g2_draw_hv_line(u8g2_t *u8g2, int16_t x, int16_t y, int16_t len, uint8_t dir, uint16_t color){
  switch(dir)
  {
    case 0:
      drawFastHLine(&paint,x,y,len,color);
      break;
    case 1:
        drawFastVLine(&paint,x,y,len,color);
      break;
    case 2:
        drawFastHLine(&paint,x-len+1,y,len,color);
      break;
    case 3:
        drawFastVLine(&paint,x,y-len+1,len,color);
      break;
  }
}

static void u8g2_font_decode_len(u8g2_t *u8g2, uint8_t len, uint8_t is_foreground){
  uint8_t cnt;  /* total number of remaining pixels, which have to be drawn */
  uint8_t rem;  /* remaining pixel to the right edge of the glyph */
  uint8_t current;  /* number of pixels, which need to be drawn for the draw procedure */
    /* current is either equal to cnt or equal to rem */
  /* local coordinates of the glyph */
  uint8_t lx,ly;
  /* target position on the screen */
  int16_t x, y;
  u8g2_font_decode_t *decode = &(u8g2->font_decode);
  cnt = len;
  /* get the local position */
  lx = decode->x;
  ly = decode->y;
  for(;;){
    /* calculate the number of pixel to the right edge of the glyph */
    rem = decode->glyph_width;
    rem -= lx;
    /* calculate how many pixel to draw. This is either to the right edge */
    /* or lesser, if not enough pixel are left */
    current = rem;
    if ( cnt < rem )
      current = cnt;
    /* now draw the line, but apply the rotation around the glyph target position */
    //u8g2_font_decode_draw_pixel(u8g2, lx,ly,current, is_foreground);
    /* get target position */
    x = decode->target_x;
    y = decode->target_y;
    /* apply rotation */
    x = u8g2_add_vector_x(x, lx, ly, decode->dir);
    y = u8g2_add_vector_y(y, lx, ly, decode->dir);
    /* draw foreground and background (if required) */
    if ( current > 0 )		/* avoid drawing zero length lines, issue #4 */
    {
      if ( is_foreground )
      {
	    u8g2_draw_hv_line(u8g2, x, y, current, decode->dir, eink_str_color);
      }
      else if ( decode->is_transparent == 0 )    
      {
	// u8g2_draw_hv_line(u8g2, x, y, current, decode->dir, decode->bg_color);
      }
    }
    /* check, whether the end of the run length code has been reached */
    if ( cnt < rem )
      break;
    cnt -= rem;
    lx = 0;
    ly++;
  }
  lx += cnt;
  decode->x = lx;
  decode->y = ly;
}
static void u8g2_font_setup_decode(u8g2_t *u8g2, const uint8_t *glyph_data)
{
  u8g2_font_decode_t *decode = &(u8g2->font_decode);
  decode->decode_ptr = glyph_data;
  decode->decode_bit_pos = 0;
  
  /* 8 Nov 2015, this is already done in the glyph data search procedure */
  /*
  decode->decode_ptr += 1;
  decode->decode_ptr += 1;
  */
  
  decode->glyph_width = u8g2_font_decode_get_unsigned_bits(decode, u8g2->font_info.bits_per_char_width);
  decode->glyph_height = u8g2_font_decode_get_unsigned_bits(decode,u8g2->font_info.bits_per_char_height);
  
}
static int8_t u8g2_font_decode_glyph(u8g2_t *u8g2, const uint8_t *glyph_data){
  uint8_t a, b;
  int8_t x, y;
  int8_t d;
  int8_t h;
  u8g2_font_decode_t *decode = &(u8g2->font_decode);
  u8g2_font_setup_decode(u8g2, glyph_data);
  h = u8g2->font_decode.glyph_height;
  x = u8g2_font_decode_get_signed_bits(decode, u8g2->font_info.bits_per_char_x);
  y = u8g2_font_decode_get_signed_bits(decode, u8g2->font_info.bits_per_char_y);
  d = u8g2_font_decode_get_signed_bits(decode, u8g2->font_info.bits_per_delta_x);
  
  if ( decode->glyph_width > 0 )
  {
    decode->target_x = u8g2_add_vector_x(decode->target_x, x, -(h+y), decode->dir);
    decode->target_y = u8g2_add_vector_y(decode->target_y, x, -(h+y), decode->dir);
    //u8g2_add_vector(&(decode->target_x), &(decode->target_y), x, -(h+y), decode->dir);
    /* reset local x/y position */
    decode->x = 0;
    decode->y = 0;
    /* decode glyph */
    for(;;){
      a = u8g2_font_decode_get_unsigned_bits(decode, u8g2->font_info.bits_per_0);
      b = u8g2_font_decode_get_unsigned_bits(decode, u8g2->font_info.bits_per_1);
      do{
        u8g2_font_decode_len(u8g2, a, 0);
        u8g2_font_decode_len(u8g2, b, 1);
      } while( u8g2_font_decode_get_unsigned_bits(decode, 1) != 0 );
      if ( decode->y >= h )
        break;
    }
  }
  return d;
}
const uint8_t *u8g2_font_get_glyph_data(u8g2_t *u8g2, uint16_t encoding);
static int16_t u8g2_font_draw_glyph(u8g2_t *u8g2, int16_t x, int16_t y, uint16_t encoding){
  int16_t dx = 0;
  u8g2->font_decode.target_x = x;
  u8g2->font_decode.target_y = y;
  const uint8_t *glyph_data = u8g2_font_get_glyph_data(u8g2, encoding);
  if ( glyph_data != NULL ){
    dx = u8g2_font_decode_glyph(u8g2, glyph_data);
  }
  return dx;
}


/**
绘制字符串
@api eink.print(x, y, str, colored, font)
@int x坐标
@int y坐标
@string 字符串
@int 默认是0
@font 字体大小,默认12
@return nil 无返回值
*/
static int l_eink_print(lua_State *L)
{
    size_t len;
    int x           = luaL_checkinteger(L, 1);
    int y           = luaL_checkinteger(L, 2);
    const char *str = luaL_checklstring(L, 3, &len);
    eink_str_color  = luaL_optinteger(L, 4, 0);
    int font        = luaL_optinteger(L, 5, 12);
switch (font)
        {
        case font_opposansm8:
            LLOGI("font_opposansm8");
            u8g2_SetFont(&(paint.luat_eink_u8g2), u8g2_font_opposansm8);
            lua_pushboolean(L, 1);
            break;
        case font_opposansm10:
            LLOGI("font_opposansm10");
            u8g2_SetFont(&(paint.luat_eink_u8g2), u8g2_font_opposansm10);
            lua_pushboolean(L, 1);
            break;
        case font_opposansm12:
            LLOGI("font_opposansm12");
            u8g2_SetFont(&(paint.luat_eink_u8g2), u8g2_font_opposansm12);
            lua_pushboolean(L, 1);
            break;
        case font_opposansm16:
            LLOGI("font_opposansm16");
            u8g2_SetFont(&(paint.luat_eink_u8g2), u8g2_font_opposansm16);
            lua_pushboolean(L, 1);
            break;
        case font_opposansm18:
            LLOGI("font_opposansm18");
            u8g2_SetFont(&(paint.luat_eink_u8g2), u8g2_font_opposansm18);
            lua_pushboolean(L, 1);
            break;
        case font_opposansm20:
            LLOGI("font_opposansm20");
            u8g2_SetFont(&(paint.luat_eink_u8g2), u8g2_font_opposansm20);
            lua_pushboolean(L, 1);
            break;
        case font_opposansm22:
            LLOGI("font_opposansm22");
            u8g2_SetFont(&(paint.luat_eink_u8g2), u8g2_font_opposansm22);
            lua_pushboolean(L, 1);
            break;
        case font_opposansm24:
            LLOGI("font_opposansm24");
            u8g2_SetFont(&(paint.luat_eink_u8g2), u8g2_font_opposansm24);
            lua_pushboolean(L, 1);
            break;
        case font_opposansm32:
            LLOGI("font_opposansm32");
            u8g2_SetFont(&(paint.luat_eink_u8g2), u8g2_font_opposansm32);
            lua_pushboolean(L, 1);
            break;
#if defined USE_U8G2_OPPOSANSM12_CHINESE
        case font_opposansm12_chinese:
            LLOGI("font_opposansm12_chinese");
            u8g2_SetFont(&(paint.luat_eink_u8g2), u8g2_font_opposansm12_chinese);
            lua_pushboolean(L, 1);
            break;
#endif
#if defined USE_U8G2_OPPOSANSM16_CHINESE
        case font_opposansm16_chinese:
            LLOGI("font_opposansm16_chinese");
            u8g2_SetFont(&(paint.luat_eink_u8g2), u8g2_font_opposansm16_chinese);
            lua_pushboolean(L, 1);
            break;
#endif
#if defined USE_U8G2_OPPOSANSM24_CHINESE
        case font_opposansm24_chinese:
            LLOGI("font_opposansm24_chinese");
            u8g2_SetFont(&(paint.luat_eink_u8g2), u8g2_font_opposansm24_chinese);
            lua_pushboolean(L, 1);
            break;
#endif
#if defined USE_U8G2_OPPOSANSM32_CHINESE
        case font_opposansm32_chinese:
            LLOGI("font_opposansm32_chinese");
            u8g2_SetFont(&(paint.luat_eink_u8g2), u8g2_font_opposansm32_chinese);
            lua_pushboolean(L, 1);
            break;
#endif
        default:
            lua_pushboolean(L, 0);
            LLOGI("no font");
            break;
        }
uint16_t e;
    int16_t delta, sum;
    utf8_state = 0;
    sum = 0;
    for(;;){
        e = utf8_next((uint8_t)*str);
        if ( e == 0x0ffff )
        break;
        str++;
        if ( e != 0x0fffe ){
        delta = u8g2_font_draw_glyph(&(paint.luat_eink_u8g2), x, y, e);
        switch(paint.luat_eink_u8g2.font_decode.dir){
            case 0:
            x += delta;
            break;
            case 1:
            y += delta;
            break;
            case 2:
            x -= delta;
            break;
            case 3:
            y -= delta;
            break;
        }
        sum += delta;    
        }
    }
    return 0;
}

/**
将缓冲区图像输出到屏幕
@api eink.show(x, y)
@int x 输出的x坐标,默认0
@int y 输出的y坐标,默认0
@return nil 无返回值
*/
static int l_eink_show(lua_State *L)
{
    int x     = luaL_optinteger(L, 1, 0);
    int y     = luaL_optinteger(L, 2, 0);
    /* Display the frame_buffer */
    //EPD_SetFrameMemory(&epd, frame_buffer, x, y, Paint_GetWidth(&paint), Paint_GetHeight(&paint));
    //EPD_DisplayFrame(&epd);
    EPD_Clear();
    EPD_Display(frame_buffer, NULL);
    return 0;
}


/**
缓冲区绘制线
@api eink.line(x, y, x2, y2, colored)
@int 起点x坐标
@int 起点y坐标
@int 终点x坐标
@int 终点y坐标
@return nil 无返回值
@usage
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
@int 左上顶点x坐标
@int 左上顶点y坐标
@int 右下顶点x坐标
@int 右下顶点y坐标
@int 默认是0
@int 是否填充,默认是0,不填充
@return nil 无返回值
@usage
eink.rect(0, 0, 10, 20)
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
@int 圆心x坐标
@int 圆心y坐标
@int 半径
@int 默认是0
@int 是否填充,默认是0,不填充
@return nil 无返回值
@usage
eink.circle(0, 0, 10)
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
@api eink.qrcode(x, y, str, version)
@int x坐标
@int y坐标
@string 二维码的内容
@int 二维码版本号
@return nil 无返回值
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
@api eink.bat(x, y, bat)
@int x坐标
@int y坐标
@int 电池电压,单位毫伏
@return nil 无返回值
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
@int x坐标
@int y坐标
@int 天气代号
@return nil 无返回值
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

/**
设置墨水屏驱动型号
@api eink.model(m)
@int 型号名称, 例如 eink.model(eink.MODEL_1in54_V2)
@return nil 无返回值
*/
static int l_eink_model(lua_State *L) {
    EPD_Model(luaL_checkinteger(L, 1));
    return 0;
}

#ifdef LUAT_USE_GTFONT

#include "GT5SLCD2E_1A.h"
extern void gtfont_draw_w(unsigned char *pBits,unsigned int x,unsigned int y,unsigned int widt,unsigned int high,int(*point)(void*),void* userdata,int mode);
extern void gtfont_draw_gray_hz(unsigned char *data,unsigned short x,unsigned short y,unsigned short w ,unsigned short h,unsigned char grade, unsigned char HB_par,int(*point)(void*,uint16_t, uint16_t, uint32_t),void* userdata,int mode);

static int l_eink_draw_gtfont_gb2312(lua_State *L) {
    unsigned char buf[128];
	int len;
	int i = 0;
	uint8_t strhigh,strlow ;
	uint16_t str;
  const char *fontCode = luaL_checklstring(L, 1,&len);
  unsigned char size = luaL_checkinteger(L, 2);
	int x = luaL_checkinteger(L, 3);
	int y = luaL_checkinteger(L, 4);
	while ( i < len){
		strhigh = *fontCode;
		fontCode++;
		strlow = *fontCode;
		str = (strhigh<<8)|strlow;
		fontCode++;
		get_font(buf, 1, str, size, size, size);
		gtfont_draw_w(buf , x ,y , size , size,Paint_DrawPixel,&paint,1);
		x+=size;
		i+=2;
	}
    return 0;
}

static int l_eink_draw_gtfont_gb2312_gray(lua_State* L) {
	unsigned char buf[2048];
	int len;
	int i = 0;
	uint8_t strhigh,strlow ;
	uint16_t str;
    const char *fontCode = luaL_checklstring(L, 1,&len);
    unsigned char size = luaL_checkinteger(L, 2);
	unsigned char font_g = luaL_checkinteger(L, 3);
	int x = luaL_checkinteger(L, 4);
	int y = luaL_checkinteger(L, 5);
	while ( i < len){
		strhigh = *fontCode;
		fontCode++;
		strlow = *fontCode;
		str = (strhigh<<8)|strlow;
		fontCode++;
		get_font(buf, 1, str, size*font_g, size*font_g, size*font_g);
		Gray_Process(buf,size,size,font_g);
		gtfont_draw_gray_hz(buf, x, y, size , size, font_g, 1,Paint_DrawPixel,&paint,1);
		x+=size;
		i+=2;
	}
    return 0;
}

#ifdef LUAT_USE_GTFONT_UTF8
extern unsigned short unicodetogb2312 ( unsigned short	chr);
static int l_eink_draw_gtfont_utf8(lua_State *L) {
    unsigned char buf[128];
    int len;
    int i = 0;
    uint8_t strhigh,strlow ;
    uint16_t e,str;
    const char *fontCode = luaL_checklstring(L, 1,&len);
    unsigned char size = luaL_checkinteger(L, 2);
    int x = luaL_checkinteger(L, 3);
    int y = luaL_checkinteger(L, 4);
    for(;;){
      e = utf8_next((uint8_t)*fontCode);
      if ( e == 0x0ffff )
      break;
      fontCode++;
      if ( e != 0x0fffe ){
        uint16_t str = unicodetogb2312(e);
        get_font(buf, 1, str, size, size, size);
        gtfont_draw_w(buf , x ,y , size , size,Paint_DrawPixel,&paint,1);
        x+=size;    
      }
    }
    return 0;
}

static int l_eink_draw_gtfont_utf8_gray(lua_State* L) {
	unsigned char buf[2048];
	int len;
	int i = 0;
	uint8_t strhigh,strlow ;
	uint16_t e,str;
  const char *fontCode = luaL_checklstring(L, 1,&len);
  unsigned char size = luaL_checkinteger(L, 2);
	unsigned char font_g = luaL_checkinteger(L, 3);
	int x = luaL_checkinteger(L, 4);
	int y = luaL_checkinteger(L, 5);
	for(;;){
        e = utf8_next((uint8_t)*fontCode);
        if ( e == 0x0ffff )
        break;
        fontCode++;
        if ( e != 0x0fffe ){
			uint16_t str = unicodetogb2312(e);
			get_font(buf, 1, str, size*font_g, size*font_g, size*font_g);
			Gray_Process(buf,size,size,font_g);
      gtfont_draw_gray_hz(buf, x, y, size , size, font_g, 1,Paint_DrawPixel,&paint,1);
        	x+=size;    
        }
    }
    return 0;
}

#endif // LUAT_USE_GTFONT_UTF8

#endif // LUAT_USE_GTFONT

static void eink_DrawHXBM(uint16_t x, uint16_t y, uint16_t len, const uint8_t *b){
  uint8_t mask;
  mask = 1;
  while(len > 0) {
    if ( *b & mask ) drawFastHLine(&paint, x, y, 1,COLORED);
    else drawFastVLine(&paint, x, y, 1,UNCOLORED);
    x++;
    mask <<= 1;
    if ( mask == 0 ){
      mask = 1;
      b++;
    }
    len--;
  }
}

/*
绘制位图
@api eink.drawXbm(x, y, w, h, data)
@int X坐标
@int y坐标
@int 位图宽
@int 位图高
@int 位图数据,每一位代表一个像素
@usage
-- 取模使用PCtoLCD2002软件即可
-- 在(0,0)为左上角,绘制 16x16 "今" 的位图
eink.drawXbm(0, 0, 16,16, string.char(
    0x80,0x00,0x80,0x00,0x40,0x01,0x20,0x02,0x10,0x04,0x48,0x08,0x84,0x10,0x83,0x60,
    0x00,0x00,0xF8,0x0F,0x00,0x08,0x00,0x04,0x00,0x04,0x00,0x02,0x00,0x01,0x80,0x00
))
*/
static int l_eink_drawXbm(lua_State *L){
    int x = luaL_checkinteger(L, 1);
    int y = luaL_checkinteger(L, 2);
    int w = luaL_checkinteger(L, 3);
    int h = luaL_checkinteger(L, 4);
    size_t len = 0;
    const char* data = luaL_checklstring(L, 5, &len);
    if (h < 1) return 0; // 行数必须大于0
    if (w < h) return 0; // 起码要填满一行
    uint8_t blen;
    blen = w;
    blen += 7;
    blen >>= 3;
    while( h > 0 ){
      eink_DrawHXBM(x, y, w, (const uint8_t*)data);
      data += blen;
      y++;
      h--;
    }
    lua_pushboolean(L, 1);
    return 1;
}

#include "rotable.h"
static const rotable_Reg reg_eink[] =
{
    { "setup",          l_eink_setup,           0},
    { "clear",          l_eink_clear,           0},
    { "setWin",         l_eink_setWin,          0},
    { "getWin",         l_eink_getWin,          0},
    { "print",          l_eink_print,           0},
    { "show",           l_eink_show,            0},
    { "rect",           l_eink_rect,            0},
    { "circle",         l_eink_circle,          0},
    { "line",           l_eink_line,            0},

    { "qrcode",         l_eink_qrcode,          0},
    { "bat",            l_eink_bat,             0},
    { "weather_icon",   l_eink_weather_icon,    0},

    { "model",          l_eink_model,           0},
    { "drawXbm",         l_eink_drawXbm,           0},
#ifdef LUAT_USE_GTFONT
    { "drawGtfontGb2312", l_eink_draw_gtfont_gb2312, 0},
    { "drawGtfontGb2312Gray", l_eink_draw_gtfont_gb2312_gray, 0},
#ifdef LUAT_USE_GTFONT_UTF8
    { "drawGtfontUtf8", l_eink_draw_gtfont_utf8, 0},
    { "drawGtfontUtf8Gray", l_eink_draw_gtfont_utf8_gray, 0},
#endif // LUAT_USE_GTFONT_UTF8
#endif // LUAT_USE_GTFONT
    { "MODEL_1in02d",         NULL,                 MODEL_1in02d},
    { "MODEL_1in54",          NULL,                 MODEL_1in54},
    { "MODEL_1in54_V2",       NULL,                 MODEL_1in54_V2},
    { "MODEL_1in54b",         NULL,                 MODEL_1in54b},
    { "MODEL_1in54b_V2",      NULL,                 MODEL_1in54b_V2},
    { "MODEL_1in54c",         NULL,                 MODEL_1in54c},
    { "MODEL_1in54f",         NULL,                 MODEL_1in54f},
    { "MODEL_2in54b_V3",      NULL,                 MODEL_2in13b_V3},
    { "MODEL_2in7",           NULL,                 MODEL_2in7},
    { "MODEL_2in7b",          NULL,                 MODEL_2in7b},
    { "MODEL_2in9",           NULL,                 MODEL_2in9},
    { "MODEL_2in9_V2",        NULL,                 MODEL_2in9_V2},
    { "MODEL_2in9bc",         NULL,                 MODEL_2in9bc},
    { "MODEL_2in9b_V3",       NULL,                 MODEL_2in9b_V3},
    { "MODEL_2in9d",          NULL,                 MODEL_2in9d},
    { "MODEL_2in9f",          NULL,                 MODEL_2in9f},
    { "MODEL_3in7",           NULL,                 MODEL_3in7},
    { "font_opposansm8", NULL,       font_opposansm8},
    { "font_opposansm10", NULL,       font_opposansm10},
    { "font_opposansm12", NULL,       font_opposansm12},
    { "font_opposansm16", NULL,       font_opposansm16},
    { "font_opposansm18", NULL,       font_opposansm18},
    { "font_opposansm20", NULL,       font_opposansm20},
    { "font_opposansm22", NULL,       font_opposansm22},
    { "font_opposansm24", NULL,       font_opposansm24},
    { "font_opposansm32", NULL,       font_opposansm32},
    { "font_opposansm12_chinese", NULL,       font_opposansm12_chinese},
    { "font_opposansm16_chinese", NULL,       font_opposansm16_chinese},
    { "font_opposansm24_chinese", NULL,       font_opposansm24_chinese},
    { "font_opposansm32_chinese", NULL,       font_opposansm32_chinese},

	{ NULL,             NULL,                   0}
};

LUAMOD_API int luaopen_eink( lua_State *L ){
    luat_newlib(L, reg_eink);
    return 1;
}
