#ifndef __LUAT_NETDRV_OPENVPN_H__
#define __LUAT_NETDRV_OPENVPN_H__

#include "luat_netdrv.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * OpenVPN netdrv 初始化函数
 * @param conf netdrv 配置结构体指针
 * @return 成功返回 luat_netdrv_t 指针，失败返回 NULL
 */
luat_netdrv_t* luat_netdrv_openvpn_setup(luat_netdrv_conf_t *conf);

#ifdef __cplusplus
}
#endif

#endif /* __LUAT_NETDRV_OPENVPN_H__ */
