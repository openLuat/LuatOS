
#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "luat_base.h"
#if (defined(TLS_CONFIG_CPU_XT804))
#include "FreeRTOS.h"
#else
#include "freertos/FreeRTOS.h"
#endif

#include "host/ble_hs.h"
#include "host/ble_uuid.h"
#include "host/util/util.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

#include "luat_msgbus.h"
#include "luat_mem.h"
#include "luat_nimble.h"

/* BLE */
#include "nimble/nimble_port.h"

typedef void (*TaskFunction_t)( void * );

struct ble_hs_cfg;
struct ble_gatt_register_ctxt;

static void gatt_svr_register_cb(struct ble_gatt_register_ctxt *ctxt, void *arg);
static int gatt_svr_init(void);

extern uint16_t g_ble_conn_handle;
extern uint16_t g_ble_state;

extern ble_uuid_any_t ble_peripheral_srv_uuid;

extern uint16_t s_chr_flags[];
extern ble_uuid_any_t s_chr_uuids[];
extern uint16_t s_chr_val_handles[];
extern uint8_t s_chr_notify_states[];
extern uint8_t s_chr_indicate_states[];

#define LUAT_LOG_TAG "nimble"
#include "luat_log.h"

extern uint8_t luat_ble_dev_name[];
extern size_t  luat_ble_dev_name_len;
extern struct ble_gap_adv_params adv_params;

static uint8_t buff_for_read[256];
static uint8_t buff_for_read_size;

typedef struct ble_write_msg {
    // uint16_t conn_handle,
    // uint16_t attr_handle,
    ble_uuid_t* uuid;
    uint16_t len;
    char buff[1];
}ble_write_msg_t;

static int
gatt_svr_chr_access_func(uint16_t conn_handle, uint16_t attr_handle,
                               struct ble_gatt_access_ctxt *ctxt, void *arg);


int luat_nimble_peripheral_set_chr(int index, ble_uuid_any_t* chr_uuid, int flags) {
    if (index < 0 || index >= LUAT_BLE_MAX_CHR)
        return -1;
    char buff[BLE_UUID_STR_LEN + 1];
    ble_uuid_to_str(chr_uuid, buff);
    // LLOGD("set chr[%d] %s flags %d", index, buff, flags);
    ble_uuid_copy(&s_chr_uuids[index], chr_uuid);
    s_chr_flags[index] = flags;
    return 0;
}

static void gatt_svr_register_cb(struct ble_gatt_register_ctxt *ctxt, void *arg)
{
    char buf[BLE_UUID_STR_LEN];
    // LLOGD("gatt_svr_register_cb op %d", ctxt->op);
    switch (ctxt->op) {
    case BLE_GATT_REGISTER_OP_SVC:
        // LLOGD("registered service %s with handle=%d",
        //             ble_uuid_to_str(ctxt->svc.svc_def->uuid, buf),
        //             ctxt->svc.handle);
        break;

    case BLE_GATT_REGISTER_OP_CHR:
        // LLOGD("registering characteristic %s with "
        //             "def_handle=%d val_handle=%d",
        //             ble_uuid_to_str(ctxt->chr.chr_def->uuid, buf),
        //             ctxt->chr.def_handle,
        //             ctxt->chr.val_handle);
        break;

    case BLE_GATT_REGISTER_OP_DSC:
        // LLOGD("registering descriptor %s with handle=%d",
        //             ble_uuid_to_str(ctxt->dsc.dsc_def->uuid, buf),
        //             ctxt->dsc.handle);
        break;

    default:
        // assert(0);
        break;
    }
}

