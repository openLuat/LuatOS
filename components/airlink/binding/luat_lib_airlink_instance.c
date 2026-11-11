#include "luat_base.h"
#ifdef LUAT_USE_AIRLINK_INSTANCE
#include "luat_airlink.h"
#include "luat_airlink_arq.h"
#include "luat_lib_airlink_internal.h"
#include "luat_network_adapter.h"

static int option(lua_State* L, const char* name, int fallback, int min, int max) {
    lua_getfield(L, 2, name);
    lua_Integer value = lua_isnil(L, -1) ? fallback : luaL_checkinteger(L, -1);
    luaL_argcheck(L, value >= min && value <= max, 2, name);
    lua_pop(L, 1);
    return (int)value;
}
static void integer(lua_State* L, const char* name, lua_Integer value) {
    lua_pushinteger(L, value); lua_setfield(L, -2, name);
}
static void boolean(lua_State* L, const char* name, int value) {
    lua_pushboolean(L, value); lua_setfield(L, -2, name);
}

/* airlink.setup(id, {drv="air6205"/"air780epm", mode=airlink.MODE_UART,
 * uart_id=1, baudrate=2000000, sta_adapter=..., cellular_adapter=...})
 * Returns success, error code. Call directly, before legacy init/start. */
int l_airlink_setup(lua_State* L) {
    int id = luaL_checkinteger(L, 1);
    luaL_checktype(L, 2, LUA_TTABLE);
    lua_getfield(L, 2, "drv");
    const char* drv = luaL_checkstring(L, -1);
    luat_airlink_setup_t c = {0};
    if (!strcmp(drv, "air6205")) c.drv = AIRLINK_DRV_6205;
    else if (!strcmp(drv, "air6208")) c.drv = AIRLINK_DRV_6208;
    else if (!strcmp(drv, "air780epm") || !strcmp(drv, "air780er2")) c.drv = AIRLINK_DRV_780EPM;
    else return luaL_argerror(L, 2, "unsupported drv");
    lua_pop(L, 1);
    c.mode = option(L, "mode", LUAT_AIRLINK_MODE_UART, 0, 255);
    c.uart_id = option(L, "uart_id", 1, 0, 255);
    c.spi_id = option(L, "spi_id", 0, 0, 255);
    c.cs = option(L, "cs", 255, 0, 255);
    c.rdy = option(L, "rdy", 255, 0, 255);
    c.speed = c.mode == LUAT_AIRLINK_MODE_UART ? option(L, "baudrate", 2000000, 1, 20000000) : option(L, "speed", 20000000, 1, 100000000);
    int cellular = c.drv == AIRLINK_DRV_780EPM;
    c.sta_adapter = option(L, "sta_adapter", cellular ? -1 : NW_ADAPTER_INDEX_LWIP_WIFI_STA, -1, LUAT_AIRLINK_MAX_ADAPTERS - 1);
    c.ap_adapter = option(L, "ap_adapter", cellular ? -1 : NW_ADAPTER_INDEX_LWIP_WIFI_AP, -1, LUAT_AIRLINK_MAX_ADAPTERS - 1);
    c.cellular_adapter = option(L, "cellular_adapter", cellular ? NW_ADAPTER_INDEX_LWIP_GP_GW : -1, -1, LUAT_AIRLINK_MAX_ADAPTERS - 1);
    int rc = luat_airlink_setup_link(id, &c);
    lua_pushboolean(L, rc == 0); lua_pushinteger(L, rc);
    return 2;
}
int l_airlink_close(lua_State* L) {
    int rc = luat_airlink_stop_link(luaL_checkinteger(L, 1));
    lua_pushboolean(L, rc == 0); lua_pushinteger(L, rc);
    return 2;
}
int l_airlink_status(lua_State* L) {
    int id = luaL_checkinteger(L, 1);
    luat_airlink_dev_info_t peer = {0};
    if (luat_airlink_link_peer_copy(id, &peer)) { lua_pushnil(L); return 1; }
    uint32_t version = 0;
    if (peer.tp == 1) memcpy(&version, peer.wifi.version, 4);
    if (peer.tp == 2) memcpy(&version, peer.cat1.version, 4);
    lua_newtable(L);
    integer(L, "id", id);
    boolean(L, "ready", luat_airlink_link_ready(id));
    integer(L, "arq", luat_airlink_arq_state_link(id));
    boolean(L, "rpc", luat_airlink_flags_supported_link(id, 1));
    boolean(L, "fragment", luat_airlink_flags_supported_link(id, 0));
    integer(L, "peer_type", peer.tp);
    integer(L, "version", version);
    integer(L, "sta_state", peer.tp == 1 ? peer.wifi.sta_state : 0);
    integer(L, "cat_state", peer.tp == 2 ? peer.cat1.cat_state : 0);
    integer(L, "sta_adapter", luat_airlink_link_adapter(id, NW_ADAPTER_INDEX_LWIP_WIFI_STA));
    integer(L, "cellular_adapter", luat_airlink_link_adapter(id, NW_ADAPTER_INDEX_LWIP_GP_GW));
    return 1;
}
static void part(lua_State* L, const char* name, const airlink_statistic_part_t* p) {
    lua_newtable(L);
    integer(L, "total", p->total); integer(L, "ok", p->ok);
    integer(L, "err", p->err); integer(L, "drop", p->drop);
    lua_setfield(L, -2, name);
}
int l_airlink_instance_statistics(lua_State* L) {
    airlink_statistic_t s;
    int id = luaL_checkinteger(L, 1);
    if (luat_airlink_link_snapshot(id, &s, NULL)) { lua_pushnil(L); return 1; }
    lua_newtable(L);
    part(L, "tx_pkg", &s.tx_pkg); part(L, "rx_pkg", &s.rx_pkg);
    part(L, "tx_ip", &s.tx_ip); part(L, "rx_ip", &s.rx_ip);
    part(L, "tx_bytes", &s.tx_bytes); part(L, "rx_bytes", &s.rx_bytes);
    integer(L, "arq", luat_airlink_arq_state_link(id));
    integer(L, "retx", s.arq.tx_retx); integer(L, "giveup", s.arq.arq_giveup);
    integer(L, "duplicate", s.arq.rx_dup);
    return 1;
}
#endif
