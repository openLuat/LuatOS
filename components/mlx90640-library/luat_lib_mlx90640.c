
/*
@module  mlx90640
@summary 红外测温(MLX90640)
@version 1.0
@date    2022.1.20
@tag LUAT_USE_MLX90640
*/

#include "luat_base.h"
#include "luat_malloc.h"
#include <MLX90640_I2C_Driver.h>
#include <MLX90640_API.h>
#include <math.h>
#include "luat_lcd.h"
#define LUAT_LOG_TAG "mlx90640"
#include "luat_log.h"

static luat_lcd_conf_t* lcd_conf;

#define  FPS1HZ   0x01
#define  FPS2HZ   0x02
#define  FPS4HZ   0x04
#define  FPS8HZ   0x08
#define  FPS16HZ  0x10
#define  FPS32HZ  0x20
#define  FPS64HZ  0x40

#define  MLX90640_ADDR 0x33
#define  TA_SHIFT 8 //Default shift for MLX90640 in open air

//low range of the sensor (this will be blue on the screen)
#define MINTEMP 20

//high range of the sensor (this will be red on the screen)
#define MAXTEMP 35

#define RAW_DATA_W 32
#define RAW_DATA_H 24
#define RAW_DATA_SIZE RAW_DATA_W*RAW_DATA_H
typedef struct mlx_ctx
{
    uint16_t eeMLX90640[832];
    float mlx90640To[RAW_DATA_SIZE];
    uint16_t frame[834];
}mlx_ctx_t;

static mlx_ctx_t* ctx = NULL;

// static uint16_t eeMLX90640[832];
// static float mlx90640To[RAW_DATA_SIZE];
// static uint16_t frame[834];
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

float map(float val, float I_Min, float I_Max, float O_Min, float O_Max){
    return(((val-I_Min)*((O_Max-O_Min)/(I_Max-I_Min)))+O_Min);
}

#define constrain(amt, low, high) ((amt)<(low)?(low):((amt)>(high)?(high):(amt)))

static paramsMLX90640* mlx90640;
mlx90640_i2c_t mlx90640_i2c;

static uint8_t mlx90640_refresh_rate;
/*
初始化MLX90640传感器
@api mlx90640.init(i2c_id,refresh_rate) (注意:2023.5.15之后使用此接口,用户需要自行初始化i2c接口)
@int 传感器所在的i2c总线id或者软i2c对象,默认为0
@int 传感器的测量速率,默认为4Hz
@return bool 成功返回true, 否则返回nil或者false
@usage
i2c.setup(i2cid,i2c_speed)
if mlx90640.init(0,mlx90640.FPS4HZ) then
    log.info("mlx90640", "init ok")
    sys.wait(500) -- 稍等片刻
    while 1 do
        mlx90640.feed() -- 取一帧数据
        mlx90640.draw2lcd(0, 0 ,32 ,24)-- 需提前把lcd初始化好
        sys.wait(250) -- 默认是4HZ
    end
else
    log.info("mlx90640", "init fail")
end

*/
static int l_mlx90640_init(lua_State *L){
    mlx90640_i2c.i2c_id = -1;
    if (!lua_isuserdata(L, 1)) {
		mlx90640_i2c.i2c_id = luaL_optinteger(L, 1 , 0);
	}else if (lua_isuserdata(L, 1)){
        mlx90640_i2c.ei2c = toei2c(L);
    }
    mlx90640_refresh_rate = luaL_optinteger(L, 2 , FPS4HZ);
    lcd_conf = luat_lcd_get_default();

    if (ctx == NULL) {
        ctx = luat_heap_malloc(sizeof(mlx_ctx_t));
        if (ctx == NULL) {
            LLOGE("out of memory when malloc mlx_ctx_t");
            return 0;
        }
    }

    MLX90640_I2CInit();
    mlx90640 = (paramsMLX90640*)luat_heap_malloc(sizeof(paramsMLX90640));
    MLX90640_SetRefreshRate(MLX90640_ADDR, mlx90640_refresh_rate);
    MLX90640_SetChessMode(MLX90640_ADDR);
	status = MLX90640_DumpEE(MLX90640_ADDR, ctx->eeMLX90640);
	if (status != 0){
        LLOGW("load system parameters error with code:%d",status);
        return 0;
    }
	status = MLX90640_ExtractParameters(ctx->eeMLX90640, mlx90640);
	if (status != 0) {
        LLOGW("Parameter extraction failed with error code:%d",status);
        return 0;
    }
    //初始化后此处先读帧,去掉初始化后一些错误数据
    for (size_t i = 0; i < 3; i++){
        int status = MLX90640_GetFrameData(MLX90640_ADDR, ctx->frame);
        if (status < 0){
            LLOGD("GetFrame Error: %d",status);
            return 0;
        }
        vdd = MLX90640_GetVdd(ctx->frame, mlx90640);
        Ta = MLX90640_GetTa(ctx->frame, mlx90640);
        MLX90640_CalculateTo(ctx->frame, mlx90640, emissivity , Ta - TA_SHIFT, ctx->mlx90640To);
        MLX90640_BadPixelsCorrection(mlx90640->brokenPixels, ctx->mlx90640To, 1, mlx90640);
        MLX90640_BadPixelsCorrection(mlx90640->outlierPixels, ctx->mlx90640To, 1, mlx90640);
    }
    lua_pushboolean(L, 1);
    return 1;
}

