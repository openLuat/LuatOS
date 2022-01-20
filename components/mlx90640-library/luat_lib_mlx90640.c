
/*
@module  mlx90640
@summary 红外测温(MLX90640)
@version 1.0
@date    2022.1.20
*/

#include "luat_base.h"
#include <MLX90640_I2C_Driver.h>
#include <MLX90640_API.h>
#include <math.h>
#include "luat_lcd.h"
#define LUAT_LOG_TAG "mlx90640"
#include "luat_log.h"

static luat_lcd_conf_t* lcd_conf;

#define  FPS2HZ   0x02
#define  FPS4HZ   0x03
#define  FPS8HZ   0x04
#define  FPS16HZ  0x05
#define  FPS32HZ  0x06

#define  MLX90640_ADDR 0x33
#define	 RefreshRate FPS4HZ 
#define  TA_SHIFT 8 //Default shift for MLX90640 in open air

static uint16_t eeMLX90640[832];  
static float mlx90640To[768];
static uint16_t frame[834];
static float emissivity=0.95;
static int status;
static float vdd;
static float Ta;

const uint16_t camColors[] = {0x480F,
0x400F,0x400F,0x400F,0x4010,0x3810,0x3810,0x3810,0x3810,0x3010,0x3010,
0x3010,0x2810,0x2810,0x2810,0x2810,0x2010,0x2010,0x2010,0x1810,0x1810,
0x1811,0x1811,0x1011,0x1011,0x1011,0x0811,0x0811,0x0811,0x0011,0x0011,
0x0011,0x0011,0x0011,0x0031,0x0031,0x0051,0x0072,0x0072,0x0092,0x00B2,
0x00B2,0x00D2,0x00F2,0x00F2,0x0112,0x0132,0x0152,0x0152,0x0172,0x0192,
0x0192,0x01B2,0x01D2,0x01F3,0x01F3,0x0213,0x0233,0x0253,0x0253,0x0273,
0x0293,0x02B3,0x02D3,0x02D3,0x02F3,0x0313,0x0333,0x0333,0x0353,0x0373,
0x0394,0x03B4,0x03D4,0x03D4,0x03F4,0x0414,0x0434,0x0454,0x0474,0x0474,
0x0494,0x04B4,0x04D4,0x04F4,0x0514,0x0534,0x0534,0x0554,0x0554,0x0574,
0x0574,0x0573,0x0573,0x0573,0x0572,0x0572,0x0572,0x0571,0x0591,0x0591,
0x0590,0x0590,0x058F,0x058F,0x058F,0x058E,0x05AE,0x05AE,0x05AD,0x05AD,
0x05AD,0x05AC,0x05AC,0x05AB,0x05CB,0x05CB,0x05CA,0x05CA,0x05CA,0x05C9,
0x05C9,0x05C8,0x05E8,0x05E8,0x05E7,0x05E7,0x05E6,0x05E6,0x05E6,0x05E5,
0x05E5,0x0604,0x0604,0x0604,0x0603,0x0603,0x0602,0x0602,0x0601,0x0621,
0x0621,0x0620,0x0620,0x0620,0x0620,0x0E20,0x0E20,0x0E40,0x1640,0x1640,
0x1E40,0x1E40,0x2640,0x2640,0x2E40,0x2E60,0x3660,0x3660,0x3E60,0x3E60,
0x3E60,0x4660,0x4660,0x4E60,0x4E80,0x5680,0x5680,0x5E80,0x5E80,0x6680,
0x6680,0x6E80,0x6EA0,0x76A0,0x76A0,0x7EA0,0x7EA0,0x86A0,0x86A0,0x8EA0,
0x8EC0,0x96C0,0x96C0,0x9EC0,0x9EC0,0xA6C0,0xAEC0,0xAEC0,0xB6E0,0xB6E0,
0xBEE0,0xBEE0,0xC6E0,0xC6E0,0xCEE0,0xCEE0,0xD6E0,0xD700,0xDF00,0xDEE0,
0xDEC0,0xDEA0,0xDE80,0xDE80,0xE660,0xE640,0xE620,0xE600,0xE5E0,0xE5C0,
0xE5A0,0xE580,0xE560,0xE540,0xE520,0xE500,0xE4E0,0xE4C0,0xE4A0,0xE480,
0xE460,0xEC40,0xEC20,0xEC00,0xEBE0,0xEBC0,0xEBA0,0xEB80,0xEB60,0xEB40,
0xEB20,0xEB00,0xEAE0,0xEAC0,0xEAA0,0xEA80,0xEA60,0xEA40,0xF220,0xF200,
0xF1E0,0xF1C0,0xF1A0,0xF180,0xF160,0xF140,0xF100,0xF0E0,0xF0C0,0xF0A0,
0xF080,0xF060,0xF040,0xF020,0xF800,};

uint8_t tempto255(float temp){
    return (uint8_t)round((temp+40)*255/340);
}

static paramsMLX90640 mlx90640;
uint8_t mlx90640_i2c_id;
uint8_t mlx90640_i2c_speed;

