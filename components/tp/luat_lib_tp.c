#include "luat_base.h"
#include "luat_tp.h"

#define LUAT_LOG_TAG "tp"
#include "luat_log.h"

// tp.init(ic_name,{port,pin_rst,pin_int,w,h,int_type,})
// local softI2C = i2c.createSoft(20, 21)
// tp.init("gt911",{port=softI2C,pin_rst = 22,pin_int = 23,w = 320,h = 480})
// tp.init("gt911",{port=0,pin_rst = 22,pin_int = 23,w = 320,h = 480})
typedef struct tp_reg {
    const char *name;
    const luat_tp_config_t *luat_tp_config;
  }tp_reg_t;

static const tp_reg_t tp_regs[] = {
    {"gt911",  &tp_config_gt911},
    {"", NULL}
  };

static int l_tp_init(lua_State* L){
    int ret;
    size_t len = 0;
    luat_tp_config_t *luat_tp = (luat_tp_config_t *)lua_newuserdata(L, sizeof(luat_tp_config_t));
    if (luat_tp == NULL) {
        LLOGE("out of system memory!!!");
        return 0;
    }
    memset(luat_tp, 0x00, sizeof(luat_tp_config_t));
    const char* tp_name = luaL_checklstring(L, 1, &len);

    for(int i = 0; i < 100; i++){
        if (strlen(tp_regs[i].name) == 0)
          break;
        if(strcmp(tp_regs[i].name,tp_name) == 0){
            luat_tp->opts = tp_regs[i].luat_tp_config;
            break;
        }
    }

    if (luat_tp->opts == NULL){
        LLOGE("tp_name:%s not found!!!", tp_name);
        return 0;
    }
    lua_settop(L, 2);
    lua_pushstring(L, "port");
    int port = lua_gettable(L, 2);
    if (LUA_TNUMBER == port) {
        luat_tp->i2c_id = luaL_checkinteger(L, -1);
    }else if(LUA_TUSERDATA == port){
        luat_tp->soft_i2c = (luat_ei2c_t*)lua_touserdata(L, -1);
    }else{
        LLOGE("port type error!!!");
        return 0;
    }
    lua_pop(L, 1);

    lua_pushstring(L, "pin_rst");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_tp->pin_rst = luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);
    lua_pushstring(L, "pin_int");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_tp->pin_int = luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);
    lua_pushstring(L, "w");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_tp->w = luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);
    lua_pushstring(L, "h");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_tp->h = luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);
    lua_pushstring(L, "refresh_rate");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_tp->refresh_rate = luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);
    lua_pushstring(L, "int_type");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_tp->int_type = luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);
    lua_pushstring(L, "tp_num");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_tp->tp_num = luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);


    // luat_tp->i2c_id = 0,
    // luat_tp->pin_rst = gpio_rst,
    // luat_tp->pin_int = gpio_int,
    // luat_tp->soft_i2c = &soft_i2c,
    // luat_tp->w = 320,
    // luat_tp->h = 480,
    // luat_tp->refresh_rate = 20,
    // luat_tp->int_type = TP_INT_TYPE_FALLING_EDGE,
    // luat_tp->tp_num = 1,
    // luat_tp->opts = &tp_config_gt911;

    // LLOGD("l_tp_init luat_tp:%p ",luat_tp);


    ret = luat_tp_init(luat_tp);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}












#include "rotable2.h"

static const rotable_Reg_t reg_tp[] =
{
	{ "init",	    ROREG_FUNC(l_tp_init)},

    { "RISING",     ROREG_INT(TP_INT_TYPE_RISING_EDGE)},
    { "FALLING",    ROREG_INT(TP_INT_TYPE_FALLING_EDGE)},
	{ NULL,         ROREG_INT(0) }
};

LUAMOD_API int luaopen_tp(lua_State *L)
{
    luat_newlib2(L, reg_tp);
    return 1;
}


