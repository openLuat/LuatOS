
#ifndef LUAT_LIBS_H
#define LUAT_LIBS_H
#include "lua.h"
#include "lauxlib.h"


/** 加载sys库, 预留, 实际不可用状态*/
LUAMOD_API int luaopen_sys( lua_State *L );
/** 加载rtos库, 必选*/
LUAMOD_API int luaopen_rtos( lua_State *L );
/** 加载timer库, 可选*/
LUAMOD_API int luaopen_timer( lua_State *L );
/** 加载msgbus库, 预留, 实际不可用状态*/
LUAMOD_API int luaopen_msgbus( lua_State *L );
/** 加载gpio库, 可选*/
LUAMOD_API int luaopen_gpio( lua_State *L );
/** 加载adc库, 可选*/
LUAMOD_API int luaopen_adc( lua_State *L );
/** 加载pwm库, 可选*/
LUAMOD_API int luaopen_pwm( lua_State *L );
/** 加载uart库, 一般都需要*/
LUAMOD_API int luaopen_uart( lua_State *L );
/** 加载pm库, 预留*/
LUAMOD_API int luaopen_pm( lua_State *L );
/** 加载fs库, 预留*/
LUAMOD_API int luaopen_fs( lua_State *L );
/** 加载wlan库, 操作wifi,可选*/
LUAMOD_API int luaopen_wlan( lua_State *L );
/** 加载socket库, 依赖netclient.h,可选*/
LUAMOD_API int luaopen_socket( lua_State *L );
/** 加载sensor库, 依赖gpio库, 可选*/
LUAMOD_API int luaopen_sensor( lua_State *L );
/** 加载log库, 必选, 依赖底层uart抽象层*/
LUAMOD_API int luaopen_log( lua_State *L );
/** 加载json库, 可选*/
LUAMOD_API int luaopen_cjson( lua_State *L );
/** 加载i2c库, 可选*/
LUAMOD_API int luaopen_i2c( lua_State *L );
/** 加载spi库, 可选*/
LUAMOD_API int luaopen_spi( lua_State *L );
/** 加载disp库, 可选, 会依赖i2c和spi*/
LUAMOD_API int luaopen_disp( lua_State *L );
/** 加载u8g2库, 可选, 会依赖i2c和spi*/
LUAMOD_API int luaopen_u8g2( lua_State *L );
/** 加载sfud库, 可选, 会依赖spi*/
LUAMOD_API int luaopen_sfud( lua_State *L );
/** 加载utest库, 预留*/
LUAMOD_API int luaopen_utest( lua_State *L );
/** 加载mqtt库, 预留*/
LUAMOD_API int luaopen_mqtt( lua_State *L );
/** 加载mqtt库, 预留*/
LUAMOD_API int luaopen_http( lua_State *L );
/** 加载pack库, 可选,平台无关*/
LUAMOD_API int luaopen_pack( lua_State *L );
/** 加载mqttcore库, 可选,平台无关*/
LUAMOD_API int luaopen_mqttcore( lua_State *L );
/** 加载crypto库, 可选*/
LUAMOD_API int luaopen_crypto( lua_State *L );
LUAMOD_API int luaopen_pm( lua_State *L);
LUAMOD_API int luaopen_m2m( lua_State *L);
LUAMOD_API int luaopen_libcoap( lua_State *L);
LUAMOD_API int luaopen_lpmem( lua_State *L);
LUAMOD_API int luaopen_ctiot( lua_State *L);
LUAMOD_API int luaopen_iconv(lua_State *L);
LUAMOD_API int luaopen_nbiot( lua_State *L );
LUAMOD_API int luaopen_libgnss( lua_State *L ) ;
LUAMOD_API int luaopen_fatfs( lua_State *L );
LUAMOD_API int luaopen_eink( lua_State *L);
LUAMOD_API int luaopen_dbg( lua_State *L );
/** 加载zbuff库, 可选,平台无关*/
LUAMOD_API int luaopen_zbuff( lua_State *L );

LUAMOD_API int luaopen_sfd( lua_State *L );
LUAMOD_API int luaopen_lfs2( lua_State *L );
LUAMOD_API int luaopen_lvgl( lua_State *L );

/** 加载ir库, 依赖gpio库, 可选*/
LUAMOD_API int luaopen_ir( lua_State *L );

LUAMOD_API int luaopen_lcd( lua_State *L );
LUAMOD_API int luaopen_lwip( lua_State *L );


LUAMOD_API int luaopen_wdt( lua_State *L );
LUAMOD_API int luaopen_mcu( lua_State *L );
LUAMOD_API int luaopen_hwtimer( lua_State *L );
LUAMOD_API int luaopen_rtc( lua_State *L );
LUAMOD_API int luaopen_sdio( lua_State *L );

LUAMOD_API int luaopen_statem( lua_State *L );
LUAMOD_API int luaopen_vmx( lua_State *L );
LUAMOD_API int luaopen_lcdseg( lua_State *L );

LUAMOD_API int luaopen_fdb( lua_State *L );

LUAMOD_API int luaopen_keyboard( lua_State *L );
LUAMOD_API int luaopen_coremark( lua_State *L );

LUAMOD_API int luaopen_fonts( lua_State *L );
LUAMOD_API int luaopen_gtfont( lua_State *L );

LUAMOD_API int luaopen_pin( lua_State *L );
LUAMOD_API int luaopen_dac( lua_State *L );
LUAMOD_API int luaopen_otp( lua_State *L );
LUAMOD_API int luaopen_mlx90640( lua_State *L );
LUAMOD_API int luaopen_zlib( lua_State *L );
LUAMOD_API int luaopen_camera( lua_State *L );
LUAMOD_API int luaopen_multimedia_audio( lua_State *L );
LUAMOD_API int luaopen_multimedia_video( lua_State *L );
LUAMOD_API int luaopen_multimedia_codec( lua_State *L );
LUAMOD_API int luaopen_luf( lua_State *L );

LUAMOD_API int luaopen_touchkey(lua_State *L);
LUAMOD_API int luaopen_softkb( lua_State *L );
LUAMOD_API int luaopen_nes( lua_State *L );

LUAMOD_API int luaopen_io_queue( lua_State *L );
LUAMOD_API int luaopen_ymodem( lua_State *L );
LUAMOD_API int luaopen_w5500( lua_State *L );
LUAMOD_API int luaopen_network_adapter( lua_State *L );

LUAMOD_API int luaopen_airui( lua_State *L );
LUAMOD_API int luaopen_fota( lua_State *L );
LUAMOD_API int luaopen_i2s( lua_State *L );

#endif
