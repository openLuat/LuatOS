/*
@module  u8g2
@summary u8g2图形处理库
@author  Dozingfiretruck
@version 1.0
@date    2021.01.25
@demo u8g2
@tag LUAT_USE_U8G2
*/
#include "luat_base.h"
#include "luat_malloc.h"

#include "luat_u8g2.h"
#include "luat_gpio.h"
#include "luat_timer.h"
#include "luat_i2c.h"
#include "luat_spi.h"
#include "qrcodegen.h"
#include "u8g2.h"
#include "u8g2_luat_fonts.h"

#define LUAT_LOG_TAG "u8g2"
#include "luat_log.h"

static u8g2_t* u8g2 = NULL;
static int u8g2_lua_ref = 0;
uint8_t pinType = 255; // I2C_SW = 1, I2C_HW = 2, SPI_SW_3PIN = 3, SPI_SW_4PIN = 4, SPI_HW_4PIN=5, P8080 = 6
static uint8_t i2c_id;
static uint8_t i2c_speed;
static uint8_t i2c_scl;
static uint8_t i2c_sda;
// static uint8_t i2c_addr = 0x3C;
static uint8_t spi_id;
static uint8_t spi_res;
static uint8_t spi_dc;
static uint8_t spi_cs;

static uint8_t * buff_ptr = NULL;

static const char* mode_strs[] = {
    "i2c_sw",
    "i2c_hw",
    "spi_sw_3pin",
    "spi_sw_4pin",
    "spi_hw_4pin"
};

/*
u8g2显示屏初始化
@api u8g2.begin(conf)
@table conf 配置信息 ic:支持 ssd1306 ssd1309 ssd1322 sh1106 sh1107 sh1108 st7567 uc1701 ssd1306_128x32, direction:方向,可选0 90 180 270 默认0 mode:模式,可选i2c_sw:软件i2c i2c_hw:硬件i2c spi_hw_4pin:硬件spi i2c_id:硬件i2c时有效 i2c_scl=1、i2c_sda:软件i2c时有效 spi_id、spi_res、spi_dc、spi_cs:硬件spi时生效
@return int 正常初始化1,已经初始化过2,内存不够3,初始化失败返回4
@usage
-- 初始化硬件i2c的ssd1306
u8g2.begin({ic = "ssd1306",direction = 0,mode="i2c_hw",i2c_id=0}) -- direction 可选0 90 180 270
-- 初始化硬件spi的ssd1306
u8g2.begin({ic = "ssd1306",direction = 0,mode="spi_hw_4pin",spi_id=0,spi_res=pin.PB03,spi_dc=pin.PB01,spi_cs=pin.PB04}) -- direction 可选0 90 180 270
-- 初始化软件i2c的ssd1306
u8g2.begin({ic = "ssd1306",direction = 0,mode="i2c_sw", i2c_scl=1, i2c_sda=4}) -- 通过PA1 SCL / PA4 SDA模拟

*/
static int l_u8g2_begin(lua_State *L) {
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

    luat_u8g2_conf_t conf = {0};
    conf.ptr = u8g2;
    conf.direction = U8G2_R0;
    char mode[12] = {0};
    size_t mode_len = 0;
    if (lua_istable(L, 1)) {
        // 参数解析
        lua_pushliteral(L, "ic");
        lua_gettable(L, 1);
        if (lua_isstring(L, -1)) {
            conf.cname = (char*)luaL_checkstring(L, -1);
            //LLOGD("using ic: %s",conf.cname);
        }
        lua_pop(L, 1);

        lua_pushliteral(L, "direction");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            int direction = luaL_checkinteger(L, -1);
            switch (direction)
            {
            case 0:
                conf.direction = U8G2_R0;
                break;
            case 90:
                conf.direction = U8G2_R1;
                break;
            case 180:
                conf.direction = U8G2_R2;
                break;
            case 270:
                conf.direction = U8G2_R3;
                break;
            
            default:
                conf.direction = U8G2_R0;
                break;
            }
        }
        lua_pop(L, 1);

        lua_pushliteral(L, "mode");
        lua_gettable(L, 1);
        if (!lua_isstring(L, -1)) {
            LLOGE("need mode!!!");
            return 0;
        }
        const char* tmp = luaL_checklstring(L, -1, &mode_len);
        if (mode_len < 1 || mode_len > 16) {
            LLOGE("mode string too short or too long!!");
            return 0;
        }
        memcpy(mode, tmp, strlen(tmp));
        lua_pop(L, 1);
        for (size_t i = 0; i < sizeof(mode_strs) / sizeof(const char*); i++)
        {
            if (strcmp(mode_strs[i], tmp) == 0) {
                pinType = i + 1;
                break;
            }
        }
        if (pinType == 255) {
            LLOGE("no such mode [%s]", tmp);
            return 0;
        }

        lua_pushliteral(L, "i2c_scl");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            i2c_scl = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);

        lua_pushliteral(L, "i2c_sda");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            i2c_sda = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);

        lua_pushliteral(L, "i2c_id");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            i2c_id = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);

        lua_pushliteral(L, "i2c_speed");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            i2c_speed = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);

        lua_pushliteral(L, "spi_id");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            spi_id = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);

        lua_pushliteral(L, "spi_res");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            spi_res = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);

        lua_pushliteral(L, "spi_dc");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            spi_dc = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);

        lua_pushliteral(L, "spi_cs");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            spi_cs = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);

    }
    LLOGD("driver %s mode %s", conf.cname, mode);
    if (luat_u8g2_setup(&conf)) {
        u8g2 = NULL;
        LLOGW("disp init fail");
        lua_pushinteger(L, 4);
        return 1; // 初始化失败
    }
    LLOGD("setup done");
    u8g2_lua_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    u8g2_SetFont(u8g2, u8g2_font_ncenB08_tr); // 设置默认字体
    lua_pushinteger(L, 1);
    return 1;
}

/*
关闭显示屏
@api u8g2.close()
@usage
-- 关闭disp,再次使用disp相关API的话,需要重新初始化
u8g2.close()
*/
static int l_u8g2_close(lua_State *L) {
    if (u8g2_lua_ref != 0) {
        lua_geti(L, LUA_REGISTRYINDEX, u8g2_lua_ref);
        if (lua_isuserdata(L, -1)) {
            luaL_unref(L, LUA_REGISTRYINDEX, u8g2_lua_ref);
        }
        u8g2_lua_ref = 0;
    }
    // buff也得释放掉
    if (buff_ptr != NULL) {
        luat_heap_free(buff_ptr);
        buff_ptr = NULL;
    }
    lua_gc(L, LUA_GCCOLLECT, 0);
    lua_gc(L, LUA_GCCOLLECT, 0);
    u8g2 = NULL;
    return 0;
}

