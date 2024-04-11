#ifndef LUAT_WLAN_RAW_H
#define LUAT_WLAN_RAW_H

typedef struct luat_wlan_raw_conf {
    int id;
}luat_wlan_raw_conf_t;

typedef struct luat_wlan_raw_data {
    int zbuff_ref;
    size_t* zbuff_used;
    uint8_t *buff;
    // int used;
}luat_wlan_raw_data_t;

int luat_wlan_raw_setup(luat_wlan_raw_conf_t *conf);
int luat_wlan_raw_close(luat_wlan_raw_conf_t *conf);
// int luat_wlan_raw_read(luat_wlan_raw_conf_t *conf, uint8_t* src, uint8_t* buf, size_t len);
int luat_wlan_raw_write(int id, uint8_t* buf, size_t len);

int l_wlan_raw_event(int tp, void* buff, size_t max_size);

#endif
