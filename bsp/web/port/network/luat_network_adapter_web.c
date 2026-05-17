#include "luat_base.h"

/*
 * Web BSP 当前只补齐最小启动链路。
 * 浏览器环境下的原生网络能力需要单独的 JS/Emscripten 适配层，
 * 因此这里先提供空初始化，避免误用 bsp/pc 的 POSIX socket 初始化逻辑。
 */
void luat_network_init(void) {
}

#ifndef LUAT_USE_LWIP
int net_lwip_check_all_ack(int socket_id) {
    (void)socket_id;
    return 0;
}
#endif
