/*
 * Copyright (c) 2011 Petr Stetiar <ynezz@true.cz>, Gaben Ltd.
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 * 
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 */

#include <lauxlib.h>
#include <lua.h>

#include <string.h>
#include <stdlib.h>

#include "librs232/rs232.h"

#define MODULE_TIMESTAMP __DATE__ " " __TIME__
#define MODULE_NAMESPACE "luars232"
#define MODULE_VERSION "1.0.3"
#define MODULE_BUILD "$Id: luars232.c 15 2011-02-23 09:02:20Z sp $"
#define MODULE_COPYRIGHT "Copyright (c) 2011 Petr Stetiar <ynezz@true.cz>, Gaben Ltd."

#ifndef luaL_reg
#define luaL_reg luaL_Reg
#endif

static struct {
	const char *name;
	unsigned long value;
} luars232_ulong_consts[] = {
	/* baudrates */
	{ "RS232_BAUD_300", RS232_BAUD_300 },
	{ "RS232_BAUD_2400", RS232_BAUD_2400 },
	{ "RS232_BAUD_4800", RS232_BAUD_4800 },
	{ "RS232_BAUD_9600", RS232_BAUD_9600 },
	{ "RS232_BAUD_19200", RS232_BAUD_19200 },
	{ "RS232_BAUD_38400", RS232_BAUD_38400 },
	{ "RS232_BAUD_57600", RS232_BAUD_57600 },
	{ "RS232_BAUD_115200", RS232_BAUD_115200 },
	{ "RS232_BAUD_460800", RS232_BAUD_460800 },
	/* databits */
	{ "RS232_DATA_5", RS232_DATA_5 },
	{ "RS232_DATA_6", RS232_DATA_6 },
	{ "RS232_DATA_7", RS232_DATA_7 },
	{ "RS232_DATA_8", RS232_DATA_8 },
	/* stop bits */
	{ "RS232_STOP_1", RS232_STOP_1 },
	{ "RS232_STOP_2", RS232_STOP_2 },
	/* parity */
	{ "RS232_PARITY_NONE", RS232_PARITY_NONE },
	{ "RS232_PARITY_ODD", RS232_PARITY_ODD },
	{ "RS232_PARITY_EVEN", RS232_PARITY_EVEN },
	/* flow */
	{ "RS232_FLOW_OFF", RS232_FLOW_OFF },
	{ "RS232_FLOW_HW", RS232_FLOW_HW },
	{ "RS232_FLOW_XON_XOFF", RS232_FLOW_XON_XOFF },
	/* DTR and RTS */
	{ "RS232_DTR_ON", RS232_DTR_ON },
	{ "RS232_DTR_OFF", RS232_DTR_OFF },
	{ "RS232_RTS_ON", RS232_RTS_ON },
	{ "RS232_RTS_OFF", RS232_RTS_OFF },
	/* errors */
	{ "RS232_ERR_NOERROR", RS232_ERR_NOERROR },
	{ "RS232_ERR_UNKNOWN", RS232_ERR_UNKNOWN },
	{ "RS232_ERR_OPEN", RS232_ERR_OPEN },
	{ "RS232_ERR_CLOSE", RS232_ERR_CLOSE },
	{ "RS232_ERR_FLUSH", RS232_ERR_FLUSH },
	{ "RS232_ERR_CONFIG", RS232_ERR_CONFIG },
	{ "RS232_ERR_READ", RS232_ERR_READ },
	{ "RS232_ERR_WRITE", RS232_ERR_WRITE },
	{ "RS232_ERR_SELECT", RS232_ERR_SELECT },
	{ "RS232_ERR_TIMEOUT", RS232_ERR_TIMEOUT },
	{ "RS232_ERR_IOCTL", RS232_ERR_IOCTL },
	{ "RS232_ERR_PORT_CLOSED", RS232_ERR_PORT_CLOSED },
	{ "RS232_ERR_BREAK", RS232_ERR_BREAK },
	{ "RS232_ERR_FRAME", RS232_ERR_FRAME },
	{ "RS232_ERR_PARITY", RS232_ERR_PARITY },
	{ "RS232_ERR_RXOVERFLOW", RS232_ERR_RXOVERFLOW },
	{ "RS232_ERR_OVERRUN", RS232_ERR_OVERRUN },
	{ NULL, 0 }
};

#ifdef WIN32
BOOL WINAPI DllMain( HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpvReserved) 
{
	return TRUE;
}
#endif

/*
 * rs232 = require("luars232")
 * error, port = rs232.open(device)
 * error, port = rs232.open("/dev/ttyUSB0")
 */