/*
清屏，清除内存帧缓冲区中的所有像素
@api u8g2.ClearBuffer()
@usage
-- 清屏
u8g2.ClearBuffer()
*/
static int l_u8g2_ClearBuffer(lua_State *L) {
    if (u8g2 == NULL) return 0;
    u8g2_ClearBuffer(u8g2);
    return 0;
}

/*
将数据更新到屏幕，将存储器帧缓冲区的内容发送到显示器
@api u8g2.SendBuffer()
@usage
-- 把显示数据更新到屏幕
u8g2.SendBuffer()
*/
static int l_u8g2_SendBuffer(lua_State *L) {
    if (u8g2 == NULL) return 0;
    u8g2_SendBuffer(u8g2);
    return 0;
}

/*
在显示屏上画一段文字，在显示屏上画一段文字,要调用u8g2.SendBuffer()才会更新到屏幕
@api u8g2.DrawUTF8(str, x, y)
@string 文件内容
@int 横坐标
@int 竖坐标
@usage
u8g2.DrawUTF8("wifi is ready", 10, 20)
*/
static int l_u8g2_DrawUTF8(lua_State *L) {
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
设置字体模式
@api u8g2.SetFontMode(mode)
@int mode字体模式，启用（1）或禁用（0）透明模式
@usage
u8g2.SetFontMode(1)
*/
static int l_u8g2_SetFontMode(lua_State *L){
    if (u8g2 == NULL) return 0;
    int font_mode = luaL_checkinteger(L, 1);
    if (font_mode < 0) {
        lua_pushboolean(L, 0);
    }
    u8g2_SetFontMode(u8g2, font_mode);
    u8g2_SetFontDirection(u8g2, 0);
    lua_pushboolean(L, 1);
    return 1;
}

/*
设置字体
@api u8g2.SetFont(font)
@userdata font, u8g2.font_opposansm8 为纯英文8号字体,还有font_opposansm10 font_opposansm12 font_opposansm16 font_opposansm18 font_opposansm20 font_opposansm22 font_opposansm24 font_opposansm32 可选 u8g2.font_opposansm12_chinese 为12x12全中文,还有 font_opposansm16_chinese font_opposansm24_chinese font_opposansm32_chinese 可选, u8g2.font_unifont_t_symbols 为符号.
@usage
-- 设置为中文字体,对之后的drawStr有效
u8g2.SetFont(u8g2.font_opposansm12)
*/
static int l_u8g2_SetFont(lua_State *L) {
    if (u8g2 == NULL) {
        LLOGI("u8g2 not init yet!!!");
        lua_pushboolean(L, 0);
        return 1;
    }
    if (!lua_islightuserdata(L, 1)) {
        LLOGE("no such font");
        return 0;
    }
    const uint8_t *ptr = (const uint8_t *)lua_touserdata(L, 1);
    if (ptr == NULL) {
        LLOGE("only font pointer is allow");
        return 0;
    }
    u8g2_SetFont(u8g2, ptr);
    lua_pushboolean(L, 1);
    return 1;
}

/*
获取显示屏高度
@api u8g2.GetDisplayHeight()
@return int 显示屏高度
@usage
u8g2.GetDisplayHeight()
*/
static int l_u8g2_GetDisplayHeight(lua_State *L){
    if (u8g2 == NULL) return 0;
    lua_pushinteger(L, u8g2_GetDisplayHeight(u8g2));
    return 1;
}

/*
获取显示屏宽度
@api u8g2.GetDisplayWidth()
@return int 显示屏宽度
@usage
u8g2.GetDisplayWidth()
*/
static int l_u8g2_GetDisplayWidth(lua_State *L){
    if (u8g2 == NULL) return 0;
    lua_pushinteger(L, u8g2_GetDisplayWidth(u8g2));
    return 1;
}

/*
为所有绘图功能分配绘图颜色。
@api u8g2.SetDrawColor(c)
@int c为颜色值 0没有色 1有色 2与底色xor
@usage
u8g2.SetDrawColor(0)
*/
static int l_u8g2_SetDrawColor(lua_State *L){
    if (u8g2 == NULL) return 0;
    u8g2_SetDrawColor(u8g2,luaL_checkinteger(L, 1));
    return 0;
}


/*
画一个点.
@api u8g2.DrawPixel(x,y)
@int X位置.
@int Y位置.
@usage
u8g2.DrawPixel(20, 5)
*/
static int l_u8g2_DrawPixel(lua_State *L){
    if (u8g2 == NULL) return 0;
    u8g2_DrawPixel(u8g2,luaL_checkinteger(L, 1),luaL_checkinteger(L, 2));
    return 0;
}

/*
在两点之间画一条线.
@api u8g2.DrawLine(x0,y0,x1,y1)
@int 第一个点的X位置.
@int 第一个点的Y位置.
@int 第二个点的X位置.
@int 第二个点的Y位置.
@usage
u8g2.DrawLine(20, 5, 5, 32)
*/
static int l_u8g2_DrawLine(lua_State *L){
    if (u8g2 == NULL) return 0;
    u8g2_DrawLine(u8g2,luaL_checkinteger(L, 1),luaL_checkinteger(L, 2),luaL_checkinteger(L, 3),luaL_checkinteger(L, 4));
    return 0;
}

/*
在x,y位置画一个半径为rad的空心圆.
@api u8g2.DrawCircle(x0,y0,rad,opt)
@int 圆心位置
@int 圆心位置
@int 圆半径.
@int 选择圆的部分或全部. 默认全画 可选 u8g2.DRAW_UPPER_RIGHT  u8g2.DRAW_UPPER_LEFT  u8g2.DRAW_LOWER_LEFT  u8g2.DRAW_LOWER_RIGHT  u8g2.DRAW_ALL
@usage
u8g2.DrawCircle(60,30,8,u8g2.DRAW_ALL)
*/
static int l_u8g2_DrawCircle(lua_State *L){
    if (u8g2 == NULL) return 0;
    u8g2_DrawCircle(u8g2,luaL_checkinteger(L, 1),luaL_checkinteger(L, 2),luaL_checkinteger(L, 3),luaL_optinteger(L, 4,U8G2_DRAW_ALL));
    return 0;
}

/*
在x,y位置画一个半径为rad的实心圆.
@api u8g2.DrawDisc(x0,y0,rad,opt)
@int 圆心位置
@int 圆心位置
@int 圆半径.
@int 选择圆的部分或全部. 默认全画 可选 u8g2.DRAW_UPPER_RIGHT  u8g2.DRAW_UPPER_LEFT  u8g2.DRAW_LOWER_LEFT  u8g2.DRAW_LOWER_RIGHT  u8g2.DRAW_ALL
@usage
u8g2.DrawDisc(60,30,8,u8g2.DRAW_ALL)
*/
static int l_u8g2_DrawDisc(lua_State *L){
    if (u8g2 == NULL) return 0;
    u8g2_DrawDisc(u8g2,luaL_checkinteger(L, 1),luaL_checkinteger(L, 2),luaL_checkinteger(L, 3),luaL_optinteger(L, 4,U8G2_DRAW_ALL));
    return 0;
}

/*
在x,y位置画一个半径为rad的空心椭圆.
@api u8g2.DrawEllipse(x0,y0,rx,ry,opt)
@int 圆心位置
@int 圆心位置
@int 椭圆大小
@int 椭圆大小
@int 选择圆的部分或全部. 默认全画 可选 u8g2.DRAW_UPPER_RIGHT  u8g2.DRAW_UPPER_LEFT  u8g2.DRAW_LOWER_LEFT  u8g2.DRAW_LOWER_RIGHT  u8g2.DRAW_ALL
@usage
u8g2.DrawEllipse(60,30,8,u8g2.DRAW_ALL)
*/
static int l_u8g2_DrawEllipse(lua_State *L){
    if (u8g2 == NULL) return 0;
    u8g2_DrawEllipse(u8g2,luaL_checkinteger(L, 1),luaL_checkinteger(L, 2),luaL_checkinteger(L, 3),luaL_checkinteger(L, 4),luaL_optinteger(L, 5,U8G2_DRAW_ALL));
    return 0;
}

/*
在x,y位置画一个半径为rad的实心椭圆.
@api u8g2.DrawFilledEllipse(x0,y0,rx,ry,opt)
@int 圆心位置
@int 圆心位置
@int 椭圆大小
@int 椭圆大小
@int 选择圆的部分或全部. 默认全画 可选 u8g2.DRAW_UPPER_RIGHT  u8g2.DRAW_UPPER_LEFT  u8g2.DRAW_LOWER_LEFT  u8g2.DRAW_LOWER_RIGHT  u8g2.DRAW_ALL
@usage
u8g2.DrawFilledEllipse(60,30,8,15)
*/
static int l_u8g2_DrawFilledEllipse(lua_State *L){
    if (u8g2 == NULL) return 0;
    u8g2_DrawFilledEllipse(u8g2,luaL_checkinteger(L, 1),luaL_checkinteger(L, 2),luaL_checkinteger(L, 3),luaL_checkinteger(L, 4),luaL_optinteger(L, 5,U8G2_DRAW_ALL));
    return 0;
}

/*
从x / y位置（左上边缘）开始绘制一个框（填充的框）.
@api u8g2.DrawBox(x,y,w,h)
@int 左上边缘的X位置
@int 左上边缘的Y位置
@int 盒子的宽度
@int 盒子的高度
@usage
u8g2.DrawBox(3,7,25,15)
*/
static int l_u8g2_DrawBox(lua_State *L){
    if (u8g2 == NULL) return 0;
    u8g2_DrawBox(u8g2,luaL_checkinteger(L, 1),luaL_checkinteger(L, 2),luaL_checkinteger(L, 3),luaL_checkinteger(L, 4));
    return 0;
}

/*
从x / y位置（左上边缘）开始绘制一个框（空框）.
@api u8g2.DrawFrame(x,y,w,h)
@int 左上边缘的X位置
@int 左上边缘的Y位置
@int 盒子的宽度
@int 盒子的高度
@usage
u8g2.DrawFrame(3,7,25,15)
*/
static int l_u8g2_DrawFrame(lua_State *L){
    if (u8g2 == NULL) return 0;
    u8g2_DrawFrame(u8g2,luaL_checkinteger(L, 1),luaL_checkinteger(L, 2),luaL_checkinteger(L, 3),luaL_checkinteger(L, 4));
    return 0;
}

/*
绘制一个从x / y位置（左上边缘）开始具有圆形边缘的填充框/框架.
@api u8g2.DrawRBox(x,y,w,h,r)
@int 左上边缘的X位置
@int 左上边缘的Y位置
@int 盒子的宽度
@int 盒子的高度
@int 四个边缘的半径
@usage
u8g2.DrawRBox(3,7,25,15)
*/
static int l_u8g2_DrawRBox(lua_State *L){
    if (u8g2 == NULL) return 0;
    u8g2_DrawRBox(u8g2,luaL_checkinteger(L, 1),luaL_checkinteger(L, 2),luaL_checkinteger(L, 3),luaL_checkinteger(L, 4),luaL_checkinteger(L, 5));
    return 0;
}

/*
绘制一个从x / y位置（左上边缘）开始具有圆形边缘的空框/框架.
@api u8g2.DrawRFrame(x,y,w,h,r)
@int 左上边缘的X位置
@int 左上边缘的Y位置
@int 盒子的宽度
@int 盒子的高度
@int 四个边缘的半径
@usage
u8g2.DrawRFrame(3,7,25,15)
*/
static int l_u8g2_DrawRFrame(lua_State *L){
    if (u8g2 == NULL) return 0;
    u8g2_DrawRFrame(u8g2,luaL_checkinteger(L, 1),luaL_checkinteger(L, 2),luaL_checkinteger(L, 3),luaL_checkinteger(L, 4),luaL_checkinteger(L, 5));
    return 0;
}

/*
绘制一个图形字符。字符放置在指定的像素位置x和y.
@api u8g2.DrawGlyph(x,y,encoding)
@int 字符在显示屏上的位置
@int 字符在显示屏上的位置
@int 字符的Unicode值
@usage
u8g2.SetFont(u8g2_font_unifont_t_symbols)
u8g2.DrawGlyph(5, 20, 0x2603)	-- dec 9731/hex 2603 Snowman
*/
static int l_u8g2_DrawGlyph(lua_State *L){
    if (u8g2 == NULL) return 0;
    u8g2_DrawGlyph(u8g2,luaL_checkinteger(L, 1),luaL_checkinteger(L, 2),luaL_checkinteger(L, 3));
    return 0;
}

/*
绘制一个三角形（实心多边形）.
@api u8g2.DrawTriangle(x0,y0,x1,y1,x2,y2)
@int 点0X位置
@int 点0Y位置
@int 点1X位置
@int 点1Y位置
@int 点2X位置
@int 点2Y位置
@usage
u8g2.DrawTriangle(20,5, 27,50, 5,32)
*/
static int l_u8g2_DrawTriangle(lua_State *L){
    if (u8g2 == NULL) return 0;
    u8g2_DrawTriangle(u8g2,luaL_checkinteger(L, 1),luaL_checkinteger(L, 2),luaL_checkinteger(L, 3),luaL_checkinteger(L, 4),luaL_checkinteger(L, 5),luaL_checkinteger(L, 6));
    return 0;
}

/*
定义位图函数是否将写入背景色
@api u8g2.SetBitmapMode(mode)
@int mode字体模式，启用（1）或禁用（0）透明模式
@usage
u8g2.SetBitmapMode(1)
*/
static int l_u8g2_SetBitmapMode(lua_State *L){
    if (u8g2 == NULL) return 0;
    u8g2_SetBitmapMode(u8g2,luaL_checkinteger(L, 1));
    return 0;
}

/*
绘制位图
@api u8g2.DrawXBM(x, y, w, h, data)
@int X坐标
@int y坐标
@int 位图宽
@int 位图高
@int 位图数据,每一位代表一个像素
@usage
-- 取模使用PCtoLCD2002软件即可
-- 在(0,0)为左上角,绘制 16x16 "今" 的位图
u8g2.DrawXBM(0, 0, 16,16, string.char(
    0x80,0x00,0x80,0x00,0x40,0x01,0x20,0x02,0x10,0x04,0x48,0x08,0x84,0x10,0x83,0x60,
    0x00,0x00,0xF8,0x0F,0x00,0x08,0x00,0x04,0x00,0x04,0x00,0x02,0x00,0x01,0x80,0x00
))
*/
static int l_u8g2_DrawXBM(lua_State *L){
    if (u8g2 == NULL) return 0;
    int x = luaL_checkinteger(L, 1);
    int y = luaL_checkinteger(L, 2);
    int w = luaL_checkinteger(L, 3);
    int h = luaL_checkinteger(L, 4);
    size_t len = 0;
    const char* data = luaL_checklstring(L, 5, &len);
    if (h < 1) return 0; // 行数必须大于0
    if (len*8/h < w) return 0; // 起码要填满一行
    if (len != h*w/8)return 0;
    u8g2_DrawXBM(u8g2, x, y, w, h, (const uint8_t*)data);
    lua_pushboolean(L, 1);
    return 1;
}

/**
缓冲区绘制QRCode
@api u8g2.DrawDrcode(x, y, str, size)
@int x坐标
@int y坐标
@string 二维码的内容
@int 显示大小 (注意:二维码生成大小与要显示内容和纠错等级有关,生成版本为1-40(对应 21x21 - 177x177)的不定大小,如果和设置大小不同会自动在指定的区域中间显示二维码,如二维码未显示请查看日志提示)
@return nil 无返回值
*/
static int l_u8g2_DrawDrcode(lua_State *L)
{
    size_t len;
    int x           = luaL_checkinteger(L, 1);
    int y           = luaL_checkinteger(L, 2);
    const char* text = luaL_checklstring(L, 3, &len);
    int size        = luaL_checkinteger(L, 4);
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
                if (qrcodegen_getModule(qrcode, i, j))
                    u8g2_DrawBox(u8g2,x+i*scale,y+j*scale,scale,scale);
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

#ifdef LUAT_USE_GTFONT

#include "GT5SLCD2E_1A.h"
extern void gtfont_draw_w(unsigned char *pBits,unsigned int x,unsigned int y,unsigned int widt,unsigned int high,int(*point)(void*),void* userdata,int mode);
extern void gtfont_draw_gray_hz(unsigned char *data,unsigned short x,unsigned short y,unsigned short w ,unsigned short h,unsigned char grade, unsigned char HB_par,int(*point)(void*,uint16_t, uint16_t, uint32_t),void* userdata,int mode);

static int gtfont_u8g2_DrawPixel(u8g2_t *u8g2, uint16_t x, uint16_t y,uint32_t color){
    u8g2_DrawPixel(u8g2,x, y);
    return 1;
}


/*
使用gtfont显示gb2312字符串
@api u8g2.drawGtfontGb2312(str,size,x,y)
@string str 显示字符串
@int size 字体大小 (支持16-192号大小字体)
@int x 横坐标
@int y 竖坐标
@usage
u8g2.drawGtfontGb2312("啊啊啊",32,0,0)
*/
static int l_u8g2_draw_gtfont_gb2312(lua_State *L) {
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
		gtfont_draw_w(buf , x ,y , size , size,gtfont_u8g2_DrawPixel,u8g2,2);
		x+=size;
		i+=2;
	}
    return 0;
}

#ifdef LUAT_USE_GTFONT_UTF8
extern unsigned short unicodetogb2312 ( unsigned short	chr);

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
/*
使用gtfont显示UTF8字符串
@api u8g2.drawGtfontUtf8(str,size,x,y)
@string str 显示字符串
@int size 字体大小 (支持16-192号大小字体)
@int x 横坐标
@int y 竖坐标
@usage
u8g2.drawGtfontUtf8("啊啊啊",32,0,0)
*/
static int l_u8g2_draw_gtfont_utf8(lua_State *L) {
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
            gtfont_draw_w(buf , x ,y , size , size,gtfont_u8g2_DrawPixel,u8g2,2);
            x+=size;
        }
    }
    return 0;
}