static int l_ble_chr_write_cb(lua_State* L, void* ptr) {
    ble_write_msg_t* wmsg = (ble_write_msg_t*)ptr;
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_getglobal(L, "sys_pub");
    if (lua_isfunction(L, -1)) {
        lua_pushstring(L, "BLE_GATT_WRITE_CHR");
        lua_newtable(L);
        char buff[BLE_UUID_STR_LEN] = {0};
        for (size_t i = 0; i < LUAT_BLE_MAX_CHR; i++)
        {
            if (s_chr_val_handles[i] == msg->arg2) {
                ble_uuid_to_str(&s_chr_uuids[i], buff);
                lua_pushstring(L, buff);
                lua_setfield(L, -2, "chr_uuid");
                break;
            }
        }
        lua_pushlstring(L, wmsg->buff, wmsg->len);
        lua_call(L, 3, 0);
    }
    luat_heap_free(wmsg);
    return 0;
}



static int l_ble_chr_read_cb(lua_State* L, void* ptr) {
    lua_getglobal(L, "sys_pub");
    if (lua_isfunction(L, -1)) {
        lua_pushstring(L, "BLE_GATT_READ_CHR");
        lua_call(L, 1, 0);
    }
    return 0;
}

static int l_ble_state_cb(lua_State* L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_getglobal(L, "sys_pub");
    if (lua_isfunction(L, -1)) {
        lua_pushstring(L, "BLE_SERVER_STATE_UPD");
        lua_pushinteger(L, msg->arg1);
        lua_call(L, 2, 0);
    }
    return 0;
}

static int
gatt_svr_chr_access_func(uint16_t conn_handle, uint16_t attr_handle,
                               struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    int rc = 0;
    struct os_mbuf *om = ctxt->om;
    ble_write_msg_t* wmsg;
    rtos_msg_t msg = {0};
    char buff[BLE_UUID_STR_LEN + 1] = {0};
    int handle_index = -1;
    for (size_t i = 0; i < LUAT_BLE_MAX_CHR; i++)
    {
        if (attr_handle == s_chr_val_handles[i]) {
            ble_uuid_to_str(&s_chr_uuids[i], buff);
            handle_index = i;
            break;
        }
    }
    
    LLOGD("gatt_svr_chr_access_func %d %d-%s %d", conn_handle, attr_handle, buff, ctxt->op);
    switch (ctxt->op) {
        case BLE_GATT_ACCESS_OP_WRITE_CHR:
            wmsg = (ble_write_msg_t*)(luat_heap_malloc(sizeof(ble_write_msg_t) + MYNEWT_VAL(BLE_ATT_PREFERRED_MTU) - 1));
            if (!wmsg) {
                LLOGW("out of memory when malloc ble_write_msg_t");
                return 0;
            }
            memset(wmsg, 0, sizeof(ble_write_msg_t) + MYNEWT_VAL(BLE_ATT_PREFERRED_MTU) - 1);
            msg.handler = l_ble_chr_write_cb;
            msg.ptr = wmsg;
            msg.arg1 = conn_handle;
            msg.arg2 = attr_handle;
            while(om) {
                memcpy(&wmsg->buff[wmsg->len], om->om_data, om->om_len);
                wmsg->len += om->om_len;
                om = SLIST_NEXT(om, om_next);
            }
            luat_msgbus_put(&msg, 0);
            return 0;
        case BLE_GATT_ACCESS_OP_READ_CHR:
            LLOGD("gatt svr read size = %d", buff_for_read_size);
            if (buff_for_read_size) {
                rc = os_mbuf_append(ctxt->om, buff_for_read, buff_for_read_size);
                buff_for_read_size = 0;
                msg.handler = l_ble_chr_read_cb;
                luat_msgbus_put(&msg, 0);
                return rc == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
            }
            return 0;
        default:
            // assert(0);
            return BLE_ATT_ERR_UNLIKELY;
    }
}

static  struct ble_gatt_svc_def gatt_svr_svcs[] = {
        {
            .type = BLE_GATT_SVC_TYPE_PRIMARY,
            .uuid = &ble_peripheral_srv_uuid,
            .characteristics = (struct ble_gatt_chr_def[]) {
                {0}, {0}, {0}, {0}
            }
        },
        {
            0, /* No more services */
        },
    };

