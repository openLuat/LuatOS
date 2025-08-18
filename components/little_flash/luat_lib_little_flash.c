/*
@module  little_flash
@summary flash驱动 软件包(同时支持驱动nor flash和nand flash设备)
@version 1.0
@date    2024.05.11
@demo little_flash
@tag LUAT_USE_LITTLE_FLASH
*/

#include "luat_base.h"
#include "luat_spi.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "little_flash"
#include "luat_log.h"
#include "little_flash.h"

/*
初始化 little_flash
@api  lf.init(spi_device)
@userdata spi_device
@return userdata 成功返回一个数据结构,否则返回nil
@usage
--spi_device
spi_device = spi.deviceSetup(0,17,0,0,8,2000000,spi.MSB,1,0)
log.info("lf.init",lf.init(spi_device))
*/
static int luat_little_flash_init(lua_State *L){
    luat_spi_device_t* little_flash_spi_device = NULL;
    little_flash_t* lf_flash = NULL;
    if (lua_type(L, 1) == LUA_TUSERDATA){
        little_flash_spi_device = (luat_spi_device_t*)lua_touserdata(L, 1);
        lf_flash = luat_heap_malloc(sizeof(little_flash_t));
        memset(lf_flash, 0, sizeof(little_flash_t));
        lf_flash->spi.user_data = little_flash_spi_device;
    }else{
        LLOGW("little_flash init spi_device is nil");
        return 0;
    }
    little_flash_init();
    lf_err_t re = little_flash_device_init(lf_flash);
    if (re == LF_ERR_OK){
        lua_pushlightuserdata(L, lf_flash);
        return 1;
    }
    luat_heap_free(lf_flash);
    return 0;
}

/*
擦除 Flash 指定地址指定大小，按照flash block大小进行擦除
@api  lf.erase(flash,add,size)
@userdata flash Flash 设备对象 lf.init()返回的数据结构
@number add 擦除地址
@number size 擦除大小
@return bool 成功返回true
@usage
lf.erase(flash,add,size)
*/
static int luat_little_flash_erase(lua_State *L){
    little_flash_t *flash = lua_touserdata(L, 1);
    if (flash == NULL) {
        LLOGE("little_flash mount flash is nil");
        return 0;
    }
    uint32_t addr = luaL_checkinteger(L, 2);
    size_t size = luaL_checkinteger(L, 3);
    lf_err_t ret = little_flash_erase(flash,addr,size);
    lua_pushboolean(L, ret ? 1 : 0);
    return 1;
}

/*
擦除 Flash 全部数据
@api  lf.chipErase(flash)
@userdata flash Flash 设备对象 lf.init()返回的数据结构
@return bool 成功返回true
@usage
lf.chipErase(flash)
*/
static int luat_little_flash_chip_erase(lua_State *L){
    little_flash_t *flash = lua_touserdata(L, 1);
    if (flash == NULL) {
        LLOGE("little_flash mount flash is nil");
        return 0;
    }
    lf_err_t ret = little_flash_chip_erase(flash);
    lua_pushboolean(L, ret ? 1 : 0);
    return 1;
}

/*
读取 Flash 数据
@api  lf.read(flash, addr, size)
@userdata flash Flash 设备对象 lf.init()返回的数据结构
@int addr 起始地址
@int size 从起始地址开始读取数据的总大小
@return string data 读取到的数据
@usage
log.info("lf.read",lf.read(lf_device,1024,4))
*/
static int luat_little_flash_read(lua_State *L){
    little_flash_t *flash = lua_touserdata(L, 1);
    if (flash == NULL) {
        LLOGE("little_flash mount flash is nil");
        return 0;
    }
    uint32_t addr = luaL_checkinteger(L, 2);
    size_t size = luaL_checkinteger(L, 3);
    uint8_t* data = (uint8_t*)luat_heap_malloc(size);
    lf_err_t ret = little_flash_read(flash, addr, data, size);
    if(ret != 0){
        size = 0;
        LLOGD("lf read ret %d", ret);
    }
    lua_pushlstring(L, (const char*)data, size);
    luat_heap_free(data);
    return 1;
}
    
/*
向 Flash 写数据
@api  lf.write(flash, addr,data)
@userdata flash Flash 设备对象 lf.init()返回的数据结构
@int addr 起始地址
@string data 待写入的数据
@return bool 成功返回true
@usage
log.info("lf.write",lf.write(lf_device,1024,"lf"))
*/
static int luat_little_flash_write(lua_State *L){
    little_flash_t *flash = lua_touserdata(L, 1);
    if (flash == NULL) {
        LLOGE("little_flash mount flash is nil");
        return 0;
    }
    uint32_t addr = luaL_checkinteger(L, 2);
    size_t size = 0;
    const char* data = luaL_checklstring(L, 3, &size);
    lf_err_t ret = little_flash_write(flash, addr, (const uint8_t*)data, size);
    lua_pushboolean(L, ret ? 1 : 0);
    return 1;
}

