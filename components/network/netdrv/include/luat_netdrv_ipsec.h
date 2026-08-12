#ifndef __LUAT_NETDRV_IPSEC_H__
#define __LUAT_NETDRV_IPSEC_H__

#include "luat_netdrv.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * IKEv2/IPsec 隧道模式 netdrv 初始化函数
 * @param conf netdrv 配置结构体指针
 * @return 成功返回 luat_netdrv_t 指针，失败返回 NULL
 */
luat_netdrv_t* luat_netdrv_ipsec_setup(luat_netdrv_conf_t *conf);

/**
 * 测试钩子: 模拟一次本地地址变更, 触发 MOBIKE 更新流程
 * @param adapter_id netdrv 适配器编号
 * @return 0 成功, 其他失败
 */
int luat_netdrv_ipsec_sim_addr_change(int adapter_id);

#ifdef __cplusplus
}
#endif

#endif /* __LUAT_NETDRV_IPSEC_H__ */
