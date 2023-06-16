

#include "luat_base.h"
#include "luat_shell.h"
#include "luat_malloc.h"
#include "luat_rtos.h"
#include "luat_repl.h"
#include "luat_msgbus.h"

#define LUAT_LOG_TAG "repl"
#include "luat_log.h"

static char* mulitline_buff;
static size_t mulitline_buff_size;
static size_t mulitline_buff_offset;
static int mulitline_mode;

#define luat_repl_write luat_shell_write

static const char* repl_tips = "";
static int repl_enable = 1;

int luat_repl_enable(int enable) {
    int tmp = repl_enable;
    if (enable >= 0) {
        repl_enable = enable;
    }
    return tmp;
}

void luat_repl_init(void) {
    luat_repl_write("LuatOS Ready\r\n>", strlen("LuatOS Ready\r\n>"));
}

static int report(lua_State* L) {
    size_t len = 0;
    const char *msg;
    msg = lua_tolstring(L, -1, &len);
    luat_repl_write(msg, len);
    luat_repl_write("\r\n", 2);
    lua_pop(L, 1);  /* remove message */
    return 0;
}

static int repl_handle(lua_State* L, void* ptr) {
    char* buff = (char*)ptr;
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    size_t sz = msg->arg1;

    // LLOGD("REPL-- %.*s --", sz, buff);

    int ret = luaL_loadbuffer(L, buff, sz, "repl");
    luat_heap_free(ptr);
    if (ret != LUA_OK) {
        // LLOGD("加载出错,语法问题? %d", ret);
        report(L);
        return 0;
    }
    // lua_pushcfunction(L, l_err);
    // lua_pushvalue(L, -2);
    ret = lua_pcall(L, 0, 0, 0);
    if (ret < LUA_OK) {
        // LLOGD("执行出错 %d", ret);
        report(L);
        return 0;
    }
    return 0;
}

static int find2run(void) {
    // LLOGD("find2run %p %d %d", mulitline_buff, mulitline_buff_size, mulitline_buff_offset);
    if (mulitline_buff == NULL)
        return 1;
    size_t i = 0;
    for (; i < mulitline_buff_offset; i++)
    {
        if (mulitline_buff[i] == '\r' || mulitline_buff[i] == '\n') {
            continue;
        }
        break;
    }
    // LLOGD("=================================");
    if (i > 0) { // 有空白字符
        if (i == mulitline_buff_offset) {
            // 全是空白字符?
            // 那就是啥都不需要
            mulitline_buff_offset = 0;
            mulitline_buff_size = 0;
            luat_heap_free(mulitline_buff);
            mulitline_buff = NULL;
            return 1;
        }
        memmove(mulitline_buff, mulitline_buff + i, mulitline_buff_offset - i);
    }
    i = 0;

    // LLOGD("待搜索字符串 | %.*s |", mulitline_buff_offset, mulitline_buff);
    // LLOGD("是开头1吗? %d", memcmp("<<EOF\r", mulitline_buff, 6));
    // LLOGD("是开头2吗? %d", memcmp("<<EOF\n", mulitline_buff, 6));

    // 是不是多行呢
    if (!memcmp("<<EOF\r", mulitline_buff, 6) || !memcmp("<<EOF\n", mulitline_buff, 6))  {
        // LLOGD("找到了<<EOF");
        // 找到开始了, 继续找结束
        i += 6;
        for (; i < mulitline_buff_offset - 4; i++)
        {
            if (!memcmp("EOF\r", mulitline_buff + i, 4) || !memcmp("EOF\n", mulitline_buff + i, 4))  {
                // if (mulitline_buff[i-1] == '\r' || mulitline_buff[i-1] == '\n') {
                    // LLOGD("找到EOF结束符了");
                    // 是否再malloc一次呢? 貌似也没啥必要
                    memmove(mulitline_buff, mulitline_buff + 6, i - 6);
                    rtos_msg_t msg = {
                        .handler = repl_handle
                    };
                    msg.ptr = mulitline_buff;
                    msg.arg1 = i - 6;
                    mulitline_buff = NULL;
                    mulitline_buff_size = 0;
                    mulitline_buff_offset = 0;
                    luat_msgbus_put(&msg, 0);
                    return 0;
                // }
            }
        }
        // LLOGD("没有找到EOF结束");
        return 1;
    }
    
    for (i = 1; i < mulitline_buff_offset; i++)
    {
        if (mulitline_buff[i] == '\r' || mulitline_buff[i] == '\n') {
            char* buff = luat_heap_malloc(i);
            if (buff == NULL) {
                mulitline_buff_size = 0;
                mulitline_buff_offset = 0;
                luat_heap_free(mulitline_buff);
                mulitline_buff = NULL;
                luat_repl_write("REPL: out of memory\r\n", strlen("REPL: out of memory\r\n"));
                return;
            }
            memcpy(buff, mulitline_buff, i);
            rtos_msg_t msg = {
                .handler = repl_handle
            };
            msg.ptr = buff;
            msg.arg1 = i;
            memmove(mulitline_buff, mulitline_buff + i, mulitline_buff_offset - i);
            mulitline_buff_offset -= i;
            luat_msgbus_put(&msg, 0);
            return 0;
        }
    }
    return 1;
}

#ifdef LUAT_USE_REPL

void luat_shell_push(char* uart_buff, size_t rcount) {
    // LLOGD("收到数据长度 %d", rcount);
    if (rcount == 0 || !repl_enable)
        return;
    rtos_msg_t msg = {
        .handler = repl_handle
    };
    if (mulitline_buff == NULL) { // 全新的?
        mulitline_buff_size = rcount > 1024 ? rcount : 1024;
        mulitline_buff  = luat_heap_malloc(mulitline_buff_size);
        if (mulitline_buff == NULL) {
            mulitline_mode = 0;
            mulitline_buff_offset = 0;
            mulitline_buff_size = 0;
            luat_repl_write("REPL: out of memory\r\n", strlen("REPL: out of memory\r\n"));
            return;
        }
    }
    if (mulitline_buff_offset + rcount > mulitline_buff_size) {
        void* tmpptr = luat_heap_realloc(mulitline_buff, mulitline_buff_offset + rcount + 256);
        if (tmpptr == NULL) {
            luat_heap_free(mulitline_buff);
            mulitline_mode = 0;
            mulitline_buff_offset = 0;
            mulitline_buff_size = 0;
            luat_repl_write("REPL: out of memory\r\n", strlen("REPL: out of memory\r\n"));
            return;
        }
    }
    memcpy(mulitline_buff + mulitline_buff_offset, uart_buff, rcount);
    mulitline_buff_offset += rcount;

    // 查找第一个\r或者\n
    while (find2run() == 0) {
        LLOGD("继续下一个查询循环");
    }
    return;
}

#endif
