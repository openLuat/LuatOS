/*
@module  sfd
@summary SPI FLASH操作库
@version 1.0
@date    2021.05.18
*/
#include "luat_base.h"
#include "luat_spi.h"
#include "luat_sfd.h"

#define LUAT_LOG_SDF
#include "luat_log.h"


extern const sdf_opts_t sfd_w25q_opts;

/*
初始化spi flash
@api    sfd.init(spi_id, spi_cs)
@int  SPI总线的id
@int  SPI FLASH的片选脚对应的GPIO
@return userdata 成功返回一个数据结构,否则返回nil
@usage
local w25q = sfd.init(0, 17)
if w25q then
    log.info("sfd", "chip id", sfd.id(w25q):toHex())
end
*/
static int l_sfd_init(lua_State *L) {
    int spi_id = luaL_checkinteger(L, 1);
    int spi_cs = luaL_checkinteger(L, 2);

    sfd_w25q_t *w25q = (sfd_w25q_t *)lua_newuserdata(L, sizeof(sfd_w25q_t));
    memset(w25q, 0, sizeof(sfd_w25q_t));
    w25q->spi_id = spi_id;
    w25q->spi_cs = spi_cs;
    w25q->opts = &sfd_w25q_opts;

    int re = w25q->opts->initialize(w25q);
    if (re == 0) {
        return 1;
    }
    return 0;
}

/*
检查spi flash状态
@api    sfd.status(w25q)
@userdata  sfd.init返回的数据结构
@return int 状态值,0 未初始化成功,1初始化成功且空闲,2正忙
@usage
local w25q = sfd.init(0, 17)
if w25q then
    log.info("sfd", "status", sfd.status(w25q))
end
*/
static int l_sfd_status(lua_State *L) {
    sfd_w25q_t *w25q = (sfd_w25q_t *) lua_touserdata(L, 1);
    lua_pushinteger(L, w25q->opts->status(w25q));
    return 1;
}

/*
读取数据
@api    sfd.read(w25q, offset, len)
@userdata  sfd.init返回的数据结构
@int    起始偏移量
@int    读取长度,当前限制在256以内
@return string 数据
@usage
local w25q = sfd.init(0, 17)
if w25q then
    log.info("sfd", "read", sfd.read(w25q, 0x100, 256))
end
*/
static int l_sfd_read(lua_State *L) {
    sfd_w25q_t *w25q = (sfd_w25q_t *) lua_touserdata(L, 1);
    size_t offset = luaL_checkinteger(L, 2);
    size_t len = luaL_checkinteger(L, 3);
    luaL_Buffer buff;
    luaL_buffinitsize(L, &buff, len);
    w25q->opts->read(w25q, buff.b, offset, len);
    luaL_pushresult(&buff);
    return 1;
}

/*
写入数据
@api    sfd.write(w25q, offset, data)
@userdata  sfd.init返回的数据结构
@int    起始偏移量
@string    需要写入的数据,当前支持256字节及以下
@return boolean 成功返回true,失败返回false
@usage
local w25q = sfd.init(0, 17)
if w25q then
    log.info("sfd", "write", sfd.write(w25q, 0x100, "hi,luatos"))
end
*/
static int l_sfd_write(lua_State *L) {
    sfd_w25q_t *w25q = (sfd_w25q_t *) lua_touserdata(L, 1);
    size_t offset = luaL_checkinteger(L,2);
    size_t len = 0;
    const char* buff = luaL_checklstring(L, 3, &len);
    int re = w25q->opts->write(w25q, buff, offset, len);
    lua_pushboolean(L, re == 0 ? 1 : 0);
    return 1;
}

/*
写入数据
@api    sfd.erase(w25q, offset)
@userdata  sfd.init返回的数据结构
@int    起始偏移量
@return boolean 成功返回true,失败返回false
@usage
local w25q = sfd.init(0, 17)
if w25q then
    log.info("sfd", "write", sfd.erase(w25q, 0x100))
end
*/
static int l_sfd_erase(lua_State *L) {
    sfd_w25q_t *w25q = (sfd_w25q_t *) lua_touserdata(L, 1);
    size_t offset = luaL_checkinteger(L,2);
    size_t len = luaL_optinteger(L, 3, 4096);
    int re = w25q->opts->erase(w25q, offset, len);
    lua_pushboolean(L, re == 0 ? 1 : 0);
    return 1;
}

static int l_sfd_ioctl(lua_State *L) {
    return 0;
}

/*
芯片唯一id
@api    sfd.id(w25q)
@userdata  sfd.init返回的数据结构
@return string 8字节(64bit)的芯片id
@usage
local w25q = sfd.init(0, 17)
if w25q then
    log.info("sfd", "chip id", sfd.id(w25q))
end
*/
static int l_sfd_id(lua_State *L) {
    sfd_w25q_t *w25q = (sfd_w25q_t *) lua_touserdata(L, 1);
    lua_pushlstring(L, w25q->chip_id, 8);
    return 1;
}

#include "rotable.h"
static const rotable_Reg reg_sfd[] =
{
    { "init" ,             l_sfd_init,           0},
    { "status",            l_sfd_status,         0},
    { "read",              l_sfd_read,           0},
    { "write",             l_sfd_write,          0},
    { "erase",             l_sfd_erase,          0},
    { "ioctl",             l_sfd_ioctl,          0},
    { "id",                l_sfd_id,             0},
};

LUAMOD_API int luaopen_sfd( lua_State *L ) {
    luat_newlib(L, reg_sfd);
    return 1;
}
