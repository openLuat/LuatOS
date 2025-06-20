#ifndef __LUAT_BLE__
#define __LUAT_BLE__




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

// Permission
#define LUAT_BLE_GATT_PERM_READ                     (0x01 << 3) // Read
#define LUAT_BLE_GATT_PERM_WRITE                    (0x01 << 4) // Write
#define LUAT_BLE_GATT_PERM_IND                      (0x01 << 5) // Indication
#define LUAT_BLE_GATT_PERM_NOTIFY                   (0x01 << 6) // Notification
#define LUAT_BLE_GATT_PERM_WRITE_CMD                (0x01 << 7) // Write Command

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

// GATT SERVICE UUIDS 0X1800 - 0X185B
#define LUAT_BLE_GATT_SERVICE_MIN   0X1800
#define LUAT_BLE_GATT_SERVICE_MAX   0X185B

// Descriptors UUIDS 0X2900 - 0X2915
#define LUAT_BLE_GATT_DESC_MIN      0X2900
#define LUAT_BLE_GATT_DESC_MAX      0X2915

// Declarations
#define LUAT_BLE_PRIMARY_SERVICE    0x2800
#define LUAT_BLE_SECONDARY_SERVICE  0x2801
#define LUAT_BLE_INCLUDE            0x2802
#define LUAT_BLE_CHARACTERISTIC     0x2803

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
    LUAT_BLE_EVENT_SCAN_REPORT, // BLE扫描到设备
    // CONN
    LUAT_BLE_EVENT_CONN,        // BLE连接成功
    LUAT_BLE_EVENT_DISCONN,     // BLE断开连接
    LUAT_BLE_EVENT_GATT_DONE,     // BLE GATT

    // WRITE
    LUAT_BLE_EVENT_WRITE,       // BLE写数据
    LUAT_BLE_EVENT_READ,        // BLE读数据

    LUAT_BLE_EVENT_MAX,

} luat_ble_event_t;

typedef enum{
    LUAT_BLE_UUID_TYPE_16 = 2,
    LUAT_BLE_UUID_TYPE_32 = 4,
    LUAT_BLE_UUID_TYPE_128 = 16,
}luat_ble_uuid_type;

typedef struct luat_bluetooth luat_bluetooth_t;
typedef struct luat_ble luat_ble_t;
typedef struct luat_ble_gatt_chara luat_ble_gatt_chara_t;

#define LUAT_BLE_UUID_LEN_MAX   16

typedef struct luat_ble_uuid{
    uint8_t uuid[LUAT_BLE_UUID_LEN_MAX];
    luat_ble_uuid_type uuid_type;
}luat_ble_uuid_t;

typedef struct luat_ble_gatt_descriptor{
    uint16_t handle;
    uint8_t uuid[LUAT_BLE_UUID_LEN_MAX];
    luat_ble_uuid_type uuid_type;
    uint16_t perm;
    uint16_t max_size;
    uint8_t* value;
    uint16_t value_len;
}luat_ble_gatt_descriptor_t;

struct luat_ble_gatt_chara{
    uint16_t handle;
    uint8_t uuid[LUAT_BLE_UUID_LEN_MAX];
    luat_ble_uuid_type uuid_type;
    uint16_t perm;
    uint16_t max_size;
    uint8_t* value;
    uint16_t value_len;
    luat_ble_gatt_descriptor_t* descriptor;     // descriptor
    uint8_t descriptors_num;            // number of descriptor
};

typedef struct {
    uint8_t uuid[LUAT_BLE_UUID_LEN_MAX];
    luat_ble_uuid_type uuid_type;
    luat_ble_gatt_chara_t* characteristics; // characteristics
    uint8_t characteristics_num;            // number of characteristics
}luat_ble_gatt_service_t;

typedef enum{
    LUAT_BLE_ADDR_MODE_PUBLIC,   // 控制器的公共地址
    LUAT_BLE_ADDR_MODE_RANDOM,   // 生成的静态地址
    LUAT_BLE_ADDR_MODE_RPA,      // 可解析的私有地址
    LUAT_BLE_ADDR_MODE_NRPA,     // 不可解析的私有地址
}luat_ble_addr_mode_t;

typedef enum{
    LUAT_BLE_ADV_CHNL_37    = 0x01, /**< Byte value for advertising channel map for channel 37 enable */
    LUAT_BLE_ADV_CHNL_38    = 0x02, /**< Byte value for advertising channel map for channel 38 enable */
    LUAT_BLE_ADV_CHNL_39    = 0x04, /**< Byte value for advertising channel map for channel 39 enable */
    LUAT_BLE_ADV_CHNLS_ALL  = 0x07, /**< Byte value for advertising channel map for channel 37, 38 and 39 enable */
}luat_ble_adv_chnl_t;

typedef struct {
    luat_ble_adv_chnl_t channel_map;
    luat_ble_addr_mode_t addr_mode;
    uint32_t intv_min;
    uint32_t intv_max;
}luat_ble_adv_cfg_t;

/// Scan type
typedef enum {
    LUAT_BLE_PASSIVE_SCANNING,      // Passive Scanning. No scanning PDUs shall be sent (default)
    LUAT_BLE_ACTIVE_SCANNING,       // Active scanning. Scanning PDUs may be sent
}luat_ble_scan_type_t;

typedef struct {
    luat_ble_scan_type_t scan_type;
    luat_ble_addr_mode_t addr_mode;
    uint16_t scan_interval;         // Scan interval (in unit of 625us).
    uint16_t scan_window;           // Scan window (in unit of 625us).
}luat_ble_scan_cfg_t;

typedef struct{
    uint8_t peer_addr_type; /**< Peer address type */
    uint8_t peer_addr[6];   /**< Peer BT address */
} luat_ble_device_info_t;

