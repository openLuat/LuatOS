
#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"

#include "lwip/init.h"
#include "lwip/sys.h"
#include "lwip/opt.h"
#include "lwip/stats.h"
#include "lwip/err.h"
#include "lwip/tcpip.h"
#include "arch/sys_arch.h"
#include "lwip/apps/mqtt.h"
#if (LWIP_VERSION_MAJOR  == 2 && LWIP_VERSION_MINOR > 0 )
#include "lwip/apps/mqtt_priv.h"
#endif

#define LUAT_LOG_TAG "lwip"
#include "luat_log.h"


typedef struct mqtt_pub {
    u32_t tot_len;
    u16_t offset;
    char* buff;
    char* topic;
}mqtt_pub_t;

typedef struct luat_lwip_mqtt {
    int conn_cb;
    int inpub_cb;
    int req_cb;
    mqtt_pub_t* pub;
} luat_lwip_mqtt_t;

static int l_inpub_cb(lua_State *L, void* ptr) {
    mqtt_pub_t* inpub = (mqtt_pub_t*)ptr;
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    if (msg->arg1 != 0) {
        lua_geti(L, LUA_REGISTRYINDEX, msg->arg1);
        if (lua_isfunction(L, -1)) {
            lua_pushstring(L, inpub->topic);
            lua_pushlstring(L, inpub->buff, inpub->offset);
            lua_call(L, 2, 0);
        }
        else {
            LLOGW("mqtt inpub cb isn't function");
        }
    }
    else {
        LLOGW("mqtt inpub cb is NULL");
    }
    if (inpub->buff)
        luat_heap_free(inpub->buff);
    if (inpub->topic)
        luat_heap_free(inpub->topic);
    luat_heap_free(inpub);
    return 0;
}

static int l_conn_cb(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    if (msg->arg1 != 0) {
        lua_geti(L, LUA_REGISTRYINDEX, msg->arg1);
        if (lua_isfunction(L, -1)) {
            lua_pushinteger(L, msg->arg2);
            lua_call(L, 1, 0);
        }
    }
    return 0;
}

static void luat_lwip_mqtt_connection_cb(mqtt_client_t *client, void *arg, mqtt_connection_status_t status) {
    rtos_msg_t msg = {0};
    msg.handler = l_conn_cb;
    msg.ptr = arg;
    msg.arg1 = ((luat_lwip_mqtt_t*)arg)->conn_cb;
    msg.arg2 = status;
    luat_msgbus_put(&msg, 0);
}

static void luat_lwip_mqtt_incoming_data_cb(void *arg, const u8_t *data, u16_t len, u8_t flags) {
    luat_lwip_mqtt_t *mqtt = (luat_lwip_mqtt_t*)arg;
    mqtt_pub_t* inpub_tmp = mqtt->pub;
    rtos_msg_t msg = {0};
    if (inpub_tmp == NULL) {
        LLOGE("inpub_tmp is NULL");
        return;
    }
    mempcpy(inpub_tmp->buff + inpub_tmp->offset, data, len);
    inpub_tmp->offset += len;
    if (flags & MQTT_DATA_FLAG_LAST) {
        msg.handler = l_inpub_cb;
        msg.ptr = inpub_tmp;
        msg.arg1 = mqtt->inpub_cb;
        msg.arg2 = 0;
        luat_msgbus_put(&msg, 0);
        mqtt->pub = NULL;
    }
    LLOGD("incoming_data %s %d %d", inpub_tmp->topic, len, flags);
}

static void luat_lwip_mqtt_incoming_publish_cb(void *arg, const char *topic, u32_t tot_len) {
    LLOGD("inpub %s %ld", topic, tot_len);
    luat_lwip_mqtt_t *mqtt = (luat_lwip_mqtt_t*)arg;
    mqtt->pub = luat_heap_malloc(sizeof(mqtt_pub_t));
    mqtt_pub_t* inpub_tmp = mqtt->pub;
    inpub_tmp->tot_len = tot_len;
    inpub_tmp->offset = 0;
    inpub_tmp->buff = (char*)luat_heap_malloc(tot_len);
    inpub_tmp->topic = (char*)luat_heap_malloc(strlen(topic)+1);
    memcpy(inpub_tmp->topic, topic, strlen(topic)+1);
}

static void luat_lwip_mqtt_request_cb(void *arg, err_t err) {
    rtos_msg_t msg = {0};
    if (((luat_lwip_mqtt_t*)arg)->req_cb == 0)
        return;
    msg.handler = l_conn_cb;
    msg.ptr = arg;
    msg.arg1 = ((luat_lwip_mqtt_t*)arg)->req_cb;
    msg.arg2 = err;
    luat_msgbus_put(&msg, 0);
}