static int gatt_svr_init(void)
{
    int rc;

    // ble_svc_gap_init();
    //ble_gatts_reset();
    // ble_svc_gatt_init();

    struct ble_gatt_chr_def defs[] =
            { {
                    // .uuid = &ble_peripheral_write_uuid,
                    .uuid = &s_chr_uuids[0],
                    .val_handle = &s_chr_val_handles[0],
                    .access_cb = gatt_svr_chr_access_func,
                    .flags = s_chr_flags[0]
                }, {
                    // .uuid = &ble_peripheral_indicate_uuid,
                    .uuid = &s_chr_uuids[1],
                    .val_handle = &s_chr_val_handles[1],
                    .access_cb = gatt_svr_chr_access_func,
                    .flags = s_chr_flags[1]
                }, {
                    // .uuid = &ble_peripheral_notify_uuid,
                    .uuid = &s_chr_uuids[2],
                    .val_handle = &s_chr_val_handles[2],
                    .access_cb = gatt_svr_chr_access_func,
                    .flags = s_chr_flags[2]
                }, {
                    0, /* No more characteristics in this service */
                },
            };
    memcpy(gatt_svr_svcs[0].characteristics, defs, sizeof(defs));

    char buff[BLE_UUID_STR_LEN + 1];
    ble_uuid_to_str(defs[0].uuid, buff);
    LLOGD("chr %s flags %d", buff,defs[0].flags);
    ble_uuid_to_str(defs[1].uuid, buff);
    LLOGD("chr %s flags %d", buff,defs[1].flags);
    ble_uuid_to_str(defs[2].uuid, buff);
    LLOGD("chr %s flags %d", buff,defs[2].flags);

    rc = ble_gatts_count_cfg(gatt_svr_svcs);
    if (rc != 0) {
        LLOGE("ble_gatts_count_cfg rc %d", rc);
        return rc;
    }

    rc = ble_gatts_add_svcs(gatt_svr_svcs);
    if (rc != 0) {
        LLOGE("ble_gatts_add_svcs rc %d", rc);
        return rc;
    }
    return 0;
}

int luat_nimble_server_send(int id, char* data, size_t data_len) {
    int rc;
    struct os_mbuf *om;

    if (g_ble_state != BT_STATE_CONNECTED) {
        //LLOGI("Not connected yet");
        return -1;
    }
    if (data_len <= 256) {
        memcpy(buff_for_read, data, data_len);
        buff_for_read_size = data_len;
    }
    else {
        LLOGW("BLE package limit to 256 bytes");
        return 1;
    }

    // 先发indicate, TODO 判断是否有监听
    om = ble_hs_mbuf_from_flat((const void*)data, (uint16_t)data_len);
    if (!om) {
        LLOGE("ble_hs_mbuf_from_flat return NULL!!");
        return BLE_HS_ENOMEM;
    }
    rc = ble_gattc_indicate_custom(g_ble_conn_handle, s_chr_val_handles[1], om);
    LLOGD("ble_gattc_indicate_custom ret %d", rc);

    // 然后发notify, TODO 判断是否有监听
    om = ble_hs_mbuf_from_flat((const void*)data, (uint16_t)data_len);
    if (om) {
        rc = ble_gattc_notify_custom(g_ble_conn_handle,  s_chr_val_handles[2], om);
        LLOGD("ble_gattc_notify_custom ret %d", rc);
    }
    return rc;
}