/*
取一帧数据
@api mlx90640.feed()
*/
static int l_mlx90640_feed(lua_State *L) {
    if (ctx == NULL) {
        LLOGE("mlx90640 NOT init yet");
        return 0;
    }
    int status = MLX90640_GetFrameData(MLX90640_ADDR, ctx->frame);
    if (status < 0){
        LLOGD("GetFrame Error: %d",status);
        return 0;
    }
    vdd = MLX90640_GetVdd(ctx->frame, mlx90640);
    Ta = MLX90640_GetTa(ctx->frame, mlx90640);
    MLX90640_CalculateTo(ctx->frame, mlx90640, emissivity , Ta - TA_SHIFT, ctx->mlx90640To);
    MLX90640_BadPixelsCorrection(mlx90640->brokenPixels, ctx->mlx90640To, 1, mlx90640);
    MLX90640_BadPixelsCorrection(mlx90640->outlierPixels, ctx->mlx90640To, 1, mlx90640);
    lua_pushboolean(L, 1);
    return 0;
}

/*
获取底层裸数据,浮点数矩阵
@api mlx90640.raw_data()
@return table 浮点数数据,768个像素对应的温度值
*/
static int l_mlx90640_raw_data(lua_State *L) {
    if (ctx == NULL) {
        LLOGE("mlx90640 NOT init yet");
        return 0;
    }
    lua_createtable(L, RAW_DATA_SIZE, 0);
    for (size_t i = 0; i < RAW_DATA_SIZE; i++)
    {
        lua_pushnumber(L, ctx->mlx90640To[i]);
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
    if (ctx == NULL) {
        LLOGE("mlx90640 NOT init yet");
        return 0;
    }
    lua_pushnumber(L, ctx->mlx90640To[luaL_checkinteger(L, 1)]);
    return 1;
}

/*
获取外壳温度
@api mlx90640.ta_temp()
@return number 外壳温度
*/
static int l_mlx90640_ta_temp(lua_State *L) {
    lua_pushnumber(L, Ta);
    return 1;
}

/*
获取最高温度
@api mlx90640.max_temp()
@return number 最高温度
@return number 最高温度位置
*/
static int l_mlx90640_max_temp(lua_State *L) {
    float max_temp = -40;
    uint16_t index = 0;
    if (ctx == NULL) {
        LLOGE("mlx90640 NOT init yet");
        return 0;
    }
    for (size_t i = 0; i < RAW_DATA_SIZE; i++){
        if (ctx->mlx90640To[i]>max_temp)
        {
            max_temp = ctx->mlx90640To[i];
            index = i;
        }
    }
    lua_pushnumber(L, max_temp);
    lua_pushinteger(L, index+1);
    return 2;
}

/*
获取最低温度
@api mlx90640.min_temp()
@return number 最低温度
@return number 最低温度位置
*/
static int l_mlx90640_min_temp(lua_State *L) {
    float min_temp = 300;
    uint16_t index = 0;
    if (ctx == NULL) {
        LLOGE("mlx90640 NOT init yet");
        return 0;
    }
    for (size_t i = 0; i < RAW_DATA_SIZE; i++){
        if (ctx->mlx90640To[i]<min_temp)
        {
            min_temp = ctx->mlx90640To[i];
            index = i;
        }
    }
    lua_pushnumber(L, min_temp);
    lua_pushinteger(L, index+1);
    return 2;
}

/*
获取平均温度
@api mlx90640.average_temp()
@return number 平均温度
*/
static int l_mlx90640_average_temp(lua_State *L) {
    float temp[RAW_DATA_H] = {0};
    float temp1=0;
    if (ctx == NULL) {
        LLOGE("mlx90640 NOT init yet");
        return 0;
    }
    for (size_t j = 0; j < RAW_DATA_H; j++)
    {
        for (size_t i = 0; i < RAW_DATA_W; i++)
        {
            temp1 += ctx->mlx90640To[i];
        }
        temp[j]=temp1/RAW_DATA_W;
        temp1 = 0;
    }

    for (size_t i = 0; i < RAW_DATA_H; i++){
        temp1+=temp[i];
    }
    lua_pushnumber(L, temp1/RAW_DATA_H);
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

static uint8_t * luat_interpolation_double(uint8_t *src, uint16_t rows,uint16_t cols) {
    int w1 = cols;
    int h1 = rows;
    int w2 = w1*2;
    //int h2 = h1*2;
    uint8_t* dst = (uint8_t*)luat_heap_malloc(rows*cols*4);
    for (size_t y = 0; y < h1; y++){
        for (size_t x = 0; x < w1; x++){
            dst[y*2*w2+x*2] = src[y*w1+x];
            if (x == w1 - 1){
                dst[y*2*w2+x*2+1] = (uint8_t)(dst[y*2*w2+x*2]*2-dst[y*2*w2+x*2-1]);
                if (y == h1 - 1){
                    dst[(y*2+1)*w2+x*2] = (uint8_t)(dst[y*2*w2+x*2]*2-dst[(y*2-1)*w2+x*2]);
                }else{
                    dst[(y*2+1)*w2+x*2] = (uint8_t)round((src[y*w1+x]+src[(y+1)*w1+x])/2);
                }
            }else{
                dst[y*2*w2+x*2+1] = (uint8_t)round((src[y*w1+x]+src[y*w1+x+1])/2);
                if (y == h1 - 1){
                    dst[(y*2+1)*w2+x*2] = (uint8_t)(dst[y*2*w2+x*2]*2-dst[(y*2-1)*w2+x*2]);
                }else{
                    dst[(y*2+1)*w2+x*2] = (uint8_t)round((src[y*w1+x]+src[(y+1)*w1+x])/2);
                }
            }
        }
    }

    for (size_t y = 0; y < h1; y++){
        for (size_t x = 0; x < w1; x++){
            if ((x == w1 - 1) && (y == h1 - 1)){
                dst[(y*2+1)*w2+x*2+1] = (uint8_t)round((dst[(y*2+1)*w2+x*2]+dst[y*2*w2+x*2+1])/2);
            }
            else if (y == h1 - 1){
                dst[(y*2+1)*w2+x*2+1] = (uint8_t)round((dst[(y*2+1)*w2+x*2]+dst[(y*2+1)*w2+x*2+2])/2);
            }
            else{
                dst[(y*2+1)*w2+x*2+1] = (uint8_t)round((dst[y*2*w2+x*2+1]+dst[(y*2+2)*w2+x*2+1])/2);
            }
        }
    }
    return dst;
}

static uint8_t * luat_interpolation(uint8_t *src, uint16_t rows,uint16_t cols,uint8_t fold) {
    uint8_t* index_data_out1 = NULL;
    uint8_t* index_data_out2 = NULL;
    for (size_t i = 2; i <= fold; i=i*2){
        if (i==2){
            index_data_out1 = luat_interpolation_double(src, rows,cols);
            luat_heap_free(src);
        }else{
            if (index_data_out1 == NULL){
                index_data_out1 = luat_interpolation_double(index_data_out2, rows,cols);
                luat_heap_free(index_data_out2);
                index_data_out2 = NULL;
            }else{
                index_data_out2 = luat_interpolation_double(index_data_out1, rows,cols);
                luat_heap_free(index_data_out1);
                index_data_out1 = NULL;
            }
        }
        rows = rows*2;
        cols = cols*2;
    }
    if (index_data_out1 != NULL){
        return index_data_out1;
    }else{
        return index_data_out2;
    }
}


/*
绘制到lcd
@api mlx90640.draw2lcd(x, y, fold)
@int 左上角x坐标
@int 左上角y坐标
@int 放大倍数,必须为2的指数倍(1,2,4,8,16...)默认为1
@return bool 成功返回true,否则返回false
*/
static int l_mlx90640_draw2lcd(lua_State *L) {
    if (lcd_conf == NULL) {
        LLOGW("init lcd first!!!");
        return 0;
    }
    uint16_t lcd_x = luaL_optinteger(L, 1 , 0);
    uint16_t lcd_y = luaL_optinteger(L, 2 , 0);
    uint8_t fold = luaL_optinteger(L, 3 , 1);

    uint8_t* index_data = luat_heap_malloc(RAW_DATA_SIZE);
    for (size_t i = 0; i < RAW_DATA_SIZE; i++){
        float t = ctx->mlx90640To[i];
        if (t<MINTEMP) t=MINTEMP;
        if (t>MAXTEMP) t=MAXTEMP;
        uint8_t colorIndex = (uint8_t)round(map(t, MINTEMP, MAXTEMP, 0, 255));
        colorIndex = constrain(colorIndex, 0, 255);
        index_data[i] = colorIndex;
    }
    uint8_t* index_data_out = NULL;
    if (fold==1){
        index_data_out = index_data;
    }else{
        index_data_out = luat_interpolation(index_data, RAW_DATA_H,RAW_DATA_W,fold);
    }
    int index_data_out_w = RAW_DATA_W*fold;
    int index_data_out_h = RAW_DATA_H*fold;

    luat_color_t line[index_data_out_w];
    for (size_t y = 0; y < index_data_out_h; y++){
        for (size_t x = 0; x < index_data_out_w; x++){
            line[x] = color_swap(camColors[index_data_out[y*index_data_out_w + x]]);
        }
        luat_lcd_draw(lcd_conf, lcd_x, lcd_y+y, lcd_x+index_data_out_w-1, lcd_y+y, line);
    }

    luat_heap_free(index_data_out);
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_mlx90640[] =
{
    {"init",        ROREG_FUNC(l_mlx90640_init) },
    {"feed",        ROREG_FUNC(l_mlx90640_feed) },
    {"raw_data",    ROREG_FUNC(l_mlx90640_raw_data)},
    {"raw_point",   ROREG_FUNC(l_mlx90640_raw_point)},
    {"draw2lcd",    ROREG_FUNC(l_mlx90640_draw2lcd)},
    {"ta_temp",     ROREG_FUNC(l_mlx90640_ta_temp)},
    {"max_temp",    ROREG_FUNC(l_mlx90640_max_temp)},
    {"min_temp",    ROREG_FUNC(l_mlx90640_min_temp)},
    {"average_temp",ROREG_FUNC(l_mlx90640_average_temp)},
    {"get_vdd",     ROREG_FUNC(l_mlx90640_get_vdd)},

    //@const FPS1HZ number FPS1HZ
    { "FPS1HZ",     ROREG_INT(FPS1HZ)},
    //@const FPS2HZ number FPS2HZ
    { "FPS2HZ",     ROREG_INT(FPS2HZ)},
    //@const FPS4HZ number FPS4HZ
    { "FPS4HZ",     ROREG_INT(FPS4HZ)},
    //@const FPS8HZ number FPS8HZ
    { "FPS8HZ",     ROREG_INT(FPS8HZ)},
    //@const FPS16HZ number FPS16HZ
    { "FPS16HZ",    ROREG_INT(FPS16HZ)},
    //@const FPS32HZ number FPS32HZ
    { "FPS32HZ",    ROREG_INT(FPS32HZ)},
    //@const FPS64HZ number FPS64HZ
    { "FPS64HZ",    ROREG_INT(FPS64HZ)},
	{ NULL,         ROREG_INT(0) }
};

LUAMOD_API int luaopen_mlx90640( lua_State *L ) {
    luat_newlib2(L, reg_mlx90640);
    return 1;
}
