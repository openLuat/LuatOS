#ifndef LUAT_BLUETOOTH
#define LUAT_BLUETOOTH




// ble

/*


*/




typedef enum{
    LUAT_BLE_IDLE
    // BLE_ACTV_IDLE,
    // BLE_ACTV_ADV_CREATED,
    // BLE_ACTV_ADV_STARTED,
    // BLE_ACTV_SCAN_CREATED,
    // BLE_ACTV_SCAN_STARTED,
    // BLE_ACTV_INIT_CREATED,
    // BLE_ACTV_PER_SYNC_CREATED,
    // BLE_ACTV_PER_SYNC_STARTED,
} luat_ble_actv_state;

#define ADV_TYPE_FLAGS                      (0x01)
#define ADV_TYPE_LOCAL_NAME                 (0x09)
#define ADV_TYPE_SERVICE_UUIDS_16BIT        (0x14)
#define ADV_TYPE_SERVICE_DATA               (0x16)
#define ADV_TYPE_MANUFACTURER_SPECIFIC      (0xFF)

typedef enum{
    LUAT_ADV_TYPE_FLAGS = 0x01,
    LUAT_ADV_TYPE_INCOMPLETE16,
    LUAT_ADV_TYPE_COMPLETE16,
    LUAT_ADV_TYPE_INCOMPLETE32,
    LUAT_ADV_TYPE_COMPLETE32,
    LUAT_ADV_TYPE_INCOMPLETE128,
    LUAT_ADV_TYPE_COMPLETE128,
    LUAT_ADV_TYPE_SHORTENED_LOCAL_NAME,
    LUAT_ADV_TYPE_COMPLETE_LOCAL_NAME,
    LUAT_ADV_TYPE_TX_POWER,
    LUAT_ADV_TYPE_CLASS_OF_DEVICE           = 0x0D,
    LUAT_ADV_TYPE_SIMPLE_PAIRING_HASH,
    LUAT_ADV_TYPE_SIMPLE_PAIRING_RANDOMIZER,
    LUAT_ADV_TYPE_DEVICE_ID,
    // LUAT_ADV_TYPE_SECURITY_MANAGER_TK_VALUE, // 0x10
    LUAT_ADV_TYPE_SECURITY_MANAGER_OOB_FLAGS,
    LUAT_ADV_TYPE_PERIPHERAL_CONN_INTERVAL,
    LUAT_ADV_TYPE_SERVICE_UUIDS_16BIT       = 0x14,
    LUAT_ADV_TYPE_SERVICE_UUIDS_128BIT,
    LUAT_ADV_TYPE_SERVICE_DATA_16BIT,
    LUAT_ADV_TYPE_PUBLIC_TARGET_ADDR,
    LUAT_ADV_TYPE_RANDOM_TARGET_ADDR,
    LUAT_ADV_TYPE_APPEARANCE,
    LUAT_ADV_TYPE_ADVERTISING_INTERVAL,
    LUAT_ADV_TYPE_LE_BLUETOOTH_DEVICE_ADDR,
    LUAT_ADV_TYPE_LE_ROLE,
    LUAT_ADV_TYPE_SIMP_PAIRING_HASH,
    LUAT_ADV_TYPE_SIMP_PAIRING_RANDOMIZER,
    LUAT_ADV_TYPE_SERVICE_UUIDS_32BIT,
    LUAT_ADV_TYPE_SERVICE_DATA_32BIT,
    LUAT_ADV_TYPE_SERVICE_DATA_128BIT,
    LUAT_ADV_TYPE_LE_SECURE_CONN_CONFIRM,
    LUAT_ADV_TYPE_LE_SECURE_CONN_RANDOM,
    LUAT_ADV_TYPE_URI,
    LUAT_ADV_TYPE_INDOOR_POSITION,
    LUAT_ADV_TYPE_TTANSPORT_DISC_DATA,
    LUAT_ADV_TYPE_LE_SUPPORT_FEATURES,
    LUAT_ADV_TYPE_CHAN_MAP_UPDATE_IND,
    LUAT_ADV_TYPE_PB_ADV,
    LUAT_ADV_TYPE_MESH_MESSAGE,
    LUAT_ADV_TYPE_MESH_BEACON,
    LUAT_ADV_TYPE_BIG_INFO,
    LUAT_ADV_TYPE_BROADCAST_CODE,
    LUAT_ADV_TYPE_RESOLVABLE_SET_ID,
    LUAT_ADV_TYPE_ADVERTISING_INTERVAL_LONG,
    LUAT_ADV_TYPE_BROADCAST_NAME,
    LUAT_ADV_TYPE_ENCRYPTED_ADVERTISING_DATA,
    LUAT_ADV_TYPE_PERIODIC_ADV_RESP_TIMING,
    LUAT_ADV_TYPE_ELECTRONIC_SHELF_LABEL        = 0X34,
    LUAT_ADV_TYPE_3D_INFO_DATA                  = 0x3D,
    LUAT_ADV_TYPE_MANUFACTURER_SPECIFIC_DATA    = 0xFF,
} luat_ble_adv_type_t;

