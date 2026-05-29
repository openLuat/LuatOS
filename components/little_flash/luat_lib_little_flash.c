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
        if (little_flash_spi_device->spi_config.mode == 1){
            LLOGW("flash need half mode, spi_device mode is full mode, change to half mode");
            little_flash_spi_device->spi_config.mode = 0;
        }
        lf_flash = luat_heap_malloc(sizeof(little_flash_t));
        memset(lf_flash, 0, sizeof(lf_flash[0]));
        lf_flash->spi.user_data = little_flash_spi_device;
    }else{
        LLOGW("little_flash init spi_device is nil");
        return 0;
    }
    // little_flash_init();
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
    lua_pushboolean(L, ret ? 0 : 1);
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
    lua_pushboolean(L, ret ? 0 : 1);
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
    lua_pushboolean(L, ret ? 0 : 1);
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
    lua_pushboolean(L, ret ? 0 : 1);
    return 1;
}

/*
获取 Flash 信息
@api  lf.getInfo(flash)
@userdata flash Flash 设备对象 lf.init()返回的数据结构
@return int capacity 总容量 (byte)
@return int prog_size 编程最小单位 (byte)
@return int erase_size 擦除最小单位 (byte)
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
    uint32_t prog_size = 0;
    uint32_t erase_size = 0;

    capacity = flash->chip_info.capacity;
    prog_size = flash->chip_info.prog_size;
    erase_size = flash->chip_info.erase_size;

    lua_pushinteger(L, capacity);
    lua_pushinteger(L, prog_size);
    lua_pushinteger(L, erase_size);
    return 3;
}

#ifdef LUAT_USE_FS_VFS
#include "luat_fs.h"
#include "luat_lfs2.h"
#ifdef LUAT_USE_LFS2_NAND_COMPONENT
#include "luat_lfs2_nand.h"
#endif
#ifdef LUAT_USE_PGFS_COMPONENT
#include "luat_pgfs.h"
#endif

extern luat_lfs2_t* flash_lfs_lf(little_flash_t* flash, size_t offset, size_t maxsize);
typedef struct {
    void* bus;
    const char* filesystem;
} luat_lf_mount_backend_t;

static void* luat_little_flash_default_bus(void* flash, size_t offset, size_t maxsize) {
    return flash_lfs_lf((little_flash_t*)flash, offset, maxsize);
}

static void* luat_little_flash_named_bus(void* flash, size_t offset, size_t maxsize, const char* fs) {
#ifdef LUAT_USE_LFS2_NAND_COMPONENT
    if (fs != NULL && strcmp(fs, "lfsn") == 0) {
        luat_lfs2_nand_vfs_init();
        return luat_fs_lfs2_nand_default_bus(flash, offset, maxsize);
    }
#else
    (void)flash;
    (void)offset;
    (void)maxsize;
    (void)fs;
#endif
#ifdef LUAT_USE_PGFS_COMPONENT
    if (fs != NULL && strcmp(fs, "pgfs") == 0) {
        pgfs_vfs_init();
        return pgfs_default_bus(flash, offset, maxsize);
    }
#endif
    return NULL;
}

static int luat_lf_mount_resolve(void* flash, size_t offset, size_t maxsize, const char* fs, luat_lf_mount_backend_t* out) {
    const char* selector = fs;
    if (!out) {
        return -1;
    }
    memset(out, 0, sizeof(*out));
    if (!selector || selector[0] == 0 || strcmp(selector, "lfs2") == 0) {
        out->filesystem = "lfs2";
        out->bus = luat_little_flash_default_bus(flash, offset, maxsize);
        return out->bus ? 0 : -1;
    }
    out->filesystem = selector;
    out->bus = luat_little_flash_named_bus(flash, offset, maxsize, selector);
    return out->bus ? 0 : -1;
}

static const char* luat_little_flash_mount_fs_selector(lua_State *L, int index) {
    const char* fs = NULL;

    if (lua_isnoneornil(L, index)) {
        return NULL;
    }
    if (lua_type(L, index) == LUA_TSTRING) {
        return lua_tostring(L, index);
    }
    if (lua_istable(L, index)) {
        lua_getfield(L, index, "fs");
        if (lua_type(L, -1) == LUA_TSTRING) {
            fs = lua_tostring(L, -1);
        }
        lua_pop(L, 1);
    }
    return fs;
}

/*
挂载 little_flash lfs文件系统
@api  lf.mount(flash, mount_point, offset, maxsize, opts)
@userdata flash Flash 设备对象 lf.init()返回的数据结构
@string mount_point 挂载目录名
@int    起始偏移量,默认0
@int    总大小, 默认是整个flash
@table/string opts 可选, 文件系统选择. nil/"lfs2"为默认; 可传"lfsn"/"pgfs"或{fs="lfsn"}、{fs="pgfs"}
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
    const char* fs = luat_little_flash_mount_fs_selector(L, 5);
    luat_lf_mount_backend_t backend = {0};
    if (luat_lf_mount_resolve(flash, offset, maxsize, fs, &backend) == 0) {
        luat_fs_conf_t conf = {
            .busname = (char*)backend.bus,
            .type = (char*)backend.filesystem,
            .filesystem = (char*)backend.filesystem,
            .mount_point = mount_point,
        };
        LLOGD("vfs mount start %s fs %s offset %u size %u", mount_point, backend.filesystem, (unsigned int)offset, (unsigned int)maxsize);
        int ret = luat_fs_mount(&conf);
        LLOGD("vfs mount %s fs %s ret %d", mount_point, backend.filesystem, ret);
        lua_pushboolean(L, ret == 0);
    }
    else {
        lua_pushboolean(L, 0);
    }
    return 1;
}

#ifdef LUAT_USE_PGFS_COMPONENT
/*
PGFS runtime control helper
@api lf.pgfsctl(cmd, value)
@string cmd lock_mode|powercut_stage|corrupt_latest_cp|bad_block_once|reset_runtime|run_c_tests
@string/bool value value for command
@return bool success
*/
static int luat_little_flash_pgfsctl(lua_State *L) {
    const char* cmd = luaL_checkstring(L, 1);
    int ret = -1;
    if (strcmp(cmd, "lock_mode") == 0) {
        const char* mode = luaL_checkstring(L, 2);
        ret = pgfs_control_set_lock_mode(mode);
    }
    else if (strcmp(cmd, "powercut_stage") == 0) {
        const char* stage = luaL_checkstring(L, 2);
        ret = pgfs_control_inject_powercut_stage(stage);
    }
    else if (strcmp(cmd, "corrupt_latest_cp") == 0) {
        ret = pgfs_control_inject_corrupt_latest_cp(lua_toboolean(L, 2));
    }
    else if (strcmp(cmd, "bad_block_once") == 0) {
        ret = pgfs_control_inject_bad_block_once(lua_toboolean(L, 2));
    }
    else if (strcmp(cmd, "reset_runtime") == 0) {
        ret = pgfs_control_reset_runtime();
    }
    else if (strcmp(cmd, "run_c_tests") == 0) {
        ret = pgfs_run_c_layer_tests();
    }
    lua_pushboolean(L, ret == 0);
    return 1;
}
#endif
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
#ifdef LUAT_USE_PGFS_COMPONENT
    { "pgfsctl",        ROREG_FUNC(luat_little_flash_pgfsctl)},
#endif
#endif
	{ NULL,             ROREG_INT(0)}
};

LUAMOD_API int luaopen_little_flash( lua_State *L ) {
    luat_newlib2(L, reg_little_flash);
    return 1;
}
