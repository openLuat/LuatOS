
/*
@module  log
@summary 日志库
@version 1.0
@date    2020.03.30
@tag LUAT_USE_GPIO
*/
#include "luat_base.h"
#include "luat_sys.h"
#include "luat_msgbus.h"
#include "luat_zbuff.h"
#include "ldebug.h"
#include "luat_rtos.h"
#define LUAT_LOG_TAG "log"
#include "luat_log.h"
typedef struct luat_log_conf
{
    uint8_t style;

}luat_log_conf_t;

#define LOG_STYLE_NORMAL        0
#define LOG_STYLE_DEBUG_INFO    1
#define LOG_STYLE_FULL          2

static luat_log_conf_t lconf = {
    .style=0
};

static int add_debug_info(lua_State *L, uint8_t pos, const char* LEVEL) {
    lua_Debug ar;
    // int arg;
    // int d = 0;
    // // 查找当前stack的深度
    // while (lua_getstack(L, d, &ar) != 0) {
    //     d++;
    // }
    // // 防御一下, 不太可能直接d==0都失败
    // if (d == 0)
    //     return 0;
    // 获取真正的stack位置信息
    if (!lua_getstack(L, 1, &ar))
        return 0;
    // S包含源码, l包含当前行号
    if (0 == lua_getinfo(L, "Sl", &ar))
        return 0;
    // 没有调试信息就跳过了
    if (ar.source == NULL)
        return 0;
    int line = ar.currentline > 64*1024 ? 0 : ar.currentline;
    // 推入文件名和行号, 注意: 源码路径的第一个字符是标识,需要跳过
    if (LEVEL)
        lua_pushfstring(L, "%s/%s:%d", LEVEL, ar.source + 1, line);
    else
        lua_pushfstring(L, "%s:%d", ar.source + 1, line);
    if (lua_gettop(L) > pos)
        lua_insert(L, pos);
    return 1;
}

/*
设置日志级别
@api   log.setLevel(level)
@string  level 日志级别,可用字符串或数值, 字符串为(SILENT,DEBUG,INFO,WARN,ERROR,FATAL), 数值为(0,1,2,3,4,5)
@return nil 无返回值
@usage
-- 设置日志级别为INFO
log.setLevel("INFO")
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

/*
设置日志风格
@api log.style(val)
@int 日志风格,默认为0, 不传就是获取当前值
@return int 当前的日志风格
@usage
-- 以 log.info("ABC", "DEF", 123) 为例, 假设该代码位于main.lua的12行
-- 默认日志0
-- I/user.ABC DEF 123
-- 调试风格1, 添加额外的调试信息
-- I/main.lua:12 ABC DEF 123
-- 调试风格2, 添加额外的调试信息, 位置有所区别
-- I/user.ABC main.lua:12 DEF 123

log.style(0) -- 默认风格0
log.style(1) -- 调试风格1
log.style(2) -- 调试风格2
 */
static int l_log_style(lua_State *L) {
    if (lua_isinteger(L, 1))
        lconf.style = luaL_checkinteger(L, 1);
    lua_pushinteger(L, lconf.style);
    return 1;
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

static int l_log_2_log(lua_State *L, const char* LEVEL) {
    // 是不是什么都不传呀?
    int argc = lua_gettop(L);
    if (argc < 1) {
        // 最起码传1个参数
        return 0;
    }
    if (lconf.style == LOG_STYLE_NORMAL) {
        lua_pushfstring(L, "%s/user.%s", LEVEL, lua_tostring(L, 1));
        lua_remove(L, 1); // remove tag
        lua_insert(L, 1);
    }
    else if (lconf.style == LOG_STYLE_DEBUG_INFO) {
        add_debug_info(L, 1, LEVEL);
    }
    else if (lconf.style == LOG_STYLE_FULL) {
        lua_pushfstring(L, "%s/user.%s", LEVEL, lua_tostring(L, 1));
        lua_remove(L, 1); // remove tag
        lua_insert(L, 1);
        add_debug_info(L, 2, NULL);
    }
    lua_getglobal(L, "print");
    lua_insert(L, 1);
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
    return l_log_2_log(L, "D");
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
    return l_log_2_log(L, "I");
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
    return l_log_2_log(L, "W");
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
    return l_log_2_log(L, "E");
}

#include "rotable2.h"
static const rotable_Reg_t reg_log[] =
{
    { "debug" ,     ROREG_FUNC(l_log_debug)},
    { "info" ,      ROREG_FUNC(l_log_info)},
    { "warn" ,      ROREG_FUNC(l_log_warn)},
    { "error" ,     ROREG_FUNC(l_log_error)},
    { "fatal" ,     ROREG_FUNC(l_log_error)}, // 以error对待
    { "setLevel" ,  ROREG_FUNC(l_log_set_level)},
    { "getLevel" ,  ROREG_FUNC(l_log_get_level)},
    { "style",      ROREG_FUNC(l_log_style)},
    //{ "_log" ,      ROREG_FUNC(l_log_2_log)},


    //@const LOG_SILENT number 无日志模式
    { "LOG_SILENT", ROREG_INT(LUAT_LOG_CLOSE)},
    //@const LOG_DEBUG number debug日志模式
    { "LOG_DEBUG",  ROREG_INT(LUAT_LOG_DEBUG)},
    //@const LOG_INFO number info日志模式
    { "LOG_INFO",   ROREG_INT(LUAT_LOG_INFO)},
    //@const LOG_WARN number warning日志模式
    { "LOG_WARN",   ROREG_INT(LUAT_LOG_WARN)},
    //@const LOG_ERROR number error日志模式
    { "LOG_ERROR",  ROREG_INT(LUAT_LOG_ERROR)},
	{ NULL,         ROREG_INT(0) }
};

LUAMOD_API int luaopen_log( lua_State *L ) {
    luat_newlib2(L, reg_log);
    return 1;
}

void luat_log_dump(const char* tag, void* ptr, size_t len) {
    if (ptr == NULL) {
        luat_log_log(LUAT_LOG_DEBUG, tag, "ptr is NULL");
        return;
    }
    if (len == 0) {
        luat_log_log(LUAT_LOG_DEBUG, tag, "ptr len is 0");
        return;
    }
    char buff[256] = {0};
    uint8_t* ptr2 = (uint8_t*)ptr;
    for (size_t i = 0; i < len; i++)
    {
        sprintf_(buff + strlen(buff), "%02X ", ptr2[i]);
        if (i % 8 == 7) {
            luat_log_log(LUAT_LOG_DEBUG, tag, "%s", buff);
            buff[0] = 0;
        }
    }
    if (strlen(buff)) {
        luat_log_log(LUAT_LOG_DEBUG, tag, "%s", buff);
    }
}
