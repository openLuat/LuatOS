
/*
@module  camera
@summary 摄像头
@version 1.0
@date    2022.01.11
*/
#include "luat_base.h"
#include "luat_camera.h"
#include "luat_msgbus.h"

#define LUAT_LOG_TAG "camera"
#include "luat_log.h"

#define MAX_DEVICE_COUNT 2

typedef struct luat_camera_cb {
    int scanned;
} luat_camera_cb_t;
static luat_camera_cb_t camera_cbs[MAX_DEVICE_COUNT];

int l_camera_handler(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_pop(L, 1);
    int camera_id = msg->arg1;
    if (camera_cbs[camera_id].scanned) {
        lua_geti(L, LUA_REGISTRYINDEX, camera_cbs[camera_id].scanned);
        if (lua_isfunction(L, -1)) {
            lua_pushinteger(L, camera_id);
            if (msg->ptr)
            {
                lua_pushlstring(L, (char *)msg->ptr,msg->arg2);
            }
            else
            {
            	lua_pushboolean(L, msg->arg2);
            }
            lua_call(L, 2, 0);
        }
    }
    lua_pushinteger(L, 0);
    return 1;
}

/*
初始化摄像头
@api    camera.init(InitReg)
@table InitReg camera初始化命令 见demo/camera/AIR105 注意:如扫码 camera初始化时需设置为灰度输出
@return int camera_id
@usage
camera_id = camera.init(GC032A_InitReg)--屏幕输出rgb图像
--初始化后需要start才开始输出/扫码
camera.start(camera_id)--开始指定的camera
*/

static int l_camera_init(lua_State *L){
    luat_camera_conf_t conf = {0};
    conf.lcd_conf = luat_lcd_get_default();
    if (lua_istable(L, 1)) {
        lua_pushliteral(L, "zbar_scan");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.zbar_scan = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "draw_lcd");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.draw_lcd = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "i2c_id");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.i2c_id = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "i2c_addr");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.i2c_addr = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "pwm_id");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.pwm_id = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "pwm_period");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.pwm_period = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "pwm_pulse");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.pwm_pulse = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "sensor_width");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.sensor_width = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "sensor_height");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.sensor_height = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "color_bit");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.color_bit = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "id_reg");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.id_reg = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "id_value");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.id_value = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "init_cmd");
        lua_gettable(L, 1);
        if (lua_istable(L, -1)) {
            conf.init_cmd_size = lua_rawlen(L, -1);
            conf.init_cmd = luat_heap_malloc(conf.init_cmd_size * sizeof(uint8_t));
            for (size_t i = 1; i <= conf.init_cmd_size; i++){
                lua_geti(L, -1, i);
                conf.init_cmd[i-1] = luaL_checkinteger(L, -1);
                lua_pop(L, 1);
            }
        }
        lua_pop(L, 1);
    }
    lua_pushinteger(L, luat_camera_init(&conf));
    return 1;
}

/*
注册摄像头事件回调
@api    camera.on(id, event, func)
@int camera id, camera 0写0, camera 1写1
@string 事件名称
@function 回调方法
@return nil 无返回值
@usage
camera.on(0, "scanned", function(id, str)
    print(id, str)
end)
*/
static int l_camera_on(lua_State *L) {
    int camera_id = luaL_checkinteger(L, 1);
    const char* event = luaL_checkstring(L, 2);
    if (!strcmp("scanned", event)) {
        if (camera_cbs[camera_id].scanned != 0) {
            luaL_unref(L, LUA_REGISTRYINDEX, camera_cbs[camera_id].scanned);
            camera_cbs[camera_id].scanned = 0;
        }
        if (lua_isfunction(L, 3)) {
            lua_pushvalue(L, 3);
            camera_cbs[camera_id].scanned = luaL_ref(L, LUA_REGISTRYINDEX);
        }
    }
    return 0;
}

/**
开始指定的camera
@api camera.start(id)
@int camera id,例如0
@return boolean 成功返回true,否则返回false
@usage
camera.start(0)
*/
static int l_camera_start(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    lua_pushboolean(L, luat_camera_start(id) == 0 ? 1 : 0);
    return 1;
}

/**
停止指定的camera
@api camera.stop(id)
@int camera id,例如0
@return boolean 成功返回true,否则返回false
@usage
camera.stop(0)
*/
static int l_camera_stop(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    lua_pushboolean(L, luat_camera_stop(id) == 0 ? 1 : 0);
    return 1;
}

/**
关闭指定的camera，释放相应的IO资源
@api camera.close(id)
@int camera id,例如0
@return boolean 成功返回true,否则返回false
@usage
camera.close(0)
*/
static int l_camera_close(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    lua_pushboolean(L, luat_camera_close(id) == 0 ? 1 : 0);
    return 1;
}

LUAT_WEAK luat_camera_capture(int id, uint8_t quality, const char *path) {
    LLOGD("not support yet");
    return -1;
}

/**
camera拍照
@api camera.capture(id, y_diff, save_path, quality)
@int camera id,例如0
@int y_diff,Y分量校准量，0~255，越大越亮，根据实际情况修改，GC032A测试下来需要填0
@string save_path,文件保存路径，空则写在上次路径里，默认是/capture.jpg
@int quality, jpeg压缩质量，1最差，占用空间小，3最高，占用空间最大而且费时间，默认1
@return boolean 成功返回true,否则返回false
@usage
camera.capture(0)
*/
static int l_camera_capture(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    const char* save_path = luaL_checkstring(L, 2);
    int quality = luaL_optinteger(L, 3, 1);
    luat_camera_capture(id, quality, save_path);
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_camera[] =
{
    { "init" ,       ROREG_FUNC(l_camera_init )},
    { "start" ,      ROREG_FUNC(l_camera_start )},
    { "stop" ,       ROREG_FUNC(l_camera_stop)},
    { "capture",     ROREG_FUNC(l_camera_capture)},
	{ "close",		 ROREG_FUNC(l_camera_close)},
    { "on",          ROREG_FUNC(l_camera_on)},
	{ NULL,          {}}
};

LUAMOD_API int luaopen_camera( lua_State *L ) {
    luat_newlib2(L, reg_camera);
    return 1;
}

