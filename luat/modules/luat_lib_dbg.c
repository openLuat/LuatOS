
#include "luat_base.h"
#ifdef LUAT_USE_DBG
#include "luat_timer.h"
#include "luat_mem.h"
#include "luat_dbg.h"
#ifdef LUAT_USE_SHELL
#include "luat_cmux.h"
extern luat_cmux_t cmux_ctx;
#endif

#define LUAT_LOG_TAG "dbg"
#include "luat_log.h"
#include "cJSON.h"

/**
 * 0 , disabled
 * 1 , wait for connect
 * 2 , configure complete, idle
 * 3 , stoped by breakpoint/stepNext/stepIn/stepOut
 * 4 , wait for step next
 * 5 , wait for step in
 */
static int cur_hook_state = 0;
// static int cur_run_state = 0;
static lua_State *dbg_L = NULL;
static lua_Debug *dbg_ar = NULL;
static line_bp_t breakpoints[BP_LINE_COUNT] = {0};
static char last_source[BP_SOURCE_LEN] = {0};
static uint16_t last_level = 0;

static luat_dbg_cb runcb = NULL;
static void* runcb_params = NULL;

// 如果其他平台有更特殊的输出方式, 定义luat_dbg_output方法吧
// TODO 写入cmux通道
// #ifndef luat_dbg_output
// #define luat_dbg_output LLOGD
// #endif
#define DBGLOG_SIZE 1024
static char dbg_printf_buff[DBGLOG_SIZE]  = {0};

void luat_dbg_output(const char* _fmt, ...) {
    int len;
    va_list args;
    va_start(args, _fmt);
    len = vsnprintf_(dbg_printf_buff, DBGLOG_SIZE, _fmt, args);
    va_end(args);
    if (len > 0) {
#ifdef LUAT_USE_SHELL
        if (cmux_ctx.state == 1 && cmux_ctx.dbg_state ==1){
            luat_cmux_write(LUAT_CMUX_CH_DBG,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,dbg_printf_buff, len);
        }else
#endif
        luat_log_write(dbg_printf_buff, len);
    }
}

void luat_dbg_set_runcb(luat_dbg_cb cb, void* params) {
    runcb_params = params;
    runcb = cb;
}

static size_t get_current_level(void) {
    size_t i = 1;
    for (; i < 100; i++)
    {
        if (lua_getstack(dbg_L, i, dbg_ar) == 0) {
            i--;
            break;
        }
    }
    if (i != 0)
        lua_getstack(dbg_L, 0, dbg_ar);
    return i;
}


static void record_last_stop(void) {
    // 首先, 确保dbg_ar正确
    //lua_getstack(dbg_L, 0, dbg_ar);
    // 重新获取一次信息
    //lua_getinfo(dbg_L, "Sl", dbg_ar);

    memcpy(last_source, dbg_ar->short_src, strlen(dbg_ar->short_src) > 15 ? 15 : strlen(dbg_ar->short_src));
    last_source[BP_SOURCE_LEN - 1] = 0x00;
    last_level = get_current_level();
}


// 设置钩子的状态
void luat_dbg_set_hook_state(int state) {
    if (state == 3)
        record_last_stop();
    luat_dbg_output("D/dbg [state,changed,%d,%d]\r\n", cur_hook_state, state);
    cur_hook_state = state;
}

// 获取钩子的状态
int luat_dbg_get_hook_state(void) {
    return cur_hook_state;
}

// 添加断点信息
void luat_dbg_breakpoint_add(const char* source, int linenumber) {
    for (size_t i = 0; i < BP_LINE_COUNT; i++)
    {
        if (breakpoints[i].source[0] == 0) {
            luat_dbg_output("D/dbg [resp,break,add,ok] %s:%d -> %d\r\n", source, linenumber, i);
            breakpoints[i].linenumber = linenumber;
            memcpy(breakpoints[i].source, source, strlen(source)+1);
            return;
        }
    }
    luat_dbg_output("D/dbg [resp,break,add,fail] %s:%d\r\n", source, linenumber);
}

// 删除断点信息
void luat_dbg_breakpoint_del(size_t index) {
    if (index < BP_LINE_COUNT) {
        if (breakpoints[index].source[0] != 0) {
            luat_dbg_output("D/dbg [resp,break,del,ok] %s:%d -> %d\r\n", breakpoints[index].source, breakpoints[index].linenumber, index);
            breakpoints[index].source[0] = 0x00;
            return;
        }
    }
    luat_dbg_output("D/dbg [resp,break,del,fail] %d\r\n", index);
}

