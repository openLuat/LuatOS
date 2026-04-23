/*
这是PC模拟器的配置文件!!!
不是模组的配置文件!!!
*/
#ifndef LUAT_CONF_BSP
#define LUAT_CONF_BSP

#include "stdint.h"

#define LUAT_BSP_VERSION "V2027"
// #define LUAT_CONF_USE_LIBSYS_SOURCE 1
#define LUAT_USE_CMDLINE_ARGS 1
// 启用64位虚拟机
// #define LUAT_CONF_VM_64bit
#define LUAT_RTOS_API_NOTOK 1
// #define LUAT_RET void
#define LUAT_RT_RET_TYPE	void
#define LUAT_RT_CB_PARAM void *param
#define LWIP_NUM_SOCKETS 64

#define LUA_USE_VFS_FILENAME_OFFSET 1

#define LUAT_USE_FS_VFS 1

#define LUAT_USE_VFS_INLINE_LIB 1

#define LUAT_COMPILER_NOWEAK 1

#define LUAT_USE_LOG_ASYNC_THREAD 0

#define LUAT_USE_NETWORK 1
#define LUAT_USE_SNTP 1
#define LUAT_USE_TLS  1
#define LUAT_USE_MOCKAPI 1

#define LUAT_USE_NETDRV 1
#define LUAT_USE_NETDRV_NAPT 1
#define LUAT_USE_NETDRV_CH390H 1
#define LUAT_USE_NETDRV_OPENVPN 1
#define LUAT_USE_NETDRV_WG 1

#define LUAT_USE_AIRLINK 1
#define LUAT_USE_AIRLINK_SPI_MASTER 1
#define LUAT_USE_AIRLINK_UART 1
#define LUAT_USE_AIRLINK_RPC 1
#define LUAT_USE_AIRLINK_MULTI_TRANSPORT 1
#define LUAT_USE_AIRLINK_EXEC_SDATA 1

// #define LV_HOR_RES_MAX          (2000)
// #define LV_VER_RES_MAX          (2000)
// #define LV_COLOR_DEPTH          32

// #define LV_COLOR_16_SWAP   0
#define LUAT_LCD_COLOR_DEPTH 16
#define LUAT_USE_LVGL_SDL2 1
#define LUAT_USE_LCD_SDL2 1
#define LUAT_USE_LCD_CUSTOM_DRAW 1
// #define LV_MEM_CUSTOM 1
// #define LV_USE_LOG 1
// #define LUAT_LV_DEBUG 1

#define MQTT_RECV_BUF_LEN_MAX (32*1024)

//----------------------------
// 外设,按需启用, 最起码启用uart和wdt库
#define LUAT_USE_UART 1
#define LUAT_USE_GPIO 1
#define LUAT_USE_I2C  1
#define LUAT_USE_SPI  1
#define LUAT_USE_ADC  1
#define LUAT_USE_PWM  1
#define LUAT_USE_WDT  1
#define LUAT_USE_PM  1
#define LUAT_USE_MCU  1
#define LUAT_USE_RTC 1
#define LUAT_USE_CAN 1
#define LUAT_USE_OTP 1
#define LUAT_USE_MOBILE 1
#define LUAT_USE_SMS 1
#define LUAT_USE_WLAN 1

#define LUAT_USE_IOTAUTH 1
#define LUAT_USE_MINIZ 1
#define LUAT_USE_GMSSL 1

#define LUAT_USE_I2S  1
#define LUAT_USE_MEDIA 1
#define LUAT_USE_AUDIO 1
#define LUAT_SUPPORT_AMR 1
#define LUAT_SUPPORT_OPUS   1
#define LUAT_USE_AUDIO_G711 1
#define LUAT_USE_AUDIO_DTMF 1

