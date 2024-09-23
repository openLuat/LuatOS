
/*
@module  otp
@summary OTP操作库
@version 1.0
@date    2021.12.08
@tag LUAT_USE_OTP
@usage
----------------------------
--- 本库已经废弃, 不要使用 ---
----------------------------
*/
#include "luat_base.h"
#include "luat_otp.h"

#define LUAT_LOG_TAG "otp"
#include "luat_log.h"

/*
读取指定OTP区域读取数据
@api otp.read(zone, offset, len)
@int 区域, 通常为0/1/2/3, 与具体硬件相关
@int 偏移量
@int 读取长度, 单位字节, 必须是4的倍数, 不能超过4096字节
@return string 成功返回字符串, 否则返回nil
@usage

local otpdata = otp.read(0, 0, 64)
if otpdata then
    log.info("otp", otpdata:toHex())
end
*/
static int l_otp_read(lua_State *L) {
    int zone;
    int offset;
    int len;

    zone = luaL_checkinteger(L, 1);
    offset = luaL_checkinteger(L, 2);
    len = luaL_checkinteger(L, 3);

    if (zone < 0 || zone > 16) {
        return 0;
    }
    if (offset < 0 || offset > 4*1024) {
        return 0;
    }
    if (len < 0 || len > 4*1024) {
        return 0;
    }
    if (offset + len > 4*1024) {
        return 0;
    }
    luaL_Buffer buff;
    luaL_buffinitsize(L, &buff, len);
    memset(buff.b, 0, len);
    int ret = luat_otp_read(zone, buff.b, (size_t)offset, (size_t)len);
    if (ret >= 0) {
        lua_pushlstring(L, buff.b, ret);
        return 1;
    }
    else {
        return 0;
    }
};

/*
往指定OTP区域写入数据
@api otp.write(zone, data, offset)
@int 区域, 通常为0/1/2/3, 与具体硬件相关
@string 数据, 长度必须是4个倍数
@int 偏移量
@return booL 成功返回true,否则返回false
*/
static int l_otp_write(lua_State *L) {
    int zone;
    int offset;
    size_t len;
    const char* data;

    zone = luaL_checkinteger(L, 1);
    data = luaL_checklstring(L, 2, &len);
    offset = luaL_checkinteger(L, 3);

    if (zone < 0 || zone > 16) {
        return 0;
    }
    if (offset < 0 || offset > 4*1024) {
        return 0;
    }
    if (len > 4*1024) {
        return 0;
    }
    if (offset + len > 4*1024) {
        return 0;
    }
    int ret = luat_otp_write(zone, (char*)data, (size_t)offset, len);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
};

/*
擦除指定OTP区域
@api otp.erase(zone)
@int 区域, 通常为0/1/2/3, 与具体硬件相关
@return bool 成功返回true,否则返回false
*/
static int l_otp_erase(lua_State *L) {
    int zone;
    zone = luaL_checkinteger(L, 1);
    int ret = luat_otp_erase(zone, 0, 1024);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
};

/*
锁定OTP区域. 特别注意!!一旦加锁即无法解锁,OTP变成只读!!!
@api otp.lock(zone)
@return bool 成功返回true,否则返回false
*/
static int l_otp_lock(lua_State *L) {
    int zone = luaL_optinteger(L, 1, 0);
    int ret = luat_otp_lock(zone);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
};


#include "rotable2.h"
static const rotable_Reg_t reg_otp[] =
{
    {"read",    ROREG_FUNC(l_otp_read)},
    {"write",   ROREG_FUNC(l_otp_write)},
    {"erase",   ROREG_FUNC(l_otp_erase)},
    {"lock",    ROREG_FUNC(l_otp_lock)},
	{ NULL,     ROREG_INT(0) }
};

LUAMOD_API int luaopen_otp( lua_State *L ) {
    luat_newlib2(L, reg_otp);
    return 1;
}