/*
新建一个mqtt客户端
@api lwip.mqtt_new()
@return userdata 客户端指针
@usage
local mqttc = lwip.mqtt_new()
if mqttc then
    lwip.mqtt_arg(mqttc, {
        conn = function(status)
            if status == lwip.CONNECTED then
                lwip.subscribe(mqttc, "/sys/req/XXXYYYZZZ", 0)
                lwip.subscribe(mqttc, "/sys/req/XXXYYYZZZ", 1)
                lwip.subscribe(mqttc, "/sys/ota/XXXYYYZZZ", 0)
            else
                sys.publish("MQTT_CLOSED")
            end
        end,
        inpub = function(topic, data)
            log.info("mqtt", topic, data)
        end,
        req = function(result)

        end
    })
    while 1 do
        if lwip.mqtt_connect(mqttc, {
            client_id = "XXXYYYZZZ",
            user = "test",
            pass = "test",
            keep_alive = 300,
            will_topic = "/sys/will/XXXYYYZZZ",
            will_data = "offline",
            will_qos = 0,
            will_retain = 0
            }) then
            while lwip.mqtt_is_connected(mqttc) do
                sys.waitUtil("MQTT_CLOSED", 2000)
            end
        end
        sys.wait(5000)
    end
end

*/
int luat_lwip_mqtt_client_new(lua_State *L) {
    LOCK_TCPIP_CORE();
    mqtt_client_t * client = mqtt_client_new();
    if (client == NULL)
        return 0;
    luat_lwip_mqtt_t *cbt = (luat_lwip_mqtt_t *)luat_heap_malloc(sizeof(luat_lwip_mqtt_t));
    if (cbt == NULL) {
        mem_free(client);
        return 0;
    }
    memset(cbt, 0, sizeof(luat_lwip_mqtt_t));
    mqtt_set_inpub_callback(client, luat_lwip_mqtt_incoming_publish_cb, luat_lwip_mqtt_incoming_data_cb, cbt);
    lua_pushlightuserdata(L, client);
    UNLOCK_TCPIP_CORE();
    return 1;
}

int luat_lwip_mqtt_cb(lua_State *L) {
    mqtt_client_t *client = (mqtt_client_t *)lua_touserdata(L, 1);
    luat_lwip_mqtt_t *cbt = client->inpub_arg;
    if (lua_istable(L, 2)) {
        // conn
        lua_pushliteral(L, "conn");
        lua_gettable(L, 2);
        if (lua_isfunction(L, -1)) {
            cbt->conn_cb = luaL_ref(L, LUA_REGISTRYINDEX);
        }
        else {
            lua_pop(L, 1);
            LLOGW("conn cb MUST be function");
        }

        // pub
        lua_pushliteral(L, "inpub");
        lua_gettable(L, 2);
        if (lua_isfunction(L, -1)) {
            cbt->inpub_cb = luaL_ref(L, LUA_REGISTRYINDEX);
        }
        else {
            lua_pop(L, 1);
            LLOGW("inpub cb MUST be function");
        }

        // req
        lua_pushliteral(L, "req");
        lua_gettable(L, 2);
        if (lua_isfunction(L, -1)) {
            cbt->req_cb = luaL_ref(L, LUA_REGISTRYINDEX);
        }
        else {
            lua_pop(L, 1);
            LLOGW("req cb MUST be function");
        }
    }

    return 1;
}

int luat_lwip_mqtt_client_connect(lua_State *L) {
    mqtt_client_t * client = lua_touserdata(L, 1);
    const char* ip = luaL_checkstring(L, 2);
    int port = luaL_checkinteger(L, 3);
    if (!lua_istable(L, 4)) {
        lua_pushnil(L);
        lua_pushliteral(L, "need client info table");
        return 2;
    }

    ip_addr_t ipaddr = {0};
    if (ipaddr_aton(ip, &ipaddr) == 0) {
        lua_pushnil(L);
        lua_pushliteral(L, "bad ip");
        return 2;
    }

    struct mqtt_connect_client_info_t client_info = {0};

    if (1) {
        // 获取 Client ID
        lua_pushliteral(L, "id");
        lua_gettable(L, 4);
        if (!lua_isstring(L, -1)) {
            lua_pushnil(L);
            lua_pushliteral(L, "need client id");
            return 2;
        }
        client_info.client_id = luaL_checkstring(L, -1);
        lua_pop(L, 1);

        // 用户名
        lua_pushliteral(L, "user");
        lua_gettable(L, 2);
        if (lua_isstring(L, -1)) {
            client_info.client_user = luaL_checkstring(L, -1);
        }
        lua_pop(L, 1);

        // 密码
        lua_pushliteral(L, "pass");
        lua_gettable(L, 2);
        if (lua_isstring(L, -1)) {
            client_info.client_pass = luaL_checkstring(L, -1);
        }
        lua_pop(L, 1);

        // 心跳周期, 默认240就好了, 经验值
        lua_pushliteral(L, "keep_alive");
        lua_gettable(L, 2);
        if (lua_isinteger(L, -1)) {
            client_info.keep_alive = luaL_checkinteger(L, -1);
        }
        else {
            client_info.keep_alive = 240;
        }
        lua_pop(L, 1);

        // will相关的topic和数据
        lua_pushliteral(L, "will_topic");
        lua_gettable(L, 2);
        if (lua_isstring(L, -1)) {
            client_info.will_topic = luaL_checkstring(L, -1);
        }
        lua_pop(L, 1);

        if (client_info.will_topic != NULL) {
            // will的msg
            lua_pushliteral(L, "will_msg");
            lua_gettable(L, 2);
            if (lua_isstring(L, -1)) {
                client_info.will_msg = luaL_checkstring(L, -1);
            }
            lua_pop(L, 1);

            // will的qos,默认0
            lua_pushliteral(L, "will_qos");
            lua_gettable(L, 2);
            if (lua_isinteger(L, -1)) {
                client_info.will_qos = luaL_checkinteger(L, -1);
            }
            lua_pop(L, 1);

            // will的retain, 默认0
            lua_pushliteral(L, "will_retain");
            lua_gettable(L, 2);
            if (lua_isinteger(L, -1)) {
                client_info.will_retain = luaL_checkinteger(L, -1);
            }
            lua_pop(L, 1);
        }

    }

    LOCK_TCPIP_CORE();
    int ret = mqtt_client_connect(client, &ipaddr, port, luat_lwip_mqtt_connection_cb, client->inpub_arg, &client_info);
    UNLOCK_TCPIP_CORE();
    //LLOGD("mqtt_client_connect ret %ld", ret);
    lua_pushboolean(L, ret == ERR_OK ? 1 : 0);
    return 1;
}