typedef struct{
    uint16_t handle;       /**< The index of the attribute */
    uint8_t *value;         /**< The attribute value */
    uint16_t len;           /**< The length of the attribute value */
    uint16_t size;
} luat_ble_write_req_t;

typedef struct{
    uint16_t handle;       /**< The index of the attribute */
    uint8_t *value;         /**< The attribute value */
    uint16_t len;           /**< The data length read */
    uint16_t size;          /**< The size of attribute value to read */
} luat_ble_read_req_t;

typedef struct{
    uint8_t actv_idx;     /**< The index of the activity */
    uint8_t evt_type;     /**< Event type (see enum \ref adv_report_info and see enum \ref adv_report_type)*/
    uint8_t adv_addr_type;  /**< Advertising address type: public/random */
    int8_t rssi;         /**< RSSI value for advertising packet (in dBm, between -127 and +20 dBm) */
    uint8_t *data;        /**< Data of advertising packet */
    uint8_t data_len;     /**< Data length in advertising packet */
    uint8_t adv_addr[6];  /**<Advertising address value */
} luat_ble_adv_req_t;

typedef struct luat_ble_conn_ind{
    /// Peer address type
    uint8_t peer_addr_type;
    /// Peer BT address
    uint8_t peer_addr[6];
    /// Clock accuracy
    uint8_t clk_accuracy;
    /// Connection interval
    uint16_t con_interval;
    /// Connection latency
    uint16_t con_latency;
    /// Link supervision timeout
    uint16_t sup_to;
}luat_ble_conn_ind_t;

typedef struct luat_ble_disconn_ind{
    uint8_t reason;
}luat_ble_disconn_ind_t;

typedef struct{
    uint8_t gatt_service_num;
    luat_ble_gatt_service_t* gatt_service;
    void* user_data;
    union {
        luat_ble_device_info_t luat_ble_device_info;
        luat_ble_write_req_t write_req;
        luat_ble_read_req_t read_req;
        luat_ble_adv_req_t adv_req;
        luat_ble_conn_ind_t conn_ind;
        luat_ble_disconn_ind_t disconn_ind;
        uint8_t data[128]; // 预留一个大的后备区域
    };
} luat_ble_param_t;

typedef struct {
    uint8_t *adv_data;
    int len;
}luat_ble_adv_data_t;

typedef void (*luat_ble_cb_t)(luat_ble_t* luat_ble, luat_ble_event_t ble_event, luat_ble_param_t* ble_param);

struct luat_ble{
    uint8_t actv_idx;
    luat_ble_actv_state state;
    luat_ble_cb_t cb;
    void* userdata;
};

typedef struct luat_ble_rw_req{
    uint16_t handle;
    uint32_t len;
    uint8_t uuid[LUAT_BLE_UUID_LEN_MAX];
    uint8_t uuid_type;
    uint8_t re0;
    uint8_t re1[16];
    uint8_t data[0];
}luat_ble_rw_req_t;


// public function
int luat_ble_uuid_swap(uint8_t* uuid_data, luat_ble_uuid_type uuid_type);

int luat_ble_init(void* args, luat_ble_cb_t luat_ble_cb);

int luat_ble_deinit(void* args);

int luat_ble_set_name(void* args, char* name, uint8_t len);

int luat_ble_set_max_mtu(void* args, uint16_t max_mtu);

// advertise
int luat_ble_create_advertising(void* args, luat_ble_adv_cfg_t* adv_cfg);

int luat_ble_set_adv_data(void* args, uint8_t* adv_buff, uint8_t adv_len);

int luat_ble_set_scan_rsp_data(void* args, uint8_t* rsp_data, uint8_t rsp_len);

int luat_ble_start_advertising(void* args);

int luat_ble_stop_advertising(void* args);

int luat_ble_delete_advertising(void* args);

// gatt
int luat_ble_create_gatt(void* args, luat_ble_gatt_service_t* gatt_service);
int luat_ble_handle2uuid(uint16_t handle, luat_ble_uuid_t* uuid_service, luat_ble_uuid_t* uuid_characteristic, luat_ble_uuid_t* uuid_descriptor);
int luat_ble_uuid2handle(luat_ble_uuid_t* uuid_service, luat_ble_uuid_t* uuid_characteristic, luat_ble_uuid_t* uuid_descriptor, uint16_t* handle);

// slaver
// int luat_ble_read_response_value(void* args, uint16_t handle, uint8_t *data, uint32_t len);

int luat_ble_write_notify_value(luat_ble_uuid_t* uuid_service, luat_ble_uuid_t* uuid_characteristic, luat_ble_uuid_t* uuid_descriptor, uint8_t *data, uint16_t len);
int luat_ble_write_value(luat_ble_uuid_t* uuid_service, luat_ble_uuid_t* uuid_characteristic, luat_ble_uuid_t* uuid_descriptor, uint8_t *data, uint16_t len);
int luat_ble_read_value(luat_ble_uuid_t* uuid_service, luat_ble_uuid_t* uuid_characteristic, luat_ble_uuid_t* uuid_descriptor, uint8_t *data, uint16_t* len);


// master
int luat_ble_notify_enable(luat_ble_uuid_t* uuid_service, luat_ble_uuid_t* uuid_characteristic, luat_ble_uuid_t* uuid_descriptor, uint8_t enable);

// scanning
int luat_ble_create_scanning(void* args, luat_ble_scan_cfg_t* scan_cfg);

int luat_ble_start_scanning(void* args);

int luat_ble_stop_scanning(void* args);

int luat_ble_delete_scanning(void* args);

int luat_ble_connect(void* args, uint8_t* adv_addr,uint8_t adv_addr_type);

int luat_ble_disconnect(void* args);

#endif
