
/**
LuatOS Shell -- LuatOS 控制台
*/
#include "lua.h"
#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "luat.shell"
#include "luat_log.h"

#include "luat_shell.h"

static uint8_t echo_enable = 1;

void luat_shell_print(const char* str) {
    luat_shell_write((char*)str, strlen(str));
}

static int luat_shell_msg_handler(lua_State *L, void* ptr) {

    lua_settop(L, 0); //重置虚拟堆栈

    size_t rcount = 0;
    char *uart_buff = luat_shell_read(&rcount);
    
    int ret = 0;
    if (rcount) {
        // 是不是ATI命令呢?
        if (echo_enable)
            luat_shell_write(uart_buff, rcount);
        // 查询版本号
        if (strncmp("ATI", uart_buff, 3) == 0 || strncmp("ati", uart_buff, 3) == 0) {
            char buff[128] = {0};
            sprintf(buff, "LuatOS_%s_%s\r\n", luat_os_bsp(), luat_version_str());
            luat_shell_print(buff);
        }
        // 重启
        else if (strncmp("AT+RESET", uart_buff, 8) == 0 
              || strncmp("at+ecrst", uart_buff, 8) == 0
              || strncmp("AT+ECRST", uart_buff, 8) == 0) {
            luat_shell_print("OK\r\n");
            luat_os_reboot(0);
        }
        // AT测试
        else if (strncmp("AT\r", uart_buff, 3) == 0 || strncmp("AT\r\n", uart_buff, 4) == 0) {
            luat_shell_print("OK\r\n");
        }
        // 回显关闭
        else if (strncmp("ATE0\r", uart_buff, 4) == 0 || strncmp("ATE0\r\n", uart_buff, 5) == 0) {
            echo_enable = 0;
            luat_shell_print("OK\r\n");
        }
        // 回显开启
        else if (strncmp("ATE1\r", uart_buff, 4) == 0 || strncmp("ATE1\r\n", uart_buff, 5) == 0) {
            echo_enable = 1;
            luat_shell_print("OK\r\n");
        }
        // 查询内存状态
        else if (strncmp("free", uart_buff, 4) == 0) {
            size_t total, used, max_used = 0;
            char buff[128] = {0};
            luat_meminfo_luavm(&total, &used, &max_used);
            sprintf(buff, "luavm total=%ld used=%ld max_used=%ld\r\n", total, used, max_used);
            luat_shell_print(buff);
            
            luat_meminfo_sys(&total, &used, &max_used);
            sprintf(buff, "sys total=%ld used=%ld max_used=%ld\r\n", total, used, max_used);
            luat_shell_print(buff);
        }
        // // 枚举根目录
        // else if (strncmp("ls\r", uart_buff, 3) == 0 || strncmp("ls\r\n", uart_buff, 4) == 0) {
        //     lfs_dir_t dir;
        //     struct lfs_info info;
        //     if (LFS_DirOpen(&dir, "/")) {
        //         luat_log_warn("luat.fs", "LFS_DirOpen open / fail, re=%ld");
        //     }
        //     else {
	    //         while (LFS_DirRead(&dir, &info) == 1) {
        //             luat_log_warn("luat.fs", "path=/%s size=%ld", info.name, info.size);
        //         }
        //         LFS_DirClose(&dir);
        //     }
        // }
        // else if (strncmp("cat ", uart_buff, strlen("cat ")) == 0) {
        //     char* path = (char*)uart_buff + strlen("cat ");
        //     lfs_file_t file = {0};
        //     ret = LFS_FileOpen(&file, (const char*)path, LFS_O_RDONLY);
        //     if (ret >= 0) {
        //         while (1) {
        //             ret = LFS_FileRead(&file, uart_buff, SHELL_BUFF_SIZE);
        //             if (ret > 0) {
        //                 drv->Send(uart_buff, ret);
        //             }
        //             else {
        //                 break; // 退出循环
        //             }
        //         }
        //         LFS_FileClose(&file);
        //     }
        //     else {
        //         drv->Send("Fail to open ", strlen("Fail to open "));
        //         drv->Send(path, strlen(path));
        //         drv->Send("\r\n", 2);
        //     }
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
            luat_shell_print("ERR\r\n");
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

