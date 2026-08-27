/**
 * \file mbedtls_config_pc_mbedtls3.h
 *
 * \brief PC simulator configuration for Mbed TLS 3.x.
 *
 * 基于 3.x 标准模板 (mbedtls/mbedtls_config.h)，按 PC 模拟器需求裁剪：
 *  - 关闭 TLS 1.3（网络适配器固定使用 TLS 1.2）
 *  - 关闭 CCM / ARIA / CAMELLIA（与旧 PC 配置一致）
 */
#ifndef LUATOS_MBEDTLS_CONFIG_PC_MBEDTLS3_H
#define LUATOS_MBEDTLS_CONFIG_PC_MBEDTLS3_H

#include "mbedtls/mbedtls_config.h"

#undef MBEDTLS_SSL_PROTO_TLS1_3
#undef MBEDTLS_CCM_C
#undef MBEDTLS_ARIA_C
#undef MBEDTLS_CAMELLIA_C

#endif /* LUATOS_MBEDTLS_CONFIG_PC_MBEDTLS3_H */
