
/**
LuatOS Shell -- LuatOS 控制台
*/
#include "lua.h"
#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "shell"
#include "luat_log.h"

#ifdef LUAT_USE_MCU
#include "luat_mcu.h"
#endif

#include "luat_shell.h"
#include "luat_str.h"
#include "luat_cmux.h"

#ifdef LUAT_USE_YMODEM
#include "luat_ymodem.h"
#endif

luat_shell_t shell_ctx = {
    .echo_enable = 1
};
extern luat_cmux_t cmux_ctx;

static int luat_shell_loadstr(lua_State *L, void* ptr);

// 查询BSP
static void cmd_ati(char* uart_buff, size_t len);
// 复位重启
static void cmd_reset(char* uart_buff, size_t len);
// AT回显OK
static void cmd_at(char* uart_buff, size_t len);
// AT回显设置
static void cmd_ate(char* uart_buff, size_t len);
// 查询内存状态
static void cmd_free(char* uart_buff, size_t len);
// 查询芯片唯一id
static void cmd_cgsn(char* uart_buff, size_t len);

// cmux初始化
static void cmd_cmux_cmd_init(char* uart_buff, size_t len);

// rpel 操作
static void cmd_loadstr(char* uart_buff, size_t len);

static void cmd_i2c_tools(char* uart_buff, size_t len);

static void cmd_ping(char* uart_buff, size_t len);
static void cmd_sntp(char* uart_buff, size_t len);

// 文件操作
static void cmd_ry(char* uart_buff, size_t len);
static void cmd_lsdir(char* uart_buff, size_t len);
static void cmd_fread(char* uart_buff, size_t len);
static void cmd_fwrite(char* uart_buff, size_t len);

const luat_shell_cmd_reg_t cmd_regs[] = {
    {"ATI", cmd_ati},
    {"ati", cmd_ati},
    {"AT+RESET", cmd_reset},
    {"at+ecrst", cmd_reset},
    {"AT+ECRST", cmd_reset},
    {"AT\r",     cmd_at},
    {"AT\n",     cmd_at},
    {"ATE",      cmd_ate},
    {"free",     cmd_free},
#ifdef LUAT_USE_MCU
    {"AT+CGSN",  cmd_cgsn},
#endif
    {LUAT_CMUX_CMD_INIT, cmd_cmux_cmd_init},
#ifdef LUAT_USE_I2CTOOLS
    {"i2c tools", cmd_i2c_tools},
#endif
#ifdef LUAT_USE_LOADSTR
    {"loadstr ", cmd_loadstr},
#endif
#ifdef LUAT_USE_YMODEM
    {"ry\r",       cmd_ry},
#endif
#ifdef LUAT_USE_SNTP
    {"sntp", cmd_sntp},
#endif
#ifdef LUAT_USE_PING
    {"ping", cmd_ping},
#endif
    {"lsdir ",     cmd_lsdir},
    {"fread ",     cmd_fread},
    {"fwrite ",    cmd_fwrite},
    {NULL, NULL}
};

#ifdef LUAT_USE_SHELL

void luat_shell_push(char* uart_buff, size_t rcount) {

    if (!rcount)
        return;
    if (cmux_ctx.state == 1) {
        luat_cmux_read((unsigned char *)uart_buff,rcount);
        return;
    }
    luat_shell_exec(uart_buff, rcount);
}

#endif

void luat_shell_exec(char* uart_buff, size_t rcount) {
    int cmd_index = 0;
    if (shell_ctx.echo_enable){
        luat_shell_write(uart_buff, rcount);
        luat_shell_write("\r\n", 2);
    }
    while (cmd_regs[cmd_index].prefix != NULL)
    {
        if (!memcmp(cmd_regs[cmd_index].prefix, uart_buff, strlen(cmd_regs[cmd_index].prefix))) {
            cmd_regs[cmd_index].cmd(uart_buff, rcount);
            return;
        }
        cmd_index++;
    }
    luat_shell_write("ERR\r\n", 5);
    return;
}

