/*
@module  eink
@summary 墨水屏操作库
@version 1.0
@date    2020.11.14
@demo eink
@tag LUAT_USE_EINK
*/
#include "luat_base.h"

#include "luat_sys.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_malloc.h"
#include "luat_spi.h"

#include "luat_gpio.h"

#include "epd.h"
#include "epdpaint.h"
#include "imagedata.h"
#include "qrcodegen.h"
#include <stdlib.h>

#include "u8g2_luat_fonts.h"
#include "luat_zbuff.h"

#include "luat_log.h"
#ifndef LUAT_LOG_TAG
#define LUAT_LOG_TAG "eink"
#endif

int8_t u8g2_font_decode_get_signed_bits(u8g2_font_decode_t *f, uint8_t cnt);
uint8_t u8g2_font_decode_get_unsigned_bits(u8g2_font_decode_t *f, uint8_t cnt);

#define COLORED      0
#define UNCOLORED    1

eink_conf_t econf = {0};

static int check_init(void) {
    if (econf.ctxs[0] == NULL) {
      LLOGW("eink NOT init yet");
      return 0;
    }
    return 1;
}

/*
eink显示屏初始化
@api eink.init(tp, args,spi_device)
@number eink类型，当前支持：https://wiki.luatos.com/api/eink.html#id1
@table 附加参数,与具体设备有关：<br>pin_busy（busy）<br>port：spi端口,例如0,1,2...如果为device方式则为"device"<br>pin_dc：eink数据/命令选择引脚<br>pin_rst：eink复位引脚
@userdata spi设备,当port = "device"时有效
@usage
-- 初始化spi0的eink.MODEL_4in2bc) 注意:eink初始化之前需要先初始化spi
spi_eink = spi.deviceSetup(0,20,0,0,8,20000000,spi.MSB,1,1)
log.info("eink.init",
eink.init(eink.MODEL_4in2bc,{port = "device",pin_dc = 17, pin_pwr = 7,pin_rst = 19,direction = 2,w = 160,h = 80,xoffset = 1,yoffset = 26},spi_eink))
*/
static int l_eink_init(lua_State* L) {
    if (lua_type(L, 3) == LUA_TUSERDATA){
        // 如果是SPI Device模式, 就可能出现变量为local, 从而在某个时间点被GC掉的可能性
        econf.eink_spi_device = (luat_spi_device_t*)lua_touserdata(L, 3);
        lua_pushvalue(L, 3);
        // 所以, 直接引用之外, 再加上强制引用, 避免被GC
        // 鉴于LCD不太可能重复初始化, 引用也没什么问题
        econf.eink_spi_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        econf.port = LUAT_EINK_SPI_DEVICE;
    }
    if (econf.async){
      luat_rtos_task_create(&econf.eink_task_handle, 512, 50, "eink", EPD_Task, NULL, 0);
      luat_rtos_queue_create(&econf.eink_queue_handle, 5, sizeof(uint8_t));
    }
    EPD_Model(luaL_checkinteger(L, 1));

    if (lua_gettop(L) > 1) {

        lua_settop(L, 2); // 丢弃多余的参数

        lua_pushstring(L, "port");
        int port = lua_gettable(L, 2);
        if (econf.port == LUAT_EINK_SPI_DEVICE && port ==LUA_TNUMBER) {
          LLOGE("port is not device but find luat_spi_device_t");
          goto end;
        }else if (econf.port != LUAT_EINK_SPI_DEVICE && LUA_TSTRING == port){
          LLOGE("port is device but not find luat_spi_device_t");
          goto end;
        }else if (LUA_TNUMBER == port) {
            econf.port = luaL_checkinteger(L, -1);
        }else if (LUA_TSTRING == port){
            econf.port = LUAT_EINK_SPI_DEVICE;
        }
        lua_pop(L, 1);

        lua_pushstring(L, "pin_dc");
        if (LUA_TNUMBER == lua_gettable(L, 2)) {
            econf.pin_dc = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);

        lua_pushstring(L, "pin_busy");
        if (LUA_TNUMBER == lua_gettable(L, 2)) {
            econf.pin_busy = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);

        lua_pushstring(L, "pin_rst");
        if (LUA_TNUMBER == lua_gettable(L, 2)) {
            econf.pin_rst = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);

        lua_pushstring(L, "mode");
        if (LUA_TNUMBER == lua_gettable(L, 2)) {
            econf.full_mode = luaL_optinteger(L, -1, 1);
        }
        lua_pop(L, 1);

        lua_pushstring(L, "pin_cs");
        if (LUA_TNUMBER == lua_gettable(L, 2)) {
            econf.pin_cs = luaL_checkinteger(L, -1);
            luat_gpio_mode(econf.pin_cs, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);
        }
        lua_pop(L, 1);
    }

    luat_gpio_mode(econf.pin_busy, Luat_GPIO_INPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);
    luat_gpio_mode(econf.pin_rst, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);
    luat_gpio_mode(econf.pin_dc, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);

    size_t epd_w = 0;
    size_t epd_h = 0;
    size_t colors = 0;

    int status = EPD_Init(econf.full_mode, &epd_w, &epd_h, &colors);

    if (status != 0) {
        LLOGD("e-Paper init failed");
        return 0;
    }

    if (colors > 2) {
        LLOGE("only 2 color eink supported yet");
        return 0;
    }
    for (size_t i = 0; i < colors; i++){
        econf.ctxs[i] = luat_heap_malloc( sizeof(eink_ctx_t) +  (epd_w * epd_h + 7) / 8);
        if (econf.ctxs[i] == NULL) {
            LLOGE("out of memory when malloc buff for eink");
            for (size_t j = 0; j < i - 1; j++)
            {
                luat_heap_free(econf.ctxs[i]);
                econf.ctxs[i] = NULL;
            }
          return 0;
        }
        Paint_Init(&econf.ctxs[i]->paint, econf.ctxs[i]->fb, epd_w, epd_h);
        Paint_Clear(&econf.ctxs[i]->paint, UNCOLORED);
        econf.ctxs[i]->paint.inited = 1;
    }

    u8g2_SetFont(&(econf.luat_eink_u8g2), u8g2_font_opposansm8);
    u8g2_SetFontMode(&(econf.luat_eink_u8g2), 0);
    u8g2_SetFontDirection(&(econf.luat_eink_u8g2), 0);
    lua_pushboolean(L, 1);
    return 1;

end:
    lua_pushboolean(L, 0);
    return 1;
}


