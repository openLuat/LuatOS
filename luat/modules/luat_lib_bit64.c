/*
@module  bit64
@summary 32位系统上对64位数据的基本算术运算和逻辑运算
@version 0.1
@date    2023.03.11
@tag LUAT_USE_BIT64
@demo  bit64
@note 64位数据用9字节string存储，byte7~byte0存数据，byte8=0表示整形，其他表示浮点
*/
#include "luat_base.h"
#include "luat_malloc.h"
#define LUAT_LOG_TAG "bit64"
#include "luat_log.h"
#define D64_FLAG 0x01
#ifdef LUAT_USE_BIT64
/**
64bit数据转成32bit输出
@api bit64.to32(data64bit)
@string 9字节数据
@return any 根据64bit数据输出int或者number
 */
static int l_bit64_to32(lua_State *L)
{
	double d64;
	int64_t i64;
    size_t len;
    const char *data = luaL_checklstring(L, 1, &len);

    if (len != 9)
    {
    	lua_pushnil(L);
    }
    if (data[8])
    {
        memcpy(&d64, data, 8);
        lua_pushnumber(L, (lua_Number)d64);
    }
    else
    {
    	memcpy(&i64, data, 8);
    	lua_pushinteger(L, (lua_Integer)i64);
    }
    return 1;
}

/**
32bit数据转成64bit数据
@api bit64.to64(data32bit)
@int/number 32bit数据
@return string 9字节数据
 */
static int l_bit64_to64(lua_State *L)
{
	double d64;
	uint64_t u64;
	uint8_t data[9] = {0};
	if (lua_isinteger(L, 1))
	{
		u64 = (lua_Unsigned)lua_tointeger(L, 1);
		memcpy(data, &u64, 8);
	}
	else if (lua_isnumber(L, 1))
	{
		d64 = lua_tonumber(L, 1);
		data[8] = D64_FLAG;
		memcpy(data, &d64, 8);

	}
	lua_pushlstring(L, (const char*)data, 9);
	return 1;
}

/**
64bit数据格式化打印成字符串，用于显示值
@api bit64.show(a,type,flag)
@string 需要打印的64bit数据
@int 进制，10=10进制，16=16进制，默认10，只支持10或者16
@boolean 整形是否按照无符号方式打印，true是，false不是，默认false，浮点忽略
@return string 可以打印的值
 */
static int l_bit64_show(lua_State *L)
{
	int64_t i64;
	double d64;
    size_t len;
    uint8_t data[64] = {0};
    uint8_t flag = 0;
    const char *string = luaL_checklstring(L, 1, &len);
    if (len != 9)
    {
    	lua_pushnil(L);
    	return 1;
    }
    if (string[8])
    {
    	memcpy(&d64, string, 8);
    }
    else
    {
    	memcpy(&i64, string, 8);
    }
    uint8_t type = luaL_optinteger(L, 2, 10);
	if (lua_isboolean(L, 3))
	{
		flag = lua_toboolean(L, 3);
	}
	if (type != 16)
	{
		if (string[8])
		{
			len = snprintf_((char*)data, 63, "%f", d64);
		}
		else
		{
			if (flag)
			{
				len = snprintf_((char*)data, 63, "%llu", i64);
			}
			else
			{
				len = snprintf_((char*)data, 63, "%lld", (uint64_t)i64);
			}
		}
	}
	else
	{
		if (string[8])
		{
			len = snprintf_((char*)data, 63, "0x%llx", d64);
		}
		else
		{
			len = snprintf_((char*)data, 63, "0x%llx", i64);
		}
	}
	lua_pushlstring(L, (const char*)data, len);
	return 1;
}

