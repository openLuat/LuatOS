
#include "luat_base.h"
#include "luat_timer.h"
#include "luat_dbg.h"

#define LUAT_LOG_TAG "dbg"
#include "luat_log.h"

/**
 * 0 , disabled
 * 1 , wait for connect
 * 2 , configure complete, idle
 * 3 , stoped by breakpoint/stepNext/stepIn/stepOut
 * 4 , wait for step next
 * 5 , wait for step in
 */
static int cur_hook_state = 0;
static int cur_run_state = 0;
static lua_State *dbg_L = NULL;
static lua_Debug *dbg_ar = NULL;
static line_bp_t breakpoints[BP_LINE_COUNT] = {0};
static char last_source[BP_SOURCE_LEN] = {0};
static uint16_t last_level = 0;

static luat_dbg_cb runcb = NULL;
static void* runcb_params = NULL;

// 如果其他平台有更特殊的输出方式, 定义luat_dbg_output方法吧
#ifndef luat_dbg_output
#define luat_dbg_output LLOGD
#endif

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
    luat_dbg_output("[state,changed,%d,%d]", cur_hook_state, state);
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
            luat_dbg_output("[resp,break,add,ok] %s:%d -> %d", source, linenumber, i);
            breakpoints[i].linenumber = linenumber;
            memcpy(breakpoints[i].source, source, strlen(source)+1);
            return;
        }
    }
    luat_dbg_output("[resp,break,add,fail] %s:%d", source, linenumber);
}

// 删除断点信息
void luat_dbg_breakpoint_del(size_t index) {
    if (index < BP_LINE_COUNT) {
        if (breakpoints[index].source[0] != 0) {
            luat_dbg_output("[resp,break,del,ok] %s:%d -> %d", breakpoints[index].source, breakpoints[index].linenumber, index);
            breakpoints[index].source[0] = 0x00;
            return;
        }
    }
    luat_dbg_output("[resp,break,del,fail] %d'", index);
}

// 清除断点信息
void luat_dbg_breakpoint_clear(const char* source) {
    for (size_t i = 0; i < BP_LINE_COUNT; i++)
    {
        if (source == NULL || strcmp(source, (const char*)breakpoints[i].source[0]) != 0) {
            breakpoints[i].source[0] = 0;
        }
    }
    luat_dbg_output("[resp,break,clear,ok]");
}