/**
初始化eink
@api eink.setup(full, spiid, pin_busy, pin_reset, pin_dc, pin_cs)
@int 全屏刷新0,局部刷新1,默认是全屏刷新
@int 所在的spi,默认是0
@int Busy 忙信号管脚
@int Reset 复位管脚
@int DC 数据命令选择管脚
@int CS 使能管脚
@return boolean 成功返回true,否则返回false
*/
static int l_eink_setup(lua_State *L) {
    int status = 0;
    econf.full_mode = luaL_optinteger(L, 1, 1);
    econf.port = luaL_optinteger(L, 2, 0);

    econf.pin_busy = luaL_checkinteger(L, 3);
    econf.pin_rst  = luaL_checkinteger(L, 4);
    econf.pin_dc = luaL_checkinteger(L, 5);
    econf.pin_cs = luaL_checkinteger(L, 6);

    luat_gpio_mode(econf.pin_busy, Luat_GPIO_INPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);
    luat_gpio_mode(econf.pin_rst, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);
    luat_gpio_mode(econf.pin_dc, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);

    if (lua_type(L, 7) == LUA_TUSERDATA){
        //LLOGD("luat_spi_device_send");
        econf.eink_spi_device = (luat_spi_device_t*)lua_touserdata(L, 3);
        econf.port = LUAT_EINK_SPI_DEVICE;

        status = 0;
    }else{
        luat_gpio_mode(econf.pin_cs, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);
    }

    if (status != 0) {
      LLOGD("spi setup fail, eink init fail");
      return 0;
    }

    size_t epd_w = 0;
    size_t epd_h = 0;
    size_t colors = 0;

    if(status == 0)
    {
        if(econf.full_mode)
            status = EPD_Init(1, &epd_w, &epd_h, &colors);
        else
            status = EPD_Init(0, &epd_w, &epd_h, &colors);

        if (status != 0) {
            LLOGD("e-Paper init failed");
            return 0;
        }
        LLOGD("spi setup complete, now setup epd");
        if (colors > 2) {
            LLOGE("only 2 color eink supported yet");
            return 0;
        }
        for (size_t i = 0; i < colors; i++)
        {
            econf.ctxs[i] = luat_heap_malloc( sizeof(eink_ctx_t) +  (epd_w * epd_h + 7) / 8);
            if (econf.ctxs[i] == NULL) {
                LLOGE("out of memory when malloc buff for eink");
                for (size_t j = 0; j < i - 1; j++)
                {
                    luat_heap_free(econf.ctxs[i]);
                    econf.ctxs[i] = NULL;
                }
              return 0;
            }
            Paint_Init(&econf.ctxs[i]->paint, econf.ctxs[i]->fb, epd_w, epd_h);
            Paint_Clear(&econf.ctxs[i]->paint, UNCOLORED);
            econf.ctxs[i]->paint.inited = 1;
        }

    }
    u8g2_SetFont(&(econf.luat_eink_u8g2), u8g2_font_opposansm8);
    u8g2_SetFontMode(&(econf.luat_eink_u8g2), 0);
    u8g2_SetFontDirection(&(econf.luat_eink_u8g2), 0);
    //paint.inited = 1;
    //LLOGD("epd init complete");
    lua_pushboolean(L, 1);

    return 1;
}

/**
进入休眠模式，再次使用时需要重新初始化
@api eink.sleep()
*/
static int l_eink_sleep(lua_State *L)
{
    EPD_Sleep();
    lua_pushboolean(L, 1);
    return 1;
}

