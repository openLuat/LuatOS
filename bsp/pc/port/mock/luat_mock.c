
#include "luat_base.h"
#include "luat_fs.h"
#include "luat_malloc.h"
#include "luat_mock.h"

#define LUAT_LOG_TAG "mock"
#include "luat_log.h"

static lua_State *mock_L;
static char mock_file_path[1024];

static int mock_main(lua_State *L);

static const luaL_Reg loadedlibs[] = {
  {"_G", luaopen_base}, // _G
  {LUA_LOADLIBNAME, luaopen_package}, // require
  {LUA_COLIBNAME, luaopen_coroutine}, // coroutine协程库
  {LUA_TABLIBNAME, luaopen_table},    // table库,操作table类型的数据结构
  {LUA_IOLIBNAME, luaopen_io},        // io库,操作文件
  {LUA_OSLIBNAME, luaopen_os},        // os库,已精简
  {LUA_STRLIBNAME, luaopen_string},   // string库,字符串操作
  {LUA_MATHLIBNAME, luaopen_math},    // math 数值计算
  {LUA_UTF8LIBNAME, luaopen_utf8},
  {LUA_DBLIBNAME, luaopen_debug},     // debug库,已精简
#if defined(LUA_COMPAT_BITLIB)
  {LUA_BITLIBNAME, luaopen_bit32},    // 不太可能启用
#endif
// 外设类
#ifdef LUAT_USE_UART
  {"uart",    luaopen_uart},              // 串口操作
#endif
#ifdef LUAT_USE_GPIO
  {"gpio",    luaopen_gpio},              // GPIO脚的操作
#endif
#ifdef LUAT_USE_I2C
  {"i2c",     luaopen_i2c},               // I2C操作
#endif
#ifdef LUAT_USE_SPI
  {"spi",     luaopen_spi},               // SPI操作
#endif
#ifdef LUAT_USE_ADC
  {"adc",     luaopen_adc},               // ADC模块
#endif
#ifdef LUAT_USE_PWM
  {"pwm",     luaopen_pwm},               // PWM模块
#endif
#ifdef LUAT_USE_WDT
  {"wdt",     luaopen_wdt},               // watchdog模块
#endif
#ifdef LUAT_USE_PM
  {"pm",      luaopen_pm},                // 电源管理模块
#endif
#ifdef LUAT_USE_MCU
  {"mcu",     luaopen_mcu},               // MCU特有的一些操作
#endif
#ifdef LUAT_USE_RTC
  {"rtc", luaopen_rtc},                   // 实时时钟
#endif
#ifdef LUAT_USE_OTP
  {"otp", luaopen_otp},                   // OTP
#endif
//-----------------------------------------------------------------
  {"log", luaopen_log},               // 日志库
  {"timer", luaopen_timer},           // 延时库
  {"pack", luaopen_pack},             // pack.pack/pack.unpack
  {"json", luaopen_cjson},             // json
  {"zbuff", luaopen_zbuff},            // 
  {"crypto", luaopen_crypto},
#ifdef LUAT_USE_RSA
  {"rsa", luaopen_rsa},
#endif
#ifdef LUAT_USE_MINIZ
  {"miniz", luaopen_miniz},
#endif
#ifdef LUAT_USE_PROTOBUF
  {"protobuf", luaopen_protobuf},
#endif
#ifdef LUAT_USE_IOTAUTH
  {"iotauth", luaopen_iotauth},
#endif
#ifdef LUAT_USE_ICONV
  {"iconv", luaopen_iconv},
#endif
#ifdef LUAT_USE_BIT64
  {"bit64", luaopen_bit64},
#endif
#ifdef LUAT_USE_FS
  {"fs",      luaopen_fs},                // 文件系统库,在io库之外再提供一些方法
#endif
#ifdef LUAT_USE_MQTTCORE
  {"mqttcore",luaopen_mqttcore},          // MQTT 协议封装
#endif
  {NULL, NULL}
};

int luat_mock_init(const char* path) {
    mock_L = lua_newstate(luat_heap_alloc, NULL);
    memcpy(mock_file_path, path, strlen(path) + 1);
    LLOGI("mock脚本路径 %s", mock_file_path);
    if (mock_L == NULL || mock_file_path[0] == 0x00) {
        return -1;
    }
    const luaL_Reg *lib;
    /* "require" functions from 'loadedlibs' and set results to global table */
    for (lib = loadedlibs; lib->func; lib++) {
        luaL_requiref(mock_L, lib->name, lib->func, 1);
        lua_pop(mock_L, 1);  /* remove lib */
        //extern void print_list_mem(const char* name);
        //print_list_mem(lib->name);
    }
    return 0;
}