// 清除断点信息
void luat_dbg_breakpoint_clear(const char* source) {
    for (size_t i = 0; i < BP_LINE_COUNT; i++)
    {
        if (source == NULL || strcmp(source, (char*)breakpoints[i].source) != 0) {
            breakpoints[i].source[0] = 0;
            breakpoints[i].linenumber = 0;
        }
    }
    luat_dbg_output("D/dbg [resp,break,clear,ok]\r\n");
}


// 打印单个深度的堆栈信息
static int luat_dbg_backtrace_print(lua_State *L, lua_Debug *ar, int level) {
    //luat_dbg_output("bt >>> %d", deep);
    int ret = lua_getstack(L, level, ar);
    if (ret == 1) {
        lua_getinfo(L, "Sl", ar);
        // resp,stack,线程号,深度
        luat_dbg_output("D/dbg [resp,stack,1,%d] %s:%d\r\n", level, ar->short_src, ar->currentline);
    }
    else {
        luat_dbg_output("D/dbg [resp,stack,1,-1] -\r\n");
    }
    return ret;
}

// 打印指定深度或者全部堆栈信息
void luat_dbg_backtrace(void *params) {
    if (dbg_L == NULL || dbg_ar == NULL) return;
    int level = (int)params;
    int ret = 0;
    if (level == -1) {
        for (size_t i = 0; i < 20; i++)
        {
            ret = luat_dbg_backtrace_print(dbg_L, dbg_ar, i);
            if (ret == 0) {
                break;
            }
        }
    }
    else {
        luat_dbg_backtrace_print(dbg_L, dbg_ar, level);
    }
    
    if (level != 0) {
        lua_getstack(dbg_L, 0, dbg_ar);
        lua_getinfo(dbg_L, "Sl", dbg_ar);
    }
}

//-------------------
// TODO 将栈顶的元素转为dbg协议所需要的json字符串形式
// 鉴于mcu的内存有限, 需要限制最大深度
// 可能要引入cjson(非lua-cjson)来配好, 走sys内存
static int value_to_dbg_json(lua_State* L, const char* name, char** buff, size_t *len, int max_deep) {
    int ltype = lua_type(L, -1);
    if (ltype == -1)
        return -1;
#ifdef LUAT_USE_DBG
    cJSON *cj = cJSON_CreateObject();

    cJSON_AddStringToObject(cj, "name", name);
    cJSON_AddStringToObject(cj, "type", lua_typename(L, lua_type(L,-1)));

    switch (ltype)
    {
    case LUA_TNIL:
        cJSON_AddNullToObject(cj, "data");
        break;
    case LUA_TBOOLEAN:
        cJSON_AddBoolToObject(cj, "data", lua_toboolean(L, -1));
        break;
    case LUA_TNUMBER:
        cJSON_AddStringToObject(cj, "data", lua_tostring(L, -1));
        break;
    case LUA_TTABLE:
        // TODO 递归之
        cJSON_AddStringToObject(cj, "data", lua_tostring(L, -1));
        break;
    case LUA_TSTRING:
    case LUA_TLIGHTUSERDATA:
    case LUA_TUSERDATA:
    case LUA_TFUNCTION:
    case LUA_TTHREAD:
    default:
        cJSON_AddStringToObject(cj, "data", lua_tostring(L, -1));
        break;
    }
    char* str = cJSON_Print(cj);
    size_t slen = strlen(str);
    *buff = luat_heap_malloc(slen+1);
    if (*buff == NULL)
        return -2;
    memcpy(*buff, str, slen+1);
    cJSON_Delete(cj);
    return 0;
#else
    return -1;
#endif
}
//-------------------

void luat_dbg_vars(void *params) {
    if (dbg_L == NULL || dbg_ar == NULL) return;
    
    int level = (int)params;

    if (lua_getstack(dbg_L, level, dbg_ar) == 1) {
        int index = 1;
        //int valtype = 0;
        char *buff = NULL;
        int ret;
        size_t valstrlen = 0;
        //size_t valoutlen = 0;
        while (1) {
            const char* varname = lua_getlocal(dbg_L, dbg_ar, index);
            if (varname) {
                if(strcmp(varname,"(*temporary)") == 0)
                {
                    break;
                }
                ret = value_to_dbg_json(dbg_L, varname, &buff, &valstrlen, 10);
                // 索引号,变量名,变量类型,值的字符串长度, 值的字符串形式
                // TODO LuatIDE把这里改成了json输出, 需要改造一下
                // 构建个table,然后json.encode?
                if (ret == 0 && (strcmp(buff,"\x0e") != 0))
                    luat_dbg_output("D/dbg [resp,vars,%d]\r\n%s\r\n", strlen(buff), buff);
                lua_pop(dbg_L, 1);
            }
            else {
                break;
            }
            index ++;
        }
        luat_dbg_output("D/dbg [resp,vars,0]\r\n");
    }
    // 还原Debug_ar的数据
    if (level != 0) {
        lua_getstack(dbg_L, 0, dbg_ar);
    }
}

