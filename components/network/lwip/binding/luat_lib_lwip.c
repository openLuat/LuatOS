
#include "luat_base.h"
#include "luat_msgbus.h"

// TCP
int l_lwip_tcp_new(lua_State* L);
int l_lwip_tcp_new_ip6(lua_State* L);
int l_lwip_tcp_arg(lua_State* L);
int l_lwip_tcp_connect(lua_State* L);
int l_lwip_tcp_bind(lua_State* L);
int l_lwip_tcp_write(lua_State* L);
int l_lwip_tcp_output(lua_State* L);
int l_lwip_tcp_recved(lua_State* L);
int l_lwip_tcp_close(lua_State* L);
int l_lwip_tcp_abort(lua_State* L);
int l_lwip_tcp_shutdown(lua_State* L);
int l_lwip_tcp_listen(lua_State* L);
int l_lwip_tcp_accepted(lua_State* L);

// MQTT
int luat_lwip_mqtt_client_new(lua_State *L);
int luat_lwip_mqtt_cb(lua_State *L) ;
int luat_lwip_mqtt_client_connect(lua_State *L);
int luat_lwip_mqtt_disconnect(lua_State *L);
int luat_lwip_mqtt_client_is_connected(lua_State *L);
int luat_lwip_mqtt_subscribe(lua_State *L);
int luat_lwip_mqtt_unsubscribe(lua_State *L);
int luat_lwip_mqtt_publish(lua_State *L);
int luat_lwip_mqtt_free(lua_State *L);

#include "rotable.h"
static const rotable_Reg reg_lwip[] =
{
    { "tcp_new",      l_lwip_tcp_new,   0},
    { "tcp_new_ip6",      l_lwip_tcp_new_ip6,   0},
    { "tcp_arg",      l_lwip_tcp_arg,   0},
    { "tcp_connect",      l_lwip_tcp_connect,   0},
    { "tcp_bind",      l_lwip_tcp_bind,   0},
    { "tcp_write",      l_lwip_tcp_write,   0},
    { "tcp_output",      l_lwip_tcp_output,   0},
    { "tcp_recved",      l_lwip_tcp_recved,   0},
    { "tcp_close",      l_lwip_tcp_close,   0},
    { "tcp_abort",      l_lwip_tcp_abort,   0},
    { "tcp_shutdown",      l_lwip_tcp_shutdown,   0},
    { "tcp_listen",      l_lwip_tcp_listen,   0},
    { "tcp_accepted",      l_lwip_tcp_accepted,   0},
    // MQTT
    { "mqtt_client_new",      luat_lwip_mqtt_client_new,   0},
    { "mqtt_new",      luat_lwip_mqtt_client_new,   0},
    { "mqtt_cb",            luat_lwip_mqtt_cb, 0},
    { "mqtt_arg",            luat_lwip_mqtt_cb, 0},
    { "mqtt_client_connect",            luat_lwip_mqtt_client_connect, 0},
    { "mqtt_connect",            luat_lwip_mqtt_client_connect, 0},
    { "mqtt_disconnect",            luat_lwip_mqtt_disconnect, 0},
    { "mqtt_client_is_connected",            luat_lwip_mqtt_client_is_connected, 0},
    { "mqtt_is_connected",            luat_lwip_mqtt_client_is_connected, 0},
    { "mqtt_subscribe",            luat_lwip_mqtt_subscribe, 0},
    { "mqtt_unsubscribe",            luat_lwip_mqtt_unsubscribe, 0},
    { "mqtt_publish",            luat_lwip_mqtt_publish, 0},
    { "mqtt_free",            luat_lwip_mqtt_free, 0},
  /** Accepted */
    {"MQTT_CONNECT_ACCEPTED", NULL, 0},
  /** Refused protocol version */
    {"MQTT_CONNECT_REFUSED_PROTOCOL_VERSION", NULL, 1},
  /** Refused identifier */
    {"MQTT_CONNECT_REFUSED_IDENTIFIER",       NULL, 2},
  /** Refused server */
    {"MQTT_CONNECT_REFUSED_SERVER",           NULL, 3},
  /** Refused user credentials */
    {"MQTT_CONNECT_REFUSED_USERNAME_PASS",    NULL, 4},
  /** Refused not authorized */
    {"MQTT_CONNECT_REFUSED_NOT_AUTHORIZED_",  NULL, 5},
  /** Disconnected */
    {"MQTT_CONNECT_DISCONNECTED",             NULL, 256},
  /** Timeout */
    {"MQTT_CONNECT_TIMEOUT",                  NULL, 257},
	{ NULL,        NULL,   0}
};



LUAMOD_API int luaopen_lwip( lua_State *L ) {
    luat_newlib(L, reg_lwip);
    return 1;
}

/* This function is only required to prevent arch.h including stdio.h
 * (which it does if LWIP_PLATFORM_ASSERT is undefined)
 */
void lwip_example_app_platform_assert(const char *msg, int line, const char *file)
{
  printf("Assertion \"%s\" failed at line %d in %s\n", msg, line, file);
  //fflush(NULL);
  //abort();
}