// ---- 各种子命令
#ifdef LUAT_USE_LOADSTR
static int luat_shell_loadstr(lua_State *L, void* ptr) {
    lua_settop(L, 0);
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    int ret = luaL_loadbuffer(L, (char*)ptr, msg->arg1, 0);
    if (ret == LUA_OK) {
        lua_pcall(L, 0, 0, 0);
    }
    else {
        LLOGW("loadstr %s", lua_tostring(L, -1));
    }
    return 0;
}
#endif
static void cmd_ati(char* uart_buff, size_t len) {
    char buff[128] = {0};
    #ifdef LUAT_BSP_VERSION
    len = sprintf(buff, "LuatOS-SoC_%s_%s\r\n", LUAT_BSP_VERSION, luat_os_bsp());
    #else
    len = sprintf(buff, "LuatOS-SoC_%s_%s\r\n", luat_version_str(), luat_os_bsp());
    #endif
    luat_shell_write(buff, len);
}

static void cmd_reset(char* uart_buff, size_t len) {
    luat_shell_write("OK\r\n", 4);
    luat_os_reboot(0);
}


static void cmd_at(char* uart_buff, size_t len) {
    luat_shell_write("OK\r\n", 4);
}

static void cmd_ate(char* uart_buff, size_t len) {
    if (len > 4) {
        if (uart_buff[4] == '1')
            shell_ctx.echo_enable = 1;
        else
            shell_ctx.echo_enable = 0;
        luat_shell_write("OK\r\n", 4);
    }
}

static void cmd_free(char* uart_buff, size_t len) {
    char buff[256] = {0};
    size_t total, used, max_used = 0;

    luat_meminfo_luavm(&total, &used, &max_used);
    len = sprintf(buff, "lua total=%d used=%d max_used=%d\r\n", total, used, max_used);
    luat_shell_write(buff, len);

    luat_meminfo_sys(&total, &used, &max_used);
    len = sprintf(buff, "sys total=%d used=%d max_used=%d\r\n", total, used, max_used);
    luat_shell_write(buff, len);
}

#ifdef LUAT_USE_MCU
static void cmd_cgsn(char* uart_buff, size_t len) {
    char buff[128] = {0};
    memcpy(buff, "+CGSN=", 6);
    char* _id = (char*)luat_mcu_unique_id(&len);
    luat_str_tohex(_id, len, buff+6);
    buff[6+len*2] = '\n';
    luat_shell_write(buff, 6+len*2+1);
}
#endif

static void cmd_cmux_cmd_init(char* uart_buff, size_t len) {
    cmux_ctx.state = 1;
    #ifdef __AIR105_BSP__
    extern uint8_t gMainWDTEnable;
    gMainWDTEnable = 1;
    #endif
    luat_shell_write("OK\r\n", 4);
}

#ifdef LUAT_USE_I2CTOOLS
#include "i2c_utils.h"
extern void i2c_tools(const char * data,size_t len);
static void cmd_i2c_tools(char* uart_buff, size_t len) {
    i2c_tools(uart_buff, len);
}
#endif

#ifdef LUAT_USE_SNTP
#include "luat_sntp.h"
static void cmd_sntp(char* uart_buff, size_t len){
    ntp_get(-1);
}
#endif

#ifdef LUAT_USE_PING
#include "luat_ping.h"
static void cmd_ping(char* uart_buff, size_t len){
    char* buff = (char*)memchr(uart_buff, ' ', len);
    l_ping(buff+1, len-(buff-uart_buff)-1);
}
#endif

#ifdef LUAT_USE_LOADSTR
static void cmd_loadstr(char* uart_buff, size_t len) {
    size_t slen =  len - strlen("loadstr ") + 1;
    char* tmp = luat_heap_malloc(slen);
    if (tmp == NULL) {
        LLOGW("loadstr out of memory");
    }
    else {
        memset(tmp, 0, slen);
        memcpy(tmp, uart_buff, slen - 1);
        rtos_msg_t msg = {
                        .handler = luat_shell_loadstr,
                        .ptr = tmp,
                        .arg1 = slen
                    };
        luat_msgbus_put(&msg, 0);
    }
}
#endif

