
#ifndef LUAT_LIBS_H
#define LUAT_LIBS_H
#include "lua.h"
#include "lauxlib.h"


/** sys库, 预留, 实际不可用状态*/
LUAMOD_API int luaopen_sys( lua_State *L );
/** rtos库*/
LUAMOD_API int luaopen_rtos( lua_State *L );
/** timer库*/
LUAMOD_API int luaopen_timer( lua_State *L );
/** msgbus库, 预留, 实际不可用状态*/
// LUAMOD_API int luaopen_msgbus( lua_State *L );
/** gpio库*/
LUAMOD_API int luaopen_gpio( lua_State *L );
/** adc库*/
LUAMOD_API int luaopen_adc( lua_State *L );
/** pwm库*/
LUAMOD_API int luaopen_pwm( lua_State *L );
/** uart库*/
LUAMOD_API int luaopen_uart( lua_State *L );
/** pm库*/
LUAMOD_API int luaopen_pm( lua_State *L );
/** fs库*/
LUAMOD_API int luaopen_fs( lua_State *L );
/** wlan库*/
LUAMOD_API int luaopen_wlan( lua_State *L );
/** socket库*/
LUAMOD_API int luaopen_socket( lua_State *L );
/** sensor库*/
LUAMOD_API int luaopen_sensor( lua_State *L );
/** log库*/
LUAMOD_API int luaopen_log( lua_State *L );
/** json库*/
LUAMOD_API int luaopen_cjson( lua_State *L );
/** i2c库*/
LUAMOD_API int luaopen_i2c( lua_State *L );
/** spi库*/
LUAMOD_API int luaopen_spi( lua_State *L );
/** disp库*/
LUAMOD_API int luaopen_disp( lua_State *L );
/** u8g2库*/
LUAMOD_API int luaopen_u8g2( lua_State *L );
/** sfud库*/
LUAMOD_API int luaopen_sfud( lua_State *L );
/** utest库*/
// LUAMOD_API int luaopen_utest( lua_State *L );
/** mqtt库*/
LUAMOD_API int luaopen_mqtt( lua_State *L );
/** http库*/
LUAMOD_API int luaopen_http( lua_State *L );
/** pack库*/
LUAMOD_API int luaopen_pack( lua_State *L );
/** mqttcore库*/
LUAMOD_API int luaopen_mqttcore( lua_State *L );
/** crypto库*/
LUAMOD_API int luaopen_crypto( lua_State *L );
LUAMOD_API int luaopen_gmssl( lua_State *L );
/** 功耗调整 */
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
/** zbuff库*/
LUAMOD_API int luaopen_zbuff( lua_State *L );

LUAMOD_API int luaopen_sfd( lua_State *L );
LUAMOD_API int luaopen_lfs2( lua_State *L );
LUAMOD_API int luaopen_lvgl( lua_State *L );

/** ir库, 依赖gpio库*/
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
LUAMOD_API int luaopen_socket_adapter( lua_State *L );

LUAMOD_API int luaopen_airui( lua_State *L );
LUAMOD_API int luaopen_fota( lua_State *L );
LUAMOD_API int luaopen_i2s( lua_State *L );
LUAMOD_API int luaopen_lora( lua_State *L );
LUAMOD_API int luaopen_lora2( lua_State *L );
LUAMOD_API int luaopen_iotauth( lua_State *L );
LUAMOD_API int luaopen_ufont( lua_State *L );
LUAMOD_API int luaopen_miniz( lua_State *L );
LUAMOD_API int luaopen_mobile( lua_State *L );

LUAMOD_API int luaopen_protobuf( lua_State *L );

LUAMOD_API int luaopen_httpsrv( lua_State *L );
LUAMOD_API int luaopen_rsa( lua_State *L );

LUAMOD_API int luaopen_websocket( lua_State *L );


LUAMOD_API int luaopen_ftp( lua_State *L );
LUAMOD_API int luaopen_hmeta( lua_State *L );
LUAMOD_API int luaopen_sms( lua_State *L );
LUAMOD_API int luaopen_errdump( lua_State *L );
LUAMOD_API int luaopen_profiler( lua_State *L );
LUAMOD_API int luaopen_fskv( lua_State *L );
LUAMOD_API int luaopen_max30102( lua_State *L );

LUAMOD_API int luaopen_bit64( lua_State *L );
#endif