int luat_nimble_server_send_notify(ble_uuid_any_t* srv, ble_uuid_any_t* chr, char* data, size_t data_len) {
    int rc = 0;
    struct os_mbuf *om;
    uint16_t handle = 0;
    char buff[BLE_UUID_STR_LEN] = {0};
    ble_uuid_to_str(chr, buff);
    for (size_t i = 0; i < LUAT_BLE_MAX_CHR; i++)
    {
        if (!ble_uuid_cmp(&s_chr_uuids[i], chr)) {
            if (s_chr_notify_states[i] == 0) {
                LLOGW("chr notify %s state == 0, skip", buff);
                return -1;
            }
            om = ble_hs_mbuf_from_flat((const void*)data, (uint16_t)data_len);
            if (!om) {
                LLOGE("ble_hs_mbuf_from_flat return NULL!!");
                return BLE_HS_ENOMEM;
            }
            rc = ble_gattc_notify_custom(g_ble_conn_handle,  s_chr_val_handles[i], om);
            LLOGD("ble_gattc_notify %s len %d ret %d", buff, data_len, rc);
            return 0;
        }
    }
    LLOGD("ble_gattc_notify not such chr %s", buff);
    return -1;
}

int luat_nimble_server_send_indicate(ble_uuid_any_t* srv, ble_uuid_any_t* chr, char* data, size_t data_len) {
    int rc = 0;
    struct os_mbuf *om;
    uint16_t handle = 0;
    for (size_t i = 0; i < LUAT_BLE_MAX_CHR; i++)
    {
        if (!ble_uuid_cmp(&s_chr_uuids[i], chr)) {
            if (s_chr_indicate_states[i] == 0) {
                LLOGW("chr indicate state == 0, skip");
                return -1;
            }
            om = ble_hs_mbuf_from_flat((const void*)data, (uint16_t)data_len);
            if (!om) {
                LLOGE("ble_hs_mbuf_from_flat return NULL!!");
                return BLE_HS_ENOMEM;
            }
            rc = ble_gattc_indicate_custom(g_ble_conn_handle,  s_chr_val_handles[i], om);
            LLOGD("ble_gattc_indicate_custom ret %d", rc);
            return 0;
        }
    }
    return -1;
}


// static const char *tag = "NimBLE_BLE_PRPH";
static int bleprph_gap_event(struct ble_gap_event *event, void *arg);
#if CONFIG_EXAMPLE_RANDOM_ADDR
static uint8_t own_addr_type = BLE_OWN_ADDR_RANDOM;
#else
static uint8_t own_addr_type;
#endif

void ble_store_config_init(void);

/**
 * Logs information about a connection to the console.
 */

#define ADDR_FMT "%02X%02X%02X%02X%02X%02X"
#define ADDR_T(addr) addr[0],addr[1],addr[2],addr[3],addr[4],addr[5]

static void
bleprph_print_conn_desc(struct ble_gap_conn_desc *desc)
{
    LLOGI("handle=%d our_ota_addr_type=%d our_ota_addr=" ADDR_FMT, desc->conn_handle, desc->our_ota_addr.type, ADDR_T(desc->our_ota_addr.val));
    LLOGI(" our_id_addr_type=%d our_id_addr=" ADDR_FMT, desc->our_id_addr.type, ADDR_T(desc->our_id_addr.val));
    LLOGI(" peer_ota_addr_type=%d peer_ota_addr=" ADDR_FMT, desc->peer_ota_addr.type, ADDR_T(desc->peer_ota_addr.val));
    LLOGI(" peer_id_addr_type=%d peer_id_addr=" ADDR_FMT, desc->peer_id_addr.type, ADDR_T(desc->peer_id_addr.val));
    LLOGI(" conn_itvl=%d conn_latency=%d supervision_timeout=%d "
                "encrypted=%d authenticated=%d bonded=%d",
                desc->conn_itvl, desc->conn_latency,
                desc->supervision_timeout,
                desc->sec_state.encrypted,
                desc->sec_state.authenticated,
                desc->sec_state.bonded);
}

#if CONFIG_EXAMPLE_EXTENDED_ADV
/**
 * Enables advertising with the following parameters:
 *     o General discoverable mode.
 *     o Undirected connectable mode.
 */