static int lua_port_open(lua_State *L)
{
	int ret = 0;
	struct rs232_port_t *p = NULL;
	struct rs232_port_t **ud = NULL;
	const char *dev = luaL_checkstring(L, 1);

	p = rs232_init();
	if (p == NULL) {
		lua_pushinteger(L, RS232_ERR_CONFIG);
		lua_pushnil(L);
		return 2;
	}

	DBG("p=%p \n", (void *)p);

	rs232_set_device(p, dev);
	ret = rs232_open(p);
	if (ret > RS232_ERR_NOERROR) {
		free(p->pt);
		free(p);
		lua_pushinteger(L, ret);
		lua_pushnil(L);
		return 2;
	}

	lua_pushinteger(L, RS232_ERR_NOERROR);
	ud = lua_newuserdata(L, sizeof(struct rs232_port_t *));
	*ud = p;

	luaL_getmetatable(L, MODULE_NAMESPACE);
	lua_setmetatable(L, -2);

	return 2;
}

/* 
 * error, data, read_len = port:read(max_read_len [[, timeout_ms], forced])
 *
 * if forced > 0 then read() blocks until 'timeout_ms' or there's 'max_read_len'
 * bytes available
 */
static int lua_port_read(lua_State *L)
{
	int ret = 0;
	int argc = 0;
	int forced = 0;
	unsigned int timeout = 0;
	unsigned int len = 0;
	unsigned int bytes_read = 0;
	unsigned char tmp[128];
	unsigned char *data = tmp;
	struct rs232_port_t *p = NULL;

	p = *(struct rs232_port_t**) luaL_checkudata(L, 1, MODULE_NAMESPACE);
	lua_remove(L, 1);

	if (p == NULL || !rs232_port_open(p)) {
		lua_pushinteger(L, RS232_ERR_PORT_CLOSED);
		lua_pushnil(L);
		lua_pushinteger(L, 0);
		return 3;
	}

	argc = lua_gettop(L);
	len = (unsigned int) luaL_checkinteger(L, 1);
	if(len > sizeof(tmp)){
		data = (unsigned char*) malloc(len);
		memset(data, 0, len);
	}

	switch (argc) {
	case 1:
		ret = rs232_read(p, data, len, &bytes_read);
		break;
	case 2:
	case 3:
		timeout = (unsigned int) luaL_checknumber(L, 2);
		if(lua_isnumber(L, 3))
			forced = (lua_tointeger(L, 3) > 0) ? 1 : 0;
			else if (!lua_isnoneornil(L, 3)) {
				luaL_checktype(L, 3, LUA_TBOOLEAN);
				forced = lua_toboolean(L, 3);
			}

		if (forced > 0)
			ret = rs232_read_timeout_forced(p, data, len, &bytes_read, timeout);
		else
			ret = rs232_read_timeout(p, data, len, &bytes_read, timeout);
		break;
	default:
		lua_pushinteger(L, RS232_ERR_UNKNOWN);
		lua_pushnil(L);
		lua_pushinteger(L, 0);
		return 3;
	}

	DBG("ret=%d hex='%s' bytes_read=%d\n",
	    ret, rs232_hex_dump(data, bytes_read), bytes_read);

	lua_pushinteger(L, ret);
	if (bytes_read > 0)
		lua_pushlstring(L, (char *) data, bytes_read);
	else
		lua_pushnil(L);

	if (data != tmp)
		free(data);

	lua_pushinteger(L, bytes_read);
	return 3;
}

/* 
 * error, bytes = port:in_queue()
 */
static int lua_port_in_queue(lua_State *L)
{
	int ret = 0;
	struct rs232_port_t *p = NULL;
	unsigned int in_bytes = 0;

	p = *(struct rs232_port_t**) luaL_checkudata(L, 1, MODULE_NAMESPACE);
	lua_remove(L, 1);

	if (p == NULL || !rs232_port_open(p)) {
		lua_pushinteger(L, RS232_ERR_PORT_CLOSED);
		lua_pushinteger(L, 0);
		return 2;
	}

	ret = rs232_in_queue(p, &in_bytes);
	lua_pushinteger(L, ret);
	lua_pushinteger(L, in_bytes);
	return 2;
}

/* 
 * error = port:in_queue_clear()
 */
static int lua_port_in_queue_clear(lua_State *L)
{
	struct rs232_port_t *p = NULL;

	p = *(struct rs232_port_t**) luaL_checkudata(L, 1, MODULE_NAMESPACE);
	lua_remove(L, 1);

	if (p == NULL || !rs232_port_open(p)) {
		lua_pushinteger(L, RS232_ERR_PORT_CLOSED);
		return 1;
	}

	rs232_in_queue_clear(p);
	lua_pushinteger(L, RS232_ERR_NOERROR);
	return 1;
}

/*
 * error, written_len = port:write(data [, timeout_ms])
 */
