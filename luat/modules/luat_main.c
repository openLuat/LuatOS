

#include "luat_base.h"
#include "luat_malloc.h"
//#include "luat_fs.h"
#include "luat_log.h"

static lua_State *L;

lua_State * luat_get_state() {
  return L;
}

static void luat_openlibs(lua_State *L) {
    luaL_requiref(L, "msgbus", luaopen_msgbus, 1);
    lua_pop(L, 1);

    luaL_requiref(L, "rtos", luaopen_rtos, 1);
    lua_pop(L, 1);

    luaL_requiref(L, "sys", luaopen_sys, 1);
    lua_pop(L, 1);
    
    luaL_requiref(L, "timer", luaopen_timer, 1);
    lua_pop(L, 1);

    #ifdef RT_USING_PIN
    luaL_requiref(L, "gpio", luaopen_gpio, 1);
    lua_pop(L, 1);
    #endif
}

static int pmain(lua_State *L) {
    int re = 0;
    //luat_print("luat_pmain!!!\n");
    // 加载系统库
    luaL_openlibs(L);

    // 加载本地库
    luat_openlibs(L);
    

    // 打印个提示
    //luat_print("luat_boot_complete\n");

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
    //  re = luaL_dostring(L, "print(_VERSION)");
    //  re = luaL_dostring(L, "local a = 1");
    //    luat_print("/lua/main.lua not found!!! run default lua string\n");
    //    re = luaL_dostring(L, "print(\"test1=====\") local a = 1\n local b=2\nprint(_G)\nprint(a+b)\nprint(sys)\nprint(_VERSION)");
    //    re = luaL_dostring(L, "print(\"test2=====\") local ab=1 \nprint(rtos.get_version()) print(rtos.get_memory_free())");
    //    re = luaL_dostring(L, "print(\"test3=====\") print(a - 1)");
    //    re = luaL_dostring(L, "print(\"test4=====\") print(rtos.get_memory_free()) collectgarbage(\"collect\") print(rtos.get_memory_free())");
    //    re = luaL_dostring(L, "print(\"test5=====\") print(rtos.timer_start(1, 3000)) print(rtos.receive(5000)) print(\"timer_get?\")");
    //    re = luaL_dostring(L, "print(\"test6=====\") local f = io.open(\"abc.log\", \"w\") print(f)");
    //    re = luaL_dostring(L, "print(_VERSION) print(\"sleep 2s\") timer.mdelay(2000) print(\"hi again\")");
    

    // 加载几个帮助方法吧
    /*
    luaL_loadstring(L, "-- rtos消息回调\n"
                       "local handlers = {}\n"
                       "setmetatable(handlers, {__index = function() return function() end end})\n"
                       "rtos.on = function(id, handler) handlers[id] = handler end\n"
                       "timer.ids = {}\n"
                       "timer.maxid = 1\n"
                       "timer.start = function(ms, func)\n"
                       "  local id = timer.maxid\n"
                       "  timer.maxid = timer.maxid + 1\n"
                       "  local nt = rtos.timer_start(id, m)\n"
                       "  timer.ids[id] = {nt=nt,func=func}\n"
                       "end\n"
                       "rtos.on(rtos.MSG_TIMER, function(msg)\n"
                       "   local t = timer.ids[msg]\n"
                       "   if t ~= nil then t.func() end\n"
                       "end\n"
                       "sys.run = functoin()\n"
                       "   while 1 do\n"
                       "     local id,msg = rtos.recv(0)\n"
                       "     if id == rtos.MSG_TIMER then handlers(id)(msg) end\n"
                       "   end\n"
                       "end\n");
    */
        re = luaL_loadstring(L, "-- rtos消息回调\n"
                      "sys.run = functoin()\n"
                      "  print(\"sys.run -- GO!GO!GO!\")"
                      "  while 1 do\n"
                      "    print(\"sys.run -- GO WHILE!\")"
                      "    local id,msg = rtos.recv(0)\n"
                      "    print(id)\n"
                      "end\n");

#ifdef RT_USING_PIN
        // pin number pls refer pin_map.c
        re = luaL_dostring(L, "print(_VERSION)\n"
                   " local PA1=14 local PA4=15 \n"
                   " gpio.setup(PA1) gpio.setup(PA4)\n"
                   " gpio.set(PA1, 0) gpio.set(PA4, 0)\n"
                   " while 1 do\n"
                   "    gpio.set(PA1, 1)\n"
                   "    gpio.set(PA4, 1)\n"
                   "    print(\"sleep 1s\")\n"
                   "    timer.mdelay(1000)\n"

                   "    gpio.set(PA1, 0)\n"
                   "    gpio.set(PA4, 0)\n"
                   "    print(\"sleep 1s\")\n"
                   "    timer.mdelay(1000)\n"
                   "end\n");
#else
        /*
        re = luaL_dostring(L, "print(_VERSION .. \" from Luat\")\n timer.mdelay(1000)\n print(_VERSION)"
                  "local c = 0\n"
                  "while 1 do\n"
                  "    print(\"count=\" .. c)\n"
                  "    timer.mdelay(1000)\n"
                  "    c = c + 1\n"
                  "end\n"
                  );
        */
       re = luaL_dostring(L, "print(_VERSION .. \" from Luat\")\n"
                             "timer.mdelay(1000)\n"
                             "print(\"END\")\n"
                             "rtos.timer_start(1, 1000, 3)\n"
                             "while 1 do print(rtos.recv(-1)) end"
                             //"sys.run()\n"
                  );
#endif
    //}
    
    if (re) {
        luat_print("luaL_dostring  return re != 0\n");
        luat_print(lua_tostring(L, -1));
    }
    lua_pushboolean(L, 1);  /* signal no errors */
    return 1;
}

/*
** Prints an error message, adding the program name in front of it
** (if present)
*/
static void l_message (const char *pname, const char *msg) {
  if (pname) lua_writestringerror("%s: ", pname);
  lua_writestringerror("%s\n", msg);
}


/*
** Check whether 'status' is not OK and, if so, prints the error
** message on the top of the stack. It assumes that the error object
** is a string, as it was either generated by Lua or by 'msghandler'.
*/
static int report (lua_State *L, int status) {
  if (status != LUA_OK) {
    const char *msg = lua_tostring(L, -1);
    l_message("LUAT", msg);
    lua_pop(L, 1);  /* remove message */
  }
  return status;
}

static int panic (lua_State *L) {
  lua_writestringerror("PANIC: unprotected error in call to Lua API (%s)\n",
                        lua_tostring(L, -1));
  return 0;  /* return to Lua to abort */
}

int luat_main (int argc, char **argv, int _) {
  int status, result;
  L = lua_newstate(luat_heap_alloc, NULL);
  if (L == NULL) {
    l_message(argv[0], "cannot create state: not enough memory");
    return 1;
  }
  if (L) lua_atpanic(L, &panic);
  lua_pushcfunction(L, &pmain);  /* to call 'pmain' in protected mode */
  lua_pushinteger(L, argc);  /* 1st argument */
  lua_pushlightuserdata(L, argv); /* 2nd argument */
  status = lua_pcall(L, 2, 1, 0);  /* do the call */
  result = lua_toboolean(L, -1);  /* get result */
  report(L, status);
  //lua_close(L);
  return (result && status == LUA_OK) ? 0 : 2;
}
