#ifndef LUAT_AIRLINK_INSTANCE_H
#define LUAT_AIRLINK_INSTANCE_H

#if defined(LUAT_USE_AIRLINK_MANUAL_SETUP) && !defined(LUAT_USE_AIRLINK_INSTANCE)
#error "LUAT_USE_AIRLINK_MANUAL_SETUP requires LUAT_USE_AIRLINK_INSTANCE"
#endif

/* Link IDs and transport modes are separate namespaces. */
#define AIRLINK_LINK_COUNT 2
#define AIRLINK_ROUTE_BASE 128
#define AIRLINK_FEATURE_WIFI 1
#define AIRLINK_FEATURE_CELLULAR 2
#define AIRLINK_FEATURE_BLE 4
#define AIRLINK_DRV_6208 1
#define AIRLINK_DRV_6205 2
#define AIRLINK_DRV_780ER2 3
#define AIRLINK_DRV_780EPM AIRLINK_DRV_780ER2
#define AIRLINK_DRV_8000S 4

/* Shared by pre-Lua onboard startup and the Lua air8000s defaults. */
#define AIRLINK_8000S_SPI_ID 0
#define AIRLINK_8000S_CS 8
#define AIRLINK_8000S_RDY 22
#define AIRLINK_8000S_SPEED 31000000

void luat_airlink_statistics_add(uint64_t* counter, uint64_t value);
void luat_airlink_statistics_copy(airlink_statistic_t* dst, const airlink_statistic_t* src);

#ifdef LUAT_USE_AIRLINK_INSTANCE
typedef struct {
    uint8_t mode, drv, uart_id, spi_id, cs, rdy;
    uint32_t speed;
    int sta_adapter, ap_adapter, cellular_adapter;
} luat_airlink_setup_t;

int luat_airlink_setup_link(int id, const luat_airlink_setup_t* conf);
int luat_airlink_stop_link(int id);
int luat_airlink_link_configured(int id);
int luat_airlink_link_ready(int id);
int luat_airlink_instance_enabled(void);
int luat_airlink_context_link(void);
int luat_airlink_in_dispatch(int route);
int luat_airlink_feature_route(int feature);
int luat_airlink_feature_rpc_supported(int feature);
int luat_airlink_rpc_route(int route, unsigned rpc_id);
int luat_airlink_instance_default_route(const luat_airlink_cmd_t* cmd);
int luat_airlink_link_send(int id, const luat_airlink_cmd_t* cmd);
int luat_airlink_link_receive(int id, const uint8_t* data, size_t len);
int luat_airlink_link_send_ip(uint8_t adapter, const uint8_t* data, size_t len);
int luat_airlink_link_adapter(int id, int remote);
int luat_airlink_link_peer_copy(int id, luat_airlink_dev_info_t* peer);
void luat_airlink_link_update_peer(int id, const luat_airlink_dev_info_t* peer);
airlink_statistic_t* luat_airlink_link_statistics(int id);
int luat_airlink_link_snapshot(int id, airlink_statistic_t* stats, luat_airlink_dev_info_t* peer);
int luat_airlink_link_spi_transfer(int id, const uint8_t* tx, uint8_t* rx, size_t len);
void luat_airlink_instance_dispatch(luat_airlink_cmd_t* cmd);
void luat_airlink_fragment_reset(void);
int luat_airlink_flags_supported_link(int id, int rpc);
int luat_airlink_arq_state_link(int id);
#else
static inline int luat_airlink_context_link(void) { return -1; }
static inline int luat_airlink_in_dispatch(int route) { (void)route; return 0; }
static inline int luat_airlink_instance_enabled(void) { return 0; }
static inline int luat_airlink_feature_route(int feature) { (void)feature; return luat_airlink_current_mode_get(); }
static inline int luat_airlink_feature_rpc_supported(int feature) {
    (void)feature;
    return luat_airlink_current_mode_get() >= 0 && luat_airlink_peer_rpc_supported();
}
static inline int luat_airlink_rpc_route(int route, unsigned rpc_id) { (void)rpc_id; return route; }
#endif
#endif
