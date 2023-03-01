
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

#define ADDR_FMT "%02X%02X%02X%02X%02X%02X"
#define ADDR_T(addr) addr[0],addr[1],addr[2],addr[3],addr[4],addr[5]

static uint8_t ble_use_custom_name;
static uint8_t own_addr_type;
static uint8_t ble_ready;
void ble_store_config_init(void);

typedef struct ibeacon_data
{
    char data[16];
    uint16_t major;
    uint16_t minor;
    int8_t measured_power;
}ibeacon_data_t;

static ibeacon_data_t ibdata;
static void ble_app_advertise(void);

int luat_nimble_ibeacon_setup(void *uuid128, uint16_t major,
                         uint16_t minor, int8_t measured_power) {
    memcpy(ibdata.data, uuid128, 16);
    ibdata.major = major;
    ibdata.minor = minor;
    ibdata.measured_power = measured_power;
    if (ble_ready) {
        int rc = ble_ibeacon_set_adv_data(ibdata.data, ibdata.major, ibdata.minor, ibdata.measured_power);
        LLOGD("ble_ibeacon_set_adv_data rc %d", rc);
    }
    return 0;
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
    struct ble_gap_adv_params adv_params = {0};
    // uint8_t uuid128[16];
    int rc;

    // /* Arbitrarily set the UUID to a string of 0x11 bytes. */
    // memset(uuid128, 0x11, sizeof uuid128);

    /* Major version=2; minor version=10. */
    rc = ble_ibeacon_set_adv_data(ibdata.data, ibdata.major, ibdata.minor, ibdata.measured_power);
    LLOGD("ble_ibeacon_set_adv_data rc %d", rc);
    // assert(rc == 0);

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
    LLOGD("iBeacon GoGoGo");
    int rc;
    ble_hs_id_infer_auto(0, &own_addr_type);
    /* Printing ADDR */
    uint8_t addr_val[6] = {0};
    rc = ble_hs_id_copy_addr(own_addr_type, addr_val, NULL);

    LLOGI("Device Address: " ADDR_FMT, ADDR_T(addr_val));
    if (ble_use_custom_name == 0) {
        char buff[32];
        sprintf_(buff, "LOS-" ADDR_FMT, ADDR_T(addr_val));
        LLOGD("BLE name: %s", buff);
        rc = ble_svc_gap_device_name_set((const char*)buff);
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

    if (ibdata.major == 0) {
        ibdata.major = 2;
    }
    if (ibdata.minor == 0) {
        ibdata.minor = 10;
    }
    if (ibdata.data[0] == 0) {
        memset(ibdata.data, 0x11, 16);
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