typedef enum{
    LUAT_BLE_EVENT_NONE,
    // BLE
    LUAT_BLE_EVENT_INIT,        // BLE初始化成功
    LUAT_BLE_EVENT_DEINIT,      // BLE反初始化成功
    // ADV
    LUAT_BLE_EVENT_ADV_INIT,    // BLE初始化广播成功
    LUAT_BLE_EVENT_ADV_START,   // BLE开始广播
    LUAT_BLE_EVENT_ADV_STOP,    // BLE停止广播
    LUAT_BLE_EVENT_ADV_DEINIT,  // BLE反初始化广播成功
    // SCAN
    LUAT_BLE_EVENT_SCAN_INIT,   // BLE初始化扫描成功
    LUAT_BLE_EVENT_SCAN_START,  // BLE开始扫描
    LUAT_BLE_EVENT_SCAN_STOP,   // BLE停止扫描
    LUAT_BLE_EVENT_SCAN_DEINIT, // BLE反初始化扫描成功
    // CONN
    LUAT_BLE_EVENT_CONN,        // BLE连接成功
    LUAT_BLE_EVENT_DISCONN,     // BLE断开连接

    // WRITE
    LUAT_BLE_EVENT_WRITE,       // BLE写数据
    LUAT_BLE_EVENT_READ,        // BLE读数据

} luat_ble_event_t;

typedef struct{
    void* param0;
    void* param1;
    void* param2;
} luat_ble_param_t;

typedef struct {
    uint8_t *adv_data;
    int len;
}luat_ble_adv_data_t;

typedef struct luat_bluetooth luat_bluetooth_t;

typedef void (*luat_ble_cb_t)(luat_bluetooth_t* luat_bluetooth, luat_ble_event_t ble_event, luat_ble_param_t* ble_param);

typedef struct{
    uint8_t uuid[16];   // 16 bits UUID LSB First
    uint16_t perm;      // Attribute Permissions (see enum \ref bk_ble_perm_mask)
    /// Attribute Extended Permissions (see enum \ref bk_ble_ext_perm_mask)
    uint16_t ext_perm;
    /// Attribute Max Size
    /// note: for characteristic declaration contains handle offset
    /// note: for included service, contains target service handle
    uint16_t max_size;

    uint16_t value_len;
    ///pointer to value if BK_BLE_PERM_SET(RI, ENABLE) not set and BK_BLE_PERM_SET(VALUE_INCL, ENABLE) set
    void *p_value_context;
} luat_ble_att_db_t;

typedef struct {
    uint8_t uuid[16];
    luat_ble_att_db_t* att_db;  // attribute database
    uint8_t att_db_num;         // number of attributes database
}luat_ble_gatt_cfg_t;

typedef enum{
    LUAT_BLE_ADV_ADDR_MODE_PUBLIC,   // 控制器的公共地址
    LUAT_BLE_ADV_ADDR_MODE_RANDOM,   // 生成的静态地址
    LUAT_BLE_ADV_ADDR_MODE_RPA,      // 可解析的私有地址
    LUAT_BLE_ADV_ADDR_MODE_NRPA,     // 不可解析的私有地址
}luat_ble_adv_addr_mode_t;

typedef struct {
    luat_ble_adv_addr_mode_t addr_mode;
    int len;
}luat_ble_adv_cfg_t;

typedef struct {
    luat_ble_actv_state state;
    luat_ble_cb_t cb;
}luat_ble_t;

typedef struct {
    luat_ble_actv_state state;
    luat_ble_cb_t cb;
}luat_bt_t;

typedef struct luat_bluetooth{
    luat_ble_t* luat_ble;
    luat_bt_t* luat_bt;
}luat_bluetooth_t;


int luat_ble_init(luat_bluetooth_t* luat_bluetooth, luat_ble_cb_t luat_ble_cb);

int luat_ble_deinit(luat_bluetooth_t* luat_bluetooth);

int luat_ble_create_advertising(luat_bluetooth_t* luat_bluetooth, luat_ble_adv_cfg_t* adv_cfg);

int luat_ble_set_name(luat_bluetooth_t* luat_bluetooth, uint8_t* name, uint8_t len);

int luat_ble_set_adv_data(luat_bluetooth_t* luat_bluetooth, uint8_t* adv_buff, uint8_t adv_len);

int luat_ble_set_scan_rsp_data(luat_bluetooth_t* luat_bluetooth, uint8_t* scan_buff, uint8_t scan_len);

int luat_ble_start_advertising(luat_bluetooth_t* luat_bluetooth);

int luat_ble_stop_advertising(luat_bluetooth_t* luat_bluetooth);

int luat_ble_delete_advertising(luat_bluetooth_t* luat_bluetooth);

int luat_ble_create_gatt(luat_bluetooth_t* luat_bluetooth, luat_ble_gatt_cfg_t* gatt_cfg);

// bt


int luat_bt_get_mac(luat_bluetooth_t* luat_bluetooth, uint8_t *addr);
int luat_bt_set_mac(luat_bluetooth_t* luat_bluetooth, uint8_t *addr, uint8_t len);



// bluetooth

luat_bluetooth_t* luat_bluetooth_init(void);
int luat_bluetooth_deinit(luat_bluetooth_t* luat_bluetooth);

typedef enum{
    LUAT_BLE_WLAN_CONFIG_TYPE_BK,
}luat_ble_wlan_config_type_t;

typedef struct{
    uint8_t ssid[32];
    uint8_t password[64];
    uint8_t security;
}luat_ble_wlan_config_info_t;

int luat_ble_wlan_config(luat_ble_wlan_config_type_t config_type, luat_ble_wlan_config_info_t* config_info);

#endif
