
#ifndef LUAT_CONF_BSP
#define LUAT_CONF_BSP

#include "stdint.h"

#define LUAT_BSP_VERSION "V2012"
// #define LUAT_CONF_USE_LIBSYS_SOURCE 1
#define LUAT_USE_CMDLINE_ARGS 1
// 启用64位虚拟机
// #define LUAT_CONF_VM_64bit
#define LUAT_RTOS_API_NOTOK 1
// #define LUAT_RET void
#define LUAT_RT_RET_TYPE	void
#define LUAT_RT_CB_PARAM void *param

#define LUA_USE_VFS_FILENAME_OFFSET 1

#define LUAT_USE_FS_VFS 1

#define LUAT_USE_VFS_INLINE_LIB 1

#define LUAT_COMPILER_NOWEAK 1

#define LUAT_USE_LOG_ASYNC_THREAD 0

#define LUAT_USE_NETWORK 1
#define LUAT_USE_SNTP 1
#define LUAT_USE_TLS  1
#define LUAT_USE_MOCKAPI 1

#define LV_HOR_RES_MAX          (2000)
#define LV_VER_RES_MAX          (2000)
#define LV_COLOR_DEPTH          32

#define LV_COLOR_16_SWAP   0
#define LUAT_LCD_COLOR_DEPTH 16
#define LUAT_USE_LVGL_SDL2 1
#define LUAT_USE_LCD_SDL2 1
#define LUAT_USE_LCD_CUSTOM_DRAW 1
#define LV_MEM_CUSTOM 1
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

#define LUAT_USE_IOTAUTH 1
#define LUAT_USE_MINIZ 1
#define LUAT_USE_GMSSL 1

// #define LUAT_USE_I2S  1
// #define LUAT_USE_MEDIA 1
// #define LUAT_USE_AUDIO 1

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
// #define LUAT_USE_SFUD  1
// #define LUAT_USE_STATEM 1
// 性能测试
#define LUAT_USE_COREMARK 1
// #define LUAT_USE_IR 1
// FDB 提供kv数据库, 与nvm库类似
// #define LUAT_USE_FDB 1
// FSKV库提供fdb库的兼容API, 目标是替代fdb库
#define LUAT_USE_FSKV 1
#define LUAT_CONF_FSKV_CUSTOM 1
// FFT 库开关
#define LUAT_USE_FFT 1
// #define LUAT_USE_OTA 1
// #define LUAT_USE_I2CTOOLS 1
// #define LUAT_USE_LORA 1
// #define LUAT_USE_LORA2 1
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
#define LUAT_USE_PROFILER 1
#define LUAT_USE_NDK 1

// #define LUAT_USE_ROSTR 1
#define LUAT_USE_VTOOL 1

//--------------------------------------------------
// GUI相关
//--------------------------------------------------
// 这里需要从环境变量里启用,不能直接修改下面的宏
// #define LUAT_USE_GUI 1

#ifdef LUAT_USE_GUI
//---------------------
// UI
// LCD  是彩屏, 若使用LVGL就必须启用LCD
#define LUAT_USE_LCD
#define LUAT_USE_TJPGD
// GT 字库：PC 模拟器仿真启用
#define LUAT_USE_GTFONT 1
// 若需要直接绘制 UTF8 字符串（lcd/u8g2 的 UTF8 接口），启用
#define LUAT_USE_GTFONT_UTF8 1
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
#define LUAT_USE_FONTS
/**********U8G2&LCD&EINK FONT*************/
#define USE_U8G2_OPPOSANSM_ENGLISH 1
#define USE_U8G2_OPPOSANSM8_CHINESE
#define USE_U8G2_OPPOSANSM10_CHINESE
#define USE_U8G2_OPPOSANSM12_CHINESE
#define USE_U8G2_OPPOSANSM16_CHINESE
// #define USE_U8G2_OPPOSANSM18_CHINESE
// #define USE_U8G2_OPPOSANSM20_CHINESE
// #define USE_U8G2_OPPOSANSM22_CHINESE
// #define USE_U8G2_OPPOSANSM24_CHINESE
// #define USE_U8G2_OPPOSANSM32_CHINESE
// SARASA
#define USE_U8G2_SARASA_ENGLISH
#define USE_U8G2_SARASA_M8_CHINESE
#define USE_U8G2_SARASA_M10_CHINESE
#define USE_U8G2_SARASA_M12_CHINESE
#define USE_U8G2_SARASA_M14_CHINESE
#define USE_U8G2_SARASA_M16_CHINESE
// #define USE_U8G2_SARASA_M18_CHINESE
// #define USE_U8G2_SARASA_M20_CHINESE
// #define USE_U8G2_SARASA_M22_CHINESE
// #define USE_U8G2_SARASA_M24_CHINESE
// #define USE_U8G2_SARASA_M26_CHINESE
// #define USE_U8G2_SARASA_M28_CHINESE
/**********LVGL FONT*************/
#define LV_FONT_OPPOSANS_M_8
#define LV_FONT_OPPOSANS_M_10
#define LV_FONT_OPPOSANS_M_12
#define LV_FONT_OPPOSANS_M_16

