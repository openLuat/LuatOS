
/*
@module   
@summary "读取-求值-输出" 循环
@date    2023.06.16
@tag LUAT_USE_REPL
@usage
--[[
本功能支持的模块及对应的端口
模块/芯片        端口     波特率及其他参数
Air101/Air103    UART0   921600  8 None 1
Air105           UART0   1500000 8 None 1
ESP32C3          UART0   921600  8 None 1 -- 注意, 简约版(无CH343)不支持
ESP32C2          UART0   921600  8 None 1
ESP32S2          UART0   921600  8 None 1
Air780E          虚拟串口 任意             -- 暂不支持从物理UART调用

使用方法:
1. 非Air780E系列可以使用任意串口工具, 打开对应的串口, 记得勾选"回车换行"
2. Air780E请配合LuaTools使用, 菜单里有 "简易串口工具" 可发送, 记得勾选"回车换行"
2. 发送lua语句, 并以回车换行结束

语句支持情况:
1. 单行lua语句, 以回车换行结束即可
2. 多行语句, 用以下格式包裹起来发送, 例如

<<EOF
for k,v in pairs(_G) do
  print(k, v)
end
EOF

注意事项:
1. 可通过repl.enable(false)语句禁用REPL
2. 使用uart.setup/uart.close指定UART端口后, REPL自动失效
3. 单行语句一般支持到510字节,更长的语句请使用"多行语句"的方式使用
4. 若需要定义全局变量, 请使用 _G.xxx = yyy 形式

若有任何疑问, 请到 chat.openluat.com 发帖反馈
]]
*/
#include "luat_base.h"
#include "luat_repl.h"
#define LUAT_LOG_TAG "repl"
#include "luat_log.h"

/*
代理打印, 暂未实现
*/
static int l_repl_print(lua_State* L) {
    return 0;
}

/*
启用或禁用REPL功能
@api repl.enable(re)
@bool 启用与否,默认是启用
@return 之前的设置状态
@usage
-- 若固件支持REPL,即编译时启用了REPL,是默认启用REPL功能的
-- 本函数是提供关闭REPL的途径
repl.enable(false)
*/
static int l_repl_enable(lua_State* L) {
    int ret = 0;
    if (lua_isboolean(L, 1))
        ret = luat_repl_enable(lua_toboolean(L, 1));
    else
        ret = luat_repl_enable(-1);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_repl[] =
{
    { "print" ,         ROREG_FUNC(l_repl_print)},
    { "enable" ,        ROREG_FUNC(l_repl_enable)},
	{ NULL,             ROREG_INT(0) }
};

LUAMOD_API int luaopen_repl( lua_State *L ) {
    luat_newlib2(L, reg_repl);
    return 1;
}
