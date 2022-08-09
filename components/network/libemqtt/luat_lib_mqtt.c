
#include "luat_base.h"

#include "luat_network_adapter.h"
#include "libemqtt.h"
#include "luat_rtos.h"
#include "luat_zbuff.h"
#define LUAT_LOG_TAG "mqtt"
#include "luat_log.h"

static int l_mqtt_client(lua_State *L) {
	luat_network_ctrl_t * l_ctrl = (luat_network_ctrl_t *)lua_touserdata(L, 1);
	const char* client_id = luaL_optstring(L, 2, "");
	int keep_alive = luaL_optinteger(L, 3, 300);
	const char* username = luaL_optstring(L, 4, "");
	const char* password = luaL_optstring(L, 5, "");

	int packet_length;
	uint16_t msg_id, msg_id_rcv;
	mqtt_broker_handle_t broker;
	mqtt_init(&broker, client_id);
	mqtt_init_auth(&broker, username, password);

	return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_mqtt[] =
{
	{"client",			ROREG_FUNC(l_mqtt_client)},
	{ NULL,            ROREG_INT(0)}
};

LUAMOD_API int luaopen_mqtt( lua_State *L ) {
    luat_newlib2(L, reg_mqtt);
    return 1;
}
