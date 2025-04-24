#include "luat_base.h"
#include "luat_mem.h"
#include "luat_bluetooth.h"

#include "luat_log.h"
#define LUAT_LOG_TAG "bluetooth"


enum{
    BEKEN_IDX_SVC,
    BEKEN_IDX_CHAR_DECL,
    BEKEN_IDX_CHAR_VALUE,
    BEKEN_IDX_CHAR_DESC,

    BEKEN_IDX_CHAR_OPERATION_DECL,
    BEKEN_IDX_CHAR_OPERATION_VALUE,

    BEKEN_IDX_CHAR_SSID_DECL,
    BEKEN_IDX_CHAR_SSID_VALUE,

    BEKEN_IDX_CHAR_PASSWORD_DECL,
    BEKEN_IDX_CHAR_PASSWORD_VALUE,

    BEKEN_IDX_NB,
};

#define BEKEN_SERVICE_UUID                   (0xFA00)

#define BEKEN_CHARA_PROPERTIES_UUID          (0xEA01)
#define BEKEN_CHARA_OPERATION_UUID           (0xEA02)

// 16 bits UUID
#define BEKEN_CHARA_SSID_UUID                (0xEA05)
#define BEKEN_CHARA_PASSWORD_UUID            (0xEA06)

// 128 bits UUID
#define DECL_PRIMARY_SERVICE_128     {0x00,0x28,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
#define DECL_CHARACTERISTIC_128      {0x03,0x28,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
#define DESC_CLIENT_CHAR_CFG_128     {0x02,0x29,0,0,0,0,0,0,0,0,0,0,0,0,0,0}

static luat_ble_att_db_t beken_service_db[BEKEN_IDX_NB] ={
    //  Service Declaration
    [BEKEN_IDX_SVC]        = {{BEKEN_SERVICE_UUID & 0xFF, BEKEN_SERVICE_UUID >> 8}, LUAT_BLE_GATT_PERM_READ, 0, 0},

    [BEKEN_IDX_CHAR_DECL]  = {DECL_CHARACTERISTIC_128,  LUAT_BLE_GATT_PERM_READ, 0, 0},
    // Characteristic Value
    [BEKEN_IDX_CHAR_VALUE] = {{BEKEN_CHARA_PROPERTIES_UUID & 0xFF, BEKEN_CHARA_PROPERTIES_UUID >> 8}, LUAT_BLE_GATT_PERM_NOTIFY, LUAT_BLE_GATT_UUID_16, 128},
    //Client Characteristic Configuration Descriptor
    [BEKEN_IDX_CHAR_DESC] = {DESC_CLIENT_CHAR_CFG_128, LUAT_BLE_GATT_PERM_READ | LUAT_BLE_GATT_PERM_WRITE, 0, 0},

    //opreation
    [BEKEN_IDX_CHAR_OPERATION_DECL]  = {DECL_CHARACTERISTIC_128, LUAT_BLE_GATT_PERM_READ, 0, 0},
    [BEKEN_IDX_CHAR_OPERATION_VALUE] = {{BEKEN_CHARA_OPERATION_UUID & 0xFF, BEKEN_CHARA_OPERATION_UUID >> 8, 0}, LUAT_BLE_GATT_PERM_WRITE, LUAT_BLE_GATT_UUID_16, 128},

    //ssid
    [BEKEN_IDX_CHAR_SSID_DECL]    = {DECL_CHARACTERISTIC_128, LUAT_BLE_GATT_PERM_READ, 0, 0},
    [BEKEN_IDX_CHAR_SSID_VALUE]   = {{BEKEN_CHARA_SSID_UUID & 0xFF, BEKEN_CHARA_SSID_UUID >> 8, 0}, LUAT_BLE_GATT_PERM_WRITE | LUAT_BLE_GATT_PERM_READ, LUAT_BLE_GATT_UUID_16, 128},

    //password
    [BEKEN_IDX_CHAR_PASSWORD_DECL]    = {DECL_CHARACTERISTIC_128, LUAT_BLE_GATT_PERM_READ, 0, 0},
    [BEKEN_IDX_CHAR_PASSWORD_VALUE]   = {{BEKEN_CHARA_PASSWORD_UUID & 0xFF, BEKEN_CHARA_PASSWORD_UUID >> 8, 0}, LUAT_BLE_GATT_PERM_WRITE | LUAT_BLE_GATT_PERM_READ, LUAT_BLE_GATT_UUID_16, 128},
};