#endif // LUAT_USE_GTFONT_UTF8

#endif // LUAT_USE_GTFONT

#include "rotable2.h"
static const rotable_Reg_t reg_u8g2[] =
{
    { "begin",       ROREG_FUNC(l_u8g2_begin)},
    { "init",        ROREG_FUNC(l_u8g2_begin)}, // 兼容disp.init函数
    { "close",       ROREG_FUNC(l_u8g2_close)},
    { "ClearBuffer", ROREG_FUNC(l_u8g2_ClearBuffer)},
    { "SendBuffer",  ROREG_FUNC(l_u8g2_SendBuffer)},
    { "DrawUTF8",    ROREG_FUNC(l_u8g2_DrawUTF8)},
    { "SetFontMode", ROREG_FUNC(l_u8g2_SetFontMode)},
    { "SetFont",     ROREG_FUNC(l_u8g2_SetFont)},
    { "GetDisplayHeight",   ROREG_FUNC(l_u8g2_GetDisplayHeight)},
    { "GetDisplayWidth",    ROREG_FUNC(l_u8g2_GetDisplayWidth)},
    { "SetDrawColor",   ROREG_FUNC(l_u8g2_SetDrawColor)},
    { "DrawPixel",   ROREG_FUNC(l_u8g2_DrawPixel)},
    { "DrawLine",    ROREG_FUNC(l_u8g2_DrawLine)},
    { "DrawCircle",  ROREG_FUNC(l_u8g2_DrawCircle)},
    { "DrawDisc",    ROREG_FUNC(l_u8g2_DrawDisc)},
    { "DrawEllipse", ROREG_FUNC(l_u8g2_DrawEllipse)},
    { "DrawFilledEllipse",  ROREG_FUNC(l_u8g2_DrawFilledEllipse)},
    { "DrawBox",     ROREG_FUNC(l_u8g2_DrawBox)},
    { "DrawFrame",   ROREG_FUNC(l_u8g2_DrawFrame)},
    { "DrawRBox",    ROREG_FUNC(l_u8g2_DrawRBox)},
    { "DrawRFrame",  ROREG_FUNC(l_u8g2_DrawRFrame)},
    { "DrawGlyph",   ROREG_FUNC(l_u8g2_DrawGlyph)},
    { "DrawTriangle", ROREG_FUNC(l_u8g2_DrawTriangle)},
    { "SetBitmapMode",ROREG_FUNC(l_u8g2_SetBitmapMode)},
    { "DrawXBM",      ROREG_FUNC(l_u8g2_DrawXBM)},
    { "DrawDrcode",   ROREG_FUNC(l_u8g2_DrawDrcode)},
#ifdef LUAT_USE_GTFONT
    { "drawGtfontGb2312", ROREG_FUNC(l_u8g2_draw_gtfont_gb2312)},
#ifdef LUAT_USE_GTFONT_UTF8
    { "drawGtfontUtf8", ROREG_FUNC(l_u8g2_draw_gtfont_utf8)},
#endif // LUAT_USE_GTFONT_UTF8
#endif // LUAT_USE_GTFONT
    // 默认只带8号字体
    { "font_opposansm8", ROREG_PTR((void*)u8g2_font_opposansm8)},
#ifdef USE_U8G2_OPPOSANSM_ENGLISH
    { "font_unifont_t_symbols",   ROREG_PTR((void*)u8g2_font_unifont_t_symbols)},
    { "font_open_iconic_weather_6x_t", ROREG_PTR((void*)u8g2_font_open_iconic_weather_6x_t)},

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
    { "font_opposansm8_chinese", ROREG_PTR((void*)u8g2_font_opposansm8_chinese)},
#endif
#ifdef USE_U8G2_OPPOSANSM10_CHINESE
    { "font_opposansm10_chinese", ROREG_PTR((void*)u8g2_font_opposansm10_chinese)},
#endif
#ifdef USE_U8G2_OPPOSANSM12_CHINESE
    { "font_opposansm12_chinese", ROREG_PTR((void*)u8g2_font_opposansm12_chinese)},
#endif
#ifdef USE_U8G2_OPPOSANSM16_CHINESE
    { "font_opposansm16_chinese", ROREG_PTR((void*)u8g2_font_opposansm16_chinese)},
#endif
#ifdef USE_U8G2_OPPOSANSM18_CHINESE
    { "font_opposansm18_chinese", ROREG_PTR((void*)u8g2_font_opposansm18_chinese)},
#endif
#ifdef USE_U8G2_OPPOSANSM20_CHINESE
    { "font_opposansm20_chinese", ROREG_PTR((void*)u8g2_font_opposansm20_chinese)},
#endif
#ifdef USE_U8G2_OPPOSANSM22_CHINESE
    { "font_opposansm22_chinese", ROREG_PTR((void*)u8g2_font_opposansm22_chinese)},
#endif
#ifdef USE_U8G2_OPPOSANSM24_CHINESE
    { "font_opposansm24_chinese", ROREG_PTR((void*)u8g2_font_opposansm24_chinese)},
#endif
#ifdef USE_U8G2_OPPOSANSM32_CHINESE
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

    //@const DRAW_UPPER_RIGHT number 上右
    { "DRAW_UPPER_RIGHT",        ROREG_INT(U8G2_DRAW_UPPER_RIGHT)},
    //@const DRAW_UPPER_LEFT number 上左
    { "DRAW_UPPER_LEFT",        ROREG_INT(U8G2_DRAW_UPPER_LEFT)},
    //@const DRAW_LOWER_LEFT number 下左
    { "DRAW_LOWER_LEFT",        ROREG_INT(U8G2_DRAW_LOWER_LEFT)},
    //@const DRAW_LOWER_RIGHT number 下右
    { "DRAW_LOWER_RIGHT",        ROREG_INT(U8G2_DRAW_LOWER_RIGHT)},
    //@const DRAW_ALL number 全部
    { "DRAW_ALL",        ROREG_INT(U8G2_DRAW_ALL)},
	{ NULL,  ROREG_INT(0)}
};