#ifdef LUAT_USE_YMODEM
static void* yhandler;
static void cmd_ry(char* uart_buff, size_t len) {
    int result;
    uint8_t ack, flag, file_ok, all_done;
    if (shell_ctx.ymodem_enable == 0) {
        shell_ctx.ymodem_enable = 1;
        yhandler = luat_ymodem_create_handler("/", NULL);
        return;
    }
    result = luat_ymodem_receive(yhandler, (uint8_t*)uart_buff, len, &ack, &flag, &file_ok, &all_done);
    if (result) {
        luat_ymodem_reset(yhandler);
        return;
    }
    if (all_done) {
        luat_ymodem_release(yhandler);
        shell_ctx.ymodem_enable = 0;
        // luat_heap_free(yhandler);
        yhandler = NULL;
    }
}
#endif

#include <string.h>
#include "luat_fs.h"
// 文件相关的命令
static void cmd_lsdir(char* uart_buff, size_t len) {
    if (uart_buff[len - 1] == '\r') {
        uart_buff[len - 1] = 0;
    }
    if (uart_buff[len - 2] == '\r') {
        uart_buff[len - 2] = 0;
    }
    strtok(uart_buff, " ");
    char* path = strtok(NULL, " ");
    luat_fs_dirent_t* ents = luat_heap_malloc(sizeof(luat_fs_dirent_t) * 10);
    if (ents == NULL) {
        LLOGE("out of memory when malloc luat_fs_dirent_t");
        return;
    }
    int i = 0;
    int ret = 0;
    while (1)
    {
        //LLOGD("lsdir for %s %d %d", path, i* 10, 10);
        ret = luat_fs_lsdir(path, ents, i* 10, 10);
        //LLOGD("luat_fs_lsdir %d", ret);
        if (ret < 1)
            break;
        for (size_t i = 0; i < ret; i++)
        {
            LLOGD(">> %s %s", ents[i].d_type == 0 ? "FILE" : "DIR ", ents[i].d_name);
        }
        if (ret != 10)
            break;
    }
    luat_heap_free(ents);
}

static void cmd_fread(char* uart_buff, size_t len) {
    if (uart_buff[len - 1] == '\r') {
        uart_buff[len - 1] = 0;
    }
    if (uart_buff[len - 2] == '\r') {
        uart_buff[len - 2] = 0;
    }
    strtok(uart_buff, " ");
    char* path = strtok(NULL, " ");
    size_t flen = luat_fs_fsize(path);
    if (flen < 1) {
        LLOGD("ERR FILE NOT FOUND");
        return;
    }
    FILE* fd = luat_fs_fopen(path, "rb");
    if (fd == NULL) {
        LLOGD("ERR FILE NOT FOUND");
        return;
    }
    LLOGD("OK %d", flen);
    char* buff = luat_heap_malloc(4096);
    if (buff == NULL) {
        luat_fs_fclose(fd);
        LLOGE("out of memory when read file");
        return;
    }
    int count = 0;
    while (count < flen) {
        int rlen = luat_fs_fread(buff, 4096, 1, fd);
        if (rlen < 1)
            break;
        luat_shell_write(buff, rlen);
    }
    luat_fs_fclose(fd);
}

static void cmd_fwrite(char* uart_buff, size_t len) {
    LLOGD("not support yet");
    return;
}

/// 已废弃的函数

//===============================================================================

