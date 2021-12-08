
/**
LuatOS Shell -- LuatOS 控制台
*/
#include "lua.h"
#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "shell"
#include "luat_log.h"

#ifdef LUAT_USE_MCU
#include "luat_mcu.h"
#endif

#include "luat_shell.h"
#include "luat_str.h"
#include "luat_cmux.h"

uint8_t echo_enable = 0;
uint8_t cmux_state = 0;

static int luat_shell_msg_handler(lua_State *L, void* ptr) {

    char buff[128] = {0};
    
    lua_settop(L, 0); //重置虚拟堆栈

    size_t rcount = 0;
    char *uart_buff = luat_shell_read(&rcount);
    
    int ret = 0;
    int len = 0;
    if (rcount) {
        if (cmux_state == 1){
            //luat_cmux_read((unsigned char *)uart_buff,rcount);
        }else{
            // 是不是ATI命令呢?
            if (echo_enable)
                luat_shell_write(uart_buff, rcount);
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
                echo_enable = 0;
                luat_shell_write("OK\r\n", 4);
            }
            // 回显开启
            else if (strncmp("ATE1\r", uart_buff, 4) == 0 || strncmp("ATE1\r\n", uart_buff, 5) == 0) {
                echo_enable = 1;
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
                char* _id = (char*)luat_mcu_unique_id(&len);
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


void luat_shell_notify_read() {
    rtos_msg_t msg;
    msg.handler = luat_shell_msg_handler;
    msg.ptr = NULL;
    msg.arg1 = 0;
    msg.arg2 = 0;
    luat_msgbus_put(&msg, 0);
}


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

void luat_shell_push(char* uart_buff, size_t rcount) {
    //int ret = 0;
    int len = 0;
    char buff[128] = {0};
    if (rcount) {
        if (cmux_state == 1){
            luat_cmux_read((unsigned char *)uart_buff,rcount);
        }else{
            // 是不是ATI命令呢?
            if (echo_enable)
            luat_shell_write(uart_buff, rcount);
            // 查询版本号
            if (strncmp("ATI", uart_buff, 3) == 0 || strncmp("ati", uart_buff, 3) == 0) {
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
                echo_enable = 0;
                luat_shell_write("OK\r\n", 4);
            }
            // 回显开启
            else if (strncmp("ATE1\r", uart_buff, 4) == 0 || strncmp("ATE1\r\n", uart_buff, 5) == 0) {
                echo_enable = 1;
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
                char* _id = (char*)luat_mcu_unique_id(&len);
                luat_str_tohex(_id, len, buff+6);
                buff[6+len*2] = '\n';
                luat_shell_write(buff, 6+len*2+1);
            }
            #endif
            else if (!strncmp(LUAT_CMUX_CMD_INIT, uart_buff, strlen(LUAT_CMUX_CMD_INIT))) {
                luat_shell_write("OK\r\n", 4);
                cmux_state = 1;
            }
            // 执行脚本
            else if (strncmp("loadstr ", uart_buff, strlen("loadstr ")) == 0) {
                size_t slen =  rcount - strlen("loadstr ") + 1;
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
            else {
                // uih_dbg_manage(uart_buff, rcount > 128 ? 128 : rcount);
                luat_shell_write("ERR\r\n", 5);
            }
        }
    }
    return;
}
