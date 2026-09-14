/**
 * \file mbedtls_config_pc_mbedtls3.h
 *
 * \brief PC simulator configuration for Mbed TLS 3.x.
 *
 * 基于 3.x 标准模板 (mbedtls/mbedtls_config.h)，按 PC 模拟器需求裁剪：
 *  - 关闭 TLS 1.3（网络适配器固定使用 TLS 1.2）
 *  - 关闭 CCM / ARIA / CAMELLIA（与旧 PC 配置一致）
 *  - 关闭 DHE / 静态 ECDH 套件（保留 ECDHE；MBEDTLS_DHM_C 保留供 ipsec 使用）
 *  - 关闭 cipher 层的 CFB / OFB / XTS / NIST KW（非 TLS 套件，crypto 库未使用）
 */
#ifndef LUATOS_MBEDTLS_CONFIG_PC_MBEDTLS3_H
#define LUATOS_MBEDTLS_CONFIG_PC_MBEDTLS3_H

#include "mbedtls/mbedtls_config.h"

#undef MBEDTLS_SSL_PROTO_TLS1_3
#undef MBEDTLS_CCM_C
#undef MBEDTLS_ARIA_C
#undef MBEDTLS_CAMELLIA_C
#undef MBEDTLS_CIPHER_MODE_CFB
#undef MBEDTLS_CIPHER_MODE_OFB
#undef MBEDTLS_CIPHER_MODE_XTS
#undef MBEDTLS_NIST_KW_C
#undef MBEDTLS_KEY_EXCHANGE_DHE_RSA_ENABLED
#undef MBEDTLS_KEY_EXCHANGE_DHE_PSK_ENABLED
#undef MBEDTLS_KEY_EXCHANGE_ECDH_RSA_ENABLED
#undef MBEDTLS_KEY_EXCHANGE_ECDH_ECDSA_ENABLED

/* 与 ec7xx 设备端配置(2024库 mbedtls3_ec7xx_config.h / 2.x 裁剪集)对齐:
 * 只保留 P-256 + P-384 + x25519. P-384 保留证书链验签能力;
 * 关闭的曲线连验签能力一并移除(对端 P-521/K1/BP/448 证书链会失败) */
#undef MBEDTLS_ECP_DP_SECP192R1_ENABLED
#undef MBEDTLS_ECP_DP_SECP224R1_ENABLED
#undef MBEDTLS_ECP_DP_SECP521R1_ENABLED
#undef MBEDTLS_ECP_DP_SECP192K1_ENABLED
#undef MBEDTLS_ECP_DP_SECP224K1_ENABLED
#undef MBEDTLS_ECP_DP_SECP256K1_ENABLED
#undef MBEDTLS_ECP_DP_BP256R1_ENABLED
#undef MBEDTLS_ECP_DP_BP384R1_ENABLED
#undef MBEDTLS_ECP_DP_BP512R1_ENABLED
#undef MBEDTLS_ECP_DP_CURVE448_ENABLED

#endif /* LUATOS_MBEDTLS_CONFIG_PC_MBEDTLS3_H */