/**
清除绘图缓冲区，默认不会马上刷新到设备
@api eink.clear(color, force)
@number color 可选，默认1。刷屏颜色
@bool force 可选，默认false。如果为true则马上清屏
@return nil 无返回值
*/
static int l_eink_clear(lua_State *L)
{
    int colored = luaL_optinteger(L, 1, 1);
    int no_clear = lua_toboolean(L, 2);
    if (econf.async){
      econf.idp = luat_pushcwait(L);
      if (check_init() == 0) {
        lua_pushinteger(L,0);
	      luat_pushcwait_error(L,1);
        return 1;
      }
      Paint_Clear(&econf.ctxs[econf.ctx_index]->paint, colored);
      if (!no_clear){
        uint8_t event = EPD_CLEAR;
        luat_rtos_queue_send(econf.eink_queue_handle, &event, sizeof(uint8_t), 0);
      }
    }else{
      if (check_init() == 0) {
        return 0;
      }
      Paint_Clear(&econf.ctxs[econf.ctx_index]->paint, colored);
      if(!no_clear)
        EPD_Clear();
      lua_pushboolean(L, 1);
    }
    return 1;
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

    if (check_init() == 0)
        return 0;

    Paint_SetWidth(&econf.ctxs[econf.ctx_index]->paint, width);
    Paint_SetHeight(&econf.ctxs[econf.ctx_index]->paint, height);
    Paint_SetRotate(&econf.ctxs[econf.ctx_index]->paint, rotate);
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
    if (check_init() == 0)
        return 0;
    int width =  Paint_GetWidth(&econf.ctxs[econf.ctx_index]->paint);
    int height = Paint_GetHeight(&econf.ctxs[econf.ctx_index]->paint);
    int rotate = Paint_GetRotate(&econf.ctxs[econf.ctx_index]->paint);

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
      drawFastHLine(&econf.ctxs[econf.ctx_index]->paint,x,y,len,color);
      break;
    case 1:
        drawFastVLine(&econf.ctxs[econf.ctx_index]->paint,x,y,len,color);
      break;
    case 2:
        drawFastHLine(&econf.ctxs[econf.ctx_index]->paint,x-len+1,y,len,color);
      break;
    case 3:
        drawFastVLine(&econf.ctxs[econf.ctx_index]->paint,x,y-len+1,len,color);
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
	    u8g2_draw_hv_line(u8g2, x, y, current, decode->dir, econf.ctxs[econf.ctx_index]->str_color);
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
设置字体
@api eink.setFont(font)
@userdata 字体
@usage
-- 设置为字体,对之后的print有效
eink.setFont(eink.font_opposansm12_chinese)
*/
static int l_eink_set_font(lua_State *L) {
    if (check_init() == 0) {
      return 0;
    }
    if (!lua_islightuserdata(L, 1)) {
        LLOGE("only font pointer is allow");
        return 0;
    }
    const uint8_t *ptr = (const uint8_t *)lua_touserdata(L, 1);
    if (ptr == NULL) {
        LLOGE("only font pointer is allow");
        return 0;
    }
    u8g2_SetFont(&(econf.luat_eink_u8g2), ptr);
    lua_pushboolean(L, 1);
    return 1;
}

/**
绘制字符串
@api eink.print(x, y, str, colored)
@int x坐标
@int y坐标
@string 字符串
@int 颜色, 可以是0或者1, 默认是0
@return nil 无返回值
@usage
-- 先设置字体, 然后写字
-- 可用字体取决于具体的固件, 如果没有你想要的大小,可以云编译一份自定义固件
-- font_opposansm8_chinese
-- font_opposansm10_chinese
-- font_opposansm12_chinese
-- font_opposansm14_chinese
-- font_opposansm16_chinese
eink.setFont(eink.font_opposansm12_chinese)
eink.print(10, 20, "LuatOS")
*/
static int l_eink_print(lua_State *L)
{
    size_t len;
    int x           = luaL_checkinteger(L, 1);
    int y           = luaL_checkinteger(L, 2);
    const char *str = luaL_checklstring(L, 3, &len);


    if (check_init() == 0) {
      return 0;
    }
    econf.ctxs[econf.ctx_index]->str_color = luaL_optinteger(L, 4, 0);

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
        delta = u8g2_font_draw_glyph(&(econf.luat_eink_u8g2), x, y, e);
        switch(econf.luat_eink_u8g2.font_decode.dir){
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
@api eink.show(x, y, noClear)
@int x 输出的x坐标,默认0
@int y 输出的y坐标,默认0
@bool 可选，默认false。如果为true则不进行清屏，直接刷上新内容
@return nil 无返回值
*/
static int l_eink_show(lua_State *L)
{
    // int x     = luaL_optinteger(L, 1, 0);
    // int y     = luaL_optinteger(L, 2, 0);
    int no_clear     = lua_toboolean(L, 3);
    /* Display the frame_buffer */
    //EPD_SetFrameMemory(&epd, frame_buffer, x, y, Paint_GetWidth(&econf.ctxs[econf.ctx_index]->paint), Paint_GetHeight(&econf.ctxs[econf.ctx_index]->paint));
    //EPD_DisplayFrame(&epd);

    if (econf.async){
      econf.idp = luat_pushcwait(L);
      if (check_init() == 0) {
        lua_pushinteger(L,0);
	      luat_pushcwait_error(L,1);
        return 1;
      }
      uint8_t event = EPD_SHOW;
      if (!no_clear){
        event |= EPD_CLEAR;
      }
      luat_rtos_queue_send(econf.eink_queue_handle, &event, sizeof(uint8_t), 0);
    }else{
      if (check_init() == 0) {
        return 0;
      }
      if(!no_clear)
        EPD_Clear();
      if (econf.ctxs[1] == NULL)
        EPD_Display(econf.ctxs[0]->fb, NULL);
      else
        EPD_Display(econf.ctxs[0]->fb, econf.ctxs[1]->fb);
      lua_pushboolean(L, 1);
    }
    return 1;
}

/**
直接输出数据到屏幕,支持双色数据
@api eink.draw(buff, buff2, noclear)
@userdata zbuff指针
@userdata zbuff指针
@bool 可选，默认false。如果为true则不进行清屏，直接刷上新内容
@return nil 无返回值
*/
static int l_eink_draw(lua_State *L)
{
    luat_zbuff_t* buff = tozbuff(L);
    luat_zbuff_t* buff2 = buff;
    int no_clear     = lua_toboolean(L, 3);
    if (lua_isuserdata(L, 2)) {
      buff2 = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
    }
    if (econf.async){
      econf.idp = luat_pushcwait(L);
      if (check_init() == 0) {
        lua_pushinteger(L,0);
	      luat_pushcwait_error(L,1);
        return 1;
      }
      uint8_t event = EPD_DRAW;
      if (!no_clear){
        event |= EPD_CLEAR;
      }
      luat_rtos_queue_send(econf.eink_queue_handle, &event, sizeof(uint8_t), 0);
    }else{
      if (check_init() == 0) {
        return 0;
      }
      if(!no_clear)
        EPD_Clear();
      EPD_Display(buff->addr, buff2->addr);
      lua_pushboolean(L, 1);
    }
    return 1;
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

    if (check_init() == 0) {
      return 0;
    }

    Paint_DrawLine(&econf.ctxs[econf.ctx_index]->paint, x, y, x2, y2, colored);
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
eink.rect(0, 0, 10, 20,0, 1) -- Filled
*/
static int l_eink_rect(lua_State *L)
{
    int x      = luaL_checkinteger(L, 1);
    int y      = luaL_checkinteger(L, 2);
    int x2      = luaL_checkinteger(L, 3);
    int y2      = luaL_checkinteger(L, 4);
    int colored = luaL_optinteger(L, 5, 0);
    int fill    = luaL_optinteger(L, 6, 0);

    if (check_init() == 0) {
      return 0;
    }

    if(fill)
        Paint_DrawFilledRectangle(&econf.ctxs[econf.ctx_index]->paint, x, y, x2, y2, colored);
    else
        Paint_DrawRectangle(&econf.ctxs[econf.ctx_index]->paint, x, y, x2, y2, colored);
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

    if (check_init() == 0) {
      return 0;
    }

    if(fill)
        Paint_DrawFilledCircle(&econf.ctxs[econf.ctx_index]->paint, x, y, radius, colored);
    else
        Paint_DrawCircle(&econf.ctxs[econf.ctx_index]->paint, x, y, radius, colored);
    return 0;
}

/**
缓冲区绘制QRCode
@api eink.qrcode(x, y, str, size)
@int x坐标
@int y坐标
@string 二维码的内容
@int 显示大小 (注意:二维码生成大小与要显示内容和纠错等级有关,生成版本为1-40(对应 21x21 - 177x177)的不定大小,如果和设置大小不同会自动在指定的区域中间显示二维码,如二维码未显示请查看日志提示)
@return nil 无返回值
*/
static int l_eink_qrcode(lua_State *L)
{
    size_t len;
    int x           = luaL_checkinteger(L, 1);
    int y           = luaL_checkinteger(L, 2);
    const char* text = luaL_checklstring(L, 3, &len);
    int size        = luaL_checkinteger(L, 4);

    if (check_init() == 0) {
      return 0;
    }

    uint8_t *qrcode = luat_heap_malloc(qrcodegen_BUFFER_LEN_MAX);
    uint8_t *tempBuffer = luat_heap_malloc(qrcodegen_BUFFER_LEN_MAX);
    if (qrcode == NULL || tempBuffer == NULL) {
        if (qrcode)
            luat_heap_free(qrcode);
        if (tempBuffer)
            luat_heap_free(tempBuffer);
        LLOGE("qrcode out of memory");
        return 0;
    }
    bool ok = qrcodegen_encodeText(text, tempBuffer, qrcode, qrcodegen_Ecc_LOW,
        qrcodegen_VERSION_MIN, qrcodegen_VERSION_MAX, qrcodegen_Mask_AUTO, true);
    if (ok){
        int qr_size = qrcodegen_getSize(qrcode);
        if (size < qr_size){
            LLOGE("size must be greater than qr_size %d",qr_size);
            goto end;
        }
        int scale = size / qr_size ;
        if (!scale)scale = 1;
        int margin = (size - qr_size * scale) / 2;
        x+=margin;
        y+=margin;
        for (int j = 0; j < qr_size; j++) {
            for (int i = 0; i < qr_size; i++) {
                if (qrcodegen_getModule(qrcode, i, j)){
                    Paint_DrawFilledRectangle(&econf.ctxs[econf.ctx_index]->paint,x+i*scale,y+j*scale,x+(i+1)*scale,y+(j+1)*scale,COLORED);
                }
            }
        }
    }else{
        LLOGE("qrcodegen_encodeText false");
    }
end:
    if (qrcode)
        luat_heap_free(qrcode);
    if (tempBuffer)
        luat_heap_free(tempBuffer);
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
    if (bat > 4200){
      LLOGE("The bat is greater than 4200");
    }
    
    if(bat > 4080)batnum = 100;
    if(bat <= 4080 && bat > 4000)batnum = 90;
    if(bat <= 4000 && bat > 3930)batnum = 80;
    if(bat <= 3930 && bat > 3870)batnum = 70;
    if(bat <= 3870 && bat > 3820)batnum = 60;
    if(bat <= 3820 && bat > 3790)batnum = 50;
    if(bat <= 3790 && bat > 3770)batnum = 40;
    if(bat <= 3770 && bat > 3730)batnum = 30;
    if(bat <= 3730 && bat > 3700)batnum = 20;
    if(bat <= 3700 && bat > 3680)batnum = 15;
    if(bat <= 3680 && bat > 3500)batnum = 10;
    if(bat <= 3500 && bat > 2500)batnum = 5;
    batnum = 20 - (int)(batnum / 5) + 3;

    if (check_init() == 0) {
      return 0;
    }
    // w外框
    Paint_DrawRectangle(&econf.ctxs[econf.ctx_index]->paint, x+0, y+3, x+2, y+6, COLORED);
    Paint_DrawRectangle(&econf.ctxs[econf.ctx_index]->paint, x+2, y+0, x+23, y+9, COLORED);
    // 3 ~21   100 / 5
    Paint_DrawFilledRectangle(&econf.ctxs[econf.ctx_index]->paint, x+batnum, y+1, x+22, y+8, COLORED);
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
    //             (gImage_103[i*8+j] << k )& 0x80 ? Paint_DrawPixel(&econf.ctxs[econf.ctx_index]->paint, x+j*8+k, y+i, COLORED) : Paint_DrawPixel(&econf.ctxs[econf.ctx_index]->paint, x+j*8+k, y+i, UNCOLORED);
    //     }
    // }

    if (check_init() == 0) {
      return 0;
    }

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
                (icon[i*6+j] << k )& 0x80 ? Paint_DrawPixel(&econf.ctxs[econf.ctx_index]->paint, x+j*8+k, y+i, COLORED) : Paint_DrawPixel(&econf.ctxs[econf.ctx_index]->paint, x+j*8+k, y+i, UNCOLORED);
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
		gtfont_draw_w(buf , x ,y , size , size,Paint_DrawPixel,&econf.ctxs[econf.ctx_index]->paint,1);
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
		gtfont_draw_gray_hz(buf, x, y, size , size, font_g, 1,Paint_DrawPixel,&econf.ctxs[econf.ctx_index]->paint,1);
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
        gtfont_draw_w(buf , x ,y , size , size,Paint_DrawPixel,&econf.ctxs[econf.ctx_index]->paint,1);
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
      gtfont_draw_gray_hz(buf, x, y, size , size, font_g, 1,Paint_DrawPixel,&econf.ctxs[econf.ctx_index]->paint,1);
        	x+=size;
        }
    }
    return 0;
}

#endif // LUAT_USE_GTFONT_UTF8

#endif // LUAT_USE_GTFONT

static void eink_DrawHXBM(uint16_t x, uint16_t y, uint16_t len, const uint8_t *b){
  uint8_t mask = 1;

  if (check_init() == 0) {
    return;
  }
  while(len > 0) {
    if ( *b & mask ) drawFastHLine(&econf.ctxs[econf.ctx_index]->paint, x, y, 1,COLORED);
    else drawFastVLine(&econf.ctxs[econf.ctx_index]->paint, x, y, 1,UNCOLORED);
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
    if (len*8/h < w) return 0; // 起码要填满一行
    if (len < h*w/8) return 0;

    if (check_init() == 0) {
      return 0;
    }

    uint8_t blen = 0;
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

/*
切换颜色画板, 适合多色墨水屏
@api eink.setCtx(index)
@int 颜色索引, 黑色为0, 红色为1
@usage
-- 仅适合多色墨水屏, 对单色墨水屏(只有黑白)的无效
eink.setCtx(1)
-- 切换后, 所有drawXXX都会操作在指定颜色的画板
*/
static int l_eink_set_ctx(lua_State *L) {
  int index = luaL_checkinteger(L, 1);
  if (index < 0 || index > 1) {
    LLOGE("invaild ctx index %d", index);
    return 0;
  }
  if (econf.ctxs[index] == NULL) {
    LLOGE("invaild ctx index %d", index);
    return 0;
  }
  econf.ctx_index = index;
  lua_pushboolean(L, 1);
  return 1;
}

/*
异步方式，使用此方式需要先 require("sysplus") 之后 eink.clear().wait() eink.show().wait()进行刷屏
@api eink.async(index)
@int 1 使用异步
@usage
    eink.async(1)
    spi_eink = spi.deviceSetup(spi_id,pin_cs,0,0,8,20*1000*1000,spi.MSB,1,1)
    eink.init(eink.MODEL_1in54,
            {port = "device",pin_dc = pin_dc, pin_busy = pin_busy,pin_rst = pin_reset},
            spi_eink)
    eink.setWin(200, 200, 0)
    sys.wait(100)
    log.info("e-paper 1.54", "Testing Go")
    eink.print(30, 20, "LuatOS-AIR780E",0x00)
    eink.show().wait()
    log.info("e-paper 1.54", "Testing End")
*/
static int l_eink_async(lua_State *L) {
  econf.async = luaL_checkinteger(L, 1);
  return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_eink[] =
{
    { "async",          ROREG_FUNC(l_eink_async)},
    { "init",           ROREG_FUNC(l_eink_init)},
    { "setup",          ROREG_FUNC(l_eink_setup)},
    { "sleep",          ROREG_FUNC(l_eink_sleep)},
    { "clear",          ROREG_FUNC(l_eink_clear)},
    { "setWin",         ROREG_FUNC(l_eink_setWin)},
    { "getWin",         ROREG_FUNC(l_eink_getWin)},
    { "print",          ROREG_FUNC(l_eink_print)},
    { "show",           ROREG_FUNC(l_eink_show)},
    { "rect",           ROREG_FUNC(l_eink_rect)},
    { "circle",         ROREG_FUNC(l_eink_circle)},
    { "line",           ROREG_FUNC(l_eink_line)},
    { "setFont",        ROREG_FUNC(l_eink_set_font)},

    { "qrcode",         ROREG_FUNC(l_eink_qrcode)},
    { "bat",            ROREG_FUNC(l_eink_bat)},
    { "weather_icon",   ROREG_FUNC(l_eink_weather_icon)},

    { "model",          ROREG_FUNC(l_eink_model)},
    { "drawXbm",        ROREG_FUNC(l_eink_drawXbm)},
    { "draw",           ROREG_FUNC(l_eink_draw)},
    { "setCtx",         ROREG_FUNC(l_eink_set_ctx)},
#ifdef LUAT_USE_GTFONT
    { "drawGtfontGb2312", ROREG_FUNC(l_eink_draw_gtfont_gb2312)},
    { "drawGtfontGb2312Gray", ROREG_FUNC(l_eink_draw_gtfont_gb2312_gray)},
#ifdef LUAT_USE_GTFONT_UTF8
    { "drawGtfontUtf8", ROREG_FUNC(l_eink_draw_gtfont_utf8)},
    { "drawGtfontUtf8Gray", ROREG_FUNC(l_eink_draw_gtfont_utf8_gray)},
#endif // LUAT_USE_GTFONT_UTF8
#endif // LUAT_USE_GTFONT
    //@const MODEL_1in02d number 1.02寸d
    { "MODEL_1in02d",         ROREG_INT(MODEL_1in02d)},
    //@const MODEL_1in54 number 1.54寸
    { "MODEL_1in54",          ROREG_INT(MODEL_1in54)},
    //@const MODEL_1in54_V2 number 1.54寸_V2
    { "MODEL_1in54_V2",       ROREG_INT(MODEL_1in54_V2)},
    //@const MODEL_1in54b number 1.54寸b
    { "MODEL_1in54b",         ROREG_INT(MODEL_1in54b)},
    //@const MODEL_1in54b_V2 number 1.54寸b_V2
    { "MODEL_1in54b_V2",      ROREG_INT(MODEL_1in54b_V2)},
    //@const MODEL_1in54_V3 number 1.54寸_V3
    { "MODEL_1in54_V3",       ROREG_INT(MODEL_1in54_V3)},
    //@const MODEL_1in54c number 1.54寸c
    { "MODEL_1in54c",         ROREG_INT(MODEL_1in54c)},
    //@const MODEL_1in54r number 1.54寸三色屏152*152
    { "MODEL_1in54r",         ROREG_INT(MODEL_1in54r)},
    //@const MODEL_2in13 number 2.13寸
    { "MODEL_2in13",          ROREG_INT(MODEL_2in13)},
    //@const MODEL_2in13bc number 2.13寸bc
    { "MODEL_2in13bc",        ROREG_INT(MODEL_2in13bc)},
    //@const MODEL_2in13d number 2.13寸d
    { "MODEL_2in13d",         ROREG_INT(MODEL_2in13d)},
    //@const MODEL_2in13_V2 number 2.13寸V2
    { "MODEL_2in13_V2",       ROREG_INT(MODEL_2in13_V2)},
    //@const MODEL_2in54b_V3 number 2.13寸b_V3
    { "MODEL_2in13b_V3",      ROREG_INT(MODEL_2in13b_V3)},
    //@const MODEL_2in66 number 2.66寸
    { "MODEL_2in66",          ROREG_INT(MODEL_2in66)},
    //@const MODEL_2in66b number 2.66寸b
    { "MODEL_2in66b",         ROREG_INT(MODEL_2in66b)},
    //@const MODEL_2in7 number 2.7寸
    { "MODEL_2in7",           ROREG_INT(MODEL_2in7)},
    //@const MODEL_2in7b number 2.7寸b
    { "MODEL_2in7b",          ROREG_INT(MODEL_2in7b)},
    //@const MODEL_2in9 number 2.9寸
    { "MODEL_2in9",           ROREG_INT(MODEL_2in9)},
    //@const MODEL_2in9_V2 number 2.9寸_V2
    { "MODEL_2in9_V2",        ROREG_INT(MODEL_2in9_V2)},
    //@const MODEL_2in9bc number 2.9寸bc
    { "MODEL_2in9bc",         ROREG_INT(MODEL_2in9bc)},
    //@const MODEL_2in9b_V3 number 2.9寸b_V3
    { "MODEL_2in9b_V3",       ROREG_INT(MODEL_2in9b_V3)},
    //@const MODEL_2in9d number 2.9寸d
    { "MODEL_2in9d",          ROREG_INT(MODEL_2in9d)},
    //@const MODEL_3in7 number 3.7寸
    { "MODEL_3in7",           ROREG_INT(MODEL_3in7)},
    //@const MODEL_4in2 number 4.2寸
    { "MODEL_4in2",           ROREG_INT(MODEL_4in2)},
    //@const MODEL_4in2bc number 4.2寸b
    { "MODEL_4in2bc",           ROREG_INT(MODEL_4in2bc)},
    //@const MODEL_4in2b_V2 number 4.2寸V2
    { "MODEL_4in2b_V2",           ROREG_INT(MODEL_4in2b_V2)},
    //@const MODEL_5in65f number 5.65寸f
    { "MODEL_5in65f",           ROREG_INT(MODEL_5in65f)},
    //@const MODEL_5in83 number 5.83寸
    { "MODEL_5in83",           ROREG_INT(MODEL_5in83)},
    //@const MODEL_5in83bc number 5.83寸bc
    { "MODEL_5in83bc",           ROREG_INT(MODEL_5in83bc)},
    //@const MODEL_5in83_V2 number 5.83寸V2
    { "MODEL_5in83_V2",           ROREG_INT(MODEL_5in83_V2)},
    //@const MODEL_5in83b_V2 number 5.83寸bV2
    { "MODEL_5in83b_V2",           ROREG_INT(MODEL_5in83b_V2)},
    //@const MODEL_7in5 number 7.5寸
    { "MODEL_7in5",           ROREG_INT(MODEL_7in5)},
    //@const MODEL_7in5_HD number 7.5寸HD
    { "MODEL_7in5_HD",           ROREG_INT(MODEL_7in5_HD)},
    //@const MODEL_7in5_V2 number 7.5寸V2
    { "MODEL_7in5_V2",           ROREG_INT(MODEL_7in5_V2)},
    //@const MODEL_7in5bc number 7.5寸bc
    { "MODEL_7in5bc",           ROREG_INT(MODEL_7in5bc)},
    //@const MODEL_7in5b_HD number 7.5寸b_HD
    { "MODEL_7in5b_HD",           ROREG_INT(MODEL_7in5b_HD)},
    //@const MODEL_7in5b_V2 number 7.5寸b_V2
    { "MODEL_7in5b_V2",           ROREG_INT(MODEL_7in5b_V2)},

    // 默认只带8号字体
    //@const font_opposansm8 font 8号字体
    { "font_opposansm8", ROREG_PTR((void*)u8g2_font_opposansm8)},
#ifdef USE_U8G2_OPPOSANSM_ENGLISH
    //@const font_unifont_t_symbols font 符号字体
    { "font_unifont_t_symbols",   ROREG_PTR((void*)u8g2_font_unifont_t_symbols)},
    //@const font_open_iconic_weather_6x_t font 天气字体
    { "font_open_iconic_weather_6x_t", ROREG_PTR((void*)u8g2_font_open_iconic_weather_6x_t)},

    //@const font_opposansm10 font 10号字体
    //@const font_opposansm12 font 12号字体
    //@const font_opposansm16 font 16号字体
    //@const font_opposansm18 font 18号字体
    //@const font_opposansm20 font 20号字体
    //@const font_opposansm22 font 22号字体
    //@const font_opposansm24 font 24号字体
    //@const font_opposansm32 font 32号字体
    { "font_opposansm10", ROREG_PTR((void*)u8g2_font_opposansm10)},
    { "font_opposansm12", ROREG_PTR((void*)u8g2_font_opposansm12)},
    { "font_opposansm16", ROREG_PTR((void*)u8g2_font_opposansm16)},
    { "font_opposansm18", ROREG_PTR((void*)u8g2_font_opposansm18)},
    { "font_opposansm20", ROREG_PTR((void*)u8g2_font_opposansm20)},
    { "font_opposansm22", ROREG_PTR((void*)u8g2_font_opposansm22)},
    { "font_opposansm24", ROREG_PTR((void*)u8g2_font_opposansm24)},
    { "font_opposansm32", ROREG_PTR((void*)u8g2_font_opposansm32)},
#endif
#ifdef USE_U8G2_OPPOSANSM8_CHINESE
    //@const font_opposansm8_chinese font 8号中文字体
    { "font_opposansm8_chinese", ROREG_PTR((void*)u8g2_font_opposansm8_chinese)},
#endif
#ifdef USE_U8G2_OPPOSANSM10_CHINESE
    //@const font_opposansm8_chinese font 10号中文字体
    { "font_opposansm10_chinese", ROREG_PTR((void*)u8g2_font_opposansm10_chinese)},
#endif
#ifdef USE_U8G2_OPPOSANSM12_CHINESE
    //@const font_opposansm12_chinese font 12号中文字体
    { "font_opposansm12_chinese", ROREG_PTR((void*)u8g2_font_opposansm12_chinese)},
#endif
#ifdef USE_U8G2_OPPOSANSM16_CHINESE
    //@const font_opposansm16_chinese font 16号中文字体
    { "font_opposansm16_chinese", ROREG_PTR((void*)u8g2_font_opposansm16_chinese)},
#endif
#ifdef USE_U8G2_OPPOSANSM18_CHINESE
    //@const font_opposansm18_chinese font 18号中文字体
    { "font_opposansm18_chinese", ROREG_PTR((void*)u8g2_font_opposansm18_chinese)},
#endif
#ifdef USE_U8G2_OPPOSANSM20_CHINESE
    //@const font_opposansm20_chinese font 20号中文字体
    { "font_opposansm20_chinese", ROREG_PTR((void*)u8g2_font_opposansm20_chinese)},
#endif
#ifdef USE_U8G2_OPPOSANSM22_CHINESE
    //@const font_opposansm22_chinese font 22号中文字体
    { "font_opposansm22_chinese", ROREG_PTR((void*)u8g2_font_opposansm22_chinese)},
#endif
#ifdef USE_U8G2_OPPOSANSM24_CHINESE
    //@const font_opposansm24_chinese font 24号中文字体
    { "font_opposansm24_chinese", ROREG_PTR((void*)u8g2_font_opposansm24_chinese)},
#endif
#ifdef USE_U8G2_OPPOSANSM32_CHINESE
    //@const font_opposansm32_chinese font 32号中文字体
    { "font_opposansm32_chinese", ROREG_PTR((void*)u8g2_font_opposansm32_chinese)},
#endif

#ifdef USE_U8G2_SARASA_ENGLISH
    { "font_sarasa_m8_ascii", ROREG_PTR((void*)u8g2_font_sarasa_m8_ascii)},
    { "font_sarasa_m10_ascii", ROREG_PTR((void*)u8g2_font_sarasa_m10_ascii)},
    { "font_sarasa_m12_ascii", ROREG_PTR((void*)u8g2_font_sarasa_m12_ascii)},
    { "font_sarasa_m14_ascii", ROREG_PTR((void*)u8g2_font_sarasa_m14_ascii)},
    { "font_sarasa_m16_ascii", ROREG_PTR((void*)u8g2_font_sarasa_m16_ascii)},
    { "font_sarasa_m18_ascii", ROREG_PTR((void*)u8g2_font_sarasa_m18_ascii)},
    { "font_sarasa_m20_ascii", ROREG_PTR((void*)u8g2_font_sarasa_m20_ascii)},
    { "font_sarasa_m22_ascii", ROREG_PTR((void*)u8g2_font_sarasa_m22_ascii)},
    //再大的很少用到先不加了
#endif

#ifdef USE_U8G2_SARASA_M8_CHINESE
    { "font_sarasa_m8_chinese", ROREG_PTR((void*)u8g2_font_sarasa_m8_chinese)},
#endif
#ifdef USE_U8G2_SARASA_M10_CHINESE
    { "font_sarasa_m10_chinese", ROREG_PTR((void*)u8g2_font_sarasa_m10_chinese)},
#endif
#ifdef USE_U8G2_SARASA_M12_CHINESE
    { "font_sarasa_m12_chinese", ROREG_PTR((void*)u8g2_font_sarasa_m12_chinese)},
#endif
#ifdef USE_U8G2_SARASA_M14_CHINESE
    { "font_sarasa_m14_chinese", ROREG_PTR((void*)u8g2_font_sarasa_m14_chinese)},
#endif
#ifdef USE_U8G2_SARASA_M16_CHINESE
    { "font_sarasa_m16_chinese", ROREG_PTR((void*)u8g2_font_sarasa_m16_chinese)},
#endif
#ifdef USE_U8G2_SARASA_M18_CHINESE
    { "font_sarasa_m18_chinese", ROREG_PTR((void*)u8g2_font_sarasa_m18_chinese)},
#endif
#ifdef USE_U8G2_SARASA_M20_CHINESE
    { "font_sarasa_m20_chinese", ROREG_PTR((void*)u8g2_font_sarasa_m20_chinese)},
#endif
#ifdef USE_U8G2_SARASA_M22_CHINESE
    { "font_sarasa_m22_chinese", ROREG_PTR((void*)u8g2_font_sarasa_m22_chinese)},
#endif
#ifdef USE_U8G2_SARASA_M24_CHINESE
    { "font_sarasa_m24_chinese", ROREG_PTR((void*)u8g2_font_sarasa_m24_chinese)},
#endif
#ifdef USE_U8G2_SARASA_M26_CHINESE
    { "font_sarasa_m26_chinese", ROREG_PTR((void*)u8g2_font_sarasa_m26_chinese)},
#endif
#ifdef USE_U8G2_SARASA_M28_CHINESE
    { "font_sarasa_m28_chinese", ROREG_PTR((void*)u8g2_font_sarasa_m28_chinese)},
#endif

    { NULL,                    ROREG_INT(0)}
};

LUAMOD_API int luaopen_eink( lua_State *L ){
    luat_newlib2(L, reg_eink);
    return 1;
}
