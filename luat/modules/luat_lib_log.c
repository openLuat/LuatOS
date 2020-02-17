
#include "luat_base.h"
#include "luat_log.h"
#include "luat_sys.h"
#include "luat_msgbus.h"

static int LOG_LEVEL = 1;

#define L_SILENT 0
#define L_DEBUG 1
#define L_INFO 2
#define L_WARN 3
#define L_ERROR 4
#define L_FATAL 5

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
    if (lua_isinteger(L, 1)) {
        LOG_LEVEL = lua_tointeger(L, 1);
    }
    else if (lua_isstring(L, 1)) {
        const char* lv = lua_tostring(L, 1);
        if (strcmp("SILENT", lv) == 0) {
            LOG_LEVEL = L_SILENT;
        }
        else if (strcmp("DEBUG", lv) == 0) {
            LOG_LEVEL = L_DEBUG;
        }
        else if (strcmp("INFO", lv) == 0) {
            LOG_LEVEL = L_INFO;
        }
        else if (strcmp("WARN", lv) == 0) {
            LOG_LEVEL = L_WARN;
        }
        else if (strcmp("ERROR", lv) == 0) {
            LOG_LEVEL = L_ERROR;
        }
        else if (strcmp("FATAL", lv) == 0) {
            LOG_LEVEL = L_FATAL;
        }
    }
    return 0;
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
    lua_pushfstring(L, "%s/%s", lua_tostring(L, 2), lua_tostring(L, 3));
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
    if (LOG_LEVEL > L_DEBUG)
        return 0;
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
    if (LOG_LEVEL > L_INFO)
        return 0;
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
    if (LOG_LEVEL > L_WARN)
        return 0;
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
    if (LOG_LEVEL > L_ERROR)
        return 0;
    lua_pushstring(L, "E");
    lua_insert(L, 1);
    return l_log_2_log(L);
}

/*
@api    log.fatal   输出日志,级别fatal
@param  tag         日志标识,必须是字符串
@param  ...         需打印的参数
@return nil
@usage  log.fatal("onenet", "connect fail") 日志输出 F/onenet connect fail
*/
static int l_log_fatal(lua_State *L) {
    if (LOG_LEVEL > L_FATAL)
        return 0;
    lua_pushstring(L, "F");
    lua_insert(L, 1);
    return l_log_2_log(L);
}

#include "rotable.h"
static const rotable_Reg reg_log[] =
{
    { "setLevel" , l_log_set_level, 0},
    { "debug" , l_log_debug, 0},
    { "info" , l_log_info, 0},
    { "warn" , l_log_warn, 0},
    { "error" , l_log_error, 0},
    { "fatal" , l_log_fatal, 0},
    { "_log" , l_log_2_log, 0},

    // { "LOG_SILENT", NULL, 0},
    // { "LOG_DEBUG", NULL, 1},
    // { "LOG_INFO", NULL, 2},
    // { "LOG_WARN", NULL, 3},
    // { "LOG_ERROR", NULL, 4},
    // { "LOG_FATAL", NULL, 5},
	{ NULL, NULL }
};

LUAMOD_API int luaopen_log( lua_State *L ) {
    rotable_newlib(L, reg_log);
    return 1;
}