static int l_bit64_calculate(lua_State *L, uint8_t op)
{
	double d64_a,d64_b;
	int64_t i64_a, i64_b;
	uint64_t u64;
    size_t len;
    uint8_t data[9] = {0};
    uint8_t flag1 = 0;
    uint8_t flag2 = 0;
    uint8_t fa,fb;
    const char *string = luaL_checklstring(L, 1, &len);
    if (len != 9)
    {
    	goto DONE;
    }
    fa = string[8];
    if (fa)
    {
    	memcpy(&d64_a, string, 8);
    }
    else
    {
    	memcpy(&i64_a, string, 8);
    }
	if (lua_isinteger(L, 2))
	{
		i64_b = lua_tointeger(L, 2);
		fb = 0;
	}
	else if (lua_isnumber(L, 2))
	{
		d64_b = lua_tonumber(L, 2);
		fb = 1;
	}
	else
	{
		string = luaL_checklstring(L, 2, &len);
	    if (len != 9)
	    {
	    	goto DONE;
	    }
	    fb = string[8];
	    if (fb)
	    {
	    	memcpy(&d64_b, string, 8);
	    }
	    else
	    {
	    	memcpy(&i64_b, string, 8);
	    }
	}

	if (lua_isboolean(L, 3))
	{
		flag1 = lua_toboolean(L, 3);
	}
	if (lua_isboolean(L, 4))
	{
		flag2 = lua_toboolean(L, 4);
	}
	switch(op)
	{
	case 0:
		if (fa && fb)
		{
			d64_a = d64_a + d64_b;
			goto FLOAT_OP;
		}
		if (fa && !fb)
		{
			d64_a = d64_a + i64_b;
			goto FLOAT_OP;
		}
		if (!fa && fb)
		{
			d64_a = i64_a + d64_b;
			goto FLOAT_OP;
		}
		if (!fa && !fb)
		{
			if (flag1)
			{
				u64 = (uint64_t)i64_a + (uint64_t)i64_b;
				memcpy(data, &u64, 8);
			}
			else
			{
				i64_a = i64_a + i64_b;
				memcpy(data, &i64_a, 8);
			}
			goto DONE;
		}
		break;
	case 1:
		if (fa && fb)
		{
			d64_a = d64_a - d64_b;
			goto FLOAT_OP;
		}

		if (fa && !fb)
		{
			d64_a = d64_a - i64_b;
			goto FLOAT_OP;
		}

		if (!fa && fb)
		{
			d64_a = i64_a - d64_b;
			goto FLOAT_OP;
		}

		if (!fa && !fb)
		{
			if (flag1)
			{
				u64 = (uint64_t)i64_a - (uint64_t)i64_b;
				memcpy(data, &u64, 8);
			}
			else
			{
				i64_a = i64_a - i64_b;
				memcpy(data, &i64_a, 8);
			}
			goto DONE;
		}
		break;
	case 2:
		if (fa && fb)
		{
			d64_a = d64_a * d64_b;
			goto FLOAT_OP;
		}
		if (fa && !fb)
		{
			d64_a = d64_a * i64_b;
			goto FLOAT_OP;
		}
		if (!fa && fb)
		{
			d64_a = i64_a * d64_b;
			goto FLOAT_OP;
		}
		if (!fa && !fb)
		{
			if (flag1)
			{
				u64 = (uint64_t)i64_a * (uint64_t)i64_b;
				memcpy(data, &u64, 8);
			}
			else
			{
				i64_a = i64_a * i64_b;
				memcpy(data, &i64_a, 8);
			}
			goto DONE;
		}
		break;
	case 3:
		if (fa && fb)
		{
			d64_a = d64_a / d64_b;
			goto FLOAT_OP;
		}
		if (fa && !fb)
		{
			d64_a = d64_a / i64_b;
			goto FLOAT_OP;
		}
		if (!fa && fb)
		{
			d64_a = i64_a / d64_b;
			goto FLOAT_OP;
		}
		if (!fa && !fb)
		{
			if (flag1)
			{
				u64 = (uint64_t)i64_a / (uint64_t)i64_b;
				memcpy(data, &u64, 8);
			}
			else
			{
				i64_a = i64_a / i64_b;
				memcpy(data, &i64_a, 8);
			}
			goto DONE;
		}
		break;
	}
FLOAT_OP:
	if (flag2)
	{
		i64_a = d64_a;
		memcpy(data, &i64_a, 8);
	}
	else
	{
		data[8] = D64_FLAG;
		memcpy(data, &d64_a, 8);
	}
	goto DONE;
DONE:
	lua_pushlstring(L, (const char*)data, 9);
	return 1;
}

