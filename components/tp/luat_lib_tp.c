
/*
@module  tp
@summary 触摸库
@version 1.0
@date    2025.02.19
@demo    lcd
@tag LUAT_USE_TP
*/

#include "luat_base.h"
#include "luat_tp.h"
#include "luat_msgbus.h"
#include "luat_mem.h"
#include "luat_gpio.h"

#define LUAT_LOG_TAG "tp"
#include "luat_log.h"

typedef struct tp_reg {
    const char *name;
    const luat_tp_config_t *luat_tp_config;
}tp_reg_t;

static const tp_reg_t tp_regs[] = {
    {"gt911",  &tp_config_gt911},
	{"jd9261t_inited",  &tp_config_jd9261t_inited},
    {"", NULL}
};

static int l_tp_handler(lua_State* L, void* ptr) {
    rtos_msg_t *msg = (rtos_msg_t *)lua_topointer(L, -1);
    luat_tp_config_t* luat_tp_config = msg->ptr;
    luat_tp_data_t* luat_tp_data = msg->arg1;

    if (luat_tp_config->luat_cb) {
        lua_geti(L, LUA_REGISTRYINDEX, luat_tp_config->luat_cb);
        if (lua_isfunction(L, -1)) {
            lua_pushlightuserdata(L, luat_tp_config);
            lua_newtable(L);
            for (uint8_t i=0; i<LUAT_TP_TOUCH_MAX; i++){
                if ((TP_EVENT_TYPE_DOWN == luat_tp_data[i].event) || (TP_EVENT_TYPE_UP == luat_tp_data[i].event) || (TP_EVENT_TYPE_MOVE == luat_tp_data[i].event)){
                    lua_newtable(L);
                    lua_pushstring(L, "event");
                    lua_pushinteger(L, luat_tp_data[i].event);
                    lua_settable(L, -3);
                    lua_pushstring(L, "track_id");
                    lua_pushinteger(L, luat_tp_data[i].track_id);
                    lua_settable(L, -3);
                    lua_pushstring(L, "x");
                    lua_pushinteger(L, luat_tp_data[i].x_coordinate);
                    lua_settable(L, -3);
                    lua_pushstring(L, "y");
                    lua_pushinteger(L, luat_tp_data[i].y_coordinate);
                    lua_settable(L, -3);
                    lua_pushstring(L, "width");
                    lua_pushinteger(L, luat_tp_data[i].width);
                    lua_settable(L, -3);
                    lua_pushstring(L, "timestamp");
                    lua_pushinteger(L, luat_tp_data[i].timestamp);
                    lua_settable(L, -3);

                    lua_pushinteger(L, i + 1);
                    lua_insert(L, -2);
                    lua_settable(L, -3);
                }
            }
            lua_call(L, 2, 0);
        }
    }
    luat_tp_config->opts->read_done(luat_tp_config);
    return 0;
}

int l_tp_callback(luat_tp_config_t* luat_tp_config, luat_tp_data_t* luat_tp_data){
	for(uint8_t i = 0; i < LUAT_TP_TOUCH_MAX; i++) {
		if (luat_tp_data[i].event != TP_EVENT_TYPE_NONE) {
		    rtos_msg_t msg = {.handler = l_tp_handler, .ptr=luat_tp_config, .arg1=luat_tp_data};
		    luat_msgbus_put(&msg, 1);
		    return 0;
		}
	}
	return 0;
}

/*
触摸初始化
@api tp.init(tp, args)
@string tp类型，当前支持：<br>gt911
@table 附加参数,与具体设备有关：<br>port 驱动方式<br>port：硬件i2c端口,例如0,1,2...如果为软件i2c对象<br>pin_rst：复位引脚<br>pin_int：中断引脚<br>w:宽度<br>h:高度

@usage
// tp.init("gt911",{port=0,pin_rst = 22,pin_int = 23,w = 320,h = 480})
// local softI2C = i2c.createSoft(20, 21)
// tp.init("gt911",{port=softI2C,pin_rst = 22,pin_int = 23,w = 320,h = 480})
*/

static int l_tp_init(lua_State* L){
    int ret;
    size_t len = 0;
    luat_tp_config_t *luat_tp_config = (luat_tp_config_t *)luat_heap_malloc(sizeof(luat_tp_config_t));
    if (luat_tp_config == NULL) {
        LLOGE("out of system memory!!!");
        return 0;
    }
    memset(luat_tp_config, 0x00, sizeof(luat_tp_config_t));
    luat_tp_config->callback = l_tp_callback;

    const char* tp_name = luaL_checklstring(L, 1, &len);
    for(int i = 0; i < 100; i++){
        if (strlen(tp_regs[i].name) == 0)
          break;
        if(strcmp(tp_regs[i].name,tp_name) == 0){
            luat_tp_config->opts = tp_regs[i].luat_tp_config;
            break;
        }
    }
    if (luat_tp_config->opts == NULL){
        LLOGE("tp_name:%s not found!!!", tp_name);
        return 0;
    }

	if (lua_isfunction(L, 3)) {
		lua_pushvalue(L, 3);
		luat_tp_config->luat_cb = luaL_ref(L, LUA_REGISTRYINDEX);
	}

    lua_settop(L, 2);
    lua_pushstring(L, "port");
    int port = lua_gettable(L, 2);
    if (LUA_TNUMBER == port) {
        luat_tp_config->i2c_id = luaL_checkinteger(L, -1);
    }else if(LUA_TUSERDATA == port){
        luat_tp_config->soft_i2c = (luat_ei2c_t*)lua_touserdata(L, -1);
    }else{
        LLOGE("port type error!!!");
        return 0;
    }
    lua_pop(L, 1);

    lua_pushstring(L, "pin_rst");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_tp_config->pin_rst = luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);
    lua_pushstring(L, "pin_int");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_tp_config->pin_int = luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);
    lua_pushstring(L, "w");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_tp_config->w = luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);
    lua_pushstring(L, "h");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_tp_config->h = luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);
    lua_pushstring(L, "refresh_rate");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_tp_config->refresh_rate = luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);
    lua_pushstring(L, "int_type");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_tp_config->int_type = luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);
    lua_pushstring(L, "tp_num");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_tp_config->tp_num = luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);

    ret = luat_tp_init(luat_tp_config);
    if (ret){
        // luat_tp_deinit(luat_tp_config);
        return 0;
    }else{
        lua_pushlightuserdata(L, luat_tp_config);
        return 1;
    }
}



#include "rotable2.h"

static const rotable_Reg_t reg_tp[] =
{
	{ "init",	    ROREG_FUNC(l_tp_init)},

    { "RISING",     ROREG_INT(LUAT_GPIO_RISING_IRQ)},
    { "FALLING",    ROREG_INT(LUAT_GPIO_FALLING_IRQ)},
	{ NULL,         ROREG_INT(0) }
};

LUAMOD_API int luaopen_tp(lua_State *L)
{
    luat_newlib2(L, reg_tp);
    return 1;
}


