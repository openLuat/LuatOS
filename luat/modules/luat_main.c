

#include "luat_base.h"
#include "luat_malloc.h"
//#include "luat_fs.h"
#include "luat_log.h"

static void luat_openlibs(lua_State *L) {
    luaL_requiref(L, "msgbus", luaopen_msgbus, 1);
    lua_pop(L, 1);

    luaL_requiref(L, "sys", luaopen_sys, 1);
    lua_pop(L, 1);
    
    luaL_requiref(L, "timer", luaopen_timer, 1);
    lua_pop(L, 1);
    
    luaL_requiref(L, "gpio", luaopen_gpio, 1);
    lua_pop(L, 1);
}

static int luat_app_main(lua_State *L) {
        int re = 0;
    luat_print("luat_pmain!!!\n");
    // 加载系统库
    luaL_openlibs(L);

    // 加载本地库
    luat_openlibs(L);

    // 打印个提示
    luat_print("luat_boot_complete\n");

    // 执行
    //lfs_file_t file;
    //if (LFS_FileOpen(&file, "/lua/main.lua", LFS_O_RDONLY) == LFS_ERR_OK) {
    //    luat_print("reading main.lua--------------------\n");
    //    char *buf = luat_heap_calloc(file.size+1);
    //    LFS_FileRead(&file, buf, file.size);
    //    LFS_FileClose(&file);
    //    luat_print("run main.lua-----------------------\n");
    //    re = luaL_dostring(L, buf);
    //    luat_heap_free(buf);
    //    luat_print("done main.lua-------------------------\n");
    //}
    //else {
    //    luat_print("/lua/main.lua not found!!! run default lua string\n");
        re = luaL_dostring(L, "print(\"test1=====\") local a = 1\n local b=2\nprint(_G)\nprint(a+b)\nprint(sys)\nprint(_VERSION)");
    //    re = luaL_dostring(L, "print(\"test2=====\") local ab=1 \nprint(rtos.get_version()) print(rtos.get_memory_free())");
    //    re = luaL_dostring(L, "print(\"test3=====\") print(a - 1)");
    //    re = luaL_dostring(L, "print(\"test4=====\") print(rtos.get_memory_free()) collectgarbage(\"collect\") print(rtos.get_memory_free())");
    //    re = luaL_dostring(L, "print(\"test5=====\") print(rtos.timer_start(1, 3000)) print(rtos.receive(5000)) print(\"timer_get?\")");
    //    re = luaL_dostring(L, "print(\"test6=====\") local f = io.open(\"abc.log\", \"w\") print(f)");
    //}
    
    if (re) {
        luat_print("luaL_dostring  return re != 0\n");
        luat_print(lua_tostring(L, -1));
    }

    //lua_pushboolean(L, 1);
    luat_print("luat_pmain_complete\n");
    return 0;
}

int luat_main(int argc, char *argv[], char * envp[]) {

    int status;
    lua_State *L = NULL;
    luat_print("lua_newstate\n");
    L = lua_newstate(luat_heap_alloc, NULL);
    //if (L) lua_atpanic(L, &ec616_lua_panic);
    if (L) {
        luat_print("lua_pushcfunction\n");
        lua_pushcfunction(L, &luat_app_main);
        luat_print("lua_pcall\n");
        status = lua_pcall(L, 0, 0, 0);
        if (status) {
            luat_print("status != 0\n");
        }
        lua_close(L);
        luat_print("lua run complete\n");
        //result = lua_toboolean(L, -1);
    }
    else
    {
        luat_print("lua_newstate FAIL\n");
    }

    return 0;
}

#ifdef LUAT_MAIN
int main(int argc, char *argv[], char *envp[] ) {
    return luat_main(argc, argv, envp);
}
#endif