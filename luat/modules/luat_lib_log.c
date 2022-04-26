
/*
@module  log
@summary 日志库
@version 1.0
@date    2020.03.30
*/
#include "luat_base.h"
#include "luat_sys.h"
#include "luat_msgbus.h"

#include "ldebug.h"

#define LUAT_LOG_TAG "log"
#include "luat_log.h"

typedef struct luat_log_conf
{
    uint8_t show_taglevel;
    uint8_t show_fileline;
}luat_log_conf_t;

static luat_log_conf_t lconf = {
    .show_taglevel=1,
    .show_fileline=0
};

static int add_debug_info(lua_State *L, uint8_t pos, const char* LEVEL) {
    lua_Debug ar;
    int arg;
    int d = 0;
    // 如果没启用, 直接返回
    // if (lconf.show_fileline == 0)
    //     return;
    // 查找当前stack的深度
    while (lua_getstack(L, d, &ar) != 0) {
        d++;
    }
    // 防御一下, 不太可能直接d==0都失败
    if (d == 0)
        return 0;
    // 获取真正的stack位置信息
    if (!lua_getstack(L, d - 1, &ar))
        return 0;
    // S包含源码, l包含当前行号
    if (0 == lua_getinfo(L, "Sl", &ar))
        return 0;
    // 没有调试信息就跳过了
    if (ar.source == NULL)
        return 0;
    // 推入文件名和行号, 注意: 源码路径的第一个字符是标识,需要跳过
    if (lconf.show_taglevel == 0)
        lua_pushfstring(L, "%s/%s:%d", LEVEL, ar.source + 1, ar.currentline);
    else
        lua_pushfstring(L, "%s:%d", ar.source + 1, ar.currentline);
    if (lua_gettop(L) > pos)
        lua_insert(L, pos);
    return 1;
}

/*
设置日志级别
@api   log.setLevel(level, show_taglevel, show_fileline)
@string  level 日志级别,可用字符串或数值, 字符串为(SILENT,DEBUG,INFO,WARN,ERROR,FATAL), 数值为(0,1,2,3,4,5)
@bool 是否显示日志级别和tag, 默认为true
@bool 是否显示所在行号及行号,需调试信息,默认为false
@return nil 无返回值
@usage
-- 设置日志级别为INFO
log.setLevel("INFO")
-- 额外显示行号及文件名, 仅20220425之后的固件可配置
log.setLevel("DEBUG", true, true)
-- 只显示行号及文件名, 不限速日志级别和tag, 仅20220425之后的固件可配置
log.setLevel("DEBUG", false, true)
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

    if (lua_isboolean(L, 2))
        lconf.show_taglevel = lua_toboolean(L, 2);
    if (lua_isboolean(L, 3))
        lconf.show_fileline = lua_toboolean(L, 3);
    return 0;
}

/*
获取日志级别
@api   log.getLevel()
@return  int   日志级别对应0,1,2,3,4,5
@usage
-- 得到日志级别
log.getLevel()
*/
int l_log_get_level(lua_State *L) {
    lua_pushinteger(L, luat_log_get_level());
    return 1;
}

static int l_log_2_log(lua_State *L, const char* LEVEL, uint8_t add_debug) {
    // 是不是什么都不传呀?
    int argc = lua_gettop(L);
    if (argc < 1) {
        // 最起码传2个参数
        return 0;
    }
    lua_getglobal(L, "print");
    lua_insert(L, 1);
    uint8_t pos = 2;
    // if (add_debug && add_debug_info(L)) {
    //     pos ++;
    // };
    if (lconf.show_taglevel) {
        lua_pushfstring(L, "%s/user.%s", LEVEL, lua_tostring(L, pos));
        lua_remove(L, pos); // remove tag
        lua_insert(L, pos);
        pos ++;
    }
    else {
        lua_remove(L, pos);
    }

    if (add_debug && add_debug_info(L, pos, LEVEL)) {
        pos ++;
    };
    lua_call(L, lua_gettop(L) - 1, 0);
    return 0;
}

/*
输出日志,级别debug
@api    log.debug(tag, val, val2, val3, ...)
@string  tag         日志标识,必须是字符串
@...         需打印的参数
@return nil 无返回值
@usage
-- 日志输出 D/onenet connect ok
log.debug("onenet", "connect ok")
*/
static int l_log_debug(lua_State *L) {
    if (luat_log_get_level() > LUAT_LOG_DEBUG) return 0;
    return l_log_2_log(L, "D", lconf.show_fileline);
}

/*
输出日志,级别info
@api    log.info(tag, val, val2, val3, ...)
@string  tag         日志标识,必须是字符串
@...         需打印的参数
@return nil 无返回值
@usage
-- 日志输出 I/onenet connect ok
log.info("onenet", "connect ok")
*/
static int l_log_info(lua_State *L) {
    if (luat_log_get_level() > LUAT_LOG_INFO) return 0;
    return l_log_2_log(L, "I", lconf.show_fileline);
}

/*
输出日志,级别warn
@api    log.warn(tag, val, val2, val3, ...)
@string  tag         日志标识,必须是字符串
@...         需打印的参数
@return nil 无返回值
@usage
-- 日志输出 W/onenet connect ok
log.warn("onenet", "connect ok")
*/
static int l_log_warn(lua_State *L) {
    if (luat_log_get_level() > LUAT_LOG_WARN) return 0;
    return l_log_2_log(L, "W", 1);
}

/*
输出日志,级别error
@api    log.error(tag, val, val2, val3, ...)
@string  tag         日志标识,必须是字符串
@...         需打印的参数
@return nil 无返回值
@usage
-- 日志输出 E/onenet connect ok
log.error("onenet", "connect ok")
*/
static int l_log_error(lua_State *L) {
    if (luat_log_get_level() > LUAT_LOG_ERROR) return 0;
    return l_log_2_log(L, "E", 1);
}

#include "rotable2.h"
static const rotable_Reg_t reg_log[] =
{
    { "setLevel" ,  ROREG_FUNC(l_log_set_level)},
    { "getLevel" ,  ROREG_FUNC(l_log_get_level)},
    { "debug" ,     ROREG_FUNC(l_log_debug)},
    { "info" ,      ROREG_FUNC(l_log_info)},
    { "warn" ,      ROREG_FUNC(l_log_warn)},
    { "error" ,     ROREG_FUNC(l_log_error)},
    { "fatal" ,     ROREG_FUNC(l_log_error)}, // 以error对待
    //{ "_log" ,      ROREG_FUNC(l_log_2_log)},

    { "LOG_SILENT", ROREG_INT(LUAT_LOG_CLOSE)},
    { "LOG_DEBUG",  ROREG_INT(LUAT_LOG_DEBUG)},
    { "LOG_INFO",   ROREG_INT(LUAT_LOG_INFO)},
    { "LOG_WARN",   ROREG_INT(LUAT_LOG_WARN)},
    { "LOG_ERROR",  ROREG_INT(LUAT_LOG_ERROR)},
	{ NULL,         ROREG_INT(0) }
};

LUAMOD_API int luaopen_log( lua_State *L ) {
    luat_newlib2(L, reg_log);
    return 1;
}