/*
初始化MLX90640传感器
@api mlx90640.init(i2c_id)
@int 传感器所在的i2c总线id,默认为0
@int 传感器所在的i2c总线速度,默认为i2c.FAST
@return bool 成功返回true, 否则返回nil或者false
@usage

if mlx90640.init(0,i2c.FAST) then
    log.info("mlx90640", "init ok")
    sys.wait(500) -- 稍等片刻
    while 1 do
        mlx90640.feed() -- 取一帧数据
        mlx90640.draw2lcd(0, 0) -- 需提前把lcd初始化好
        sys.wait(250) -- 默认是4HZ
    end
else
    log.info("mlx90640", "init fail")
end

*/
static int l_mlx90640_init(lua_State *L){
    mlx90640_i2c_id = luaL_checkinteger(L, 1);
    mlx90640_i2c_speed = luaL_optinteger(L, 2 , 1);

    lcd_conf = luat_lcd_get_default();
    MLX90640_I2CInit();
    // luat_timer_mdelay(50);
    MLX90640_SetRefreshRate(MLX90640_ADDR, RefreshRate);//测量速率1Hz(0~7对应0.5,1,2,4,8,16,32,64Hz)
    MLX90640_SetChessMode(MLX90640_ADDR); 
	status = MLX90640_DumpEE(MLX90640_ADDR, eeMLX90640);  //读取像素校正参数 
	if (status != 0){
        LLOGW("load system parameters error with code:%d",status);
        return 0;
    } 
	status = MLX90640_ExtractParameters(eeMLX90640, &mlx90640);  //解析校正参数（计算温度时需要）
	if (status != 0) {
        LLOGW("Parameter extraction failed with error code:%d",status);
        return 0;
    }
    lua_pushboolean(L, 1);
    return 1;
    // while (1){
    //     luat_timer_mdelay(10);
        
        
    //     int x,y = 0;
    //     // uint8_t mul = 3;
    //     for(int i = 0; i < 768; i++){
    //         if(i%32 == 0 && i != 0){
    //             x = 0;
    //             // y+=mul;
    //             y++;
    //             // printf("\n");
    //         }
            
    //         // uint8_t mul_size = mul*mul;
    //         // uint16_t draw_data[mul_size];
    //         // for (size_t m = 0; m < mul_size; m++){
    //         //     draw_data[m] = camColors[tempto255(mlx90640To[i])];
    //         // }
    //         // luat_lcd_draw(lcd_conf,x, y, x+mul-1, y+mul-1, draw_data);
    //         // x+=mul;

    //         luat_lcd_draw(lcd_conf,x, y, x, y, &(camColors[tempto255(mlx90640To[i])]));

    //         x++;
    //     }
    // }
}

static int l_mlx90640_feed(lua_State *L) {
    int status = MLX90640_GetFrameData(MLX90640_ADDR, frame);  //读取一帧原始数据
    if (status < 0){
        LLOGD("GetFrame Error: %d",status);
        return 0;
    }
    vdd = MLX90640_GetVdd(frame, &mlx90640);  //计算 Vdd（这句可有可无）
    Ta = MLX90640_GetTa(frame, &mlx90640);    //计算实时外壳温度
    MLX90640_CalculateTo(frame, &mlx90640, emissivity , Ta - TA_SHIFT, mlx90640To);            //计算像素点温度
    MLX90640_BadPixelsCorrection(mlx90640.brokenPixels, mlx90640To, 1, &mlx90640);  //坏点处理
    MLX90640_BadPixelsCorrection(mlx90640.outlierPixels, mlx90640To, 1, &mlx90640); //坏点处理
    lua_pushboolean(L, 1);
    return 0;
}

/*
获取底层裸数据,浮点数矩阵
@api mlx90640.raw_data()
@return table 浮点数数据,768个像素对应的温度值
*/
static int l_mlx90640_raw_data(lua_State *L) {
    lua_createtable(L, 768, 0);
    for (size_t i = 0; i < 768; i++)
    {
        lua_pushnumber(L, mlx90640To[i]);
        lua_seti(L, -2, i + 1);
    }
    return 1;
}

/*
获取单一点数据
@api mlx90640.raw_point(index)
@int 索引值(0-767)
@return number 单点温度值
*/
static int l_mlx90640_raw_point(lua_State *L) {
    lua_pushnumber(L, mlx90640To[luaL_checkinteger(L, 1)]);
    return 1;
}

/*
获取外壳温度
@api mlx90640.get_temp()
@return number 外壳温度
*/
static int l_mlx90640_get_temp(lua_State *L) {
    lua_pushnumber(L, Ta);
    return 1;
}

/*
获取vdd
@api mlx90640.get_vdd()
@return number vdd
*/
static int l_mlx90640_get_vdd(lua_State *L) {
    lua_pushnumber(L, vdd);
    return 1;
}

/*
绘制到lcd
@api mlx90640.draw2lcd(x, y, w, h)
@int 左上角x坐标
@int 左上角y坐标
@int 显示尺寸的宽,需要是32的倍数, 若大于32会进行插值
@int 显示尺寸的高,需要是16的倍数, 若大于16会进行插值
@return bool 成功返回true,否则返回false
*/
static int l_mlx90640_draw2lcd(lua_State *L) {
    luat_color_t line[32];
    // TODO 还得插值

    if (lcd_conf == NULL) {
        LLOGW("init lcd first!!!");
        return 0;
    }

    for (size_t y = 0; y < 768/32; y++)
    {
        for (size_t x = 0; x < 32; x++)
        {
            int i = y*32 + x;
            line[x] = &(camColors[tempto255(mlx90640To[i])]);
        }
        luat_lcd_draw(lcd_conf, 0, y, 31, y, line);
    }
    return 0;
}

#include "rotable.h"
static const rotable_Reg reg_mlx90640[] =
{
    {"init", l_mlx90640_init, 0},
    {"feed", l_mlx90640_feed, 0},
    {"raw_data", l_mlx90640_raw_data, 0},
    {"raw_point", l_mlx90640_raw_point, 0},
    {"draw2lcd", l_mlx90640_draw2lcd, 0},
    {"get_temp", l_mlx90640_get_temp, 0},
    {"get_vdd", l_mlx90640_get_vdd, 0},
	{ NULL, NULL , 0}
};

LUAMOD_API int luaopen_mlx90640( lua_State *L ) {
    luat_newlib(L, reg_mlx90640);
    return 1;
}