/**
64bit数据加,a+b,a和b中有一个为浮点，则按照浮点运算
@api bit64.plus(a,b,flag1,flag2)
@string a
@string/int/number b
@boolean 整形运算时是否按照无符号方式，true是，false不是，默认false，浮点运算忽略
@boolean 浮点运算结果是否要强制转成整数，true是，false不是，默认false，整形运算忽略
@return string 9字节数据
 */
static int l_bit64_plus(lua_State *L)
{
	return l_bit64_calculate(L, 0);
}


/**
64bit数据减,a-b,a和b中有一个为浮点，则按照浮点运算
@api bit64.minus(a,b,flag1,flag2)
@string a
@string/int/number b
@boolean 整形运算时是否按照无符号方式，true是，false不是，默认false，浮点运算忽略
@boolean 浮点运算结果是否要强制转成整数，true是，false不是，默认false，整形运算忽略
@return string 9字节数据
 */
static int l_bit64_minus(lua_State *L)
{
	return l_bit64_calculate(L, 1);
}

/**
64bit数据乘,a*b,a和b中有一个为浮点，则按照浮点运算
@api bit64.mult(a,b,flag1,flag2)
@string a
@string/int/number b
@boolean 整形运算时是否按照无符号方式，true是，false不是，默认false，浮点运算忽略
@boolean 浮点运算结果是否要强制转成整数，true是，false不是，默认false，整形运算忽略
@return string 9字节数据
 */
static int l_bit64_multiply(lua_State *L)
{
	return l_bit64_calculate(L, 2);
}

/**
64bit数据除,a/b,a和b中有一个为浮点，则按照浮点运算
@api bit64.pide(a,b,flag1,flag2)
@string a
@string/int/number b
@boolean 整形运算时是否按照无符号方式，true是，false不是，默认false，浮点运算忽略
@boolean 浮点运算结果是否要强制转成整数，true是，false不是，默认false，整形运算忽略
@return string 9字节数据
 */
static int l_bit64_pide(lua_State *L)
{
	return l_bit64_calculate(L, 3);
}

/**
64bit数据位移 a>>b 或者 a<<b
@api bit64.shift(a,b,flag)
@string a
@int b
@boolean 位移方向，true左移<<，false右移>>，默认false
@return string 9字节数据
 */
static int l_bit64_shift(lua_State *L)
{
	uint64_t u64;
	uint32_t pos = 0;
    size_t len;
    uint8_t data[9] = {0};
    uint8_t flag = 0;
    const char *string = luaL_checklstring(L, 1, &len);
    if (len != 9)
    {
    	goto DONE;
    }
    data[8] = string[8];
    memcpy(&u64, string, 8);

	if (lua_isinteger(L, 2))
	{
		pos = lua_tointeger(L, 2);
		if (!pos)
		{
			goto DONE;
		}
	}
	else
	{
		goto DONE;
	}
	if (lua_isboolean(L, 3))
	{
		flag = lua_toboolean(L, 3);
	}
	if (flag)
	{
		u64 = u64 << pos;
	}
	else
	{
		u64 = u64 >> pos;
	}
    data[8] = string[8];
    memcpy(data, &u64, 8);
	lua_pushlstring(L, (const char*)data, 9);
	return 1;
DONE:
	lua_pushlstring(L, (const char*)string, len);
	return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_bit64[] = {
	{"to32", ROREG_FUNC(l_bit64_to32)},
	{"to64", ROREG_FUNC(l_bit64_to64)},
	{"plus", ROREG_FUNC(l_bit64_plus)},
	{"minus", ROREG_FUNC(l_bit64_minus)},
	{"multi", ROREG_FUNC(l_bit64_multiply)},
	{"pide", ROREG_FUNC(l_bit64_pide)},
	{"shift", ROREG_FUNC(l_bit64_shift)},
	{"show", ROREG_FUNC(l_bit64_show)},
	{NULL,       ROREG_INT(0)}
};

LUAMOD_API int luaopen_bit64(lua_State *L)
{
    luat_newlib2(L, reg_bit64);
    return 1;
}
#endif