LUAMOD_API int luaopen_u8g2( lua_State *L ) {
    lua_getglobal(L, "disp"); // disp库已经加载过u8g2库, 那就直接重用
    if (lua_isuserdata(L, -1))
        return 1;
    luat_newlib2(L, reg_u8g2);
    return 1;
}

//-------------------------------------------------------------------------------------------------

// 往下是一些U8G2方法的默认实现

uint8_t u8x8_luat_gpio_and_delay(u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr);
uint8_t u8x8_luat_byte_hw_i2c(u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr);
uint8_t u8x8_luat_byte_4wire_hw_spi(u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr);

uint8_t u8x8_luat_gpio_and_delay_default(u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr);
uint8_t u8x8_luat_byte_hw_i2c_default(u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr);
uint8_t u8x8_luat_byte_4wire_hw_spi_default(u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr);

int luat_u8g2_setup_default(luat_u8g2_conf_t *conf);

typedef void (*dev_setup_cb)(u8g2_t *u8g2, const u8g2_cb_t *rotation, u8x8_msg_cb byte_cb, u8x8_msg_cb gpio_and_delay_cb);

typedef struct luat_u8g2_dev_reg
{
    const char* name;
    dev_setup_cb devcb;
    uint16_t w; // 屏幕宽, 最大值
    uint16_t h; // 屏幕高, 最大值
    uint16_t spi_i2c; // 使用 I2C 0, 使用 SPI 1
}luat_u8g2_dev_reg_t;