void luat_dbg_gvars(void *params) {
    lua_pushglobaltable(dbg_L);
    lua_pushnil(dbg_L);
    char buff[128];
    size_t len;
    const char* varname = NULL;
    const char* vartype = NULL;
    const char* vardata = NULL;
    while (lua_next(dbg_L, -2) != 0) {
       if (lua_isstring(dbg_L, -2)) {
           varname = luaL_checkstring(dbg_L, -2);
           vartype = lua_typename(dbg_L, lua_type(dbg_L, -1));
           vardata = lua_tostring(dbg_L, -1);
           if(strcmp(vardata,"\x0e") != 0)
            {
                len = snprintf(buff, 127, "{\"type\":\"%s\", \"name\":\"%s\", \"data\":\"%s\"}", vartype, varname, vardata);
                luat_dbg_output("D/dbg [resp,gvars,%d]\r\n%s\r\n", len, buff);
            }
       }
       lua_pop(dbg_L, 1);
    }
    luat_dbg_output("D/dbg [resp,gvars,0]\r\n");
    lua_pop(dbg_L, 1); // 把_G弹出去
}

void luat_dbg_jvars(void *params) {
    size_t valstrlen = 0;
    char* buff = NULL;
    size_t top = 0;

    top = lua_gettop(dbg_L);
    const char* varname = (const char*)params;

    //lua_pushglobaltable(dbg_L);
    //lua_pushstring(dbg_L, (const char*)params);
    lua_getglobal(dbg_L, varname);
    int ret = value_to_dbg_json(dbg_L, varname, &buff, &valstrlen, 10);
    if (ret == 0)
        luat_dbg_output("D/dbg [resp,jvars,%d]\r\n%s\r\n", valstrlen, buff);
    //luat_dbg_output("D/dbg [resp,jvars,%d]\r\n%s\r\n", len, value);
    //lua_pop(dbg_L, 1); // 弹出栈顶的元素,减少内存
    
    luat_dbg_output("D/dbg [resp,jvars,0]\r\n");
    lua_settop(dbg_L, top); // 把栈还原
}

// 等待钩子状态变化
static void luat_dbg_waitby(int origin) {
    while (cur_hook_state == origin) {
        if (runcb != NULL) {
            runcb(runcb_params);
            runcb = NULL;
        }
        luat_timer_mdelay(5);
    }
}

// 供Lua VM调用的钩子函数
void luat_debug_hook(lua_State *L, lua_Debug *ar) {
    // luat_dbg_output("D/dbg [state][print] event:%d | short_src: %s | line:%d | currentState:%d | currentHookState:%d\r\n", ar->event, ar->short_src, ar->currentline, cur_hook_state, cur_hook_state);

    if (cur_hook_state == 0) {
        return; // hook 已经关掉了哦
    }
    
    dbg_L = L;
    dbg_ar = ar;

    lua_getinfo(L, "Sl", ar);



    // 不是lua文件, 就没调试价值
    if (ar->source[0] != '@') {
        return;
    }

    if (cur_hook_state == 1) {
        LLOGE("check state == 1 ? BUG?");
        return; // 不会是这种状态呀
    }

    //if (cur_hook_state == 2) {
        // 当前执行到行, 那肯定要检查是不是断点呀
        if (ar->event == LUA_HOOKLINE)
        {
            // 当前文件名
            for (size_t i = 0; i < BP_LINE_COUNT; i++)
            {
                // 对比行数
                if (breakpoints[i].linenumber != ar->currentline) {
                    continue;
                }
                // 那文件名呢?
                //luat_dbg_output("check breakpoint %s %d <==> %s %d", breakpoints[i].source, breakpoints[i].linenumber, ar->source, ar->currentline);
                //luat_dbg_output("check breakpoint %c %c %c", breakpoints[i].source[0], ar->source[0], ar->source[1]);
                if (
                    strcmp(breakpoints[i].source, ar->short_src + 0) != 0 && 
                    strcmp(breakpoints[i].source, ar->short_src + 1) != 0 &&
                    strcmp(breakpoints[i].source, ar->short_src + 2) != 0 &&
                    strcmp(breakpoints[i].source, ar->short_src + 7) != 0
                    ) {
                    continue;
                }
                // 命中了!!!!
                luat_dbg_output("D/dbg [event,stopped,breakpoint] %s:%d\r\n", ar->short_src, ar->currentline);
                luat_dbg_set_hook_state(3); // 停止住
                //send_msg(event_breakpoint_stop)
                luat_dbg_waitby(3);
                return;
            }
        }
        //return;
    //}

    // stepOver == next    level 相同或减少, source相同(level相同时)
    // stepIn        任何情况, 遇到HOOKLINE就算
    // stepOver      level减少, 除非level=0
    if (cur_hook_state == 4) {
        if (ar->event == LUA_HOOKLINE) {
            int current_level = get_current_level();
            if (last_level > current_level || (last_level == current_level && !strcmp(ar->short_src, last_source))) {
                //send_msg(event_stepover_stop)
                luat_dbg_output("D/dbg [event,stopped,step] %s:%d\r\n", ar->short_src, ar->currentline);
                luat_dbg_set_hook_state(3); // 停止住
                luat_dbg_waitby(3);
            }
        }
    }
    else if (cur_hook_state == 5) {
        if (ar->event == LUA_HOOKLINE) {
            //send_msg(event_stepover_stop)
            luat_dbg_output("D/dbg [event,stopped,stepIn] %s:%d\r\n", ar->short_src, ar->currentline);
            luat_dbg_set_hook_state(3); // 停止住
            luat_dbg_waitby(3);
        }
    }
    else if (cur_hook_state == 6) {
        if (ar->event == LUA_HOOKLINE) {
            int current_level = get_current_level();
            if (last_level == 0 || last_level > current_level) {
                luat_dbg_output("D/dbg [event,stopped,stepOut] %s:%d\r\n", ar->short_src, ar->currentline);
                luat_dbg_set_hook_state(3); // 停止住
                luat_dbg_waitby(3);
            }
        }
    }

    return;
}

