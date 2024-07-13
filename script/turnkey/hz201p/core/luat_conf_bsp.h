
#ifndef LUAT_CONF_BSP
#define LUAT_CONF_BSP

//------------------------------------------------------
// 以下custom --> 到  <-- custom 之间的内容,是供用户配置的
// 同时也是云编译可配置的部分. 提交代码时切勿删除会修改标识

#define LUAT_USE_GPIO 1
#define LUAT_USE_UART 1
#define LUAT_USE_I2C 1
#define LUAT_USE_ADC 1
#define LUAT_USE_PWM 1
#define LUAT_USE_WDT 1
#define LUAT_USE_SPI 1
#define LUAT_USE_MCU 1
#define LUAT_USE_RTC 1
#define LUAT_USE_PM 1
#define LUAT_USE_MEDIA 1
#define LUAT_USE_RECORD 1
#define LUAT_USE_WLAN 1
#define LUAT_USE_MQTT 1
#define LUAT_USE_CJSON 1
#define LUAT_USE_FS 1
#define LUAT_USE_PACK 1
#define LUAT_USE_ZBUFF 1
#define LUAT_USE_LIBGNSS 1
#define LUAT_USE_FSKV 1

#define LUAT_SCRIPT_SIZE 96
#define LUAT_SCRIPT_OTA_SIZE 72


//------------------------------------------------------------------------------

// 以下选项仅开发人员可修改, 一般用户切勿自行修改
//-----------------------------
// 内存配置, 默认200k, 128 ~ 324k 可调. 324k属于极限值, 不可使用音频, 并限制TLS连接的数量不超过2个
// #ifdef LUAT_HEAP_SIZE_324K
// #define LUAT_HEAP_SIZE (324*1024)
// #endif
#ifdef LUAT_HEAP_SIZE_300K
#define LUAT_HEAP_SIZE (300*1024)
#endif
#ifdef LUAT_HEAP_SIZE_200K
#define LUAT_HEAP_SIZE (200*1024)
#endif
// // 一般无需修改. 若不需要使用SSL/TLS/TTS,可适当增加,但不应该超过256k
#ifndef LUAT_HEAP_SIZE
#define LUAT_HEAP_SIZE (250*1024)
#endif

#if defined TYPE_EC718P && defined (FEATURE_IMS_ENABLE)
#if LUAT_HEAP_SIZE > (160*1024)
#undef LUAT_HEAP_SIZE
#define LUAT_HEAP_SIZE (160*1024)
#endif

#if LUAT_SCRIPT_SIZE > 128
#undef LUAT_SCRIPT_SIZE
#undef LUAT_SCRIPT_OTA_SIZE
#define LUAT_SCRIPT_SIZE 128
#define LUAT_SCRIPT_OTA_SIZE 96
#endif
#endif

//-----------------------------

// 将UART0切换到用户模式, 默认是UNILOG模式
// 使用UART0, 日志将完全依赖USB输出, 若USB未引出或失效, 将无法获取底层日志
// 本功能仅限完全了解风险的用户使用
// #define LUAT_UART0_FORCE_USER     1
// #define LUAT_UART0_FORCE_ALT1     1
// #define LUAT_UART0_LOG_BR_12M     1
#if defined CHIP_EC716
#define LUAT_GPIO_PIN_MAX 29
#else
#define LUAT_GPIO_PIN_MAX 47
#endif
// #define LUAT__UART_TX_NEED_WAIT_DONE
// // 内存优化: 减少内存消耗, 会稍微减低性能
#define LUAT_USE_MEMORY_OPTIMIZATION_CODE_MMAP 1

//----------------------------------
// 使用VFS(虚拟文件系统)和内置库文件, 必须启用
#define LUAT_USE_VFS_INLINE_LIB 1
#define LUA_USE_VFS_FILENAME_OFFSET 1
// //----------------------------------

#define LUAT_WS2812B_MAX_CNT	(8)

#define LV_DISP_DEF_REFR_PERIOD 30
#define LUAT_LV_DEBUG 0

#define LV_MEM_CUSTOM 1

#define LUAT_USE_LVGL_INDEV 1 // 输入设备

#define LV_HOR_RES_MAX          (160)
#define LV_VER_RES_MAX          (80)
#define LV_COLOR_DEPTH          16

#define LV_COLOR_16_SWAP   1
#define __LVGL_SLEEP_ENABLE__

#undef LV_DISP_DEF_REFR_PERIOD
#define LV_DISP_DEF_REFR_PERIOD g_lvgl_flash_time

#define LV_TICK_CUSTOM 1
#define LV_TICK_CUSTOM_INCLUDE  "common_api.h"         /*Header for the system time function*/
#define LV_TICK_CUSTOM_SYS_TIME_EXPR ((uint32_t)GetSysTickMS())     /*Expression evaluating to current system time in ms*/

// #define LUAT_USE_LCD_CUSTOM_DRAW

#define __LUATOS_TICK_64BIT__

#define LUAT_RET int
#define LUAT_RT_RET_TYPE	void
#define LUAT_RT_CB_PARAM void *param

#define LUAT_USE_NETWORK 1
// LUAT_USE_TLS 通过xmake判断打开
// #define LUAT_USE_TLS 1
#define LUAT_USE_LWIP 1
#define LUAT_USE_DNS 1
#define LUAT_USE_ERR_DUMP 1
#define LUAT_USE_DHCP  1
#define LUAT_USE_ERRDUMP 1
#define LUAT_USE_FOTA 1
#define LUAT_USE_MOBILE 1
#define LUAT_USE_SNTP 1
#define LUAT_USE_WLAN_SCANONLY 1
//目前没用到的宏，但是得写在这里
#define LUAT_USE_I2S
#ifdef LUAT_USE_MEDIA
#define LUAT_SUPPORT_AMR  1
#endif
#ifndef LUAT_USE_HMETA
#define LUAT_USE_HMETA 1
#endif