static int lua_port_write(lua_State *L)
{
	int ret = 0;
	int argc = 0;
	unsigned int timeout = 0;
	unsigned int wlen = 0;
	size_t len = 0;
	const char *data;
	struct rs232_port_t *p = NULL;

	p = *(struct rs232_port_t**) luaL_checkudata(L, 1, MODULE_NAMESPACE);
	lua_remove(L, 1);

	if (p == NULL || !rs232_port_open(p)) {
		lua_pushinteger(L, RS232_ERR_PORT_CLOSED);
		lua_pushinteger(L, 0);
		return 2;
	}

	argc = lua_gettop(L);
	switch (argc) {
	case 1: {
		data = luaL_checklstring(L, 1, &len);
		ret = rs232_write(p, (unsigned char*) data, (unsigned int) len, &wlen);
		break;
	}
	case 2:
		data = luaL_checklstring(L, 1, &len);
		timeout = (unsigned int) luaL_checknumber(L, 2);
		ret = rs232_write_timeout(p, (unsigned char*) data, (unsigned int) len, &wlen, timeout);
		break;
	default:
		lua_pushinteger(L, RS232_ERR_CONFIG);
		lua_pushinteger(L, 0);
		return 2;
	}

	lua_pushinteger(L, ret);
	lua_pushinteger(L, wlen);
	return 2;
}

/* error = port:close() */
static int lua_port_close(lua_State *L)
{
	struct rs232_port_t *p = *(struct rs232_port_t**) luaL_checkudata(L, 1, MODULE_NAMESPACE);

	if (p == NULL || !rs232_port_open(p)) {
		lua_pushinteger(L, RS232_ERR_PORT_CLOSED);
		return 1;
	}

	lua_pushinteger(L, rs232_close(p));
	return 1;
}

/* __gc */
static int lua_port_gc(lua_State *L)
{
	struct rs232_port_t **p = (struct rs232_port_t**) luaL_checkudata(L, 1, MODULE_NAMESPACE);

	if (*p != NULL) {
		rs232_end(*p);
		*p = NULL;
	}

	return 1;
}

/* error = port:flush() */
static int lua_port_flush(lua_State *L)
{
	struct rs232_port_t *p = *(struct rs232_port_t**) luaL_checkudata(L, 1, MODULE_NAMESPACE);

	if (p == NULL || !rs232_port_open(p)) {
		lua_pushinteger(L, RS232_ERR_PORT_CLOSED);
		return 1;
	}

	lua_pushinteger(L, rs232_flush(p));
	return 1;
}

/* __tostring metamethod */
static int lua_port_tostring(lua_State *L)
{
	const char *ret;
	struct rs232_port_t *p = *(struct rs232_port_t**) luaL_checkudata(L, 1, MODULE_NAMESPACE);

	if (p == NULL) {
		lua_pushnil(L);
		return 1;
	}

	ret = rs232_to_string(p);
	if (ret == NULL)
		lua_pushnil(L);
	else
		lua_pushstring(L, ret);

	return 1;
}

static int lua_port_device(lua_State *L)
{
	struct rs232_port_t *p = *(struct rs232_port_t**) luaL_checkudata(L, 1, MODULE_NAMESPACE);
	const char *ret = rs232_get_device(p);
	if (ret == NULL)
		lua_pushnil(L);
	else
		lua_pushstring(L, ret);

	return 1;
}

static int lua_port_fd(lua_State *L)
{
	struct rs232_port_t *p = *(struct rs232_port_t**) luaL_checkudata(L, 1, MODULE_NAMESPACE);
	lua_pushinteger(L, rs232_fd(p));
	return 1;
}

/*
 * print(port:error_tostring(error))
 */
static int lua_port_strerror(lua_State *L)
{
	const char *ret = rs232_strerror((unsigned int) luaL_checkinteger(L, 1));
	if (ret == NULL)
		lua_pushnil(L);
	else
		lua_pushstring(L, ret);

	return 1;
}

