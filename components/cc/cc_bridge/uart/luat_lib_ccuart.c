#include "luat_base.h"
#ifdef LUAT_USE_CC_UART_BRIDGE
#include "luat_cc_uart_bridge.h"
#include "luat_msgbus.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "rotable2.h"
#include <string.h>
#include <stdio.h>

static int callback_ref=LUA_NOREF;
static void push_session(lua_State *L,uint64_t session) {
    char text[17];snprintf(text,sizeof(text),"%08x%08x",(unsigned)(session>>32),(unsigned)session);lua_pushstring(L,text);
}
static uint64_t check_session(lua_State *L,int index) {
    size_t length;const char *text=luaL_checklstring(L,index,&length);uint64_t session=0;unsigned i;
    luaL_argcheck(L,length==16,index,"session requires 16 hex digits");
    for(i=0;i<16;i++) {
        unsigned digit;
        if(text[i]>='0' && text[i]<='9')digit=(unsigned)(text[i]-'0');
        else if(text[i]>='a' && text[i]<='f')digit=(unsigned)(text[i]-'a'+10);
        else if(text[i]>='A' && text[i]<='F')digit=(unsigned)(text[i]-'A'+10);
        else {luaL_argerror(L,index,"invalid hex session");return 0;}
        session=(session<<4)|digit;
    }
    luaL_argcheck(L,session!=0,index,"zero session is reserved");return session;
}
static void field_string(lua_State *L,const char *key,const char *value) {lua_pushstring(L,value);lua_setfield(L,-2,key);}
static void field_integer(lua_State *L,const char *key,uint32_t value) {lua_pushinteger(L,value);lua_setfield(L,-2,key);}
/* Preserve exact long-event counters on both 32- and 64-bit Lua VMs. */
static void field_duration(lua_State *L,const char *key,uint64_t value) {
    if (value <= (uint64_t)LUA_MAXINTEGER) lua_pushinteger(L,(lua_Integer)value);
    else {
        char text[21];
        snprintf(text,sizeof(text),"%llu",(unsigned long long)value);
        lua_pushstring(L,text);
    }
    lua_setfield(L,-2,key);
}
static void field_symbol(lua_State *L,const char *key,char value) {
    if(value)lua_pushlstring(L,&value,1);else lua_pushliteral(L,"-");
    lua_setfield(L,-2,key);
}
static int dispatch(lua_State *L,void *unused) {
    rtos_msg_t *message=(rtos_msg_t *)lua_topointer(L,-1);
    luat_cc_uart_notice_t *n=(luat_cc_uart_notice_t *)message->ptr;
    (void)unused;
    if(callback_ref==LUA_NOREF) {luat_heap_free(n);return 0;}
    lua_rawgeti(L,LUA_REGISTRYINDEX,callback_ref);
    lua_newtable(L);field_string(L,"event",n->event);push_session(L,n->session);lua_setfield(L,-2,"session");
    lua_newtable(L);
    if(!strcmp(n->event,"control") || !strcmp(n->event,"send_failed")) {
        lua_getglobal(L,"json");
        if(lua_istable(L,-1) || lua_type(L,-1)==LUA_TUSERDATA)lua_getfield(L,-1,"decode");else lua_pushnil(L);
        if(lua_isfunction(L,-1)) {
            lua_pushstring(L,n->data);
            if(lua_pcall(L,1,1,0)==LUA_OK && lua_istable(L,-1)) {
                lua_remove(L,-2);lua_remove(L,-2); /* replace empty data table by decoded envelope */
            } else {
                lua_pop(L,2);field_string(L,"reason","invalid control JSON");
            }
        } else {
            lua_pop(L,2);field_string(L,"reason","json.decode unavailable");
        }
        field_integer(L,"sequence",n->sequence);
    } else if(!strcmp(n->event,"media_ready") || !strcmp(n->event,"media_changed")) {
        field_integer(L,"rate",n->value);
        field_integer(L,"epoch",n->epoch);
    } else if(!strcmp(n->event,"primed")) {
        field_integer(L,"epoch",n->epoch);
        field_integer(L,"wire_epoch",n->value);
    } else if(!strcmp(n->event,"dtmf_end")) {
        field_symbol(L,"digit",n->dtmf_end.digit);
        field_duration(L,"duration_ticks",n->dtmf_end.duration_ticks);
        field_duration(L,"duration_ms",n->dtmf_end.duration_ms);
        field_integer(L,"clock_hz",n->dtmf_end.clock_hz);
        field_integer(L,"epoch",n->epoch);
        lua_pushboolean(L,n->dtmf_end.complete);lua_setfield(L,-2,"complete");
    } else if(!strcmp(n->event,"dtmf"))field_string(L,"digit",n->data);
    else if(!strcmp(n->event,"play_done") || !strcmp(n->event,"record_started"))field_string(L,"path",n->data);
    else if(n->data[0])field_string(L,"reason",n->data);
    lua_setfield(L,-2,"data");
    luat_heap_free(n);
    if(lua_pcall(L,1,0,0)!=LUA_OK) {lua_pop(L,1);luat_cc_uart_fault("Lua event callback failed");}
    return 0;
}
static void notify(const luat_cc_uart_notice_t *n) {
    luat_cc_uart_notice_t *copy=luat_heap_malloc(sizeof(*copy));rtos_msg_t message={0};
    if(!copy) {luat_cc_uart_fault("event allocation failed");return;}
    *copy=*n;message.handler=dispatch;message.ptr=copy;
    /* Only the separate notification task waits for the VM. Media never waits. */
    while(luat_msgbus_put(&message,0))luat_rtos_task_sleep(5);
}
static int result(lua_State *L,int ret) {lua_pushboolean(L,ret==0);if(ret){lua_pushfstring(L,"ccuart error %d",ret);return 2;}return 1;}
static int l_on(lua_State *L) {
    luaL_checktype(L,1,LUA_TFUNCTION);
    if(callback_ref!=LUA_NOREF)luaL_unref(L,LUA_REGISTRYINDEX,callback_ref);
    lua_pushvalue(L,1);callback_ref=luaL_ref(L,LUA_REGISTRYINDEX);lua_pushboolean(L,1);return 1;
}
static int l_setup(lua_State *L) {
    luat_cc_uart_config_t config={0};const char *role,*mount;
    luaL_checktype(L,1,LUA_TTABLE);
    lua_getfield(L,1,"role");role=luaL_checkstring(L,-1);luaL_argcheck(L,strlen(role)==1 && (*role=='A'||*role=='B'),1,"role A or B required");config.role=*role;lua_pop(L,1);
    lua_getfield(L,1,"dtmf_only");luaL_argcheck(L,lua_isnil(L,-1) || lua_isboolean(L,-1),1,"dtmf_only must be boolean");config.dtmf_only=(uint8_t)lua_toboolean(L,-1);lua_pop(L,1);
    lua_getfield(L,1,"uart_id");config.uart_id=(int)luaL_optinteger(L,-1,1);lua_pop(L,1);
    lua_getfield(L,1,"baud_rate");config.baud_rate=(uint32_t)luaL_optinteger(L,-1,2000000);lua_pop(L,1);
    lua_getfield(L,1,"min_free_bytes");config.min_free_bytes=(uint32_t)luaL_optinteger(L,-1,268435456);lua_pop(L,1);
    lua_getfield(L,1,"clock_p_ppm");config.clock_p_ppm=(int32_t)luaL_optinteger(L,-1,1000);lua_pop(L,1);
    lua_getfield(L,1,"clock_i_ppm");config.clock_i_ppm=(int32_t)luaL_optinteger(L,-1,10);lua_pop(L,1);
    lua_getfield(L,1,"clock_limit_ppm");config.clock_limit_ppm=(int32_t)luaL_optinteger(L,-1,1000);lua_pop(L,1);
    lua_getfield(L,1,"clock_slew_ppm");config.clock_slew_ppm=(int32_t)luaL_optinteger(L,-1,50);lua_pop(L,1);
    lua_getfield(L,1,"record_mount");mount=luaL_optstring(L,-1,"/sd");luaL_argcheck(L,strlen(mount)<sizeof(config.record_mount) && mount[0]=='/',1,"invalid record mount");snprintf(config.record_mount,sizeof(config.record_mount),"%s",mount);lua_pop(L,1);
    luaL_argcheck(L,callback_ref!=LUA_NOREF,1,"register ccuart.on before setup");return result(L,luat_cc_uart_setup(&config,notify));
}
static int l_begin(lua_State *L) {
    uint64_t session;int ret=luat_cc_uart_begin(lua_isnoneornil(L,1)?0:check_session(L,1),&session);
    if(ret){lua_pushnil(L);lua_pushfstring(L,"begin error %d",ret);return 2;}push_session(L,session);return 1;
}
static int l_send(lua_State *L) {
    uint64_t session=check_session(L,1);const char *op=luaL_checkstring(L,2),*json;size_t length;uint32_t sequence;int ret;
    luaL_argcheck(L,strlen(op)>0 && strlen(op)<=32,2,"operation length 1..32 required");
    lua_getglobal(L,"json");lua_getfield(L,-1,"encode");luaL_argcheck(L,lua_isfunction(L,-1),2,"json.encode unavailable");
    lua_newtable(L);field_string(L,"op",op);if(lua_istable(L,3))lua_pushvalue(L,3);else lua_newtable(L);lua_setfield(L,-2,"data");
    lua_call(L,1,1);json=luaL_checklstring(L,-1,&length);ret=luat_cc_uart_send(session,json,length,&sequence);
    if(ret){lua_pushnil(L);lua_pushfstring(L,"send error %d",ret);return 2;}lua_pushinteger(L,sequence);return 1;
}
static int l_route(lua_State *L) {static const char *const modes[]={"isolated","priming","bridge",NULL};return result(L,luat_cc_uart_route(check_session(L,1),(unsigned)luaL_checkoption(L,2,NULL,modes)));}
static int l_play(lua_State *L) {return result(L,luat_cc_uart_play(check_session(L,1),luaL_checkstring(L,2)));}
static int l_play_stop(lua_State *L) {return result(L,luat_cc_uart_play_stop(check_session(L,1)));}
static int l_dtmf(lua_State *L) {return result(L,luat_cc_uart_dtmf(check_session(L,1),lua_toboolean(L,2)));}
static int l_record(lua_State *L) {return result(L,luat_cc_uart_record(check_session(L,1),luaL_checkstring(L,2)));}
static int l_record_stop(lua_State *L) {return result(L,luat_cc_uart_record_stop(check_session(L,1)));}
static int l_finish(lua_State *L) {return result(L,luat_cc_uart_finish(check_session(L,1)));}
static int l_stats(lua_State *L) {
    luat_cc_uart_stats_t stats={0};luat_cc_uart_get_stats(&stats);lua_newtable(L);
#define B(name) lua_pushboolean(L,stats.name!=0);lua_setfield(L,-2,#name)
#define I(name) field_integer(L,#name,stats.name)
    B(link_ready);B(ready);B(active);B(connected);B(media_ready);B(record_active);B(record_failed);B(dtmf_enabled);B(dtmf_only);
    push_session(L,stats.session);lua_setfield(L,-2,"session");
    I(media_epoch);I(wire_epoch);I(rate);I(route);I(rx_frames);I(tx_frames);I(capture_dropped);I(tx_dropped);I(upload_errors);I(clock_skipped);I(notice_dropped);I(control_retries);I(crc_errors);I(framing_errors);I(stale_packets);I(underflow);I(overflow);I(queue_samples);I(record_frames);
    I(capture_frames);I(dtmf_missing_frames);
    lua_pushinteger(L,stats.correction_ppm);lua_setfield(L,-2,"correction_ppm");
    lua_newtable(L);
#define D(name) field_integer(L,#name,stats.dtmf.name)
    D(frames);D(peak);D(mean_square);D(max_peak);D(strict40_hits);D(previous20_hits);D(current20_hits);
    D(loose40_samples);D(loose40_hits);D(emitted);
#undef D
#define S(name) field_symbol(L,#name,stats.dtmf.name)
    S(strict40);S(previous20);S(current20);S(loose40);S(last_strict40);S(last_loose40);
#undef S
    lua_setfield(L,-2,"dtmf");
    lua_newtable(L);
#define N(name) field_integer(L,#name,stats.source.name)
    N(speech_calls);N(speech_bytes);N(speech_rate);N(speech_bits);N(speech_len);
    N(speech_peak);N(speech_max_peak);N(speech_mean_square);
    N(hal_frames);N(hal_peak);N(hal_max_peak);N(hal_mean_square);
#undef N
    lua_setfield(L,-2,"source");
    lua_newtable(L);
#define R(name) field_integer(L,#name,stats.network_dtmf.name)
    R(supported);R(active);R(enabled);R(mapped);R(network_mode);
    R(generation);R(payload_type);R(clock_hz);R(local_port);
    R(sip_messages);R(sip_errors);R(sip_oversize);
    R(rtp_packets);R(source_rejected);R(events);R(delivered);R(dropped);
#undef R
    lua_setfield(L,-2,"network_dtmf");
#undef B
#undef I
    return 1;
}
static const rotable_Reg_t reg[]={
    {"DTMF_END_VERSION",ROREG_INT(1)},
    {"setup",ROREG_FUNC(l_setup)},{"on",ROREG_FUNC(l_on)},{"begin",ROREG_FUNC(l_begin)},{"send",ROREG_FUNC(l_send)},
    {"route",ROREG_FUNC(l_route)},{"play",ROREG_FUNC(l_play)},{"playStop",ROREG_FUNC(l_play_stop)},
    {"dtmf",ROREG_FUNC(l_dtmf)},{"record",ROREG_FUNC(l_record)},{"recordStop",ROREG_FUNC(l_record_stop)},
    {"finish",ROREG_FUNC(l_finish)},{"stats",ROREG_FUNC(l_stats)},{NULL,ROREG_FUNC(NULL)}
};
LUAMOD_API int luaopen_ccuart(lua_State *L) {luat_newlib2(L,reg);return 1;}
#endif