int luat_mock_call(luat_mock_ctx_t* ctx) {
    if (mock_L == NULL) {
        return -0xFF;
    }
    if (mock_file_path[0] == 0x00) {
        return -2;
    }
    
    const char *resp;
    lua_Integer intVal;
    lua_Number numVal;
    lua_pushcfunction(mock_L, &mock_main);
	  lua_pushstring(mock_L, ctx->key);
	  lua_pushlstring(mock_L, ctx->req_data, ctx->req_len);
    int ret = lua_pcall(mock_L, 2, 2, 0);
    if (ret) {
        LLOGE("pcall %d %s", ret, lua_tostring(mock_L, -1));
        return ret;
    }
    else {
        ctx->resp_code = lua_tointeger(mock_L, 1);
        ctx->resp_type = lua_type(mock_L, 2);
        switch (lua_type(mock_L, 2))
        {
        case LUA_TNIL: // 空值
            /* code */
            break;
        case LUA_TBOOLEAN:
            ctx->resp_data = luat_heap_malloc(1);
            ctx->resp_data[0] = lua_toboolean(mock_L, 2);
            ctx->resp_len = 1;
            break;
        case LUA_TNUMBER:
            ctx->resp_data = luat_heap_malloc(sizeof(lua_Integer));
            ctx->resp_len = sizeof(lua_Integer);
            if (lua_isinteger(mock_L, 2)) {
                intVal = lua_tointeger(mock_L, 2);
                memcpy(ctx->resp_data, &intVal, sizeof(lua_Integer));
            }
            else {
                numVal = lua_tonumber(mock_L, 2);
                memcpy(ctx->resp_data, &numVal, sizeof(lua_Integer));
            }
            break;
        case LUA_TSTRING:
            resp = lua_tolstring(mock_L, 2, &ctx->resp_len);
            if (ctx->resp_len > 0) {
                ctx->resp_data = luat_heap_malloc(ctx->resp_len + 1);
                memcpy(ctx->resp_data, resp, ctx->resp_len + 1);
            }
            break;
        default:
            break;
        }
    }
    return ret;
}

static int load_mock_lua_file(lua_State *L) {
    const char* name = mock_file_path;
    const char* path = mock_file_path;
    // 加载mock.lua
    //----------------------------------------------
	size_t len = 0;
	int ret = 0;
	// LLOGD("把%s当做main.lua运行", path);
	char tmpname[512] = {0};
	FILE *f = fopen(name, "rb");
	if (!f)
	{
		LLOGE("文件不存在 %s", path);
		return -3;
	}
	fseek(f, 0, SEEK_END);
	len = ftell(f);
	fseek(f, 0, SEEK_SET);
	// void* fptr = luat_heap_malloc(len);
	char *tmp = luat_heap_malloc(len);
	if (tmp == NULL)
	{
		fclose(f);
		LLOGE("文件太大,内存放不下 %s", path);
        return -3;
	}
	fread(tmp, 1, len, f);
	fclose(f);

	for (size_t i = strlen(path); i > 0; i--)
	{
		if (path[i - 1] == '/' || path[i - 1] == '\\')
		{
			memcpy(tmpname, name + i, strlen(path) - 1);
			break;
		}
	}
	if (tmpname[0] == 0x00)
	{
		memcpy(tmpname, path, strlen(path));
	}

    //----------------------------------------------

    ret = luaL_loadbufferx(L, tmp, len, name, NULL);
    if (ret) {
        LLOGE("文件加载失败 %s %s", name, lua_tostring(L, -1));
		return -3;
    }
    ret = lua_pcall(L, 0, 1, 0);
    if (ret) {
        LLOGE("mock加载失败 %s %s", name, lua_tostring(L, -1));
		return -4;
    }
    // LLOGD("栈顶对象的类型 %d", lua_type(L, -1));
    lua_setglobal(L, "mockf");
    return 0;
}

static int mock_main(lua_State *L) {
    int ret = 0;

    ret = load_mock_lua_file(L);
    if (ret) {
        LLOGD("加载mock脚本失败 %d", ret);
        return ret;
    }
    lua_getglobal(L, "mockf");
    lua_pushvalue(L, 1);
    lua_pushvalue(L, 2);
    lua_call(L, 2, 2);
    return 2;
}
