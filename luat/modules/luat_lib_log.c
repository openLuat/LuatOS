
#include "luat_base.h"
#include "luat_log.h"
#include "luat_sys.h"
#include "luat_msgbus.h"

/*
@module log 日志 
@since 1.0.0
*/

/*
@api    log.setLevel 设置日志级别
@param  level        日志级别,可用字符串或数值, 字符串为(SILENT,DEBUG,INFO,WARN,ERROR,FATAL), 数值为(0,1,2,3,4,5)
@return nil
@usage  log.setLevel("INFO") 设置日志级别为INFO.
*/
static int l_log_set_level(lua_State *L) {
    int LOG_LEVEL = 0;
    if (lua_isinteger(L, 1)) {
        LOG_LEVEL = lua_tointeger(L, 1);
    }
    else if (lua_isstring(L, 1)) {
        const char* lv = lua_tostring(L, 1);
        if (strcmp("SILENT", lv) == 0) {
            LOG_LEVEL = LUAT_LOG_CLOSE;
        }
        else if (strcmp("DEBUG", lv) == 0) {
            LOG_LEVEL = LUAT_LOG_DEBUG;
        }
        else if (strcmp("INFO", lv) == 0) {
            LOG_LEVEL = LUAT_LOG_INFO;
        }
        else if (strcmp("WARN", lv) == 0) {
            LOG_LEVEL = LUAT_LOG_WARN;
        }
        else if (strcmp("ERROR", lv) == 0) {
            LOG_LEVEL = LUAT_LOG_ERROR;
        }
    }
    if (LOG_LEVEL == 0) {
        LOG_LEVEL = LUAT_LOG_CLOSE;
    }
    luat_log_set_level(LOG_LEVEL);
    return 0;
}

int l_log_get_level(lua_State *L) {
    lua_pushinteger(L, luat_log_get_level());
    return 1;
}

static int l_log_2_log(lua_State *L) {
    // 是不是什么都不传呀?
    int argc = lua_gettop(L);
    if (argc < 2) {
        // 最起码传2个参数
        return 0;
    }
    lua_getglobal(L, "print");
    lua_insert(L, 1);
    lua_pushfstring(L, "%s/user.%s", lua_tostring(L, 2), lua_tostring(L, 3));
    lua_remove(L, 2); // remove level
    lua_remove(L, 2); // remove tag
    lua_insert(L, 2);
    lua_call(L, argc - 1, 0);
    return 0;
}

/*
@api    log.debug   输出日志,级别debug
@param  tag         日志标识,必须是字符串
@param  ...         需打印的参数
@return nil
@usage  log.debug("onenet", "connect ok") 日志输出 D/onenet connect ok
*/
static int l_log_debug(lua_State *L) {
    if (luat_log_get_level() > LUAT_LOG_DEBUG) return 0;
    lua_pushstring(L, "D");
    lua_insert(L, 1);
    return l_log_2_log(L);
}

/*
@api    log.info   输出日志,级别info
@param  tag         日志标识,必须是字符串
@param  ...         需打印的参数
@return nil
@usage  log.info("onenet", "connect ok") 日志输出 I/onenet connect ok
*/
static int l_log_info(lua_State *L) {
    if (luat_log_get_level() > LUAT_LOG_INFO) return 0;
    lua_pushstring(L,"I");
    lua_insert(L, 1);
    return l_log_2_log(L);
}

/*
@api    log.warn   输出日志,级别warn
@param  tag         日志标识,必须是字符串
@param  ...         需打印的参数
@return nil
@usage  log.warn("onenet", "connect ok") 日志输出 W/onenet connect ok
*/
static int l_log_warn(lua_State *L) {
    if (luat_log_get_level() > LUAT_LOG_WARN) return 0;
    lua_pushstring(L, "W");
    lua_insert(L, 1);
    return l_log_2_log(L);
}

/*
@api    log.error   输出日志,error
@param  tag         日志标识,必须是字符串
@param  ...         需打印的参数
@return nil
@usage  log.error("onenet", "connect ok") 日志输出 E/onenet connect ok
*/
static int l_log_error(lua_State *L) {
    if (luat_log_get_level() > LUAT_LOG_ERROR) return 0;
    lua_pushstring(L, "E");
    lua_insert(L, 1);
    return l_log_2_log(L);
}

#include "rotable.h"
static const rotable_Reg reg_log[] =
{
    { "setLevel" , l_log_set_level, 0},
    { "getLevel" , l_log_get_level, 0},
    { "debug" , l_log_debug, 0},
    { "info" , l_log_info, 0},
    { "warn" , l_log_warn, 0},
    { "error" , l_log_error, 0},
    { "fatal" , l_log_error, 0}, // 以error对待
    { "_log" , l_log_2_log, 0},

    { "LOG_SILENT", NULL, LUAT_LOG_CLOSE},
    { "LOG_DEBUG",  NULL, LUAT_LOG_DEBUG},
    { "LOG_INFO",   NULL, LUAT_LOG_INFO},
    { "LOG_WARN",   NULL, LUAT_LOG_WARN},
    { "LOG_ERROR",  NULL, LUAT_LOG_ERROR},
	{ NULL, NULL }
};

LUAMOD_API int luaopen_log( lua_State *L ) {
    rotable_newlib(L, reg_log);
    return 1;
}