// 这个函数已废弃
static int luat_shell_msg_handler(lua_State *L, void* ptr) {

    char buff[128] = {0};
    
    lua_settop(L, 0); //重置虚拟堆栈

    size_t rcount = 0;
    char *uart_buff = luat_shell_read(&rcount);
    
    int ret = 0;
    int len = 0;
    if (rcount) {
        if (cmux_ctx.state == 1){
            //luat_cmux_read((unsigned char *)uart_buff,rcount);
        }else{
            // 是不是ATI命令呢?
            if (shell_ctx.echo_enable){
                luat_shell_write(uart_buff, rcount);
                luat_shell_write("\r\n", 2);
            }
            // 查询版本号
            if (strncmp("ATI", uart_buff, 3) == 0 || strncmp("ati", uart_buff, 3) == 0) {
                char buff[128] = {0};
                #ifdef LUAT_BSP_VERSION
                len = sprintf(buff, "LuatOS-SoC_%s_%s\r\n", LUAT_BSP_VERSION, luat_os_bsp());
                #else
                len = sprintf(buff, "LuatOS-SoC_%s_%s\r\n", luat_version_str(), luat_os_bsp());
                #endif
                luat_shell_write(buff, len);
            }
            // 重启
            else if (strncmp("AT+RESET", uart_buff, 8) == 0 
                || strncmp("at+ecrst", uart_buff, 8) == 0
                || strncmp("AT+ECRST", uart_buff, 8) == 0) {
                luat_shell_write("OK\r\n", 4);
                luat_os_reboot(0);
            }
            // AT测试
            else if (strncmp("AT\r", uart_buff, 3) == 0 || strncmp("AT\r\n", uart_buff, 4) == 0) {
                luat_shell_write("OK\r\n", 4);
            }
            // 回显关闭
            else if (strncmp("ATE0\r", uart_buff, 4) == 0 || strncmp("ATE0\r\n", uart_buff, 5) == 0) {
                shell_ctx.echo_enable = 0;
                luat_shell_write("OK\r\n", 4);
            }
            // 回显开启
            else if (strncmp("ATE1\r", uart_buff, 4) == 0 || strncmp("ATE1\r\n", uart_buff, 5) == 0) {
                shell_ctx.echo_enable = 1;
                luat_shell_write("OK\r\n", 4);
            }
            // 查询内存状态
            else if (strncmp("free", uart_buff, 4) == 0) {
                size_t total, used, max_used = 0;
                luat_meminfo_luavm(&total, &used, &max_used);
                len = sprintf(buff, "lua total=%d used=%d max_used=%d\r\n", total, used, max_used);
                luat_shell_write(buff, len);
                
                luat_meminfo_sys(&total, &used, &max_used);
                len = sprintf(buff, "sys total=%d used=%d max_used=%d\r\n", total, used, max_used);
                luat_shell_write(buff, len);
            }
            #ifdef LUAT_USE_MCU
            else if (strncmp("AT+CGSN", uart_buff, 7) == 0) {
                memcpy(buff, "+CGSN=", 6);
                char* _id = (char*)luat_mcu_unique_id((size_t *)&len);
                luat_str_tohex(_id, len, buff+6);
                buff[6+len*2] = '\n';
                luat_shell_write(buff, 6+len*2+1);
            }
            #endif
            // else if (!strncmp(LUAT_CMUX_CMD_INIT, uart_buff, strlen(LUAT_CMUX_CMD_INIT))) {
            //     luat_shell_write("OK\n", 3);
            //     cmux_state = 1;
            // }
            // 执行脚本
            else if (strncmp("loadstr ", uart_buff, strlen("loadstr ")) == 0) {
                char * tmp = (char*)uart_buff + strlen("loadstr ");
                ret = luaL_loadbuffer(L, tmp, strlen(uart_buff) - strlen("loadstr "), 0);
                if (ret == LUA_OK) {
                    lua_pcall(L, 0, 0, 0);
                }
                else {
                    LLOGW("loadstr %s", lua_tostring(L, -1));
                }
            }
            else {
                luat_shell_write("ERR\r\n", 5);
            }
        }
    }
    luat_shell_notify_recv();
    return 0;
}

// 函数已废弃
void luat_shell_notify_read() {
    rtos_msg_t msg;
    msg.handler = luat_shell_msg_handler;
    msg.ptr = NULL;
    msg.arg1 = 0;
    msg.arg2 = 0;
    luat_msgbus_put(&msg, 0);
}