/**
 * 等待调试器进入
 * @api dbg.wait(timeout)
 * @int 超时秒数,默认5,单位秒, 最大值当前为5.
 * @return nil 无返回值
 * 
*/
int l_debug_wait(lua_State *L) {
    if (cur_hook_state == 0) {
        // luat_dbg_output("setup hook for debgger\r\n");
        lua_sethook(L, luat_debug_hook, LUA_MASKCALL | LUA_MASKRET | LUA_MASKLINE, 0);
        luat_dbg_set_hook_state(1);
        int timeout = luaL_optinteger(L, 1, 5) * 1000;
        if (timeout > 5000)
            timeout = 5000;
        int t = 0;
        while (timeout > 0 && cur_hook_state == 1) {
            timeout -= 10;
            luat_timer_mdelay(10);
            if ((t*10)%1000 == 0) {
                luat_dbg_output("D/dbg [event,waitc] waiting for debugger\r\n");
            }
            t++;
        }
        if (cur_hook_state == 1) {
            luat_dbg_output("D/dbg [event,waitt] timeout!!!!\r\n");
            luat_dbg_set_hook_state(0);
        }
    }
    else {
        LLOGD("debugger is running, only one wait is allow!!!\r\n");
    }
    return 0;
}

/**
 * 结束调试,一般不需要调用
 * @api dbg.close()
 * @return nil 无返回值
 * 
*/
int l_debug_close(lua_State *L) {
    luat_dbg_set_hook_state(0);
    lua_sethook(L, NULL, 0, 0);
    return 0;
}

int luat_dbg_init(lua_State *L) {
    lua_sethook(L, luat_debug_hook, LUA_MASKCALL | LUA_MASKRET | LUA_MASKLINE, 0);
    if (dbg_L == NULL)
        dbg_L = L;
    return 0;
}

#ifdef LUAT_USE_SHELL
// 供dbg_init.lua判断cmux状态
int l_debug_cmux_state(lua_State *L) {
    lua_pushinteger(L, cmux_ctx.state);
    lua_pushinteger(L, cmux_ctx.dbg_state);
    return 2;
}
#endif

#include "rotable2.h"
static const rotable_Reg_t reg_dbg[] =
{
	{ "wait",  ROREG_FUNC(l_debug_wait)},
    { "close", ROREG_FUNC(l_debug_close)},
    { "stop",  ROREG_FUNC(l_debug_close)},
#ifdef LUAT_USE_SHELL
    { "cmux_state", ROREG_FUNC(l_debug_cmux_state)},
#endif
	{ NULL,     ROREG_INT(0)}
};

LUAMOD_API int luaopen_dbg( lua_State *L ) {
    luat_newlib2(L, reg_dbg);
    return 1;
}
#endif