// 打印单个深度的堆栈信息
static int luat_dbg_backtrace_print(lua_State *L, lua_Debug *ar, int level) {
    //luat_dbg_output("bt >>> %d", deep);
    int ret = lua_getstack(L, level, ar);
    if (ret == 1) {
        lua_getinfo(L, "Sl", ar);
        // resp,stack,线程号,深度
        luat_dbg_output("[resp,stack,1,%d] %s:%d", level, ar->short_src, ar->currentline);
    }
    else {
        luat_dbg_output("[resp,stack,1,-1] -");
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

void luat_dbg_vars(void *params) {
    if (dbg_L == NULL || dbg_ar == NULL) return;
    
    int level = (int)params;

    if (lua_getstack(dbg_L, level, dbg_ar) == 1) {
        int index = 1;
        int valtype = 0;
        char buff[128] = {0};
        size_t valstrlen = 0;
        size_t valoutlen = 0;
        while (1) {
            const char* varname = lua_getlocal(dbg_L, dbg_ar, index);
            if (varname) {
                valtype = lua_type(dbg_L, -1);
                const char* valstr = lua_tolstring(dbg_L, -1, &valstrlen);
                valoutlen = valstrlen > 127 ? 127 : valstrlen;
                memcpy(buff, valstr, valoutlen);
                buff[valoutlen] = 0x00;
                // 索引号,变量名,变量类型,值的字符串长度, 值的字符串形式
                luat_dbg_output("[resp,vars,1,%d] %s %d %d %s", index, varname, valtype, valoutlen, buff);
                lua_pop(dbg_L, 1);
            }
            else {
                break;
            }
            index ++;
        }
        luat_dbg_output("[resp,vars,1,-1]");
    }
    // 还原Debug_ar的数据
    if (level != 0) {
        lua_getstack(dbg_L, 0, dbg_ar);
    }
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
    if (cur_hook_state == 0) {
        return; // hook 已经关掉了哦
    }
    
    dbg_L = L;
    dbg_ar = ar;

    lua_getinfo(L, "Sl", ar);

    //luat_dbg_output("[state][print] event:%d | short_src: %s | line:%d | currentState:%d | currentHookState:%d", ar->event, ar->short_src, ar->currentline, cur_run_state, cur_hook_state);

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
                // 文件名对上了, 那行数呢?
                //luat_dbg_output("check breakpoint %s %d <==> %s %d", breakpoints[i].source, breakpoints[i].linenumber, ar->source, ar->currentline);
                if (strcmp(breakpoints[i].source, ar->short_src))
                    continue;
                for (size_t j = 0; j < BP_LINE_COUNT; j++)
                {
                    if (breakpoints[i].linenumber != ar->currentline) {
                        continue;
                    }
                    // 命中了!!!!
                    luat_dbg_output("[event,stopped,breakpoint] %s:%d", ar->short_src, ar->currentline);
                    luat_dbg_set_hook_state(3); // 停止住
                    //send_msg(event_breakpoint_stop)
                    luat_dbg_waitby(3);
                    return;
                }
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
                luat_dbg_output("[event,stopped,step] %s:%d", ar->short_src, ar->currentline);
                luat_dbg_set_hook_state(3); // 停止住
                luat_dbg_waitby(3);
            }
        }
    }
    else if (cur_hook_state == 5) {
        if (ar->event == LUA_HOOKLINE) {
            //send_msg(event_stepover_stop)
            luat_dbg_output("[event,stopped,stepIn] %s:%d", ar->short_src, ar->currentline);
            luat_dbg_set_hook_state(3); // 停止住
            luat_dbg_waitby(3);
        }
    }
    else if (cur_hook_state == 6) {
        if (ar->event == LUA_HOOKLINE) {
            int current_level = get_current_level();
            if (last_level == 0 || last_level > current_level) {
                luat_dbg_output("[event,stopped,stepOut] %s:%d", ar->short_src, ar->currentline);
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
 * @int 超时秒数,默认120,即120秒
 * @return nil 无返回值
 * 
*/
int l_debug_wait(lua_State *L) {
    if (cur_hook_state == 0) {
        //luat_dbg_output("setup hook for debgger");
        lua_sethook(L, luat_debug_hook, LUA_MASKCALL | LUA_MASKRET | LUA_MASKLINE, 0);
        luat_dbg_set_hook_state(1);
        int timeout = luaL_optinteger(L, 1, 120) * 1000;
        int t = 0;
        while (timeout > 0 && cur_hook_state == 1) {
            timeout -= 5;
            luat_timer_mdelay(5);
            if ((t*5)%1000 == 0) {
                luat_dbg_output("[event,waitc] waiting for debugger");
            }
            t++;
        }
        if (cur_hook_state == 1) {
            luat_dbg_output("[event,waitt] timeout!!!!");
            luat_dbg_set_hook_state(0);
        }
    }
    else {
        luat_dbg_output("debugger is running, only one wait is allow!!!");
    }
    return 0;
}

/**
 * 结束调试,一般不需要调用
 * @api dbg.stop()
 * @return nil 无返回值
 * 
*/
int l_debug_close(lua_State *L) {
    luat_dbg_set_hook_state(0);
    lua_sethook(L, NULL, 0, 0);
    return 0;
}

#include "rotable.h"
static const rotable_Reg reg_dbg[] =
{
	{ "wait",  l_debug_wait, 0},
    { "close",  l_debug_close, 0},
	{ NULL, NULL , 0}
};

LUAMOD_API int luaopen_dbg( lua_State *L ) {
    luat_newlib(L, reg_dbg);
    return 1;
}