int luat_lwip_mqtt_disconnect(lua_State *L) {
    mqtt_client_t * client = lua_touserdata(L, 1);
    LOCK_TCPIP_CORE();
    mqtt_disconnect(client);
    UNLOCK_TCPIP_CORE();
    return 0;
}

int luat_lwip_mqtt_client_is_connected(lua_State *L) {
    mqtt_client_t * client = lua_touserdata(L, 1);
    LOCK_TCPIP_CORE();
    lua_pushboolean(L, mqtt_client_is_connected(client) == 0 ? 0 : 1);
    UNLOCK_TCPIP_CORE();
    return 1;
}

int luat_lwip_mqtt_subscribe(lua_State *L) {
    mqtt_client_t * client = lua_touserdata(L, 1);
    const char* topic = luaL_checkstring(L, 2);
    uint8_t qos = luaL_optinteger(L, 3, 0);
    //LLOGD("mqtt_subscribe %s %d", topic, qos);
    LOCK_TCPIP_CORE();
    int ret = mqtt_subscribe(client, topic, qos, luat_lwip_mqtt_request_cb, client->inpub_arg);
    UNLOCK_TCPIP_CORE();
    //LLOGD("mqtt_subscribe ret %ld", ret);
    lua_pushboolean(L, ret == ERR_OK ? 1 : 0);
    return 1;
}

int luat_lwip_mqtt_unsubscribe(lua_State *L) {
    mqtt_client_t * client = lua_touserdata(L, 1);
    const char* topic = luaL_checkstring(L, 2);
    LOCK_TCPIP_CORE();
    int ret = mqtt_unsubscribe(client, topic, luat_lwip_mqtt_request_cb, client->inpub_arg);
    UNLOCK_TCPIP_CORE();
    //LLOGD("mqtt_unsubscribe ret %ld", ret);
    lua_pushboolean(L, ret == ERR_OK ? 1 : 0);
    return 1;
}

int luat_lwip_mqtt_publish(lua_State *L) {
    mqtt_client_t * client = lua_touserdata(L, 1);
    const char* topic = luaL_checkstring(L, 2);
    size_t len = 0;
    const char* data = luaL_checklstring(L, 3, &len);
    u8_t qos = luaL_optinteger(L, 4, 0);
    u8_t retain = luaL_optinteger(L, 5, 0);
    LOCK_TCPIP_CORE();
    int ret = mqtt_publish(client, topic, data, len, qos, retain, luat_lwip_mqtt_request_cb, client->inpub_arg);
    UNLOCK_TCPIP_CORE();
    //LLOGD("mqtt_publish ret %ld", ret);
    lua_pushboolean(L, ret == ERR_OK ? 1 : 0);
    return 1;
}

int luat_lwip_mqtt_free(lua_State *L) {
    mqtt_client_t * client = lua_touserdata(L, 1);
    if (client->inpub_arg) {
        luat_lwip_mqtt_t *cbt = (luat_lwip_mqtt_t *)client->inpub_arg;
        if (cbt->conn_cb)
            luaL_unref(L, LUA_REGISTRYINDEX, cbt->conn_cb);
        if (cbt->inpub_cb)
            luaL_unref(L, LUA_REGISTRYINDEX, cbt->inpub_cb);
        if (cbt->req_cb)
            luaL_unref(L, LUA_REGISTRYINDEX, cbt->req_cb);
        if (cbt->pub)
            luat_heap_free(cbt->pub);
        luat_heap_free(cbt);
        client->inpub_arg = NULL;
    }
    mem_free(client);
    client = NULL;
    return 0;
}