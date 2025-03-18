#ifndef LUAT_AIRLINK_H
#define LUAT_AIRLINK_H

typedef struct luat_airlink_cmd
{
    uint16_t cmd; // 命令, 从0x0001开始, 到0xfffe结束
    uint16_t len; // 数据长度,最高64k, 实际使用最高2k
    uint8_t data[0];
}luat_airlink_cmd_t;

int luat_airlink_init(void);
int luat_airlink_start(int id);
int luat_airlink_stop(int id);

void luat_airlink_data_pack(uint8_t* buff, size_t len, uint8_t* dst);
void luat_airlink_data_unpack(uint8_t* buff, size_t len, size_t* pkg_offset, size_t* pkg_size);

void luat_airlink_task_start(void);
void luat_airlink_print_buff(const char* tag, uint8_t* buff, size_t len);
void luat_airlink_on_data_recv(uint8_t *data, size_t len);

typedef void (*luat_airlink_newdata_notify_cb)(void);

typedef int (*luat_airlink_cmd_exec)(luat_airlink_cmd_t* cmd, void* userdata);

typedef struct luat_airlink_cmd_reg
{
    uint16_t id;
    luat_airlink_cmd_exec exec;
}luat_airlink_cmd_reg_t;

enum {
    LUAT_AIRLINK_QUEUE_CMD = 1,
    LUAT_AIRLINK_QUEUE_IPPKG
};

typedef struct airlink_queue_item {
    size_t len;
    luat_airlink_cmd_t* cmd;
}airlink_queue_item_t;

int luat_airlink_queue_send(int tp, airlink_queue_item_t* item);

int luat_airlink_queue_get_cnt(int tp);

int luat_airlink_cmd_recv(int tp, airlink_queue_item_t* cmd, size_t timeout);

int luat_airlink_cmd_recv_simple(airlink_queue_item_t* cmd);

int luat_airlink_queue_send_ippkg(uint8_t adapter_id, uint8_t* data, size_t len);

void luat_airlink_print_mac_pkg(uint8_t* buff, uint16_t len);
void luat_airlink_hexdump(const char* tag, uint8_t* buff, uint16_t len);

typedef struct luat_airlink_dev_wifi_info {
    uint8_t sta_mac[6];
    uint8_t ap_mac[6];
    uint8_t bt_mac[6];
    uint8_t sta_state;
    uint8_t ap_state;
}luat_airlink_dev_wifi_info_t;

typedef struct luat_airlink_dev_cat_info {
    uint8_t ipv4[4];
    uint8_t ipv6[16];
    uint8_t cat_state;
    uint8_t sim_state;
    uint8_t imei[16];
    uint8_t iccid[20];
    uint8_t imsi[16];
}luat_airlink_dev_wifi_cat_t;

typedef struct luat_airlink_dev_info
{
    uint8_t tp;
    union
    {
        luat_airlink_dev_wifi_info_t wifi;
        luat_airlink_dev_wifi_cat_t cat1;
    };
    uint8_t unique_id_len;
    uint8_t unique_id[24];
}luat_airlink_dev_info_t;


extern luat_airlink_newdata_notify_cb g_airlink_newdata_notify_cb;

#endif