// MCU引脚复用
#define LUAT_MCU_IOMUX_CTRL 1

#if defined TYPE_EC718P && defined (FEATURE_IMS_ENABLE)
#define LUAT_USE_VOLTE

#ifndef LUAT_USE_MEDIA
#define LUAT_USE_MEDIA 1
#endif

#endif

// // TTS 相关
#ifdef LUAT_USE_TTS

#ifndef LUAT_USE_TTS_8K
#define LUAT_USE_TTS_16K 1
#endif // LUAT_USE_TTS_8K

#ifndef LUAT_USE_MEDIA
#define LUAT_USE_MEDIA 1
#endif

// #ifdef LUAT_USE_TTS_ONCHIP
// #undef LUAT_USE_SFUD
// #else
// #ifndef LUAT_USE_SFUD
// #define LUAT_USE_SFUD  1
// #endif // LUAT_USE_SFUD
// #endif // LUAT_USE_TTS_ONCHIP

#endif // LUAT_USE_TTS

// 当前不支持软件UART, 自动禁用之
#ifdef LUAT_USE_SOFT_UART
#undef LUAT_USE_SOFT_UART
#endif

// #ifdef LUAT_USE_TTS_ONCHIP
// #undef LUAT_SCRIPT_SIZE
// #undef LUAT_SCRIPT_OTA_SIZE
// #define LUAT_SCRIPT_SIZE 64
// #define LUAT_SCRIPT_OTA_SIZE 48
// #endif

#define LUA_SCRIPT_ADDR (FLASH_FOTA_REGION_START - (LUAT_SCRIPT_SIZE + LUAT_SCRIPT_OTA_SIZE) * 1024)
#define LUA_SCRIPT_OTA_ADDR FLASH_FOTA_REGION_START - (LUAT_SCRIPT_OTA_SIZE * 1024)

#define __LUAT_C_CODE_IN_RAM__ __attribute__((__section__(".platFMRamcode")))

#ifdef LUAT_USE_TLS_DISABLE
#undef LUAT_USE_TLS
#endif

// 关闭加密版本的UDP, 类似于TCP的TLS/SSL, 极少使用
#ifdef LUAT_CONF_TLS_DTLS_DISABLE
#undef MBEDTLS_SSL_PROTO_DTLS
#undef MBEDTLS_SSL_DTLS_ANTI_REPLAY
#undef MBEDTLS_SSL_DTLS_HELLO_VERIFY
#undef MBEDTLS_SSL_DTLS_BADMAC_LIMIT
#endif

// 关闭几个不常用的东西
#ifdef LUAT_CONF_TLS_DISABLE_NC
#undef MBEDTLS_X509_RSASSA_PSS_SUPPORT
#undef MBEDTLS_DES_C
#undef MBEDTLS_DHM_C
#undef MBEDTLS_GCM_C
#undef MBEDTLS_PSA_CRYPTO_C
#undef MBEDTLS_PKCS1_V21
#endif

// 关闭几个不常用的东西
#ifdef LUAT_CONF_TLS_DISABLE_ECP_ECDHE
#undef MBEDTLS_ECP_DP_SECP192R1_ENABLED
#undef MBEDTLS_ECP_DP_SECP224R1_ENABLED
#undef MBEDTLS_ECP_DP_SECP256R1_ENABLED
#undef MBEDTLS_ECP_DP_SECP384R1_ENABLED
#undef MBEDTLS_ECP_DP_SECP521R1_ENABLED
#undef MBEDTLS_ECP_DP_SECP192K1_ENABLED
#undef MBEDTLS_ECP_DP_SECP224K1_ENABLED
#undef MBEDTLS_ECP_DP_SECP256K1_ENABLED
#undef MBEDTLS_ECP_DP_BP256R1_ENABLED
#undef MBEDTLS_ECP_DP_BP384R1_ENABLED
#undef MBEDTLS_ECP_DP_BP512R1_ENABLED
/* Montgomery curves (supporting ECP) */
#undef MBEDTLS_ECP_DP_CURVE25519_ENABLED
#undef MBEDTLS_ECP_DP_CURVE448_ENABLED

#undef MBEDTLS_ECP_NIST_OPTIM
// #undef MBEDTLS_ECDH_LEGACY_CONTEXT

#undef MBEDTLS_KEY_EXCHANGE_ECDHE_RSA_ENABLED
#undef MBEDTLS_KEY_EXCHANGE_ECDHE_ECDSA_ENABLED
#undef MBEDTLS_ECDH_C
#undef MBEDTLS_ECP_C
#undef MBEDTLS_ECDSA_C

#endif


#ifndef PSRAM_FEATURE_ENABLE
#undef LUAT_USE_CAMERA
#endif

#ifdef TYPE_EC716E
#undef LUAT_HEAP_SIZE
#define LUAT_HEAP_SIZE (200*1024)
#endif

#ifdef LUAT_USE_CAMERA
#define LUAT_USE_LCD_SERVICE 1
#endif

#ifdef LUAT_SUPPORT_AMR
#if defined (FEATURE_AMR_CP_ENABLE) || defined (FEATURE_VEM_CP_ENABLE)
#define LUAT_USE_INTER_AMR	1
#endif
#endif

#if defined (PSRAM_FEATURE_ENABLE) && (PSRAM_EXIST==1)
#define LUAT_USE_PSRAM
#endif

#endif
