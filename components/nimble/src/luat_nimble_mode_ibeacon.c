
#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "luat_base.h"
#if (defined(AIR101) || defined(AIR103))
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
#include "luat_malloc.h"
#include "luat_nimble.h"

#define LUAT_LOG_TAG "nimble"
#include "luat_log.h"

/* BLE */
#include "nimble/nimble_port.h"
// #include "nimble/nimble_port_freertos.h"

#define BLE_IBEACON_MFG_DATA_SIZE       25

#define ADDR_FMT "%02X%02X%02X%02X%02X%02X"
#define ADDR_T(addr) addr[0],addr[1],addr[2],addr[3],addr[4],addr[5]

static uint8_t ble_use_custom_name;
static uint8_t own_addr_type;
static uint8_t ble_ready;
void ble_store_config_init(void);


extern uint8_t luat_ble_dev_name[];
extern size_t  luat_ble_dev_name_len;

extern uint8_t adv_buff[];
extern int adv_buff_len;
extern struct ble_hs_adv_fields adv_fields;
extern struct ble_gap_adv_params adv_params;

static void ble_app_advertise(void);

int luat_nimble_ibeacon_setup(void *uuid128, uint16_t major,
                         uint16_t minor, int8_t measured_power) {
    uint8_t buf[BLE_IBEACON_MFG_DATA_SIZE];
    int rc;
    /** Company identifier (Apple). */
    buf[0] = 0x4c;
    buf[1] = 0x00;
    /** iBeacon indicator. */
    buf[2] = 0x02;
    buf[3] = 0x15;
    /** UUID. */
    memcpy(buf + 4, uuid128, 16);
    /** Version number. */
    put_be16(buf + 20, major);
    put_be16(buf + 22, minor);

    /* Measured Power ranging data (Calibrated tx power at 1 meters). */
    if(measured_power < -126 || measured_power > 20) {
        return BLE_HS_EINVAL;
    }

    buf[24] = measured_power;
    int flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    return luat_nimble_set_adv_data((char* )buf, BLE_IBEACON_MFG_DATA_SIZE, flags);
}

int luat_nimble_set_adv_data(char* buff, size_t len, int flags) {
    if (buff == NULL)
        return -1;
    int rc = 0;
    if (len > 128)
        len = 128;
    adv_buff_len = len;
    memcpy(adv_buff, buff, len);
    memset(&adv_fields, 0, sizeof adv_fields);
    adv_fields.mfg_data = adv_buff;
    adv_fields.mfg_data_len = adv_buff_len;
    adv_fields.flags = flags;

    if (luat_ble_dev_name_len == 0) {
        const char * name = ble_svc_gap_device_name();
        adv_fields.name = (uint8_t *)name;
        adv_fields.name_len = strlen(name);
        adv_fields.name_is_complete = 1;
    }
    else {
        adv_fields.name = (uint8_t *)luat_ble_dev_name;
        adv_fields.name_len = luat_ble_dev_name_len;
        adv_fields.name_is_complete = 1;
    }

    if (ble_ready) {
        rc = ble_gap_adv_set_fields(&adv_fields);
        LLOGD("ble_gap_adv_set_fields rc %d", rc);
        return rc;
    }

    return rc;
}

static int
bleprph_gap_event(struct ble_gap_event *event, void *arg)
{
    switch (event->type) {
    case BLE_GAP_EVENT_ADV_COMPLETE:
        LLOGI("advertise complete; reason=%d", event->adv_complete.reason);
        return 0;
    }
    return 0;
}

static void
ble_app_advertise(void)
{
    // uint8_t uuid128[16];
    int rc;

    rc = ble_gap_adv_set_fields(&adv_fields);
    LLOGD("ble_gap_adv_set_fields rc %d", rc);

    /* Begin advertising. */
    // adv_params = (struct ble_gap_adv_params){ 0 };
    rc = ble_gap_adv_start(own_addr_type, NULL, BLE_HS_FOREVER,
                           &adv_params, bleprph_gap_event, NULL);
    LLOGD("ble_gap_adv_start rc %d", rc);
    ble_ready = 1;
}

static void
bleprph_on_sync(void)
{
    // LLOGD("iBeacon GoGoGo");
    int rc;
    ble_hs_id_infer_auto(0, &own_addr_type);
    /* Printing ADDR */
    uint8_t addr_val[6] = {0};
    rc = ble_hs_id_copy_addr(own_addr_type, addr_val, NULL);

    LLOGI("Device Address: " ADDR_FMT, ADDR_T(addr_val));
    if (luat_ble_dev_name_len == 0) {
        sprintf_((char*)luat_ble_dev_name, "LOS-" ADDR_FMT, ADDR_T(addr_val));
        LLOGD("BLE name: %s", luat_ble_dev_name);
        luat_ble_dev_name_len = strlen((const char*)luat_ble_dev_name);
        rc = ble_svc_gap_device_name_set((const char*)luat_ble_dev_name);
        
    }

    /* Advertise indefinitely. */
    ble_app_advertise();
}

int luat_nimble_init_ibeacon(uint8_t uart_idx, char* name, int mode) {
    int rc = 0;
    nimble_port_init();

    /* Set the default device name. */
    if (name != NULL && strlen(name)) {
        rc = ble_svc_gap_device_name_set((const char*)name);
        ble_use_custom_name = 1;
    }

    /* Initialize the NimBLE host configuration. */
    // ble_hs_cfg.reset_cb = bleprph_on_reset;
    ble_hs_cfg.sync_cb = bleprph_on_sync;
    // ble_hs_cfg.gatts_register_cb = gatt_svr_register_cb;
    // ble_hs_cfg.store_status_cb = ble_store_util_status_rr;

    ble_hs_cfg.sm_io_cap = BLE_SM_IO_CAP_NO_IO;
    ble_hs_cfg.sm_sc = 0;

    ble_svc_gap_init();
    // ble_svc_gatt_init();

    // rc = gatt_svr_init();
    // LLOGD("gatt_svr_init rc %d", rc);

    /* XXX Need to have template for store */
    ble_store_config_init();

    return 0;
}