//---------------------
// LVGL
// 主推的UI库, 功能强大但API繁琐
#define LUAT_USE_LVGL      1

#define LUAT_USE_LVGL_JPG 1 // 启用JPG解码支持
#define LUAT_USE_LVGL_PNG 1 // 启用PNG解码支持
#define LUAT_USE_LVGL_BMP 1 // 启用BMP解码支持

#define LUAT_USE_LVGL_INDEV 1 // 输入设备

// TP 模块与PC触摸驱动
#define LUAT_USE_TP 1
#define LUAT_USE_TP_PC 1

#define LUAT_USE_LVGL_ARC   //圆弧 无依赖
#define LUAT_USE_LVGL_BAR   //进度条 无依赖
#define LUAT_USE_LVGL_BTN   //按钮 依赖容器CONT
#define LUAT_USE_LVGL_BTNMATRIX   //按钮矩阵 无依赖
#define LUAT_USE_LVGL_CALENDAR   //日历 无依赖
#define LUAT_USE_LVGL_CANVAS   //画布 依赖图片IMG
#define LUAT_USE_LVGL_CHECKBOX   //复选框 依赖按钮BTN 标签LABEL
#define LUAT_USE_LVGL_CHART   //图表 无依赖
#define LUAT_USE_LVGL_CONT   //容器 无依赖
#define LUAT_USE_LVGL_CPICKER   //颜色选择器 无依赖
#define LUAT_USE_LVGL_DROPDOWN   //下拉列表 依赖页面PAGE 标签LABEL
#define LUAT_USE_LVGL_GAUGE   //仪表 依赖进度条BAR 仪表(弧形刻度)LINEMETER
#define LUAT_USE_LVGL_IMG   //图片 依赖标签LABEL
#define LUAT_USE_LVGL_IMGBTN   //图片按钮 依赖按钮BTN
#define LUAT_USE_LVGL_KEYBOARD   //键盘 依赖图片按钮IMGBTN
#define LUAT_USE_LVGL_LABEL   //标签 无依赖
#define LUAT_USE_LVGL_LED   //LED 无依赖
#define LUAT_USE_LVGL_LINE   //线 无依赖
#define LUAT_USE_LVGL_LIST   //列表 依赖页面PAGE 按钮BTN 标签LABEL
#define LUAT_USE_LVGL_LINEMETER   //仪表(弧形刻度) 无依赖
#define LUAT_USE_LVGL_OBJMASK   //对象蒙版 无依赖
#define LUAT_USE_LVGL_MSGBOX   //消息框 依赖图片按钮IMGBTN 标签LABEL
#define LUAT_USE_LVGL_PAGE   //页面 依赖容器CONT
#define LUAT_USE_LVGL_SPINNER   //旋转器 依赖圆弧ARC 动画ANIM
#define LUAT_USE_LVGL_ROLLER   //滚筒 无依赖
#define LUAT_USE_LVGL_SLIDER   //滑杆 依赖进度条BAR
#define LUAT_USE_LVGL_SPINBOX   //数字调整框 无依赖
#define LUAT_USE_LVGL_SWITCH   //开关 依赖滑杆SLIDER
#define LUAT_USE_LVGL_TEXTAREA   //文本框 依赖标签LABEL 页面PAGE
#define LUAT_USE_LVGL_TABLE   //表格 依赖标签LABEL
#define LUAT_USE_LVGL_TABVIEW   //页签 依赖页面PAGE 图片按钮IMGBTN
#define LUAT_USE_LVGL_TILEVIEW   //平铺视图 依赖页面PAGE
#define LUAT_USE_LVGL_WIN   //窗口 依赖容器CONT 按钮BTN 标签LABEL 图片IMG 页面PAGE

// #define LUAT_USE_AIRUI 1
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
