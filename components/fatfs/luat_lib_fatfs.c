
/*
@module  fatfs
@summary 读写fatfs格式
@version 1.0
@date    2020.07.03
@demo    fatfs
@tag LUAT_USE_FATFS
@usage
-- 通常只使用fatfs.mount挂载tf/sd卡,其他操作走io库就可以了
*/
#include "luat_base.h"
#include "luat_spi.h"
#include "luat_sdio.h"
#include "luat_timer.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_fs.h"

#include "ff.h"			/* Obtains integer types */
#include "diskio.h"		/* Declarations of disk functions */

#define LUAT_LOG_TAG "fatfs"
#include "luat_log.h"


static FATFS *fs = NULL;		/* FatFs work area needed for each volume */
extern BYTE FATFS_DEBUG; // debug log, 0 -- disable , 1 -- enable
extern BYTE FATFS_POWER_PIN;
extern uint16_t FATFS_POWER_DELAY;
extern uint8_t FATFS_NO_CRC_CHECK;
extern uint16_t FATFS_WRITE_TO;
DRESULT diskio_open_ramdisk(BYTE pdrv, size_t len);
DRESULT diskio_open_spitf(BYTE pdrv, void* userdata);
DRESULT diskio_open_sdio(BYTE pdrv, void* userdata);

#ifdef LUAT_USE_FS_VFS
extern const struct luat_vfs_filesystem vfs_fs_fatfs;
#endif

static int s_fatfs_fmt = FM_FAT32;

