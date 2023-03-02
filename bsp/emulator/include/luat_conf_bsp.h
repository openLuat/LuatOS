
#ifndef LUAT_CONF_BSP
#define LUAT_CONF_BSP

#define LUAT_BSP_VERSION "V0007"
#define LUAT_USE_CMDLINE_ARGS 1

#define LUAT_WIN32_REMOTE_MODE 1

#define LUA_USE_VFS_FILENAME_OFFSET 1

#define LUAT_USE_FS_VFS 1

#define LUAT_USE_VFS_INLINE_LIB 1

// #define LUAT_MEMORY_OPT_G_FUNCS 1

#define LUAT_USE_LOG_ASYNC_THREAD 0

#define LUAT_FORCE_WIN32 1
#define LUAT_EMULATOR_MODE 1

#define LV_COLOR_16_SWAP 1
#define LV_COLOR_DEPTH 16

#define LUAT_USE_LVGL 1
#define LV_MEM_CUSTOM 1
#define LUAT_LV_DEBUG 0
#define LUAT_USE_LVGL_INDEV 1

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
