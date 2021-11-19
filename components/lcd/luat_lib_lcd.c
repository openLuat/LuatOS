
/*
@module  lcd
@summary lcd驱动模块
@version 1.0
@date    2021.06.16
*/
#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_malloc.h"
#include "luat_zbuff.h"
#include "luat_spi.h"

#define LUAT_LOG_TAG "lcd"
#include "luat_log.h"

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

extern uint32_t BACK_COLOR , FORE_COLOR ;

extern const luat_lcd_opts_t lcd_opts_st7735;
extern const luat_lcd_opts_t lcd_opts_st7735s;
extern const luat_lcd_opts_t lcd_opts_st7789;
extern const luat_lcd_opts_t lcd_opts_gc9a01;
extern const luat_lcd_opts_t lcd_opts_gc9106l;
extern const luat_lcd_opts_t lcd_opts_gc9306;
extern const luat_lcd_opts_t lcd_opts_ili9341;
extern const luat_lcd_opts_t lcd_opts_ili9488;
extern const luat_lcd_opts_t lcd_opts_custom;

static luat_lcd_conf_t *default_conf = NULL;

static uint32_t lcd_str_fg_color,lcd_str_bg_color;
/*
lcd显示屏初始化
@api lcd.init(tp, args)
@string lcd类型, 当前支持st7789/st7735/st7735s/gc9a01/gc9106l/gc9306/ili9341/custom
@table 附加参数,与具体设备有关,pin_pwr为可选项,可不设置port:spi端口,例如0,1,2...如果为device方式则为"device";pin_dc:lcd数据/命令选择引脚;pin_rst:lcd复位引脚;pin_pwr:lcd背光引脚 可选项,可不设置;direction:lcd屏幕方向 0:0° 1:180° 2:270° 3:90°;w:lcd 水平分辨率;h:lcd 竖直分辨率;xoffset:x偏移(不同屏幕ic 不同屏幕方向会有差异);yoffset:y偏移(不同屏幕ic 不同屏幕方向会有差异)
@userdata spi设备,当port = "device"时有效
@usage
-- 初始化spi0的st7789 注意:lcd初始化之前需要先初始化spi
local spi_lcd = spi.deviceSetup(0,20,0,0,8,2000000,spi.MSB,1,1)
log.info("lcd.init",
lcd.init("st7735s",{port = "device",pin_dc = 17, pin_pwr = 7,pin_rst = 19,direction = 2,w = 160,h = 80,xoffset = 1,yoffset = 26},spi_lcd))
*/
static int l_lcd_init(lua_State* L) {
    size_t len = 0;
    luat_lcd_conf_t *conf = luat_heap_malloc(sizeof(luat_lcd_conf_t));
    memset(conf, 0, sizeof(luat_lcd_conf_t)); // 填充0,保证无脏数据
    conf->pin_pwr = 255;
    if (lua_type(L, 3) == LUA_TUSERDATA){
        conf->userdata = (luat_spi_device_t*)lua_touserdata(L, 3);
        conf->port = LUAT_LCD_SPI_DEVICE;
    }
    const char* tp = luaL_checklstring(L, 1, &len);
    if (!strcmp("st7735", tp) || !strcmp("st7789", tp) || !strcmp("st7735s", tp)
            || !strcmp("gc9a01", tp)  || !strcmp("gc9106l", tp)
            || !strcmp("gc9306", tp)  || !strcmp("ili9341", tp)  || !strcmp("ili9488", tp)
            || !strcmp("custom", tp)) {
              LLOGD("ic support: %s",tp);
        if (lua_gettop(L) > 1) {
            lua_settop(L, 2); // 丢弃多余的参数

            lua_pushstring(L, "port");
            int port = lua_gettable(L, 2);
            if (conf->port == LUAT_LCD_SPI_DEVICE && port ==LUA_TNUMBER) {
              LLOGE("port is not device but find luat_spi_device_t");
              goto end;
            }else if (conf->port != LUAT_LCD_SPI_DEVICE && LUA_TSTRING == port){
              LLOGE("port is device but not find luat_spi_device_t");
              goto end;
            }else if (LUA_TNUMBER == port) {
                conf->port = luaL_checkinteger(L, -1);
            }else if (LUA_TSTRING == port){
                conf->port = LUAT_LCD_SPI_DEVICE;
            }
            lua_pop(L, 1);

            lua_pushstring(L, "pin_dc");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                conf->pin_dc = luaL_checkinteger(L, -1);
            }
            lua_pop(L, 1);

            lua_pushstring(L, "pin_pwr");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                conf->pin_pwr = luaL_checkinteger(L, -1);
            }
            lua_pop(L, 1);

            lua_pushstring(L, "pin_rst");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                conf->pin_rst = luaL_checkinteger(L, -1);
            }
            lua_pop(L, 1);

            lua_pushstring(L, "direction");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                conf->direction = luaL_checkinteger(L, -1);
            }
            lua_pop(L, 1);

            lua_pushstring(L, "w");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                conf->w = luaL_checkinteger(L, -1);
            }
            lua_pop(L, 1);

            lua_pushstring(L, "h");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                conf->h = luaL_checkinteger(L, -1);
            }
            lua_pop(L, 1);

            lua_pushstring(L, "xoffset");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                conf->xoffset = luaL_checkinteger(L, -1);
            }
            lua_pop(L, 1);

            lua_pushstring(L, "yoffset");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                conf->yoffset = luaL_checkinteger(L, -1);
            }
            lua_pop(L, 1);
        }
        if (!strcmp("st7735", tp))
            conf->opts = (luat_lcd_opts_t*)&lcd_opts_st7735;
        else if (!strcmp("st7735s", tp))
            conf->opts = (luat_lcd_opts_t*)&lcd_opts_st7735s;
        else if (!strcmp("st7789", tp))
            conf->opts = (luat_lcd_opts_t*)&lcd_opts_st7789;
        else if (!strcmp("gc9a01", tp))
            conf->opts = (luat_lcd_opts_t*)&lcd_opts_gc9a01;
        else if (!strcmp("gc9106l", tp))
            conf->opts = (luat_lcd_opts_t*)&lcd_opts_gc9106l;
        else if (!strcmp("gc9306", tp))
            conf->opts = (luat_lcd_opts_t*)&lcd_opts_gc9306;
        else if (!strcmp("ili9341", tp))
            conf->opts = (luat_lcd_opts_t*)&lcd_opts_ili9341;
        else if (!strcmp("ili9488", tp))
            conf->opts = (luat_lcd_opts_t*)&lcd_opts_ili9488;
        else if (!strcmp("custom", tp)) {
            conf->opts = (luat_lcd_opts_t*)&lcd_opts_custom;
            luat_lcd_custom_t *cst = luat_heap_malloc(sizeof(luat_lcd_custom_t));

            // 获取initcmd/sleepcmd/wakecmd
            lua_pushstring(L, "sleepcmd");
            lua_gettable(L, 2);
            cst->sleepcmd = luaL_checkinteger(L, -1);
            lua_pop(L, 1);

            lua_pushstring(L, "wakecmd");
            lua_gettable(L, 2);
            cst->wakecmd = luaL_checkinteger(L, -1);
            lua_pop(L, 1);

            lua_pushstring(L, "initcmd");
            lua_gettable(L, 2);
            cst->init_cmd_count = lua_rawlen(L, -1);
            luat_heap_realloc(cst, sizeof(luat_lcd_custom_t) + cst->init_cmd_count * 4);
            for (size_t i = 1; i <= cst->init_cmd_count; i++)
            {
                lua_geti(L, -1, i);
                cst->initcmd[i-1] = luaL_checkinteger(L, -1);
                lua_pop(L, 1);
            }
            lua_pop(L, 1);
        }
        int ret = luat_lcd_init(conf);
        lua_pushboolean(L, ret == 0 ? 1 : 0);
        if (ret == 0)
            default_conf = conf;
        u8g2_SetFontMode(&(default_conf->luat_lcd_u8g2), 0);
        u8g2_SetFontDirection(&(default_conf->luat_lcd_u8g2), 0);
        // lua_pushlightuserdata(L, conf);
        return 1;
    }
    LLOGE("ic not support: %s",tp);
