#ifndef LUAT_AIRLINK_TRANSPORT_H
#define LUAT_AIRLINK_TRANSPORT_H

#include "luat_airlink.h"

// =====================================================================
// 多出口支持：per-transport 槽位 + adapter-to-transport 绑定
// =====================================================================

#define LUAT_AIRLINK_MAX_TRANSPORTS  3   // slot 总数 (0=SPI_SLAVE, 1=SPI_MASTER, 2=UART)
#define LUAT_AIRLINK_MAX_ADAPTERS   16   // adapter-to-transport 绑定表大小

typedef struct luat_airlink_transport_slot {
    uint8_t  active;
    luat_rtos_queue_t cmd_queue;
    luat_rtos_queue_t ippkg_queue;
    luat_airlink_newdata_notify_cb notify_cb;
} luat_airlink_transport_slot_t;

// 注册/注销 transport 槽位 (由各 transport task 调用); 队列由 luat_airlink_start 创建
int luat_airlink_slot_register(uint8_t mode, luat_airlink_newdata_notify_cb notify_cb);
int luat_airlink_slot_unregister(uint8_t mode);

// 绑定 adapter_id 到指定 transport mode (0xFF=解绑)
int luat_airlink_bind_adapter_transport(uint8_t adapter_id, uint8_t mode);

// 向特定 transport 发送命令
int luat_airlink_send2transport(luat_airlink_cmd_t* cmd, uint8_t mode);

// transport task 从自己专属的槽位队列获取待发送数据 (替代 luat_airlink_cmd_recv_simple)
int luat_airlink_cmd_recv_for_mode(uint8_t mode, airlink_queue_item_t* item);

#endif /* LUAT_AIRLINK_TRANSPORT_H */
