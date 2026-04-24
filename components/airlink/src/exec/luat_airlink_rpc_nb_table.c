/*
 * luat_airlink_rpc_nb_table.c
 *
 * 静态 nanopb RPC handler 表 — 按编译宏控制哪些模块参与
 * 在 nb_dispatch 中优先于动态注册表搜索（无需加锁）
 */

#include "luat_base.h"  /* 引入 luat_conf_bsp.h 以获得 LUAT_USE_AIRLINK_RPC 等宏 */

#ifdef LUAT_USE_AIRLINK_RPC

#include "luat_airlink_rpc.h"

#ifdef LUAT_USE_AIRLINK_RPC_GPIO
extern const luat_airlink_rpc_nb_reg_t luat_airlink_rpc_gpio_reg;
#endif
#ifdef LUAT_USE_AIRLINK_RPC_UART
extern const luat_airlink_rpc_nb_reg_t luat_airlink_rpc_uart_reg;
#endif
#ifdef LUAT_USE_AIRLINK_RPC_WLAN
extern const luat_airlink_rpc_nb_reg_t luat_airlink_rpc_wlan_reg;
#endif
#ifdef LUAT_USE_AIRLINK_RPC_PM
extern const luat_airlink_rpc_nb_reg_t luat_airlink_rpc_pm_reg;
#endif
#ifdef LUAT_USE_AIRLINK_RPC_SDATA
extern const luat_airlink_rpc_nb_reg_t luat_airlink_rpc_sdata_reg;
#endif

const luat_airlink_rpc_nb_reg_t* const luat_airlink_rpc_nb_static_table[] = {
#ifdef LUAT_USE_AIRLINK_RPC_GPIO
    &luat_airlink_rpc_gpio_reg,
#endif
#ifdef LUAT_USE_AIRLINK_RPC_UART
    &luat_airlink_rpc_uart_reg,
#endif
#ifdef LUAT_USE_AIRLINK_RPC_WLAN
    &luat_airlink_rpc_wlan_reg,
#endif
#ifdef LUAT_USE_AIRLINK_RPC_PM
    &luat_airlink_rpc_pm_reg,
#endif
#ifdef LUAT_USE_AIRLINK_RPC_SDATA
    &luat_airlink_rpc_sdata_reg,
#endif
};

const size_t luat_airlink_rpc_nb_static_count =
    sizeof(luat_airlink_rpc_nb_static_table) / sizeof(luat_airlink_rpc_nb_static_table[0]);

#endif /* LUAT_USE_AIRLINK_RPC */