static void
ext_bleprph_advertise(void)
{
    struct ble_gap_ext_adv_params params;
    struct os_mbuf *data;
    uint8_t instance = 1;
    int rc;

    /* use defaults for non-set params */
    memset (&params, 0, sizeof(params));

    /* enable connectable advertising */
    params.connectable = 1;
    params.scannable = 1;
    params.legacy_pdu = 1;

    /* advertise using random addr */
    params.own_addr_type = BLE_OWN_ADDR_PUBLIC;

    params.primary_phy = BLE_HCI_LE_PHY_1M;
    params.secondary_phy = BLE_HCI_LE_PHY_2M;
    //params.tx_power = 127;
    params.sid = 1;

    params.itvl_min = BLE_GAP_ADV_FAST_INTERVAL1_MIN;
    params.itvl_max = BLE_GAP_ADV_FAST_INTERVAL1_MIN;

    /* configure instance 0 */
    rc = ble_gap_ext_adv_configure(instance, &params, NULL,
                                   bleprph_gap_event, NULL);
    assert (rc == 0);

    /* in this case only scan response is allowed */

    /* get mbuf for scan rsp data */
    data = os_msys_get_pkthdr(sizeof(ext_adv_pattern_1), 0);
    assert(data);

    /* fill mbuf with scan rsp data */
    rc = os_mbuf_append(data, ext_adv_pattern_1, sizeof(ext_adv_pattern_1));
    assert(rc == 0);

    rc = ble_gap_ext_adv_set_data(instance, data);
    assert (rc == 0);

    /* start advertising */
    rc = ble_gap_ext_adv_start(instance, 0, 0);
    assert (rc == 0);
}
#else
/**
 * Enables advertising with the following parameters:
 *     o General discoverable mode.
 *     o Undirected connectable mode.
 */
static void
bleprph_advertise(void)
{
    // struct ble_gap_adv_params adv_params;
    struct ble_hs_adv_fields fields;
    const char *name;
    int rc;

    /**
     *  Set the advertisement data included in our advertisements:
     *     o Flags (indicates advertisement type and other general info).
     *     o Advertising tx power.
     *     o Device name.
     *     o 16-bit service UUIDs (alert notifications).
     */

    memset(&fields, 0, sizeof fields);

    /* Advertise two flags:
     *     o Discoverability in forthcoming advertisement (general)
     *     o BLE-only (BR/EDR unsupported).
     */
    fields.flags = BLE_HS_ADV_F_DISC_GEN |
                   BLE_HS_ADV_F_BREDR_UNSUP;

    /* Indicate that the TX power level field should be included; have the
     * stack fill this value automatically.  This is done by assigning the
     * special value BLE_HS_ADV_TX_PWR_LVL_AUTO.
     */
    fields.tx_pwr_lvl_is_present = 1;
    fields.tx_pwr_lvl = BLE_HS_ADV_TX_PWR_LVL_AUTO;

    name = ble_svc_gap_device_name();
    fields.name = (uint8_t *)name;
    fields.name_len = strlen(name);
    fields.name_is_complete = 1;

    // fields.uuids16 = (ble_uuid16_t[]) {
    //     ble_peripheral_srv_uuid
    // };
    fields.uuids16 = (const ble_uuid16_t *)&ble_peripheral_srv_uuid;
    fields.num_uuids16 = 1;
    fields.uuids16_is_complete = 1;

    rc = ble_gap_adv_set_fields(&fields);
    if (rc != 0) {
        LLOGE("error setting advertisement data; rc=%d", rc);
        return;
    }

    /* Begin advertising. */
    // memset(&adv_params, 0, sizeof adv_params);
    adv_params.conn_mode = BLE_GAP_CONN_MODE_UND;
    adv_params.disc_mode = BLE_GAP_DISC_MODE_GEN;
    rc = ble_gap_adv_start(own_addr_type, NULL, BLE_HS_FOREVER,
                           &adv_params, bleprph_gap_event, NULL);
    if (rc != 0) {
        LLOGE("error enabling advertisement; rc=%d", rc);
        return;
    }
    else {
        LLOGD("ble_gap_adv start rc=0");
    }
}
#endif