/*
先擦除再往 Flash 写数据
@api  lf.eraseWrite(flash, addr,data)
@userdata flash Flash 设备对象 lf.init()返回的数据结构
@int addr 起始地址
@string data 待写入的数据
@return bool 成功返回true
@usage
log.info("lf.eraseWrite",lf.eraseWrite(lf_device,1024,"lf"))
*/
static int luat_little_flash_erase_write(lua_State *L){
    little_flash_t *flash = lua_touserdata(L, 1);
    if (flash == NULL) {
        LLOGE("little_flash mount flash is nil");
        return 0;
    }
    uint32_t addr = luaL_checkinteger(L, 2);
    size_t size = 0;
    const char* data = luaL_checklstring(L, 3, &size);
    lf_err_t ret = little_flash_erase_write(flash, addr, (const uint8_t*)data, size);
    lua_pushboolean(L, ret ? 1 : 0);
    return 1;
}

/*
获取 Flash 容量和page大小
@api  lf.getInfo(flash)
@userdata flash Flash 设备对象 lf.init()返回的数据结构
@return int Flash 容量
@return int page 页大小
@usage
log.info("lf.getInfo",lf.getInfo(lf_device))
*/

static int luat_little_flash_get_info(lua_State *L){
    little_flash_t *flash = lua_touserdata(L, 1);
    if (flash == NULL) {
        LLOGE("little_flash mount flash is nil");
        return 0;
    }
    uint32_t capacity = 0;
    uint32_t page = 0;
    capacity = flash->chip_info.capacity;
    page = flash->chip_info.prog_size;
    lua_pushinteger(L, capacity);
    lua_pushinteger(L, page);
    return 2;
}

#ifdef LUAT_USE_FS_VFS
#include "luat_fs.h"
#include "lfs.h"
extern lfs_t* flash_lfs_lf(little_flash_t* flash, size_t offset, size_t maxsize);

/*
挂载 little_flash lfs文件系统
@api  lf.mount(flash, mount_point, offset, maxsize)
@userdata flash Flash 设备对象 lf.init()返回的数据结构
@string mount_point 挂载目录名
@int    起始偏移量,默认0
@int    总大小, 默认是整个flash
@return bool 成功返回true
@usage
log.info("lf.mount",lf.mount(little_flash_device,"/little_flash"))
*/
static int luat_little_flash_mount(lua_State *L) {
    little_flash_t *flash = lua_touserdata(L, 1);
    if (flash == NULL) {
        LLOGE("little_flash mount flash is nil");
        return 0;
    }
    const char* mount_point = luaL_checkstring(L, 2);
    size_t offset = luaL_optinteger(L, 3, 0);
    size_t maxsize = luaL_optinteger(L, 4, 0);
    lfs_t* lfs = flash_lfs_lf(flash, offset, maxsize);
    if (lfs) {
	    luat_fs_conf_t conf = {
		    .busname = (char*)lfs,
		    .type = "lfs2",
		    .filesystem = "lfs2",
		    .mount_point = mount_point,
	    };
	    int ret = luat_fs_mount(&conf);
        LLOGD("vfs mount %s ret %d", mount_point, ret);
        lua_pushboolean(L, 1);
    }
    else {
        lua_pushboolean(L, 0);
    }
    return 1;
}
#endif

#include "rotable2.h"
static const rotable_Reg_t reg_little_flash[] =
{
    { "init",           ROREG_FUNC(luat_little_flash_init)},
    { "erase",          ROREG_FUNC(luat_little_flash_erase)},
    { "chipErase",      ROREG_FUNC(luat_little_flash_chip_erase)},
    { "read",           ROREG_FUNC(luat_little_flash_read)},
    { "write",          ROREG_FUNC(luat_little_flash_write)},
    { "eraseWrite",     ROREG_FUNC(luat_little_flash_erase_write)},
    { "getInfo",        ROREG_FUNC(luat_little_flash_get_info)},
#ifdef LUAT_USE_FS_VFS
    { "mount",          ROREG_FUNC(luat_little_flash_mount)},
#endif
	{ NULL,             ROREG_INT(0)}
};

LUAMOD_API int luaopen_little_flash( lua_State *L ) {
    luat_newlib2(L, reg_little_flash);
    return 1;
}
