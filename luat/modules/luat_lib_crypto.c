
#include "luat_base.h"
#include "luat_crypto.h"

static unsigned char hexchars[] = "0123456789ABCDEF";
static void fixhex(const char* source, char* dst, size_t len) {
    for (size_t i = 0; i < len; i++)
    {
        char ch = *(source+i);
        dst[i*2] = hexchars[(unsigned char)ch >> 4];
        dst[i*2+1] = hexchars[(unsigned char)ch & 0xF];
    }
}

static int l_crypto_md5(lua_State *L) {
    size_t size = 0;
    const char* str = luaL_checklstring(L, 1, &size);
    char tmp[32];
    char dst[32];
    if (luat_crypto_md5_simple(str, size, tmp) == 0) {
        fixhex(tmp, dst, 16);
        lua_pushlstring(L, dst, 32);
        return 1;
    }
    return 0;
}

static int l_crypto_hmac_md5(lua_State *L) {
    return 0;
}

#include "rotable.h"
static const rotable_Reg reg_crypto[] =
{
    { "md5" ,           l_crypto_md5        ,0},
    { "hmac_md5" ,      l_crypto_hmac_md5   ,0},
	{ NULL,             NULL                ,0}
};

LUAMOD_API int luaopen_crypto( lua_State *L ) {
    rotable_newlib(L, reg_crypto);
    return 1;
}