static uint8_t bk_notify[2] = {0};

static void luat_ble_cb(luat_bluetooth_t* luat_bluetooth, luat_ble_event_t ble_event, luat_ble_param_t* ble_param){
    luat_ble_wlan_config_info_t* config_info = (luat_ble_wlan_config_info_t*)luat_bluetooth->luat_ble->userdata;
    luat_ble_wlan_config_cb_t luat_ble_wlan_config_cb = luat_bluetooth->luat_ble->wlan_config_cb;
    // LLOGD("ble event: %d", ble_event);
    switch(ble_event){
        case LUAT_BLE_EVENT_INIT:
    //         // luat_msgbus_push(0, "ble", "init");
            break;
        case LUAT_BLE_EVENT_DEINIT:
    //         // luat_msgbus_push(0, "ble", "connected");
            break;
        case LUAT_BLE_EVENT_WRITE:{
            luat_ble_write_req_t* write_req = &(ble_param->write_req);
            // LLOGD("write att_idx: %d", write_req->att_idx);
            switch (write_req->att_idx){
            case BEKEN_IDX_CHAR_DECL:
                break;
            case BEKEN_IDX_CHAR_VALUE:
                break;
            case BEKEN_IDX_CHAR_DESC:{
                memcpy(&bk_notify[0], &write_req->value[0], sizeof(bk_notify));
                // LLOGI("write notify: %02X %02X, length: %d", write_req->value[0], write_req->value[1], write_req->len);
                break;
            }
            case BEKEN_IDX_CHAR_OPERATION_DECL:
                break;

            case BEKEN_IDX_CHAR_OPERATION_VALUE:{
                uint16_t opcode = 0, length = 0;
                uint8_t *data = NULL;
                if (write_req->len < 2){
                    // LLOGE("error input: operation code length: " + write_req->len);
                    break;
                }
                opcode = write_req->value[0] | write_req->value[1] << 8;
                if (write_req->len >= 4){
                    // length = write_req->value[2] | write_req->value[3] << 8;
                }
                if (write_req->len > 4){
                    // data = &write_req->value[4];
                }
                // LLOGD("%s, opcode: %04X, length: %04X ", __func__, opcode, length);
                if(opcode == 0x01){
                    luat_ble_wlan_config_cb(luat_bluetooth, LUAT_BLE_EVENT_WLAN_CONFIG_SUCCESS, config_info);
                }
                break;
            }
            case BEKEN_IDX_CHAR_SSID_DECL:
                break;
            case BEKEN_IDX_CHAR_SSID_VALUE:{
                config_info->ssid_len = write_req->len;
                memset(config_info->ssid, 0, write_req->len+1);
                memcpy(config_info->ssid, write_req->value, write_req->len);

                // LLOGI("write ssid: %s, length: %d", config_info->ssid, config_info->ssid_len);
                break;
            }
            case BEKEN_IDX_CHAR_PASSWORD_DECL:
                break;
            case BEKEN_IDX_CHAR_PASSWORD_VALUE:{
                config_info->password_len = write_req->len;
                memset(config_info->password, 0, write_req->len+1);
                memcpy(config_info->password, write_req->value, write_req->len);

                // LLOGI("write password: %s, length: %d", config_info->password, config_info->password_len);
                break;
            }
            default:
                break;
            }
        }
        case LUAT_BLE_EVENT_READ: {
            luat_ble_read_req_t* read_req = &(ble_param->read_req);
            // LLOGD("read att_idx: %d", read_req->att_idx);
            switch (read_req->att_idx){
            case BEKEN_IDX_CHAR_DECL:
                break;
            case BEKEN_IDX_CHAR_VALUE:
                break;
            case BEKEN_IDX_CHAR_DESC:{
                luat_ble_read_response(luat_bluetooth,read_req->conn_idx, read_req->att_idx, sizeof(bk_notify), &bk_notify[0]);
                break;
            }

            case BEKEN_IDX_CHAR_SSID_DECL:
                break;
            case BEKEN_IDX_CHAR_SSID_VALUE:{
                luat_ble_read_response(luat_bluetooth,read_req->conn_idx, read_req->att_idx, config_info->ssid_len, config_info->ssid);
                // LLOGI("read ssid: %s, length: %d", config_info->ssid, config_info->ssid_len);
                break;
            }
            case BEKEN_IDX_CHAR_PASSWORD_DECL:
                break;
            case BEKEN_IDX_CHAR_PASSWORD_VALUE:{
                luat_ble_read_response(luat_bluetooth,read_req->conn_idx, read_req->att_idx, config_info->password_len, config_info->password);
                // LLOGI("read ssid: %s, length: %d", config_info->password, config_info->password_len);
                break;
            }
            default:
                break;
            }
        }
        default:
            break;
    }
}

