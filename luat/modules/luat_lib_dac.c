
/*
@module  dac
@summary 数模转换
@version 1.0
@date    2021.12.03
@demo multimedia
@tag LUAT_USE_DAC
*/

#include "luat_base.h"
#include "luat_dac.h"
#include "luat_fs.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "dac"
#include "luat_log.h"

/*
打开DAC通道,并配置参数
@api dac.open(ch, freq, mode)
@int 通道编号,例如0
@int 输出频率,单位hz
@int 模式,默认为0,预留
@return true 成功返回true,否则返回false
@return int 底层返回值,调试用
@usage
if dac.open(0, 44000) then
    log.info("dac", "dac ch0 is opened")
end

*/
static int l_dac_open(lua_State *L) {
    int ch = luaL_checkinteger(L, 1);
    int freq = luaL_checkinteger(L, 2);
    int mode = luaL_optinteger(L, 3, 0);
    int ret = luat_dac_setup(ch, freq, mode);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

/*
从指定DAC通道输出一段波形,或者单个值
@api dac.write(ch, data)
@int 通道编号,例如0
@string 若输出固定值,可以填数值, 若输出波形,填string
@return true 成功返回true,否则返回false
@return int 底层返回值,调试用
@usage
if dac.open(0, 44000) then
    log.info("dac", "dac ch0 is opened")
    dac.write(0, string.fromHex("ABCDABCD"))
end
dac.close(0)
*/
static int l_dac_write(lua_State *L) {
    uint16_t* buff;
    size_t len;
    int ch;
    uint16_t value;

    ch = luaL_checkinteger(L, 1);
    if (lua_isinteger(L, 2)) {
        value = luaL_checkinteger(L, 2);
        buff = &value;
        len = 2;
    }
    else if (lua_isuserdata(L, 2)) {
        return 0; // TODO 支持zbuff
    }
    else if (lua_isstring(L, 2)) {
        buff = (uint16_t*)luaL_checklstring(L, 2, &len);
    }
    else {
        return 0;
    }
    // 防御过短的数据
    if (len < 2) {
        return 0;
    }
    int ret = luat_dac_write(ch, buff, len >> 1);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

// /*
// 从指定DAC通道输出一段波形,数据从文件读取
// @api dac.writeFile(ch, fd)
// @int 通道编号,例如0
// @string 文件路径
// @return true 成功返回true,否则返回false
// @return int 底层返回值,调试用

// if dac.open(0, 44000) then
//     log.info("dac", "dac ch0 is opened")
//     dac.writeFile(0, "/luadb/test.wav")
// end
// dac.close(0)
// */
// static int l_dac_write_file(lua_State *L) {
//     uint16_t* buff;
//     int ch;
//     size_t buff_size = 4096;
//     size_t len;

//     ch = luaL_checkinteger(L, 1);
//     const char* path = luaL_checkstring(L, 2);
//     FILE* fd = luat_fs_fopen(path, "rb");
//     if (fd == NULL) {
//         LLOGD("file not exist %s", path);
//         lua_pushboolean(L, 0);
//         return 1;
//     }
//     if (lua_isinteger(L, 3)) {
//         buff_size = luaL_checkinteger(L, 3);
//     }
//     buff = luat_heap_malloc(buff_size);
//     if (buff == NULL) {
//         luat_fs_fclose(fd);
//         LLOGW("buff size too big? %d", buff_size);
//         lua_pushboolean(L, 0);
//         return 1;
//     }
//     while (1) {
//         len = luat_fs_fread(buff, buff_size, 1, fd);
//         if (len == 0) {
//             break;
//         }
//         luat_dac_write(ch, buff, len);
//     }
//     luat_heap_free(buff);
//     luat_fs_fclose(fd);
//     lua_pushboolean(L, 1);
//     return 1;
// }

/*
关闭DAC通道
@api dac.close(ch)
@int 通道编号,例如0
@return true 成功返回true,否则返回false
@return int 底层返回值,调试用
@usage
if dac.open(0, 44000) then
    log.info("dac", "dac ch0 is opened")
    dac.write(0, string.fromHex("ABCDABCD"))
end
dac.close(0)
*/
static int l_dac_close(lua_State *L) {
    int ch = luaL_checkinteger(L, 1);
    int ret = luat_dac_close(ch);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

#include "rotable2.h"
static const rotable_Reg_t reg_dac[] =
{
    { "open" ,       ROREG_FUNC(l_dac_open)},
    { "write" ,      ROREG_FUNC(l_dac_write)},
//    { "writeFile",   ROREG_FUNC(l_dac_write_file)},
    { "close" ,      ROREG_FUNC(l_dac_close)},
	{ NULL,          ROREG_INT(0) }
};

LUAMOD_API int luaopen_dac( lua_State *L ) {
    luat_newlib2(L, reg_dac);
    return 1;
}
