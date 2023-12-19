
/*
@module  ymodem
@summary ymodem协议
@version 1.0
@date    2022.09.30
@author  Dozingfiretruck
@tag LUAT_USE_YMODEM
@usage
-- 本库的用途是接收数据, 若需要发送文件, 建议用xmodem库
local handler = ymodem.create("/")
uart.setup(1, 115200)
uart.on(1, "receive", function(id, len)
	while 1 do
		local data = uart.read(id, 512)
		if not data or #data == 0 then
			break
		end
		ymodem.receive(handler, data)
	end
end)
*/

#include "luat_base.h"
#include "luat_mem.h"
#include "luat_ymodem.h"
#include "luat_zbuff.h"
#define LUAT_LOG_TAG "ymodem"
#include "luat_log.h"

typedef struct
{
	void *ctrl;
}ymodem_handler;

/*
创建一个ymodem处理句柄
@api ymodem.create(dir_path,file_path)
@string 保存的文件夹路径，默认是"/"
@string 强制保存的绝对文件路径，默认是空，如果设置了，就会直接保存在该文件中
@return boolean 成功true, 失败false
@usage
local handler = ymodem.create("/")
*/
static int l_ymodem_create(lua_State *L){
	ymodem_handler *handler = (ymodem_handler *)lua_newuserdata(L, sizeof(ymodem_handler));
	size_t len;
	const char *dir_path,*file_path;
	if (lua_isstring(L, 1))
	{
		dir_path = lua_tolstring(L, 1, &len);

	}
	else
	{
		dir_path = NULL;
	}
	if (lua_isstring(L, 2))
	{
		file_path = lua_tolstring(L, 2, &len);

	}
	else
	{
		file_path = NULL;
	}
	handler->ctrl = luat_ymodem_create_handler(dir_path?dir_path:"/", file_path);
	lua_pushlightuserdata(L, handler);
    return 1;
}

/*
ymodem接收文件数据并保存
@api ymodem.receive(handler, data)
@userdata ymodem处理句柄
@zbuff/string 输入的数据
@return boolean 成功true，失败false
@return int ack值，需要通过串口/网络等途径返回发送方
@return int flag值，需要通过串口/网络等途径返回发送方，如果有ack值则不发送flag
@return boolean, 一个文件接收完成true，传输中false
@return boolean, 整个传输完成true 否则false
@usage
-- 注意, 数据来源不限, 通常是uart.read得到data
no_error,ack,flag,file_done,all_done = ymodem.receive(handler, data)
*/

static int l_ymodem_receive(lua_State *L){
	ymodem_handler *handler = (ymodem_handler *)lua_touserdata(L, 1);
	int result;
	size_t len;
	uint8_t ack, flag, file_ok, all_done;
	const char *data;
	if (handler && handler->ctrl)
	{
		if (lua_isstring(L, 2))
		{
			data = lua_tolstring(L, 1, &len);
		}
		else if(lua_isuserdata(L, 2))
	    {
	        luat_zbuff_t *buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
	        len = buff->used;
	        data = (const char *)(buff->addr);

	    }
		else
		{
			data = NULL;
			len = 0;
		}
		result = luat_ymodem_receive(handler->ctrl, (uint8_t*)data, len, &ack, &flag, &file_ok, &all_done);
		lua_pushboolean(L, !result);
		lua_pushinteger(L, ack);
		if (flag)
		{
			lua_pushinteger(L, flag);
		}
		else
		{
			lua_pushnil(L);
		}
		lua_pushboolean(L, file_ok);
		lua_pushboolean(L, all_done);
	}
	else
	{
		LLOGE("%x,%x", handler, handler->ctrl);
		lua_pushboolean(L, 0);
		lua_pushnil(L);
		lua_pushnil(L);
		lua_pushboolean(L, 0);
		lua_pushboolean(L, 0);
	}
	return 5;
}

/*
重置ymodem处理过程
@api ymodem.reset(handler)
@userdata ymodem处理句柄
@usage
-- 恢复到初始状态，一般用于接收出错后重置，从而进行下一次接收
ymodem.reset(handler)
*/
static int l_ymodem_reset(lua_State *L){
	ymodem_handler *handler = (ymodem_handler *)lua_touserdata(L, 1);
	if (handler && handler->ctrl) luat_ymodem_reset(handler->ctrl);
    return 0;
}

/*
释放ymodem处理句柄
@api ymodem.release(handler)
@userdata handler
@usage
ymodem.release(handler)
*/

static int l_ymodem_release(lua_State *L){
	ymodem_handler *handler = (ymodem_handler *)lua_touserdata(L, 1);
	if (handler && handler->ctrl) {
		luat_ymodem_release(handler->ctrl);
		handler->ctrl = NULL;
	}
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_ymodem[] =
{
    { "create",           	ROREG_FUNC(l_ymodem_create)},
    { "receive",   			ROREG_FUNC(l_ymodem_receive)},
    { "reset",      		ROREG_FUNC(l_ymodem_reset)},
    { "release",			ROREG_FUNC(l_ymodem_release)},
	{ NULL,             ROREG_INT(0)}
};

LUAMOD_API int luaopen_ymodem( lua_State *L ) {
    luat_newlib2(L, reg_ymodem);
    return 1;
}