/*
挂载fatfs
@api fatfs.mount(mode,mount_point, spiid_or_spidevice, spi_cs, spi_speed, power_pin, power_on_delay, auto_format)
@int fatfs模式,可选fatfs.SPI,fatfs.SDIO,fatfs.RAM,fatfs.USB
@string 虚拟文件系统的挂载点, 默认是 /fatfs
@int 传入spi device指针,或者spi的id,或者sdio的id
@int 片选脚的GPIO 号, spi模式有效. 特别约定,若前一个参数传的是spi device,这个参数要传SPI最高速度, 就是传2个"SPI最高速度", 也可以两个都填nil.
@int SPI最高速度,默认10M.
@int TF卡电源控制脚,TF卡初始前先拉低复位再拉高,如果没有,或者是内置电源控制方式,这个参数就不需要传
@int TF卡电源复位过程时间,单位ms,默认值是1
@bool 挂载失败是否尝试格式化,默认是true,即自动格式化. 本参数在2023.8.16添加
@return bool 成功返回true, 否则返回nil或者false
@return string 失败的原因
@usage
-- 方法1, 使用SPI模式
    local spiId = 2
    local result = spi.setup(
        spiId,--spi id
        255, -- 不使用默认CS脚
        0,--CPHA
        0,--CPOL
        8,--数据宽度
        400*1000  -- 初始化时使用较低的频率
    )
    local TF_CS = 8
    gpio.setup(TF_CS, 1)
    --fatfs.debug(1) -- 若挂载失败,可以尝试打开调试信息,查找原因
	-- 提醒, 若TF/SD模块带电平转换, 通常不支持10M以上的波特率!!
    fatfs.mount(fatfs.SPI,"/sd", spiId, TF_CS, 24000000)
    local data, err = fatfs.getfree("/sd")
    if data then
        log.info("fatfs", "getfree", json.encode(data))
    else
        log.info("fatfs", "err", err)
    end
	-- 往下的操作, 使用 io.open("/sd/xxx", "w+") 等io库的API就可以了
-- 方法2, 使用spi device方式
	local spiId = 2
	local TF_CS = 8
	-- 选一个合适的全局变量名
	tf_spi_dev = spi.device_setup(spiId, TF_CS, 0, 8, 20*1000*1000)
	fatfs.mount(fatfs.SPI,"/sd", tf_spi_dev)
*/
static int fatfs_mount(lua_State *L)
{
	if (FATFS_DEBUG)
		LLOGD("fatfs_init>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>");

	if (fs == NULL) {
		fs = luat_heap_malloc(sizeof(FATFS));
		if (fs == NULL) {
			lua_pushboolean(L, 0);
			LLOGD("out of memory when malloc FATFS");
			lua_pushstring(L, "out of memory when malloc FATFS");
			return 2;
		}
	}

	// 挂载点
	const char *mount_point = luaL_optstring(L, 2, "/fatfs");

	int fatfs_mode = luaL_checkinteger(L, 1);
	FATFS_POWER_PIN = luaL_optinteger(L, 6, 0xff);
	FATFS_POWER_DELAY = luaL_optinteger(L, 7, 1);
	if (fatfs_mode == DISK_SPI){
		luat_fatfs_spi_t *spit = luat_heap_malloc(sizeof(luat_fatfs_spi_t));
		if (spit == NULL) {
			lua_pushboolean(L, 0);
			LLOGD("out of memory when malloc luat_fatfs_spi_t");
			lua_pushstring(L, "out of memory when malloc luat_fatfs_spi_t");
			return 2;
		}
		memset(spit, 0, sizeof(luat_fatfs_spi_t));
		
		if (lua_type(L, 3) == LUA_TUSERDATA){
			spit->spi_device = (luat_spi_device_t*)lua_touserdata(L, 3);
			spit->fast_speed = luaL_optinteger(L, 4, 10000000);
			if (lua_isinteger(L, 5)) {
				spit->fast_speed = luaL_optinteger(L, 5, 10000000);
			}
			if (spit->fast_speed < 5*1000*1000) {
				spit->fast_speed = 5*1000*1000;
			}
			spit->type = 1;
			diskio_open_spitf(0, (void*)spit);
		} else {
			spit->type = 0;
			spit->spi_id = luaL_optinteger(L, 3, 0); // SPI_1
			spit->spi_cs = luaL_optinteger(L, 4, 3); // GPIO_3
			spit->fast_speed = luaL_optinteger(L, 5, 10000000);
			LLOGD("init sdcard at spi=%d cs=%d", spit->spi_id, spit->spi_cs);
			diskio_open_spitf(0, (void*)spit);
		}
	#ifdef LUAT_USE_SDIO
	}else if(fatfs_mode == DISK_SDIO){
		luat_fatfs_sdio_t *fatfs_sdio = luat_heap_malloc(sizeof(luat_fatfs_sdio_t));
		if (fatfs_sdio == NULL) {
			lua_pushboolean(L, 0);
				LLOGD("out of memory when malloc luat_fatfs_sdio_t");
			lua_pushstring(L, "out of memory when malloc luat_fatfs_sdio_t");
			return 2;
		}
		memset(fatfs_sdio, 0, sizeof(luat_fatfs_sdio_t));

		fatfs_sdio->id = luaL_optinteger(L, 3, 0); // SDIO_ID

		LLOGD("init FatFS at sdio");
		diskio_open_sdio(0, (void*)fatfs_sdio);
	#endif
	#if defined(LUA_USE_LINUX) || defined(LUA_USE_WINDOWS) || defined(LUA_USE_MACOSX)
	}else if(fatfs_mode == DISK_RAM){
		LLOGD("init ramdisk at FatFS");
		diskio_open_ramdisk(0, luaL_optinteger(L, 3, 64*1024));
	#endif
	}else if(fatfs_mode == DISK_USB){

	}else{
		LLOGD("fatfs_mode error %d", fatfs_mode);
		lua_pushboolean(L, 0);
		lua_pushstring(L, "fatfs_mode error");
		return 2;
	}
	FRESULT re = f_mount(fs, mount_point, 1);
    if (re != FR_OK) {
		if (lua_isboolean(L, 8) && lua_toboolean(L, 8) == 0) {
			LLOGI("sd/tf mount failed %d but auto-format is disabled", re);
			lua_pushboolean(L, 0);
			lua_pushstring(L, "mount error");
			return 2;
		}
		else {
			LLOGW("mount failed, try auto format");
			MKFS_PARM parm = {
				.fmt = s_fatfs_fmt,
				.au_size = 0,
				.align = 0,
				.n_fat = 0,
				.n_root = 0,
			};
			BYTE work[FF_MAX_SS] = {0};
			re = f_mkfs(mount_point, &parm, work, FF_MAX_SS);
			LLOGD("auto format ret %d", re);
			if (re == FR_OK) {
				re = f_mount(fs, mount_point, 1);
				LLOGD("remount again %d", re);
				if (re == FR_OK) {
					LLOGI("sd/tf mount success after auto format");
				}
				else {
					LLOGE("sd/tf mount failed again %d after auto format", re);
					lua_pushboolean(L, 0);
					lua_pushstring(L, "mount error");
					return 2; 
				}
			}
			else {
				LLOGE("sd/tf format failed %d", re);
				lua_pushboolean(L, 0);
				lua_pushstring(L, "format error");
				return 2;
			}
		}
	}
	
	lua_pushboolean(L, re == FR_OK);
	lua_pushinteger(L, re);
	if (re == FR_OK) {
		LLOGI("mount success at %s", fs->fs_type == FS_EXFAT ? "exfat" : (fs->fs_type == FS_FAT32 ? "fat32" : "fat16"));
		#ifdef LUAT_USE_FS_VFS
              luat_fs_conf_t conf2 = {
		            .busname = (char*)fs,
		            .type = "fatfs",
		            .filesystem = "fatfs",
		            .mount_point = mount_point,
	            };
	            luat_fs_mount(&conf2);
		#endif
	}
	else {
		LLOGE("[FatFS]fatfs_init FAIL!! re=%d", re);
	}

	if (FATFS_DEBUG)
		LLOGD("fatfs_init<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
    return 2;
}

/*
取消挂载fatfs
@api fatfs.unmount(mount_point)
@string 虚拟文件系统的挂载点, 默认是 fatfs,必须与fatfs.mount一致
@return int 成功返回0, 否则返回失败码
@usage
-- 注意, 取消挂载, 在 2025.9.29 之后编译的固件才真正支持
fatfs.mount("/sd")
*/
static int fatfs_unmount(lua_State *L) {

	const char *mount_point = luaL_optstring(L, 1, "/fatfs");
#ifdef LUAT_USE_FS_VFS
      luat_fs_conf_t conf = {
            .busname = (char*)fs,
            .type = "fatfs",
            .filesystem = "fatfs",
            .mount_point = mount_point,
        };
      luat_fs_umount(&conf);
#endif
    FRESULT re = f_mount(NULL, "/", 0);
	lua_pushinteger(L, re);
	return 1;
}

/**
获取可用空间信息
@api fatfs.getfree(mount_point)
@string 挂载点, 需要跟fatfs.mount传入的值一致
@return table 若成功会返回table,否则返回nil
@return int 导致失败的底层返回值
@usage
-- table包含的内容有
-- total_sectors 总扇区数量
-- free_sectors 空闲扇区数量
-- total_kb 总字节数,单位kb
-- free_kb 空闲字节数, 单位kb
-- 注意,当前扇区大小固定在512字节

    local data, err = fatfs.getfree("SD")
    if data then
        log.info("fatfs", "getfree", json.encode(data))
    else
        log.info("fatfs", "err", err)
    end
 */
static int fatfs_getfree(lua_State *L)
{
	DWORD fre_clust, fre_sect, tot_sect;
	// 挂载点
	const char *mount_point = luaL_optstring(L, 1, "/fatfs");
	FATFS *fs2;
    FRESULT re2 = f_getfree(mount_point, &fre_clust, &fs2);
    if (re2) {
		lua_pushnil(L);
		lua_pushinteger(L, re2);
		return 2;
	}
	/* Get total sectors and free sectors */
    tot_sect = (fs2->n_fatent - 2) * fs2->csize;
    fre_sect = fre_clust * fs2->csize;
	lua_newtable(L);

	lua_pushstring(L, "total_sectors");
	lua_pushinteger(L, tot_sect);
	lua_settable(L, -3);

	lua_pushstring(L, "free_sectors");
	lua_pushinteger(L, fre_sect);
	lua_settable(L, -3);

	lua_pushstring(L, "total_kb");
	lua_pushinteger(L, tot_sect / 2);
	lua_settable(L, -3);

	lua_pushstring(L, "free_kb");
	lua_pushinteger(L, fre_sect / 2);
	lua_settable(L, -3);
	
	return 1;
}

/**
设置调试模式
@api fatfs.debug(value)
@int 是否进入调试模式,1代表进入调试模式,增加调试日志
@return nil 无返回值
 */
static int fatfs_debug_mode(lua_State *L) {
	FATFS_DEBUG = luaL_optinteger(L, 1, 1);
	return 0;
}

/**
设置fatfs一些特殊参数
@api fatfs.config(crc_check, write_to, fmt)
@int 读取时是否跳过CRC检查,1跳过不检查CRC,0不跳过检查CRC,默认不跳过,除非TF卡不支持CRC校验,否则不应该跳过!
@int 单次写入超时时间,单位ms,默认100ms。
@int 文件系统格式,默认FM_FAT32, 可选值 FM_FAT32, FM_EXFAT
@return nil 无返回值
-- 前2个配置项不建议修改
*/
static int fatfs_config(lua_State *L) {
	if (lua_isinteger(L, 1)) {
		FATFS_NO_CRC_CHECK = luaL_optinteger(L, 1, 0);
	}
	if (lua_isinteger(L, 2)) {
		FATFS_WRITE_TO = luaL_optinteger(L, 2, 100);
	}
	if (lua_isinteger(L, 3)) {
		s_fatfs_fmt = luaL_optinteger(L, 3, FM_FAT32);
		if (s_fatfs_fmt != FM_FAT32 && s_fatfs_fmt != FM_EXFAT) {
			s_fatfs_fmt = FM_FAT32;
		}
		if (s_fatfs_fmt == FM_EXFAT) {
			LLOGI("fatfs set to exfat , when format sd/tf");
		}
		else {
			LLOGI("fatfs set to fat32 , when format sd/tf");
		}
	}
	return 0;
}

// Module function map
#include "rotable2.h"
static const rotable_Reg_t reg_fatfs[] =
{ 
  { "init",		ROREG_FUNC(fatfs_mount)}, //初始化,挂载, 别名方法
  { "mount",	ROREG_FUNC(fatfs_mount)}, //初始化,挂载
  { "getfree",	ROREG_FUNC(fatfs_getfree)}, // 获取文件系统大小,剩余空间
  { "debug",	ROREG_FUNC(fatfs_debug_mode)}, // 调试模式,打印更多日志
  { "config",	ROREG_FUNC(fatfs_config)}, //初始化,挂载, 别名方法
  { "unmount",	ROREG_FUNC(fatfs_unmount)}, // 取消挂载
  { "SPI",      ROREG_INT(DISK_SPI)},
  { "SDIO",     ROREG_INT(DISK_SDIO)},
  { "RAM",      ROREG_INT(DISK_RAM)},

  { "FM_FAT32",         ROREG_INT(FM_FAT32)},
  { "FM_EXFAT",         ROREG_INT(FM_EXFAT)},

  { NULL,		ROREG_INT(0)}
};

int luaopen_fatfs( lua_State *L )
{
  luat_newlib2(L, reg_fatfs);
  #ifdef LUAT_USE_FS_VFS
  luat_vfs_reg(&vfs_fs_fatfs);
  #endif
  return 1;
}