#define BEKEN_COMPANY_ID                    (0x05F0)
#define BEKEN_GATTS_UUID                    (0xFE01)

int luat_ble_wlan_config_bk(luat_ble_wlan_config_info_t* config_info, luat_ble_cb_t luat_ble_wlan_config_cb){
    int ret = 0;
    luat_bluetooth_t* luat_bluetooth = luat_bluetooth_init();
    luat_ble_init(luat_bluetooth, luat_ble_cb);
    luat_bluetooth->luat_ble->userdata = config_info;
    luat_bluetooth->luat_ble->wlan_config_cb = luat_ble_wlan_config_cb;
    luat_ble_gatt_cfg_t luat_ble_gatt_cfg = {
        .uuid = {0x00, 0xFA},
        .att_db = beken_service_db,
        .att_db_num = BEKEN_IDX_NB,
    };
    luat_ble_create_gatt(luat_bluetooth, &luat_ble_gatt_cfg);

    char complete_local_name[32] = {0};
    sprintf_(complete_local_name, "LuatOS_%s", luat_os_bsp());

    luat_ble_adv_cfg_t luat_ble_adv_cfg = {
        .addr_mode = LUAT_BLE_ADV_ADDR_MODE_PUBLIC,
    };
    ret = luat_ble_create_advertising(luat_bluetooth, &luat_ble_adv_cfg);

    // 广播内容 (adv data)
    uint8_t adv_data[255] = {0};
    uint8_t adv_index = 0;
    /* flags */
    adv_data[adv_index++] = 0x02;
    adv_data[adv_index++] = LUAT_ADV_TYPE_FLAGS;
    adv_data[adv_index++] = 0x06;
    /* dev_name */
    adv_data[adv_index++] = 0x0F;
    adv_data[adv_index++] = LUAT_ADV_TYPE_COMPLETE_LOCAL_NAME;
    memcpy(adv_data + adv_index, complete_local_name, strlen(complete_local_name));
    adv_index += strlen(complete_local_name);
    /* 16bit uuid */
    adv_data[adv_index++] = 0x03;
    adv_data[adv_index++] = LUAT_ADV_TYPE_SERVICE_DATA_16BIT;
    adv_data[adv_index++] = BEKEN_GATTS_UUID & 0xFF;
    adv_data[adv_index++] = BEKEN_GATTS_UUID >> 8;
    /* manufacturer */
    adv_data[adv_index++] = 0x03;
    adv_data[adv_index++] = LUAT_ADV_TYPE_MANUFACTURER_SPECIFIC_DATA;
    adv_data[adv_index++] = BEKEN_COMPANY_ID & 0xFF;
    adv_data[adv_index++] = BEKEN_COMPANY_ID >> 8;
	
    /* set adv paramters */
	ret = luat_ble_set_adv_data(luat_bluetooth, adv_data, adv_index);

    luat_ble_set_name(luat_bluetooth, complete_local_name, strlen(complete_local_name));

	/* sart adv */
	ret = luat_ble_start_advertising(luat_bluetooth);

    return ret;
}

int luat_ble_wlan_config(luat_ble_wlan_config_type_t config_type, luat_ble_wlan_config_cb_t luat_ble_wlan_config_cb){
    luat_ble_wlan_config_info_t* config_info = luat_heap_malloc(sizeof(luat_ble_wlan_config_info_t));
    memset(config_info, 0, sizeof(luat_ble_wlan_config_info_t));
    switch (config_type){
    case LUAT_BLE_WLAN_CONFIG_TYPE_BK:
        return luat_ble_wlan_config_bk(config_info, luat_ble_wlan_config_cb);
    default:
        break;
    }
    return -1;
}





