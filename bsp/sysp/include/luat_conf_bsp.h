
#ifndef LUAT_CONF_BSP
#define LUAT_CONF_BSP

#define LUAT_USE_FS_VFS 1
#define LUAT_USE_VFS_INLINE_LIB 1
#define LUAT_VFS_FILESYSTEM_MOUNT_MAX (256)


//---------------------
// UI
// LCD  是彩屏, 若使用LVGL就必须启用LCD
#define LUAT_USE_LCD
// EINK 是墨水屏
#define LUAT_USE_EINK

//---------------------
// U8G2
// 单色屏, 支持i2c/spi
// #define LUAT_USE_DISP
#define LUAT_USE_U8G2
#define U8G2_USE_SH1106
#define U8G2_USE_ST7567

/**************FONT*****************/
// Luat Fonts
#define LUAT_USE_FONTS
/**********U8G2&LCD FONT*************/
#define USE_U8G2_OPPOSANSM_ENGLISH
#define USE_U8G2_UNIFONT_SYMBOLS
#define USE_U8G2_OPPOSANSM8_CHINESE
#define USE_U8G2_OPPOSANSM10_CHINESE
#define USE_U8G2_OPPOSANSM12_CHINESE
#define USE_U8G2_OPPOSANSM14_CHINESE
#define USE_U8G2_OPPOSANSM16_CHINESE
#define USE_U8G2_OPPOSANSM18_CHINESE
#define USE_U8G2_OPPOSANSM20_CHINESE
#define USE_U8G2_OPPOSANSM22_CHINESE
#define USE_U8G2_OPPOSANSM24_CHINESE
#define USE_U8G2_OPPOSANSM32_CHINESE


#define LUAT_HAS_CUSTOM_LIB_INIT 1
#define LUAT_COMPILER_NOWEAK 1



#define LV_TICK_CUSTOM     1
#define LV_TICK_CUSTOM_INCLUDE "stdio.h"
unsigned int get_timestamp(void);
#define LV_TICK_CUSTOM_SYS_TIME_EXPR ((uint32_t)get_timestamp())     /*Expression evaluating to current system time in ms*/

#define LV_COLOR_16_SWAP 1
#define LV_COLOR_DEPTH 16

#define LUAT_USE_LVGL_SDL2 1
#define LUAT_USE_LCD_SDL2 1
#define LUAT_USE_LCD_CUSTOM_DRAW 1

#define LUAT_USE_LVGL 1
#define LV_MEM_CUSTOM 1
#define LUAT_LV_DEBUG 0
#define LUAT_USE_LVGL_INDEV 1
#define LV_USE_LOG 1

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


#define LV_FONT_OPPOSANS_M_8
#define LV_FONT_OPPOSANS_M_10
#define LV_FONT_OPPOSANS_M_12
#define LV_FONT_OPPOSANS_M_14
#define LV_FONT_OPPOSANS_M_16
#define LV_FONT_OPPOSANS_M_18
#define LV_FONT_OPPOSANS_M_20
#define LV_FONT_OPPOSANS_M_22

#endif
