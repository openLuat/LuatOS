#include "luat_base.h"
#include "rotable.h"
#include "rotable2.h"
#include "luat_msgbus.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "main"
#include "luat_log.h"

#include "rotable.h"
void luat_newlib(lua_State* l, const rotable_Reg* reg) {
  #ifdef LUAT_CONF_DISABLE_ROTABLE
  luaL_newlibtable(l,reg);
  int i;
  int nup = 0;

  luaL_checkstack(l, nup, "too many upvalues");
  for (; reg->name != NULL; reg++) {  /* fill the table with given functions */
        for (i = 0; i < nup; i++)  /* copy upvalues to the top */
            lua_pushvalue(l, -nup);
        if (reg->func)
            lua_pushcclosure(l, reg->func, nup);  /* closure with those upvalues */
        else
            lua_pushinteger(l, reg->value);
        lua_setfield(l, -(nup + 2), reg->name);
    }
    lua_pop(l, nup);  /* remove upvalues */
  #else
  rotable_newlib(l, reg);
  #endif
}

#include "rotable2.h"
void luat_newlib2(lua_State* l, const rotable_Reg_t* reg) {
  #ifdef LUAT_CONF_DISABLE_ROTABLE
  luaL_newlibtable(l,reg);
  int i;
  int nup = 0;

  luaL_checkstack(l, nup, "too many upvalues");
  for (; reg->name != NULL; reg++) {  /* fill the table with given functions */
        for (i = 0; i < nup; i++)  /* copy upvalues to the top */
            lua_pushvalue(l, -nup);
        switch (reg->value.type) {
            case LUA_TFUNCTION:
              lua_pushcfunction( l, reg->value.value.func );
              break;
            case LUA_TINTEGER:
              lua_pushinteger( l, reg->value.value.intvalue );
              break;
            case LUA_TSTRING:
              lua_pushstring( l, reg->value.value.strvalue );
              break;
            case LUA_TNUMBER:
              lua_pushnumber( l, reg->value.value.numvalue );
              break;
            case LUA_TLIGHTUSERDATA:
              lua_pushlightuserdata(l, reg->value.value.ptr);
              break;
            default:
              lua_pushinteger( l, 0 );
              break;
        }
        lua_setfield(l, -(nup + 2), reg->name);
    }
    lua_pop(l, nup);  /* remove upvalues */
  #else
  rotable2_newlib(l, reg);
  #endif
}

void luat_os_print_heapinfo(const char* tag) {
    size_t total; size_t used; size_t max_used;
    luat_meminfo_luavm(&total, &used, &max_used);
    LLOGD("%s luavm %ld %ld %ld", tag, total, used, max_used);
    luat_meminfo_sys(&total, &used, &max_used);
    LLOGD("%s sys   %ld %ld %ld", tag, total, used, max_used);
    #ifdef LUAT_USE_PSRAM
    luat_meminfo_opt_sys(LUAT_HEAP_PSRAM, &total, &used, &max_used);
    LLOGD("%s psram %ld %ld %ld", tag, total, used, max_used);
    #endif
}


//唯一c等待接口使用的id
uint64_t c_wait_id = 0;
//c等待接口
//获取一个消息等待的唯一id
//并向栈中推入一个可等待对象
//返回值为0时，表示用户没有启用sys库，无法使用该功能
//[-0, +1, –]
uint64_t luat_pushcwait(lua_State *L) {
    if(lua_getglobal(L, "sys_cw") != LUA_TFUNCTION)
    {
        LLOGE("sys lib not found!");
        return 0;
    }
    c_wait_id++;
//    char* topic = (char*)luat_heap_malloc(1 + sizeof(uint64_t));
    char topic[10] = {0};
    topic[0] = 0x01;//前缀用一个不可见字符，防止和用户用的重复
    memcpy(topic + 1,&c_wait_id,sizeof(uint64_t));
    lua_pushlstring(L,topic,1 + sizeof(uint64_t));
//    luat_heap_free(topic);
    lua_call(L,1,1);
    return c_wait_id;
}

//c等待接口，直接向用户返回错误的对象
//使用时推入需要返回的所有参数
//该函数会向栈中推入一个可等待对象，但该对象会直接返回结果，无需等待
//用户没有启用sys库，不会进行任何操作（[-0, +0, –]）
//[-arg_num, +1, –]
void luat_pushcwait_error(lua_State *L, int arg_num) {
    if(lua_getglobal(L, "sys_cw") != LUA_TFUNCTION)
    {
        LLOGE("sys lib not found!");
        return;
    }
    lua_pushnil(L);
    lua_rotate(L,-arg_num-2,2);
    lua_call(L,arg_num+1,1);
}

//c等待接口，对指定id进行回调响应
//使用时推入需要返回的所有参数
//调用时传入消息id和参数个数
//该函数会调用sys_pub代为发送消息事件
//用户没有启用sys库，不会进行任何操作（[-0, +0, –]），并返回0
//[-arg_num, +0, –] 成功返回1
int luat_cbcwait(lua_State *L, uint64_t id, int arg_num) {
    if(lua_getglobal(L, "sys_pub") != LUA_TFUNCTION)
        return 0;
    char* topic = (char*)luat_heap_malloc(1 + sizeof(uint64_t));
    topic[0] = 0x01;
    memcpy(topic + 1,&id,sizeof(uint64_t));
    lua_pushlstring(L,topic,1 + sizeof(uint64_t));
    luat_heap_free(topic);
    lua_rotate(L,-arg_num-2,2);
    lua_call(L, arg_num + 1, 0);
    return 1;
}

/*
@sys_pub sys
用于luatos内部的系统消息传递
以0x01为第一个字节开头
@args 返回的数据
@usage
--此为系统内部使用的消息，请勿在外部使用
*/
static int luat_cbcwait_cb(lua_State *L, void* ptr) {
    (void)ptr;
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    if(lua_getglobal(L, "sys_pub") != LUA_TFUNCTION)
        return 0;
    char* topic = (char*)luat_heap_malloc(1 + sizeof(uint64_t));
    topic[0] = 0x01;
    memcpy(topic + 1,msg->ptr,sizeof(uint64_t));
    lua_pushlstring(L,topic,1 + sizeof(uint64_t));
    luat_heap_free(topic);
    luat_heap_free(msg->ptr);
    lua_call(L, 1, 0);
    return 0;
}

//c等待接口，无参数的回调，可不传入lua栈
void luat_cbcwait_noarg(uint64_t id) {
    if(id == 0)
        return;
    rtos_msg_t msg = {0};
    msg.handler = luat_cbcwait_cb;
    uint64_t* idp = (uint64_t*)luat_heap_malloc(sizeof(uint64_t));
    memcpy(idp, &id, sizeof(uint64_t));
    msg.ptr = (void*)idp;
    luat_msgbus_put(&msg, 0);
}