static const luat_u8g2_dev_reg_t devregs[] = {
    // ssd1306是默认值
    {.name="ssd1306", .w=128, .h=64, .spi_i2c=0, .devcb=u8g2_Setup_ssd1306_i2c_128x64_noname_f},       // ssd1306 128x64,I2C
    {.name="ssd1306", .w=128, .h=64, .spi_i2c=1, .devcb=u8g2_Setup_ssd1306_128x64_noname_f},           // ssd1306 128x64,SPI
    {.name="ssd1309", .w=128, .h=64, .spi_i2c=1, .devcb=u8g2_Setup_ssd1309_128x64_noname2_f},           // ssd1309 128x64,SPI
    {.name="ssd1322", .w=256, .h=64, .spi_i2c=0, .devcb=u8g2_Setup_ssd1322_nhd_256x64_f},              // ssd1322 128x64
    {.name="sh1106",  .w=128, .h=64, .spi_i2c=0, .devcb=u8g2_Setup_sh1106_i2c_128x64_noname_f},        // sh1106 128x64,I2C
    {.name="sh1106",  .w=128, .h=64, .spi_i2c=1, .devcb=u8g2_Setup_sh1106_128x64_noname_f},        // sh1106 128x64,SPI
    {.name="sh1107",  .w=64, .h=128, .spi_i2c=0, .devcb=u8g2_Setup_ssd1306_i2c_128x64_noname_f},       // sh1107 64x128
    {.name="sh1108",  .w=160, .h=160, .spi_i2c=0, .devcb=u8g2_Setup_sh1108_i2c_160x160_f},          // sh1108 160x160
    {.name="st7567",  .w=128, .h=64, .spi_i2c=1, .devcb=u8g2_Setup_st7567_jlx12864_f},                 // st7567 128x64
    {.name="uc1701",  .w=128, .h=64, .spi_i2c=1, .devcb=u8g2_Setup_uc1701_mini12864_f},                // uc1701
    {.name="ssd1306_128x32", .w=128, .h=32, .spi_i2c=0, .devcb=u8g2_Setup_ssd1306_i2c_128x32_univision_f},       // ssd1306 128x32,I2C
    {.name="st7565", .w=132, .h=64, .spi_i2c=1, .devcb=u8g2_Setup_st7565_ea_dogm132_f},       // st7565 128x32,SPI
    {.name=NULL} // 结尾用,必须加.
};

