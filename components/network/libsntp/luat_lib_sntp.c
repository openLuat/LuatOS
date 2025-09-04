/*
@module  socket
@summary 网络接口
@version 1.0
@date    2022.11.13
*/

#include "luat_base.h"

#include "luat_network_adapter.h"
#include "luat_rtos.h"
#include "luat_msgbus.h"
#include "luat_mcu.h"
#include "luat_mem.h"
#include "luat_rtc.h"

#include "luat_sntp.h"

#define LUAT_LOG_TAG "sntp"
#include "luat_log.h"

#define SNTP_SERVER_COUNT       3
#define SNTP_SERVER_LEN_MAX     32

#define NTP_UPDATE 1
#define NTP_ERROR  2
#define NTP_TIMEOUT 3

extern sntp_ctx_t g_sntp_ctx;
extern char* sntp_servers[];

int luat_ntp_on_result(network_ctrl_t *sntp_netc, int result);

int l_sntp_event_handle(lua_State* L, void* ptr) {
    (void)ptr;
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    // 清理现场
    if (msg->arg1 == NTP_TIMEOUT) {
        luat_ntp_on_result(g_sntp_ctx.ctrl, NTP_ERROR);
        return 0;
    }
    ntp_cleanup();
    if (lua_getglobal(L, "sys_pub") != LUA_TFUNCTION) {
        return 0;
    };
    switch (msg->arg1)
    {
/*
@sys_pub socket
时间已经同步
NTP_UPDATE
@usage
sys.subscribe("NTP_UPDATE", function()
    log.info("socket", "sntp", os.date())
end)
*/
    case NTP_UPDATE:
        lua_pushstring(L, "NTP_UPDATE");
        break;
/*
@sys_pub socket
时间同步失败
NTP_ERROR
@usage
sys.subscribe("NTP_ERROR", function()
    log.info("socket", "sntp error")
end)
*/
    case NTP_ERROR:
        lua_pushstring(L, "NTP_ERROR");
        break;
    }
    lua_call(L, 1, 0);
    return 0;
}


/*
sntp时间同步
@api    socket.sntp(sntp_server, adapter)
@tag LUAT_USE_SNTP
@string/table sntp服务器地址 选填
@int 适配器序号,请参考socket库的常量表
@usage
socket.sntp()
--socket.sntp("ntp.aliyun.com") --自定义sntp服务器地址
--socket.sntp({"ntp.aliyun.com","ntp1.aliyun.com","ntp2.aliyun.com"}) --sntp自定义服务器地址
--socket.sntp(nil, socket.ETH0) --sntp自定义适配器序号
sys.subscribe("NTP_UPDATE", function()
    log.info("sntp", "time", os.date())
end)
sys.subscribe("NTP_ERROR", function()
    log.info("socket", "sntp error")
    socket.sntp()
end)
*/
int l_sntp_get(lua_State *L) {
    size_t len = 0;
	if (lua_isstring(L, 1)){
        const char * server_addr = luaL_checklstring(L, 1, &len);
        if (len < SNTP_SERVER_LEN_MAX - 1){
            memcpy(sntp_servers[0], server_addr, len + 1);
        } 
        else if (len < 5) {
            LLOGE("server_addr too short %s", server_addr);
            return 0;
        }
        else{
            LLOGE("server_addr too long %s", server_addr);
            return 0;
        }
	}else if(lua_istable(L, 1)){
        size_t count = lua_rawlen(L, 1);
        if (count > SNTP_SERVER_COUNT){
            count = SNTP_SERVER_COUNT;
        }
		for (size_t i = 1; i <= count; i++){
			lua_geti(L, 1, i);
			const char * server_addr = luaL_checklstring(L, -1, &len);
            if (len < SNTP_SERVER_LEN_MAX - 1){
                memcpy(sntp_servers[i-1], server_addr, len + 1);
            }else{
                LLOGE("server_addr too long %s", server_addr);
            }
			lua_pop(L, 1);
		}
	}
    if (g_sntp_ctx.is_running) {
        LLOGI("sntp is running");
        return 0;
    }
    int adapter_index = luaL_optinteger(L, 2, network_register_get_default());
    int ret = ntp_get(adapter_index);
    if (ret) {
#ifdef __LUATOS__
        rtos_msg_t msg;
        msg.handler = l_sntp_event_handle;
        msg.arg1 = NTP_ERROR;
        luat_msgbus_put(&msg, 0);
#else
        ntp_cleanup();
#endif
    }
	return 0;
}