/**
 * The nimble host executes this callback when a GAP event occurs.  The
 * application associates a GAP event callback with each connection that forms.
 * bleprph uses the same callback for all connections.
 *
 * @param event                 The type of event being signalled.
 * @param ctxt                  Various information pertaining to the event.
 * @param arg                   Application-specified argument; unused by
 *                                  bleprph.
 *
 * @return                      0 if the application successfully handled the
 *                                  event; nonzero on failure.  The semantics
 *                                  of the return code is specific to the
 *                                  particular GAP event being signalled.
 */
static int
bleprph_gap_event(struct ble_gap_event *event, void *arg)
{
    struct ble_gap_conn_desc desc;
    int rc;
    // LLOGD("gap event->type %d", event->type);
    char buff[BLE_UUID_STR_LEN + 1] = {0};
    rtos_msg_t msg = {
        .handler = l_ble_state_cb
    };
    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        /* A new connection was established or a connection attempt failed. */
        LLOGI("connection %s; status=%d ",
                    event->connect.status == 0 ? "established" : "failed",
                    event->connect.status);
        if (event->connect.status == 0) {
            g_ble_conn_handle = event->connect.conn_handle;
            rc = ble_gap_conn_find(event->connect.conn_handle, &desc);
            // if (rc == 0)
            //     bleprph_print_conn_desc(&desc);
            g_ble_state = BT_STATE_CONNECTED;
        }
        else {
            g_ble_state = BT_STATE_DISCONNECT;
        }
        msg.arg1 = g_ble_state;
        luat_msgbus_put(&msg, 0);
        // LLOGI("");

        if (event->connect.status != 0) {
            /* Connection failed; resume advertising. */
#if CONFIG_EXAMPLE_EXTENDED_ADV
            ext_bleprph_advertise();
#else
            bleprph_advertise();
#endif
        }
        return 0;

    case BLE_GAP_EVENT_DISCONNECT:
        g_ble_state = BT_STATE_DISCONNECT;
        LLOGI("disconnect; reason=%d ", event->disconnect.reason);
        // bleprph_print_conn_desc(&event->disconnect.conn);
        for (size_t i = 0; i < LUAT_BLE_MAX_CHR; i++)
        {
            s_chr_notify_states[i] = 0;
            s_chr_indicate_states[i] = 0;
        }
        
        msg.arg1 = g_ble_state;
        luat_msgbus_put(&msg, 0);

        /* Connection terminated; resume advertising. */
#if CONFIG_EXAMPLE_EXTENDED_ADV
        ext_bleprph_advertise();
#else
        bleprph_advertise();
#endif
        return 0;

    case BLE_GAP_EVENT_CONN_UPDATE:
        /* The central has updated the connection parameters. */
        LLOGI("connection updated; status=%d ", event->conn_update.status);
        rc = ble_gap_conn_find(event->conn_update.conn_handle, &desc);
        // if (rc == 0)
        //     bleprph_print_conn_desc(&desc);
        // LLOGI("");
        return 0;

    case BLE_GAP_EVENT_ADV_COMPLETE:
        LLOGI("advertise complete; reason=%d", event->adv_complete.reason);
#if !CONFIG_EXAMPLE_EXTENDED_ADV
        bleprph_advertise();
#endif
        return 0;

    case BLE_GAP_EVENT_ENC_CHANGE:
        /* Encryption has been enabled or disabled for this connection. */
        LLOGI("encryption change event; status=%d ",
                    event->enc_change.status);
        rc = ble_gap_conn_find(event->enc_change.conn_handle, &desc);
        if (rc == 0)
            bleprph_print_conn_desc(&desc);
        // LLOGI("");
        return 0;

    case BLE_GAP_EVENT_SUBSCRIBE:
        // LLOGI("subscribe event; conn_handle=%d attr_handle=%d "
        //             "reason=%d prevn=%d curn=%d previ=%d curi=%d",
        //             event->subscribe.conn_handle,
        //             event->subscribe.attr_handle,
        //             event->subscribe.reason,
        //             event->subscribe.prev_notify,
        //             event->subscribe.cur_notify,
        //             event->subscribe.prev_indicate,
        //             event->subscribe.cur_indicate);
        for (size_t i = 0; i < LUAT_BLE_MAX_CHR; i++)
        {
            if (s_chr_val_handles[i] == event->subscribe.attr_handle) {
                ble_uuid_to_str(&s_chr_uuids[i], buff);
                LLOGD("subscribe %s notify %d indicate %d", buff, event->subscribe.cur_notify, event->subscribe.cur_indicate);
                s_chr_notify_states[i] = event->subscribe.cur_notify;
                s_chr_indicate_states[i] = event->subscribe.cur_indicate;
                // TODO 发送系统消息
                return 0;
            }
        }
        LLOGI("subscribe event but chr NOT FOUND");
        return 0;

    case BLE_GAP_EVENT_MTU:
        LLOGI("mtu update event; conn_handle=%d cid=%d mtu=%d",
                    event->mtu.conn_handle,
                    event->mtu.channel_id,
                    event->mtu.value);
        return 0;

    case BLE_GAP_EVENT_REPEAT_PAIRING:
        /* We already have a bond with the peer, but it is attempting to
         * establish a new secure link.  This app sacrifices security for
         * convenience: just throw away the old bond and accept the new link.
         */

        /* Delete the old bond. */
        rc = ble_gap_conn_find(event->repeat_pairing.conn_handle, &desc);
        // assert(rc == 0);
        ble_store_util_delete_peer(&desc.peer_id_addr);

        /* Return BLE_GAP_REPEAT_PAIRING_RETRY to indicate that the host should
         * continue with the pairing operation.
         */
        return BLE_GAP_REPEAT_PAIRING_RETRY;

    case BLE_GAP_EVENT_PASSKEY_ACTION:
        LLOGI("PASSKEY_ACTION_EVENT started");
#if 0
        struct ble_sm_io pkey = {0};
        int key = 0;

        if (event->passkey.params.action == BLE_SM_IOACT_DISP) {
            pkey.action = event->passkey.params.action;
            pkey.passkey = 123456; // This is the passkey to be entered on peer
            // LLOGI("Enter passkey %d on the peer side", pkey.passkey);
            rc = ble_sm_inject_io(event->passkey.conn_handle, &pkey);
            LLOGI("ble_sm_inject_io BLE_SM_IOACT_DISP result: %d", rc);
        } else if (event->passkey.params.action == BLE_SM_IOACT_NUMCMP) {
            LLOGI("Passkey on device's display: %d", event->passkey.params.numcmp);
            LLOGI("Accept or reject the passkey through console in this format -> key Y or key N");
            pkey.action = event->passkey.params.action;
            // if (scli_receive_key(&key)) {
            //     pkey.numcmp_accept = key;
            // } else {
            //     pkey.numcmp_accept = 0;
            //     ESP_LOGE(tag, "Timeout! Rejecting the key");
            // }
            pkey.numcmp_accept = 1;
            rc = ble_sm_inject_io(event->passkey.conn_handle, &pkey);
            LLOGI("ble_sm_inject_io BLE_SM_IOACT_NUMCMP result: %d", rc);
        } else if (event->passkey.params.action == BLE_SM_IOACT_OOB) {
            static uint8_t tem_oob[16] = {0};
            pkey.action = event->passkey.params.action;
            for (int i = 0; i < 16; i++) {
                pkey.oob[i] = tem_oob[i];
            }
            rc = ble_sm_inject_io(event->passkey.conn_handle, &pkey);
            LLOGI("ble_sm_inject_io BLE_SM_IOACT_OOB result: %d", rc);
        } else if (event->passkey.params.action == BLE_SM_IOACT_INPUT) {
            LLOGI("Passkey on device's display: %d", event->passkey.params.numcmp);
            LLOGI("Enter the passkey through console in this format-> key 123456");
            pkey.action = event->passkey.params.action;
            // if (scli_receive_key(&key)) {
            //     pkey.passkey = key;
            // } else {
            //     pkey.passkey = 0;
            //     ESP_LOGE(tag, "Timeout! Passing 0 as the key");
            // }
            pkey.passkey = event->passkey.params.numcmp;
            rc = ble_sm_inject_io(event->passkey.conn_handle, &pkey);
            LLOGI("ble_sm_inject_io BLE_SM_IOACT_INPUT result: %d", rc);
        }
#endif
        return 0;
    }

    return 0;
}