#define FN_SET_PORT(type) \
	static int lua_port_set_##type(lua_State *L) \
	{ \
		struct rs232_port_t *p = *(struct rs232_port_t**) luaL_checkudata(L, 1, MODULE_NAMESPACE); \
		lua_pushinteger(L, rs232_set_##type(p, (unsigned int) luaL_checknumber(L, 2))); \
		return 1; \
	} \

#define FN_GET_PORT(type) \
	static int lua_port_get_##type(lua_State *L) \
	{ \
		struct rs232_port_t *p = *(struct rs232_port_t**) luaL_checkudata(L, 1, MODULE_NAMESPACE); \
		lua_pushinteger(L, rs232_get_##type(p)); \
		return 1; \
	}

#define FN_GET_PORT_STRING(type) \
	static int lua_port_get_str##type(lua_State *L) \
	{ \
		struct rs232_port_t *p = *(struct rs232_port_t**) luaL_checkudata(L, 1, MODULE_NAMESPACE); \
		int param = (int) luaL_optinteger(L, 2, -1); \
		const char *ret = rs232_str##type(param == -1 ? rs232_get_##type(p) : (unsigned int) param); \
		if (ret == NULL) { \
			lua_pushnil(L); \
		} else { \
			lua_pushstring(L, ret); \
		} \
		return 1; \
	}

FN_SET_PORT(baud)
FN_SET_PORT(data)
FN_SET_PORT(stop)
FN_SET_PORT(parity)
FN_SET_PORT(flow)
FN_SET_PORT(dtr)
FN_SET_PORT(rts)

FN_GET_PORT(baud)
FN_GET_PORT(data)
FN_GET_PORT(stop)
FN_GET_PORT(parity)
FN_GET_PORT(flow)
FN_GET_PORT(dtr)
FN_GET_PORT(rts)

FN_GET_PORT_STRING(baud)
FN_GET_PORT_STRING(data)
FN_GET_PORT_STRING(stop)
FN_GET_PORT_STRING(parity)
FN_GET_PORT_STRING(flow)
FN_GET_PORT_STRING(dtr)
FN_GET_PORT_STRING(rts)

static luaL_reg port_methods[] = {
	{ "__tostring", lua_port_tostring },
	{ "__gc", lua_port_gc },
	{ "read", lua_port_read },
	{ "write", lua_port_write },
	{ "close", lua_port_close },
	{ "flush", lua_port_flush },
	{ "device", lua_port_device },
	{ "fd", lua_port_fd },
	{ "in_queue", lua_port_in_queue },
	{ "in_queue_clear", lua_port_in_queue_clear },
	/* baud */
	{ "baud_rate", lua_port_get_baud },
	{ "baud_rate_tostring", lua_port_get_strbaud },
	{ "set_baud_rate", lua_port_set_baud },
	/* data */
	{ "data_bits", lua_port_get_data },
	{ "data_bits_tostring", lua_port_get_strdata },
	{ "set_data_bits", lua_port_set_data },
	/* stop */
	{ "stop_bits", lua_port_get_stop },
	{ "stop_bits_tostring", lua_port_get_strstop },
	{ "set_stop_bits", lua_port_set_stop },
	/* parity */
	{ "parity", lua_port_get_parity },
	{ "parity_tostring", lua_port_get_strparity },
	{ "set_parity", lua_port_set_parity },
	/* flow */
	{ "flow_control", lua_port_get_flow },
	{ "flow_control_tostring", lua_port_get_strflow },
	{ "set_flow_control", lua_port_set_flow },
	/* dtr */
	{ "dtr", lua_port_get_dtr },
	{ "dtr_tostring", lua_port_get_strdtr },
	{ "set_dtr", lua_port_set_dtr },
	/* rts */
	{ "rts", lua_port_get_rts },
	{ "rts_tostring", lua_port_get_strrts },
	{ "set_rts", lua_port_set_rts },
	{ NULL, NULL }
};

static luaL_reg port_functions[] = {
	{ "open", lua_port_open },
	{ "error_tostring", lua_port_strerror },
	{ NULL, NULL }
};

static void create_metatables(lua_State *L, const char *name, const luaL_reg *methods)
{
	luaL_newmetatable(L, name);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
#if LUA_VERSION_NUM < 502
	luaL_register(L, NULL, methods);
#else
	luaL_setfuncs(L, methods, 0);
#endif
}

RS232_LIB int luaopen_luars232(lua_State *L)
{
	int i;
	create_metatables(L, MODULE_NAMESPACE, port_methods);
#if LUA_VERSION_NUM < 502
	luaL_register(L, MODULE_NAMESPACE, port_functions);
#else
	luaL_newlib(L, port_functions);
#endif

	for (i = 0; luars232_ulong_consts[i].name != NULL; i++) {
		lua_pushstring(L, luars232_ulong_consts[i].name);
		lua_pushnumber(L, luars232_ulong_consts[i].value);
		lua_settable(L, -3);
	}

	lua_pushstring(L, MODULE_VERSION);
	lua_setfield(L, -2, "_VERSION");

	lua_pushstring(L, MODULE_BUILD);
	lua_setfield(L, -2, "_BUILD");

	lua_pushstring(L, MODULE_TIMESTAMP);
	lua_setfield(L, -2, "_TIMESTAMP");

	lua_pushstring(L, MODULE_COPYRIGHT);
	lua_setfield(L, -2, "_COPYRIGHT");

	DBG("[*] luaopen_luars232(Version: '%s' Build: '%s' TimeStamp: '%s')\n",
	    MODULE_VERSION, MODULE_BUILD, MODULE_TIMESTAMP);

	return 1;
}

RS232_LIB int luaopen_rs232_core(lua_State *L){
	return luaopen_luars232(L);
}