//----------------------------
// 常用工具库, 按需启用, cjson和pack是强烈推荐启用的
#define LUAT_USE_CRYPTO  1
#define LUAT_USE_CJSON  1
#define LUAT_USE_ZBUFF  1
#define LUAT_USE_PACK  1
#define LUAT_USE_LIBGNSS  1
#define LUAT_USE_MQTTCORE 1
#define LUAT_USE_LIBCOAP 1
#define LUAT_USE_FS  1
// #define LUAT_USE_SENSOR  1
#define LUAT_USE_SFUD  1
#define LUAT_USE_LITTLE_FLASH 1
// #define LUAT_USE_STATEM 1
// 性能测试
#define LUAT_USE_COREMARK 1
// #define LUAT_USE_IR 1
// FSKV库提供fdb库的兼容API, 目标是替代fdb库
#define LUAT_USE_FSKV 1
#define LUAT_CONF_FSKV_CUSTOM 1
// FFT 库开关
#define LUAT_USE_FFT 1
// #define LUAT_USE_OTA 1
// #define LUAT_USE_I2CTOOLS 1
// #define LUAT_USE_LORA 1
#define LUAT_USE_LORA2 1
// #define LUAT_USE_MAX30102 1
// #define LUAT_USE_MLX90640 1
#define LUAT_USE_YMODEM 1

#define LUAT_USE_FATFS
#define LUAT_USE_FATFS_CHINESE 3

//----------------------------
// 高级功能, 推荐使用repl, shell已废弃
// #define LUAT_USE_SHELL 1
// #define LUAT_USE_DBG
// #define LUAT_USE_REPL 1
// 多虚拟机支持,实验性,一般不启用
// #define LUAT_USE_VMX 1
#define LUAT_USE_PROTOBUF 1

#define LUAT_USE_RSA 1
#define LUAT_USE_ICONV 1
#define LUAT_USE_BIT64 1
#define LUAT_USE_FASTLZ 1
// #define LUAT_USE_SQLITE3 1
// #define LUAT_USE_ONEWIRE 1
// #define LUAT_USE_WS2812 1
#define LUAT_USE_XXTEA 1
// #define LUAT_USE_PROFILER 1
#define LUAT_USE_NDK 1

// #define LUAT_USE_ROSTR 1
#define LUAT_USE_VTOOL 1

#define LUAT_USE_MREPORT 1

#define LUAT_USE_MEMPROF 1

#define LUAT_USE_H264_DECODER 1

#define LUAT_USE_VIDEOPLAYER 1
// videoplayer软解依赖TJPGD, 需在GUI块外启用
#define LUAT_USE_TJPGD

#define LUAT_USE_WEBP 1

//--------------------------------------------------
// mGBA GBA模拟器
//--------------------------------------------------
// #define LUAT_USE_MGBA 1
#ifdef LUAT_USE_MGBA
// mGBA 配置文件
#define MGBA_CONFIG_FILE "mgba_config_luatos.h"
#endif

//--------------------------------------------------
// GUI相关
//--------------------------------------------------
// 这里需要从环境变量里启用,不能直接修改下面的宏
// #define LUAT_USE_GUI 1

#ifdef LUAT_USE_GUI
//---------------------

// TP 模块与PC触摸驱动
#define LUAT_USE_TP 1
#define LUAT_USE_TP_PC 1

// UI
// LCD  是彩屏, 若使用LVGL就必须启用LCD
#define LUAT_USE_LCD
// hzfont 字体库支持
#define LUAT_USE_HZFONT 1
#define LUAT_CONF_USE_HZFONT_BUILTIN_TTF 1
// pinyin 拼音库支持
#define LUAT_USE_PINYIN 1
// EINK 是墨水屏
// #define LUAT_USE_EINK

//---------------------
// U8G2
// 单色屏, 支持i2c/spi
// #define LUAT_USE_DISP
#define LUAT_USE_U8G2

/**************FONT*****************/
// #define LUAT_USE_FONTS
/**********U8G2&LCD&EINK FONT*************/
#define USE_U8G2_OPPOSANSM_ENGLISH 1
#define USE_U8G2_OPPOSANSM8_CHINESE
#define USE_U8G2_OPPOSANSM10_CHINESE
#define USE_U8G2_OPPOSANSM12_CHINESE
#define USE_U8G2_OPPOSANSM16_CHINESE

#define LUAT_USE_AIRUI 1
#define LUAT_USE_AIRUI_SDL2 1

#endif


// 注意这里是 LUAT_USE_WINDOWS
#ifdef _WIN32
#define LUAT_USE_LWIP 1
// #define LUAT_USE_ULWIP 1
#define LUAT_USE_DNS 1
#endif

#define LUAT_UART_MAX_DEVICE_COUNT 128
#define LUAT_USE_PSRAM 1

#ifndef LUAT_USE_LWIP
#undef LUAT_USE_MOBILE
#endif

#endif