/*
网络对时后的时间戳(ms级别)
@api socket.ntptm()
@return table 包含时间信息的数据
@usage
-- 本API于 2023.11.15 新增
-- 注意, 本函数在执行socket.sntp()且获取到NTP时间后才有效
-- 而且是2次sntp之后才是比较准确的值
-- 网络波动越小, 该时间戳越稳定
local tm = socket.ntptm()

-- 对应的table包含多个数据, 均为整数值

-- 标准数据
-- tsec 当前秒数,从1900.1.1 0:0:0 开始算, UTC时间
-- tms  当前毫秒数
-- vaild 是否有效, true 或者 nil

-- 调试数据, 调试用,一般用户不用管
-- ndelay 网络延时平均值,单位毫秒
-- ssec 系统启动时刻与1900.1.1 0:0:0的秒数偏移量
-- sms 系统启动时刻与1900.1.1 0:0:0的毫秒偏移量
-- lsec 本地秒数计数器,基于mcu.tick64()
-- lms 本地毫秒数计数器,基于mcu.tick64()

log.info("tm数据", json.encode(tm))
log.info("时间戳", string.format("%u.%03d", tm.tsec, tm.tms))
*/
int l_sntp_tm(lua_State *L) {
    lua_newtable(L);

    lua_pushinteger(L, g_sntp_ctx.network_delay_ms);
    lua_setfield(L, -2, "ndeley");
    lua_pushinteger(L, g_sntp_ctx.sysboot_diff_sec);
    lua_setfield(L, -2, "ssec");
    lua_pushinteger(L, g_sntp_ctx.sysboot_diff_ms);
    lua_setfield(L, -2, "sms");

    uint64_t tick64 = luat_mcu_tick64();
    uint32_t us_period = luat_mcu_us_period();
    uint64_t ll_sec = tick64 /us_period/ 1000 / 1000;
    uint64_t ll_ms  = (tick64 /us_period/ 1000) % 1000;
    uint64_t tmp = ll_sec + g_sntp_ctx.sysboot_diff_sec;
    tmp *= 1000;
    tmp += ll_ms + g_sntp_ctx.sysboot_diff_ms;
    uint64_t tsec = tmp / 1000;
    uint64_t tms = (tmp % 1000) & 0xFFFF;

    
    lua_pushinteger(L, tsec);
    lua_setfield(L, -2, "tsec");
    lua_pushinteger(L, tms);
    lua_setfield(L, -2, "tms");
    lua_pushinteger(L, ll_sec);
    lua_setfield(L, -2, "lsec");
    lua_pushinteger(L, ll_ms);
    lua_setfield(L, -2, "lms");

    if (g_sntp_ctx.sysboot_diff_sec > 0) {
        lua_pushboolean(L, 1);
        lua_setfield(L, -2, "vaild");
    }

    return 1;
}

/*
设置SNTP服务器的端口号
@api socket.sntp_port(port)
@int port 端口号, 默认123
@return int 返回当前的端口号
@usage
-- 本函数于2024.5.17新增
-- 大部分情况下不需要设置NTP服务器的端口号,默认123即可
*/
int l_sntp_port(lua_State *L) {
    if (lua_type(L, 1) == LUA_TNUMBER){
        uint16_t port = (uint16_t)luaL_checkinteger(L, 1);
        if (port > 0){
            g_sntp_ctx.port = port;
        }
    }
    lua_pushinteger(L, g_sntp_ctx.port ? g_sntp_ctx.port : 123);
    return 1;
}
