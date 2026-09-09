#include "luat_base.h"
#include "luat_input_service.h"
#include "luat_rtos.h"
#include "luat_msgbus.h"
#include "rotable2.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#define CHECK(x) do {if (!(x)) {fprintf(stderr,"FAIL %d: %s\n",__LINE__,#x);exit(1);}} while(0)
static int locked, heap_blocks, message_ready, fail_message;
static rtos_msg_t message;
static void (*timer_cb)(void *);
static void *timer_data;
static unsigned callback_errors;
static int fail_allocation = -1;
int luaopen_input(lua_State *);
void luat_newlib2(lua_State *L,const rotable_Reg_t *reg) {rotable2_newlib(L,reg);}
void *luat_heap_malloc(size_t n) { void *p=malloc(n); if(p) heap_blocks++; return p; }
void *luat_heap_calloc(size_t n,size_t s) {
    if (fail_allocation == 0) return NULL;
    if (fail_allocation > 0) fail_allocation--;
    void *p=calloc(n,s); if(p) heap_blocks++; return p;
}
void luat_heap_free(void *p) {if(p) {heap_blocks--;free(p);}}
void luat_meminfo_luavm(size_t *a,size_t *b,size_t *c) {*a=*b=*c=0;}
void luat_nprint(char *s,size_t n) {fwrite(s,1,n,stdout);}
void input_test_log(const char *format, ...) {(void)format; callback_errors++;}
int luat_rtos_mutex_create(luat_rtos_mutex_t *m) {*m=(void*)1; return 0;}
int luat_rtos_mutex_lock(luat_rtos_mutex_t m,uint32_t timeout) {(void)m;(void)timeout;CHECK(!locked);locked=1;return 0;}
int luat_rtos_mutex_unlock(luat_rtos_mutex_t m) {(void)m;CHECK(locked);locked=0;return 0;}
int luat_rtos_timer_create(luat_rtos_timer_t *t) {*t=(void*)2;return 0;}
int luat_rtos_timer_start(luat_rtos_timer_t t,uint32_t ms,int repeat,void (*cb)(void*),void *data)
{(void)t;(void)ms;(void)repeat;timer_cb=cb;timer_data=data;return 0;}
int luat_rtos_timer_stop(luat_rtos_timer_t t) {(void)t;timer_cb=NULL;return 0;}
int luat_rtos_timer_delete(luat_rtos_timer_t t) {(void)t;timer_cb=NULL;return 0;}
unsigned luat_msgbus_put(rtos_msg_t *msg,size_t timeout)
{(void)timeout;if(fail_message){fail_message=0;return 1;}CHECK(!message_ready);message=*msg;message_ready=1;return 0;}
static void *allocator(void *ud,void *p,size_t old,size_t n)
{(void)ud;(void)old;CHECK(!locked);if(!n){free(p);return NULL;}return realloc(p,n);}
static struct {luat_input_device_t dev;luat_input_handle_t handle;uint32_t state[16];} fixture[4];
static const uint32_t keys[9] = {[0]=1U<<30,[1]=1U<<10,[8]=1U<<16};
static const luat_input_axis_t axes[]={{0,0,0,1023,0},{1,0,0,599,0}};
static const luat_input_axis_t mt[]={{0x35,0,0,1023,0},{0x36,0,0,599,0},{0x39,0,-1,127,-1}};
static const luat_input_device_desc_t desc={.name="fixture",.bus=3,.vendor=0x1234,.product=0x5678,
    .caps={.keys=keys,.key_words=9,.rel_bits=0x103,.abs=axes,.abs_count=2,.mt=mt,.mt_count=3,.mt_slots=1}};
static int add(lua_State *L)
{
    unsigned slot=(unsigned)luaL_checkinteger(L,1);CHECK(slot<4&&!fixture[slot].handle.id);
    luat_input_service_lock();
    CHECK(!luat_input_register(luat_input_service_core(),&fixture[slot].dev,&desc,fixture[slot].state,16,&fixture[slot].handle));
    CHECK(!luat_input_service_attach(fixture[slot].handle));
    uint32_t id=fixture[slot].handle.id;
    luat_input_service_unlock();lua_pushinteger(L,id);return 1;
}
static int remove_device(lua_State *L)
{
    uint32_t id=(uint32_t)luaL_checkinteger(L,1);
    luat_input_service_lock();
    for(unsigned i=0;i<4;i++) if(fixture[i].handle.id==id){
        luat_input_service_detach(fixture[i].handle);
        CHECK(!luat_input_unregister(fixture[i].handle,100));fixture[i].handle.id=0;}
    luat_input_service_unlock();return 0;
}
static int emit(lua_State *L)
{
    uint32_t id=(uint32_t)luaL_checkinteger(L,1);
    luat_input_event_t events[128];
    luaL_checktype(L,2,LUA_TTABLE);size_t n=lua_rawlen(L,2);CHECK(n<=128);
    for(size_t i=0;i<n;i++){
        lua_rawgeti(L,2,i+1);
        lua_rawgeti(L,-1,1);events[i].type=(uint16_t)luaL_checkinteger(L,-1);lua_pop(L,1);
        lua_rawgeti(L,-1,2);events[i].code=(uint16_t)luaL_checkinteger(L,-1);lua_pop(L,1);
        lua_rawgeti(L,-1,3);events[i].value=(int32_t)luaL_checkinteger(L,-1);lua_pop(L,2);
    }
    luat_input_handle_t h;luat_input_service_lock();
    CHECK(!luat_input_lookup(luat_input_service_core(),id,&h));
    CHECK(!luat_input_submit(h,123,events,(uint16_t)n));
    luat_input_service_unlock();return 0;
}
static int pump(lua_State *L)
{if(message_ready){rtos_msg_t msg=message;message_ready=0;msg.handler(L,NULL);}return 0;}
static int tick(lua_State *L) {(void)L;if(timer_cb)timer_cb(timer_data);return 0;}
static int reject(lua_State *L) {(void)L;fail_message=1;return 0;}
static int fail_alloc(lua_State *L) {fail_allocation=(int)luaL_checkinteger(L,1);return 0;}
int main(int argc,char **argv)
{
    CHECK(argc==2);CHECK(!luat_input_service_init());
    lua_State *L=lua_newstate(allocator,NULL);CHECK(L);
    luaL_requiref(L,"_G",luaopen_base,1);lua_pop(L,1);
    luaL_requiref(L,"table",luaopen_table,1);lua_pop(L,1);
    luaL_requiref(L,"input",luaopen_input,1);lua_pop(L,1);
    const luaL_Reg functions[]={{"test_add",add},{"test_remove",remove_device},{"test_emit",emit},
        {"test_pump",pump},{"test_tick",tick},{"test_reject",reject},{"test_fail_alloc",fail_alloc},{NULL,NULL}};
    for(const luaL_Reg *f=functions;f->name;f++){lua_pushcfunction(L,f->func);lua_setglobal(L,f->name);}
    if(luaL_dofile(L,argv[1])) {fprintf(stderr,"Lua failure: %s\n",lua_tostring(L,-1));return 1;}
    lua_close(L);CHECK(!locked);CHECK(!heap_blocks);CHECK(callback_errors==1);
    puts("input Lua PASS: lifecycle, retained frames, filtering, snapshots, MT, overflow, close/GC, wake retry, callback isolation");
    return 0;
}