static const luat_u8g2_dev_reg_t* search_dev_reg(luat_u8g2_conf_t *conf, uint16_t spi_i2c) {
    size_t dev_reg_index = 0;
    while (devregs[dev_reg_index].name != NULL){
        if (devregs[dev_reg_index].spi_i2c == spi_i2c && strcmp(devregs[dev_reg_index].name, conf->cname) == 0) {
            return &devregs[dev_reg_index];
        }
        dev_reg_index ++;
    }
    return &devregs[0];
}

#ifndef LUAT_COMPILER_NOWEAK
LUAT_WEAK int luat_u8g2_setup(luat_u8g2_conf_t *conf) {
    return luat_u8g2_setup_default(conf);
}
LUAT_WEAK uint8_t u8x8_luat_gpio_and_delay(u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr) {
    return u8x8_luat_gpio_and_delay_default(u8x8, msg, arg_int, arg_ptr);
}
LUAT_WEAK uint8_t u8x8_luat_byte_hw_i2c(u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr) {
    return u8x8_luat_byte_hw_i2c_default(u8x8, msg, arg_int, arg_ptr);
}
LUAT_WEAK uint8_t u8x8_luat_byte_4wire_hw_spi(u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr) {
    return u8x8_luat_byte_4wire_hw_spi_default(u8x8, msg, arg_int, arg_ptr);
}
#endif

int luat_u8g2_setup_default(luat_u8g2_conf_t *conf) {
    u8g2_t* u8g2 = (u8g2_t*)conf->ptr;
    const luat_u8g2_dev_reg_t* devreg = NULL;
    // LLOGD("conf->pinType %d", conf->pinType);
    if (pinType == 1) {
        devreg = search_dev_reg(conf, 0);
        if (devreg == NULL) {
            LLOGD("unkown dev %s", conf->cname);
            return -1;
        }
        devreg->devcb(u8g2, conf->direction, u8x8_byte_sw_i2c, u8x8_luat_gpio_and_delay_default);
        #ifdef U8G2_USE_DYNAMIC_ALLOC
        buff_ptr = (uint8_t *)luat_heap_malloc(u8g2_GetBufferSize(u8g2));
        u8g2_SetBufferPtr(u8g2, buff_ptr);
        #endif
        u8g2->u8x8.pins[U8X8_PIN_I2C_CLOCK] = i2c_scl;
        u8g2->u8x8.pins[U8X8_PIN_I2C_DATA] = i2c_sda;
        u8g2_InitDisplay(u8g2);
        u8g2_SetPowerSave(u8g2, 0);
        return 0;
    }else if (pinType == 2) {
        devreg = search_dev_reg(conf, 0);
        if (devreg == NULL) {
            LLOGD("unkown dev %s", conf->cname);
            return -1;
        }
        devreg->devcb(u8g2, conf->direction, u8x8_luat_byte_hw_i2c_default, u8x8_luat_gpio_and_delay_default);
        #ifdef U8G2_USE_DYNAMIC_ALLOC
        buff_ptr = (uint8_t *)luat_heap_malloc(u8g2_GetBufferSize(u8g2));
        u8g2_SetBufferPtr(u8g2, buff_ptr);
        #endif
        //LLOGD("setup disp i2c.hw");
        u8g2_InitDisplay(u8g2);
        u8g2_SetPowerSave(u8g2, 0);
        return 0;
    }else if (pinType == 5) {
        devreg = search_dev_reg(conf, 1);
        if (devreg == NULL) {
            LLOGD("unkown dev %s", conf->cname);
            return -1;
        }
        devreg->devcb(u8g2, conf->direction, u8x8_luat_byte_4wire_hw_spi_default, u8x8_luat_gpio_and_delay_default);
        #ifdef U8G2_USE_DYNAMIC_ALLOC
        buff_ptr = (uint8_t *)luat_heap_malloc(u8g2_GetBufferSize(u8g2));
        u8g2_SetBufferPtr(u8g2, buff_ptr);
        #endif
        LLOGD("setup disp spi.hw  spi_id=%d spi_dc=%d spi_cs=%d spi_res=%d",spi_id,spi_dc,spi_cs,spi_res);
        u8x8_SetPin(u8g2_GetU8x8(u8g2), U8X8_PIN_CS, spi_cs);
        u8x8_SetPin(u8g2_GetU8x8(u8g2), U8X8_PIN_DC, spi_dc);
        u8x8_SetPin(u8g2_GetU8x8(u8g2), U8X8_PIN_RESET, spi_res);
        u8g2_InitDisplay(u8g2);
        u8g2_SetPowerSave(u8g2, 0);
        return 0;
    }
    else {
        LLOGI("no such u8g2 mode!!");
    }
    return -1;
}