static void
bleprph_on_reset(int reason)
{
    g_ble_state = BT_STATE_OFF;
    LLOGE("Resetting state; reason=%d", reason);
    //app_adapter_state_changed_callback(WM_BT_STATE_OFF);
}


static void
bleprph_on_sync(void)
{
    int rc;

#if CONFIG_EXAMPLE_RANDOM_ADDR
    /* Generate a non-resolvable private address. */
    ble_app_set_addr();
#endif

    /* Make sure we have proper identity address set (public preferred) */
#if CONFIG_EXAMPLE_RANDOM_ADDR
    rc = ble_hs_util_ensure_addr(1);
#else
    rc = ble_hs_util_ensure_addr(0);
#endif
    // assert(rc == 0);

    /* Figure out address to use while advertising (no privacy for now) */
    rc = ble_hs_id_infer_auto(0, &own_addr_type);
    if (rc != 0) {
        LLOGE("error determining address type; rc=%d", rc);
        return;
    }

    /* Printing ADDR */
    uint8_t addr_val[6] = {0};
    rc = ble_hs_id_copy_addr(own_addr_type, addr_val, NULL);
    if (rc) {
        LLOGE("ble_hs_id_copy_addr rc %d", rc);
    }

    LLOGI("Device Address: " ADDR_FMT, ADDR_T(addr_val));
    if (luat_ble_dev_name_len == 0) {
        sprintf_((char*)luat_ble_dev_name, "LOS-" ADDR_FMT, ADDR_T(addr_val));
        LLOGD("BLE name: %s", luat_ble_dev_name);
        luat_ble_dev_name_len = strlen((const char*)luat_ble_dev_name);
        rc = ble_svc_gap_device_name_set((const char*)luat_ble_dev_name);
        if (rc) {
            LLOGE("ble_svc_gap_device_name_set rc %d", rc);
        }
    }
    rc = ble_gatts_start();
    if (rc) {
        LLOGE("ble_gatts_start rc %d", rc);
    }

    /* Begin advertising. */
#if CONFIG_EXAMPLE_EXTENDED_ADV
    ext_bleprph_advertise();
#else
    bleprph_advertise();
#endif

    if (g_ble_state == BT_STATE_OFF)
        g_ble_state = BT_STATE_ON;
}



int luat_nimble_init_peripheral(uint8_t uart_idx, char* name, int mode) {
    int rc = 0;
    nimble_port_init();

    /* Set the default device name. */
    if (name != NULL && strlen(name)) {
        rc = ble_svc_gap_device_name_set((const char*)name);
    }

    /* Initialize the NimBLE host configuration. */
    ble_hs_cfg.reset_cb = bleprph_on_reset;
    ble_hs_cfg.sync_cb = bleprph_on_sync;
    ble_hs_cfg.gatts_register_cb = gatt_svr_register_cb;
    ble_hs_cfg.store_status_cb = ble_store_util_status_rr;

    ble_hs_cfg.sm_io_cap = BLE_SM_IO_CAP_NO_IO;
    ble_hs_cfg.sm_sc = 0;

    ble_svc_gap_init();
    ble_svc_gatt_init();

    rc = gatt_svr_init();
    if (rc)
        LLOGD("gatt_svr_init rc %d", rc);

    /* XXX Need to have template for store */
    ble_store_config_init();

    return 0;
}