end:
    lua_pushboolean(L, 0);
    luat_heap_free(conf);
    return 1;
}

/*
关闭lcd显示屏
@api lcd.close()
@usage
-- 关闭lcd
lcd.close()
*/
static int l_lcd_close(lua_State* L) {
    int ret = luat_lcd_close(default_conf);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
开启lcd显示屏背光
@api lcd.on()
@usage
-- 开启lcd显示屏背光
lcd.on()
*/
static int l_lcd_display_on(lua_State* L) {
    int ret = luat_lcd_display_on(default_conf);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
关闭lcd显示屏背光
@api lcd.off()
@usage
-- 关闭lcd显示屏背光
lcd.off()
*/
static int l_lcd_display_off(lua_State* L) {
    int ret = luat_lcd_display_off(default_conf);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
lcd睡眠
@api lcd.sleep()
@usage
-- lcd睡眠
lcd.sleep()
*/
static int l_lcd_sleep(lua_State* L) {
    int ret = luat_lcd_sleep(default_conf);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
lcd唤醒
@api lcd.wakeup()
@usage
-- lcd唤醒
lcd.wakeup()
*/
static int l_lcd_wakeup(lua_State* L) {
    int ret = luat_lcd_wakeup(default_conf);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
lcd颜色设置
@api lcd.setColor(back,fore)
@int 背景色
@int 前景色
@usage
-- lcd颜色设置
lcd.setColor(0xFFFF,0x0000)
*/
static int l_lcd_set_color(lua_State* L) {
    uint32_t back,fore;
    back = (uint32_t)luaL_checkinteger(L, 1);
    fore = (uint32_t)luaL_checkinteger(L, 2);
    int ret = luat_lcd_set_color(back, fore);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
lcd颜色填充
@api lcd.draw(x1, y1, x2, y2,color)
@int 左上边缘的X位置.
@int 左上边缘的Y位置.
@int 右上边缘的X位置.
@int 右上边缘的Y位置.
@string 字符串或zbuff对象
@usage
-- lcd颜色填充
local buff = zbuff.create({201,1,16},0x001F)
lcd.draw(20,30,220,30,buff)
*/
static int l_lcd_draw(lua_State* L) {
    uint16_t x1, y1, x2, y2;
    int ret;
    // luat_color_t *color = NULL;
    luat_zbuff_t *buff;
    x1 = luaL_checkinteger(L, 1);
    y1 = luaL_checkinteger(L, 2);
    x2 = luaL_checkinteger(L, 3);
    y2 = luaL_checkinteger(L, 4);
    if (lua_isinteger(L, 5)) {
        // color = (luat_color_t *)luaL_checkstring(L, 5);
        uint32_t color = (uint32_t)luaL_checkinteger(L, 1);
        ret = luat_lcd_draw(default_conf, x1, y1, x2, y2, &color);
    }
    else if (lua_isuserdata(L, 5)) {
        buff = luaL_checkudata(L, 5, LUAT_ZBUFF_TYPE);
        luat_color_t *color = (luat_color_t *)buff->addr;
        ret = luat_lcd_draw(default_conf, x1, y1, x2, y2, color);
    }
    else if(lua_isstring(L, 5)) {
        luat_color_t *color = (luat_color_t *)luaL_checkstring(L, 5);
        ret = luat_lcd_draw(default_conf, x1, y1, x2, y2, color);
    }
    else {
        return 0;
    }
    // int ret = luat_lcd_draw(default_conf, x1, y1, x2, y2, color);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
lcd清屏
@api lcd.clear(color)
@int 屏幕颜色 可选参数,默认背景色
@usage
-- lcd清屏
lcd.clear()
*/
static int l_lcd_clear(lua_State* L) {
    //size_t len = 0;
    uint32_t color = BACK_COLOR;
    if (lua_gettop(L) > 0)
        color = (uint32_t)luaL_checkinteger(L, 1);
    int ret = luat_lcd_clear(default_conf, color);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
lcd颜色填充
@api lcd.fill(x1, y1, x2, y2,color)
@int 左上边缘的X位置.
@int 左上边缘的Y位置.
@int 右上边缘的X位置.
@int 右上边缘的Y位置.
@int 绘画颜色 可选参数,默认背景色
@usage
-- lcd颜色填充
lcd.fill(20,30,220,30,0x0000)
*/
static int l_lcd_draw_fill(lua_State* L) {
    uint16_t x1, y1, x2, y2;
    uint32_t color = BACK_COLOR;
    x1 = luaL_checkinteger(L, 1);
    y1 = luaL_checkinteger(L, 2);
    x2 = luaL_checkinteger(L, 3);
    y2 = luaL_checkinteger(L, 4);
    if (lua_gettop(L) > 4)
        color = (uint32_t)luaL_checkinteger(L, 5);
    int ret = luat_lcd_draw_fill(default_conf, x1,  y1,  x2,  y2, color);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
画一个点.
@api lcd.drawPoint(x0,y0,color)
@int 点的X位置.
@int 点的Y位置.
@int 绘画颜色 可选参数,默认前景色
@usage
lcd.drawPoint(20,30,0x001F)
*/
static int l_lcd_draw_point(lua_State* L) {
    uint16_t x, y;
    uint32_t color = FORE_COLOR;
    x = luaL_checkinteger(L, 1);
    y = luaL_checkinteger(L, 2);
    if (lua_gettop(L) > 2)
        color = (uint32_t)luaL_checkinteger(L, 3);
    int ret = luat_lcd_draw_point(default_conf, x, y, color);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
在两点之间画一条线.
@api lcd.drawLine(x0,y0,x1,y1,color)
@int 第一个点的X位置.
@int 第一个点的Y位置.
@int 第二个点的X位置.
@int 第二个点的Y位置.
@int 绘画颜色 可选参数,默认前景色
@usage
lcd.drawLine(20,30,220,30,0x001F)
*/
static int l_lcd_draw_line(lua_State* L) {
    uint16_t x1, y1, x2, y2;
    uint32_t color = FORE_COLOR;
    x1 = luaL_checkinteger(L, 1);
    y1 = luaL_checkinteger(L, 2);
    x2 = luaL_checkinteger(L, 3);
    y2 = luaL_checkinteger(L, 4);
    if (lua_gettop(L) > 4)
        color = (uint32_t)luaL_checkinteger(L, 5);
    int ret = luat_lcd_draw_line(default_conf, x1,  y1,  x2,  y2, color);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
从x / y位置（左上边缘）开始绘制一个框
@api lcd.drawRectangle(x0,y0,x1,y1,color)
@int 左上边缘的X位置.
@int 左上边缘的Y位置.
@int 右下边缘的X位置.
@int 右下边缘的Y位置.
@int 绘画颜色 可选参数,默认前景色
@usage
lcd.drawRectangle(20,40,220,80,0x001F)
*/
static int l_lcd_draw_rectangle(lua_State* L) {
    uint16_t x1, y1, x2, y2;
    uint32_t color = FORE_COLOR;
    x1 = luaL_checkinteger(L, 1);
    y1 = luaL_checkinteger(L, 2);
    x2 = luaL_checkinteger(L, 3);
    y2 = luaL_checkinteger(L, 4);
    if (lua_gettop(L) > 4)
        color = (uint32_t)luaL_checkinteger(L, 5);
    int ret = luat_lcd_draw_rectangle(default_conf, x1,  y1,  x2,  y2, color);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
从x / y位置（圆心）开始绘制一个圆
@api lcd.drawCircle(x0,y0,r,color)
@int 圆心的X位置.
@int 圆心的Y位置.
@int 半径.
@int 绘画颜色 可选参数,默认前景色
@usage
lcd.drawCircle(120,120,20,0x001F)
*/
static int l_lcd_draw_circle(lua_State* L) {
    uint16_t x0, y0, r;
    uint32_t color = FORE_COLOR;
    x0 = luaL_checkinteger(L, 1);
    y0 = luaL_checkinteger(L, 2);
    r = luaL_checkinteger(L, 3);
    if (lua_gettop(L) > 3)
        color = (uint32_t)luaL_checkinteger(L, 4);
    int ret = luat_lcd_draw_circle(default_conf, x0,  y0,  r, color);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
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

static void u8g2_draw_hv_line(u8g2_t *u8g2, int16_t x, int16_t y, int16_t len, uint8_t dir, uint16_t color){
  switch(dir)
  {
    case 0:
      luat_lcd_draw_hline(default_conf,x,y,len,color);
      break;
    case 1:
      luat_lcd_draw_vline(default_conf,x,y,len,color);
      break;
    case 2:
        luat_lcd_draw_hline(default_conf,x-len+1,y,len,color);
      break;
    case 3:
      luat_lcd_draw_vline(default_conf,x,y-len+1,len,color);
      break;
  }
}
static int16_t u8g2_add_vector_x(int16_t dx, int8_t x, int8_t y, uint8_t dir) U8X8_NOINLINE;
static int16_t u8g2_add_vector_x(int16_t dx, int8_t x, int8_t y, uint8_t dir)
{
  switch(dir)
  {
    case 0:
      dx += x;
      break;
    case 1:
      dx -= y;
      break;
    case 2:
      dx -= x;
      break;
    default:
      dx += y;
      break;
  }
  return dx;
}
static int16_t u8g2_add_vector_y(int16_t dy, int8_t x, int8_t y, uint8_t dir) U8X8_NOINLINE;
static int16_t u8g2_add_vector_y(int16_t dy, int8_t x, int8_t y, uint8_t dir)
{
  switch(dir)
  {
    case 0:
      dy += y;
      break;
    case 1:
      dy += x;
      break;
    case 2:
      dy -= y;
      break;
    default:
      dy -= x;
      break;
  }
  return dy;
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
	    u8g2_draw_hv_line(u8g2, x, y, current, decode->dir, lcd_str_fg_color);
      }
      else if ( decode->is_transparent == 0 )
      {
	    u8g2_draw_hv_line(u8g2, x, y, current, decode->dir, lcd_str_bg_color);
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

/*
设置字体
@api lcd.setFont(font)
@string font
@usage
-- 设置为中文字体,对之后的drawStr有效,使用中文字体需在luat_conf_bsp.h.h开启#define USE_U8G2_OPPOSANSM12_CHINESE
lcd.setFont(lcd.font_opposansm12)
lcd.drawStr(40,10,"drawStr")
sys.wait(2000)
lcd.setFont(lcd.font_opposansm12_chinese)
lcd.drawStr(40,40,"drawStr测试")
*/
static int l_lcd_set_font(lua_State *L) {
    int font = luaL_checkinteger(L, 1);
    switch (font)
        {
        case font_opposansm8:
            LLOGI("font_opposansm8");
            u8g2_SetFont(&(default_conf->luat_lcd_u8g2), u8g2_font_opposansm8);
            lua_pushboolean(L, 1);
            break;
        case font_opposansm10:
            LLOGI("font_opposansm10");
            u8g2_SetFont(&(default_conf->luat_lcd_u8g2), u8g2_font_opposansm10);
            lua_pushboolean(L, 1);
            break;
        case font_opposansm12:
            LLOGI("font_opposansm12");
            u8g2_SetFont(&(default_conf->luat_lcd_u8g2), u8g2_font_opposansm12);
            lua_pushboolean(L, 1);
            break;
        case font_opposansm16:
            LLOGI("font_opposansm16");
            u8g2_SetFont(&(default_conf->luat_lcd_u8g2), u8g2_font_opposansm16);
            lua_pushboolean(L, 1);
            break;
        case font_opposansm18:
            LLOGI("font_opposansm18");
            u8g2_SetFont(&(default_conf->luat_lcd_u8g2), u8g2_font_opposansm18);
            lua_pushboolean(L, 1);
            break;
        case font_opposansm20:
            LLOGI("font_opposansm20");
            u8g2_SetFont(&(default_conf->luat_lcd_u8g2), u8g2_font_opposansm20);
            lua_pushboolean(L, 1);
            break;
        case font_opposansm22:
            LLOGI("font_opposansm22");
            u8g2_SetFont(&(default_conf->luat_lcd_u8g2), u8g2_font_opposansm22);
            lua_pushboolean(L, 1);
            break;
        case font_opposansm24:
            LLOGI("font_opposansm24");
            u8g2_SetFont(&(default_conf->luat_lcd_u8g2), u8g2_font_opposansm24);
            lua_pushboolean(L, 1);
            break;
        case font_opposansm32:
            LLOGI("font_opposansm32");
            u8g2_SetFont(&(default_conf->luat_lcd_u8g2), u8g2_font_opposansm32);
            lua_pushboolean(L, 1);
            break;
#if defined USE_U8G2_OPPOSANSM12_CHINESE
        case font_opposansm12_chinese:
            LLOGI("font_opposansm12_chinese");
            u8g2_SetFont(&(default_conf->luat_lcd_u8g2), u8g2_font_opposansm12_chinese);
            lua_pushboolean(L, 1);
            break;
#endif
#if defined USE_U8G2_OPPOSANSM16_CHINESE
        case font_opposansm16_chinese:
            LLOGI("font_opposansm16_chinese");
            u8g2_SetFont(&(default_conf->luat_lcd_u8g2), u8g2_font_opposansm16_chinese);
            lua_pushboolean(L, 1);
            break;
#endif
#if defined USE_U8G2_OPPOSANSM24_CHINESE
        case font_opposansm24_chinese:
            LLOGI("font_opposansm24_chinese");
            u8g2_SetFont(&(default_conf->luat_lcd_u8g2), u8g2_font_opposansm24_chinese);
            lua_pushboolean(L, 1);
            break;
#endif
#if defined USE_U8G2_OPPOSANSM32_CHINESE
        case font_opposansm32_chinese:
            LLOGI("font_opposansm32_chinese");
            u8g2_SetFont(&(default_conf->luat_lcd_u8g2), u8g2_font_opposansm32_chinese);
            lua_pushboolean(L, 1);
            break;
#endif
        default:
            lua_pushboolean(L, 0);
            LLOGI("no font");
            break;
        }
    return 1;
}

/*
显示字符串
@api lcd.drawStr(x,y,str,fg_color,bg_color)
@int x 横坐标
@int y 竖坐标
@string str 文件内容
@int fg_color str颜色
@int bg_color str背景颜色
@usage
-- 显示之前先设置为中文字体,对之后的drawStr有效,使用中文字体需在luat_conf_bsp.h.h开启#define USE_U8G2_WQY16_T_GB2312
lcd.setFont(lcd.font_opposansm12)
lcd.drawStr(40,10,"drawStr")
sys.wait(2000)
lcd.setFont(lcd.font_opposansm16_chinese)
lcd.drawStr(40,40,"drawStr测试")
*/
static int l_lcd_draw_str(lua_State* L) {
    int x, y;
    int sz;
    const uint8_t* data;
    uint32_t color = FORE_COLOR;
    x = luaL_checkinteger(L, 1);
    y = luaL_checkinteger(L, 2);
    data = (const uint8_t*)luaL_checklstring(L, 3, &sz);
    lcd_str_fg_color = (uint32_t)luaL_optinteger(L, 4,FORE_COLOR);
    lcd_str_bg_color = (uint32_t)luaL_optinteger(L, 5,BACK_COLOR);
    if (sz == 0)
        return 0;
    uint16_t e;
    int16_t delta, sum;
    utf8_state = 0;
    sum = 0;
    for(;;){
        e = utf8_next((uint8_t)*data);
        if ( e == 0x0ffff )
        break;
        data++;
        if ( e != 0x0fffe ){
        delta = u8g2_font_draw_glyph(&(default_conf->luat_lcd_u8g2), x, y, e);
        switch(default_conf->luat_lcd_u8g2.font_decode.dir){
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

#ifdef LUAT_USE_GTFONT

#include "GT5SLCD2E_1A.h"
extern void gtfont_draw_w(unsigned char *pBits,unsigned int x,unsigned int y,unsigned int widt,unsigned int high,int(*point)(void*),void* userdata,int mode);
extern void gtfont_draw_gray_hz(unsigned char *data,unsigned short x,unsigned short y,unsigned short w ,unsigned short h,unsigned char grade, unsigned char HB_par,int(*point)(void*,uint16_t, uint16_t, uint32_t),void* userdata,int mode);

/*
使用gtfont显示gb2312字符串
@api lcd.drawGtfontGb2312(str,size,x,y)
@string str 显示字符串
@int size 字体大小 (支持16-192号大小字体)
@int x 横坐标
@int y 竖坐标
@usage
lcd.drawGtfontGb2312("啊啊啊",32,0,0)
*/
static int l_lcd_draw_gtfont_gb2312(lua_State *L) {
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
		gtfont_draw_w(buf , x ,y , size , size,luat_lcd_draw_point,default_conf,0);
		x+=size;
		i+=2;
	}
    return 0;
}

/*
使用gtfont灰度显示gb2312字符串
@api lcd.drawGtfontGb2312Gray(str,size,gray,x,y)
@string str 显示字符串
@int size 字体大小 (支持16-192号大小字体)
@int gray 灰度[1阶/2阶/3阶/4阶]
@int x 横坐标
@int y 竖坐标
@usage
lcd.drawGtfontGb2312Gray("啊啊啊",32,4,0,40)
*/
static int l_lcd_draw_gtfont_gb2312_gray(lua_State* L) {
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
		gtfont_draw_gray_hz(buf, x, y, size , size, font_g, 1,luat_lcd_draw_point,default_conf,0);
		x+=size;
		i+=2;
	}
    return 0;
}

#ifdef LUAT_USE_GTFONT_UTF8
extern unsigned short unicodetogb2312 ( unsigned short	chr);

/*
使用gtfont显示UTF8字符串
@api lcd.drawGtfontUtf8(str,size,x,y)
@string str 显示字符串
@int size 字体大小 (支持16-192号大小字体)
@int x 横坐标
@int y 竖坐标
@usage
lcd.drawGtfontUtf8("啊啊啊",32,0,0)
*/
static int l_lcd_draw_gtfont_utf8(lua_State *L) {
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
        gtfont_draw_w(buf , x ,y , size , size,luat_lcd_draw_point,default_conf,0);
        x+=size;    
      }
    }
    return 0;
}

/*
使用gtfont灰度显示UTF8字符串
@api lcd.drawGtfontUtf8Gray(str,size,gray,x,y)
@string str 显示字符串
@int size 字体大小 (支持16-192号大小字体)
@int gray 灰度[1阶/2阶/3阶/4阶]
@int x 横坐标
@int y 竖坐标
@usage
lcd.drawGtfontUtf8Gray("啊啊啊",32,4,0,40)
*/
static int l_lcd_draw_gtfont_utf8_gray(lua_State* L) {
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
      gtfont_draw_gray_hz(buf, x, y, size , size, font_g, 1,luat_lcd_draw_point,default_conf,0);
        	x+=size;    
        }
    }
    return 0;
}

#endif // LUAT_USE_GTFONT_UTF8

#endif // LUAT_USE_GTFONT

static int l_lcd_set_default(lua_State *L) {
    if (lua_gettop(L) == 1) {
        default_conf = lua_touserdata(L, 1);
        lua_pushboolean(L, 1);
        return 1;
    }
    return 1;
}

static int l_lcd_get_default(lua_State *L) {
    if (default_conf == NULL)
      return 0;
    lua_pushlightuserdata(L, default_conf);
    return 1;
}

/*
获取屏幕尺寸
@api lcd.getSize()
@return int 宽, 如果未初始化会返回0
@return int 高, 如果未初始化会返回0
@usage
log.info("lcd", "size", lcd.getSize())
*/
static int l_lcd_get_size(lua_State *L) {
  if (lua_gettop(L) == 1) {
    luat_lcd_conf_t * conf = lua_touserdata(L, 1);
    if (conf) {
      lua_pushinteger(L, conf->w);
      lua_pushinteger(L, conf->h);
    }
  }
  if (default_conf == NULL) {
    lua_pushinteger(L, 0);
    lua_pushinteger(L, 0);
  }
  else {
    lua_pushinteger(L, default_conf->w);
    lua_pushinteger(L, default_conf->h);
  }
  return 2;
}

#include "rotable.h"
static const rotable_Reg reg_lcd[] =
{
    { "init",      l_lcd_init,   0},
    { "close",      l_lcd_close,       0},
    { "on",      l_lcd_display_on,       0},
    { "off",      l_lcd_display_off,       0},
    { "sleep",      l_lcd_sleep,       0},
    { "wakeup",      l_lcd_wakeup,       0},
    { "setColor",      l_lcd_set_color,       0},
    { "draw",      l_lcd_draw,       0},
    { "clear",      l_lcd_clear,       0},
    { "fill",      l_lcd_draw_fill,       0},
    { "drawPoint",      l_lcd_draw_point,       0},
    { "drawLine",      l_lcd_draw_line,       0},
    { "drawRectangle",      l_lcd_draw_rectangle,       0},
    { "drawCircle",      l_lcd_draw_circle,       0},
    { "drawStr",      l_lcd_draw_str,       0},
    { "setFont", l_lcd_set_font, 0},
    { "setDefault", l_lcd_set_default, 0},
    { "getDefault", l_lcd_get_default, 0},
    { "getSize",    l_lcd_get_size, 0},
#ifdef LUAT_USE_GTFONT
    { "drawGtfontGb2312", l_lcd_draw_gtfont_gb2312, 0},
    { "drawGtfontGb2312Gray", l_lcd_draw_gtfont_gb2312_gray, 0},
#ifdef LUAT_USE_GTFONT_UTF8
    { "drawGtfontUtf8", l_lcd_draw_gtfont_utf8, 0},
    { "drawGtfontUtf8Gray", l_lcd_draw_gtfont_utf8_gray, 0},
#endif // LUAT_USE_GTFONT_UTF8
#endif // LUAT_USE_GTFONT
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
	{ NULL,        NULL,   0}
};

LUAMOD_API int luaopen_lcd( lua_State *L ) {
    luat_newlib(L, reg_lcd);
    return 1;
}