LUAT_WEAK int luat_u8g2_close(luat_u8g2_conf_t *conf) {
    return 0;
}

uint8_t u8x8_luat_byte_hw_i2c_default(u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr) {
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
      luat_i2c_setup(i2c_id,i2c_speed);
      break;
    case U8X8_MSG_BYTE_SET_DC:
      /* ignored for i2c */
      break;
    case U8X8_MSG_BYTE_START_TRANSFER:
      buf_idx = 0;
      break;
    case U8X8_MSG_BYTE_END_TRANSFER:
      luat_i2c_send(i2c_id, u8x8_GetI2CAddress(u8x8) >> 1, buffer, buf_idx,1);
      break;
    default:
      return 0;
  }
  return 1;
}

int hw_spi_begin(uint8_t spi_mode, uint32_t max_hz, uint8_t cs_pin )
{

    luat_spi_t u8g2_spi = {0};
    u8g2_spi.id = spi_id;
    switch(spi_mode)
    {
        case 0: u8g2_spi.CPHA = 0;u8g2_spi.CPOL = 0; break;
        case 1: u8g2_spi.CPHA = 1;u8g2_spi.CPOL = 0; break;
        case 2: u8g2_spi.CPHA = 0;u8g2_spi.CPOL = 1; break;
        case 3: u8g2_spi.CPHA = 1;u8g2_spi.CPOL = 1; break;
    }
    u8g2_spi.dataw = 8;
    u8g2_spi.bit_dict = 1;
    u8g2_spi.master = 1;
    u8g2_spi.mode = 0;
    u8g2_spi.bandrate = max_hz;
    u8g2_spi.cs = -1;
    LLOGI("spi_mode:%d bandrate:%d cs_pin:%d",spi_mode,max_hz,cs_pin);
    luat_spi_setup(&u8g2_spi);

    luat_gpio_mode(spi_res,Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
    luat_gpio_mode(spi_dc,Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
    return 0;
}
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
uint8_t u8x8_luat_byte_4wire_hw_spi_default(u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr) {
    switch(msg)
    {
        case U8X8_MSG_BYTE_SEND:
            luat_spi_send(spi_id, (const char*)arg_ptr, arg_int);
            break;

        case U8X8_MSG_BYTE_INIT:
            /* SPI mode has to be mapped to the mode of the current controller, at least Uno, Due, 101 have different SPI_MODEx values */
            /*   0: clock active high, data out on falling edge, clock default value is zero, takover on rising edge */
            /*   1: clock active high, data out on rising edge, clock default value is zero, takover on falling edge */
            /*   2: clock active low, data out on rising edge */
            /*   3: clock active low, data out on falling edge */
            u8x8_gpio_SetCS(u8x8, u8x8->display_info->chip_disable_level);
            hw_spi_begin(u8x8->display_info->spi_mode, u8x8->display_info->sck_clock_hz, u8x8->pins[U8X8_PIN_CS]);
            break;

        case U8X8_MSG_BYTE_SET_DC:
            u8x8_gpio_SetDC(u8x8, arg_int);
            break;

        case U8X8_MSG_BYTE_START_TRANSFER:
            u8x8_gpio_SetCS(u8x8, u8x8->display_info->chip_enable_level);
            u8x8->gpio_and_delay_cb(u8x8, U8X8_MSG_DELAY_NANO, u8x8->display_info->post_chip_enable_wait_ns, NULL);
            break;

        case U8X8_MSG_BYTE_END_TRANSFER:
            u8x8->gpio_and_delay_cb(u8x8, U8X8_MSG_DELAY_NANO, u8x8->display_info->pre_chip_disable_wait_ns, NULL);
            u8x8_gpio_SetCS(u8x8, u8x8->display_info->chip_disable_level);
            break;

        default:
            return 0;
    }
    return 1;
}

uint8_t u8x8_luat_gpio_and_delay_default(u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr)
{
    uint8_t i;
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
            if (pinType == 1){
                // set i2c pin mode
                luat_gpio_mode(u8x8->pins[U8X8_PIN_I2C_DATA],Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_HIGH);
                luat_gpio_mode(u8x8->pins[U8X8_PIN_I2C_CLOCK],Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_HIGH);
            }else if (pinType == 3){
                luat_gpio_mode(u8x8->pins[U8X8_PIN_SPI_CLOCK],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);//d0 a5 15 d1 a7 17 res b0 18 dc b1 19 cs a4 14
                luat_gpio_mode(u8x8->pins[U8X8_PIN_SPI_DATA],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
                luat_gpio_mode(u8x8->pins[U8X8_PIN_RESET],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
                luat_gpio_mode(u8x8->pins[U8X8_PIN_DC],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
                luat_gpio_mode(u8x8->pins[U8X8_PIN_CS],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
            }else if (pinType == 4){
                luat_gpio_mode(u8x8->pins[U8X8_PIN_SPI_CLOCK],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);//d0 a5 15 d1 a7 17 res b0 18 dc b1 19 cs a4 14
                luat_gpio_mode(u8x8->pins[U8X8_PIN_SPI_DATA],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
                luat_gpio_mode(u8x8->pins[U8X8_PIN_RESET],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
                luat_gpio_mode(u8x8->pins[U8X8_PIN_DC],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
                luat_gpio_mode(u8x8->pins[U8X8_PIN_CS],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
            }else if (pinType == 5){
                luat_gpio_mode(u8x8->pins[U8X8_PIN_RESET],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
                luat_gpio_mode(u8x8->pins[U8X8_PIN_DC],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
                luat_gpio_mode(u8x8->pins[U8X8_PIN_CS],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
            }else if (pinType == 6){
                // set 8080 pin mode
                luat_gpio_mode(u8x8->pins[U8X8_PIN_D0],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
                luat_gpio_mode(u8x8->pins[U8X8_PIN_D1],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
                luat_gpio_mode(u8x8->pins[U8X8_PIN_D2],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
                luat_gpio_mode(u8x8->pins[U8X8_PIN_D3],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
                luat_gpio_mode(u8x8->pins[U8X8_PIN_D4],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
                luat_gpio_mode(u8x8->pins[U8X8_PIN_D5],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
                luat_gpio_mode(u8x8->pins[U8X8_PIN_D6],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
                luat_gpio_mode(u8x8->pins[U8X8_PIN_D7],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
                luat_gpio_mode(u8x8->pins[U8X8_PIN_E],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
                luat_gpio_mode(u8x8->pins[U8X8_PIN_DC],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
                luat_gpio_mode(u8x8->pins[U8X8_PIN_RESET],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
            }
            
            // // set menu pin mode
            // luat_gpio_mode(u8x8->pins[U8X8_PIN_MENU_HOME],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
            // luat_gpio_mode(u8x8->pins[U8X8_PIN_MENU_SELECT],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
            // luat_gpio_mode(u8x8->pins[U8X8_PIN_MENU_PREV],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
            // luat_gpio_mode(u8x8->pins[U8X8_PIN_MENU_NEXT],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
            // luat_gpio_mode(u8x8->pins[U8X8_PIN_MENU_UP],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
            // luat_gpio_mode(u8x8->pins[U8X8_PIN_MENU_DOWN],Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);

            // // set value
            // luat_gpio_set(u8x8->pins[U8X8_PIN_SPI_CLOCK],Luat_GPIO_HIGH);
            // luat_gpio_set(u8x8->pins[U8X8_PIN_SPI_DATA],Luat_GPIO_HIGH);
            // luat_gpio_set(u8x8->pins[U8X8_PIN_RESET],Luat_GPIO_HIGH);
            // luat_gpio_set(u8x8->pins[U8X8_PIN_DC],Luat_GPIO_HIGH);
            // luat_gpio_set(u8x8->pins[U8X8_PIN_CS],Luat_GPIO_HIGH);

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
            luat_gpio_set(u8x8->pins[U8X8_PIN_D2],arg_int);
            break;

        case U8X8_MSG_GPIO_D3:                // D3 pin: Output level in arg_int
            luat_gpio_set(u8x8->pins[U8X8_PIN_D3],arg_int);
            break;

        case U8X8_MSG_GPIO_D4:                // D4 pin: Output level in arg_int
            luat_gpio_set(u8x8->pins[U8X8_PIN_D4],arg_int);
            break;

        case U8X8_MSG_GPIO_D5:                // D5 pin: Output level in arg_int
            luat_gpio_set(u8x8->pins[U8X8_PIN_D5],arg_int);
            break;

        case U8X8_MSG_GPIO_D6:                // D6 pin: Output level in arg_int
            luat_gpio_set(u8x8->pins[U8X8_PIN_D6],arg_int);
            break;

        case U8X8_MSG_GPIO_D7:                // D7 pin: Output level in arg_int
            luat_gpio_set(u8x8->pins[U8X8_PIN_D7],arg_int);
            break;

        case U8X8_MSG_GPIO_E:                // E/WR pin: Output level in arg_int
            luat_gpio_set(u8x8->pins[U8X8_PIN_E],arg_int);
            break;

        case U8X8_MSG_GPIO_I2C_CLOCK:
            // arg_int=0: Output low at I2C clock pin
            // arg_int=1: Input dir with pullup high for I2C clock pin
            luat_gpio_set(u8x8->pins[U8X8_PIN_I2C_CLOCK],arg_int);
            break;

        case U8X8_MSG_GPIO_I2C_DATA:
            // arg_int=0: Output low at I2C data pin
            // arg_int=1: Input dir with pullup high for I2C data pin
            luat_gpio_set(u8x8->pins[U8X8_PIN_I2C_DATA],arg_int);
            break;

        case U8X8_MSG_GPIO_SPI_CLOCK:
            //Function to define the logic level of the clockline
            luat_gpio_set(u8x8->pins[U8X8_PIN_SPI_CLOCK],arg_int);
            break;

        case U8X8_MSG_GPIO_SPI_DATA:
            //Function to define the logic level of the data line to the display
            luat_gpio_set(u8x8->pins[U8X8_PIN_SPI_DATA],arg_int);
            break;

        case U8X8_MSG_GPIO_CS:
            // Function to define the logic level of the CS line
            luat_gpio_set(u8x8->pins[U8X8_PIN_CS],arg_int);
            break;

        case U8X8_MSG_GPIO_DC:
            //Function to define the logic level of the Data/ Command line
            luat_gpio_set(u8x8->pins[U8X8_PIN_DC],arg_int);
            break;

        case U8X8_MSG_GPIO_RESET:
            //Function to define the logic level of the RESET line
            luat_gpio_set(u8x8->pins[U8X8_PIN_RESET],arg_int);
            break;

        default:
            //A message was received which is not implemented, return 0 to indicate an error
            if ( msg >= U8X8_MSG_GPIO(0) )
            {
                i = u8x8_GetPinValue(u8x8, msg);
                if ( i != U8X8_PIN_NONE )
                {
                    if ( u8x8_GetPinIndex(u8x8, msg) < U8X8_PIN_OUTPUT_CNT )
                    {
                        luat_gpio_set(i, arg_int);
                    }
                    else
                    {
                        if ( u8x8_GetPinIndex(u8x8, msg) == U8X8_PIN_OUTPUT_CNT )
                        {
                            // call yield() for the first pin only, u8x8 will always request all the pins, so this should be ok
                            // yield();
                        }
                        u8x8_SetGPIOResult(u8x8, luat_gpio_get(i) == 0 ? 0 : 1);
                    }
                }
                break;
            }
            return 0;
    }
    return 1;
}



