#include "luat_base.h"
#include "luat_fs.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "fs"
#include "luat_log.h"

#include "dirent.h"

extern const struct luat_vfs_filesystem vfs_fs_posix;
extern const struct luat_vfs_filesystem vfs_fs_luadb;
extern const struct luat_vfs_filesystem vfs_fs_ram;
extern const struct luat_vfs_filesystem vfs_fs_lfs2;
extern const struct luat_vfs_filesystem vfs_fs_lfs3;

extern int cmdline_argc;
extern char **cmdline_argv;

extern char *luadb_ptr;

// 从命令行参数构建luadb

void *build_luadb_from_cmd(void);

static void lvgl_fs_init(void);

static void pc_lfs2_mount(void);
static void pc_lfs3_mount(void);

int luat_fs_init(void)
{
	// vfs进行必要的初始化
	luat_vfs_init(NULL);
	// 注册vfs for posix 实现
	luat_vfs_reg(&vfs_fs_posix);
	luat_vfs_reg(&vfs_fs_luadb);
	luat_vfs_reg(&vfs_fs_ram);
	luat_vfs_reg(&vfs_fs_lfs2);
	luat_vfs_reg(&vfs_fs_lfs3);

	luat_fs_conf_t conf = {
		.busname = "",
		.type = "posix",
		.filesystem = "posix",
		.mount_point = "",
	};
	luat_fs_mount(&conf);

	// 挂载虚拟的/ram
	luat_fs_conf_t conf_ram = {
		.busname = "",
		.type = "ram",
		.filesystem = "ram",
		.mount_point = "/ram/",
	};
	luat_fs_mount(&conf_ram);

	// 挂载虚拟的/luadb
	void *ptr = luadb_ptr;
	if (ptr != NULL)
	{
		luat_fs_conf_t conf2 = {
			.busname = ptr,
			.type = "luadb",
			.filesystem = "luadb",
			.mount_point = "/luadb/",
		};
		luat_fs_mount(&conf2);
	}

	// 挂载/lfs2作为测试lfs文件系统的目录
	pc_lfs2_mount();

	// 挂载/lfs3作为测试lfsv3文件系统的目录
	pc_lfs3_mount();

#ifdef LUAT_USE_LVGL
	lvgl_fs_init();
#endif
	return 0;
}


#ifdef LUAT_USE_LVGL
#undef LUAT_LOG_TAG
#include "luat_lvgl.h"
static void lvgl_fs_init(void) {
	luat_lv_fs_init();
    #ifdef LUAT_USE_LVGL_BMP
	lv_bmp_init();
    #endif
    #ifdef LUAT_USE_LVGL_PNG
	lv_png_init();
    #endif
    #ifdef LUAT_USE_LVGL_JPG
	lv_split_jpeg_init();
    #endif
}
#endif


#include "lfs.h"
#define LUAT_LFS_MEM_SIZE (512 * 1024)
#define LUAT_LFS_MEM_BLOCK_SIZE ( 4 * 1024)
#define LUAT_LFS_MEM_BLOCK_COUNT (LUAT_LFS_MEM_SIZE / LUAT_LFS_MEM_BLOCK_SIZE)
static char lfs_mem_buff[LUAT_LFS_MEM_SIZE];
static int mem_read(const struct lfs_config *c, lfs_block_t block,
            lfs_off_t off, void *buffer, lfs_size_t size) {
	(void)c;
	// LLOGD("lfs内存读取 %d %d", block * LUAT_LFS_MEM_BLOCK_SIZE + off, size);
	memcpy(buffer, lfs_mem_buff + (block * LUAT_LFS_MEM_BLOCK_SIZE + off), size);
	return 0;
}
static int mem_prog(const struct lfs_config *c, lfs_block_t block,
            lfs_off_t off, const void *buffer, lfs_size_t size) {	
	(void)c;
	// LLOGD("lfs内存写入 %d %d", block * LUAT_LFS_MEM_BLOCK_SIZE + off, size);
	memcpy(lfs_mem_buff + (block * LUAT_LFS_MEM_BLOCK_SIZE + off), buffer, size);
	return 0;
}
static int mem_erase(const struct lfs_config *c, lfs_block_t block) {
	(void)c;
	// LLOGD("lfs内存块清除 %d", block * LUAT_LFS_MEM_BLOCK_SIZE);
	memset(lfs_mem_buff + (block * LUAT_LFS_MEM_BLOCK_SIZE), 0xFF, LUAT_LFS_MEM_BLOCK_SIZE);
	return 0;
}
static int mem_sync(const struct lfs_config *c) {
	(void)c;
	return 0;
}

#define LFS_BLOCK_DEVICE_READ_SIZE (256)
#define LFS_BLOCK_DEVICE_PROG_SIZE (256)
#define LFS_BLOCK_DEVICE_CACHE_SIZE (256)
#define LFS_BLOCK_DEVICE_ERASE_SIZE (4096) // one sector 4KB
#define LFS_BLOCK_DEVICE_TOTOAL_SIZE (LUAT_LFS_MEM_SIZE)
#define LFS_BLOCK_DEVICE_LOOK_AHEAD (16)
static char lfs_read_buf[256];
static char lfs_prog_buf[256];
static char lfs_lookahead_buf[LFS_BLOCK_DEVICE_LOOK_AHEAD];

static lfs_t lfs_mem;
const struct lfs_config cfg = {
	.read = mem_read,
	.prog = mem_prog,
	.erase = mem_erase,
	.sync = mem_sync,
    // block device configuration
    .read_size = LFS_BLOCK_DEVICE_READ_SIZE,
    .prog_size = LFS_BLOCK_DEVICE_PROG_SIZE,
    .block_size = LFS_BLOCK_DEVICE_ERASE_SIZE,
    .block_count = LUAT_LFS_MEM_BLOCK_COUNT,
    .block_cycles = 200,
    .cache_size = LFS_BLOCK_DEVICE_CACHE_SIZE,
    .lookahead_size = LFS_BLOCK_DEVICE_LOOK_AHEAD,

    .read_buffer = lfs_read_buf,
    .prog_buffer = lfs_prog_buf,
    .lookahead_buffer = lfs_lookahead_buf,
    .name_max = 63,
    .file_max = 0,
    .attr_max = 0
};
static void pc_lfs2_mount(void) {
	// LLOGD("执行/lfs2挂载");
	int ret = lfs_mount(&lfs_mem, &cfg);
	if (ret) {
		// LLOGD("格式化");
		lfs_format(&lfs_mem, &cfg);
		ret = lfs_mount(&lfs_mem, &cfg);
		if (ret) {
			LLOGE("挂载/lfs2/失败!!! %d", ret);
			return;
		}
	}
	luat_fs_conf_t conf = {
		.busname = (char*)&lfs_mem,
		.type = "lfs2",
		.filesystem = "lfs2",
		.mount_point = "/lfs2/",
	};
	luat_fs_mount(&conf);
	// LLOGD("挂载/lfs2/ 成功");
}

#include "lfs3.h"
#define LUAT_LFS3_MEM_SIZE       (512 * 1024)
#define LUAT_LFS3_MEM_BLOCK_SIZE (4 * 1024)
#define LUAT_LFS3_MEM_BLOCK_COUNT (LUAT_LFS3_MEM_SIZE / LUAT_LFS3_MEM_BLOCK_SIZE)
#define LFS3_BLOCK_DEVICE_READ_SIZE  (256)
#define LFS3_BLOCK_DEVICE_PROG_SIZE  (256)
#define LFS3_BLOCK_DEVICE_CACHE_SIZE (256)
#define LFS3_BLOCK_DEVICE_LOOK_AHEAD (16)

static char lfs3_mem_buff[LUAT_LFS3_MEM_SIZE];
static int lfs3_mem_read(const struct lfs3_cfg *c, lfs3_block_t block,
		lfs3_off_t off, void *buffer, lfs3_size_t size) {
	(void)c;
	memcpy(buffer, lfs3_mem_buff + (block * LUAT_LFS3_MEM_BLOCK_SIZE + off), size);
	return LFS3_ERR_OK;
}
static int lfs3_mem_prog(const struct lfs3_cfg *c, lfs3_block_t block,
		lfs3_off_t off, const void *buffer, lfs3_size_t size) {
	(void)c;
	memcpy(lfs3_mem_buff + (block * LUAT_LFS3_MEM_BLOCK_SIZE + off), buffer, size);
	return LFS3_ERR_OK;
}
static int lfs3_mem_erase(const struct lfs3_cfg *c, lfs3_block_t block) {
	(void)c;
	memset(lfs3_mem_buff + (block * LUAT_LFS3_MEM_BLOCK_SIZE), 0xFF, LUAT_LFS3_MEM_BLOCK_SIZE);
	return LFS3_ERR_OK;
}
static int lfs3_mem_sync(const struct lfs3_cfg *c) {
	(void)c;
	return LFS3_ERR_OK;
}

static char lfs3_rcache_buf[LFS3_BLOCK_DEVICE_CACHE_SIZE];
static char lfs3_pcache_buf[LFS3_BLOCK_DEVICE_CACHE_SIZE];
static char lfs3_lookahead_buf[LFS3_BLOCK_DEVICE_LOOK_AHEAD];

static lfs3_t lfs3_mem;
static const struct lfs3_cfg lfs3_cfg = {
	.read    = lfs3_mem_read,
	.prog    = lfs3_mem_prog,
	.erase   = lfs3_mem_erase,
	.sync    = lfs3_mem_sync,
	.read_size   = LFS3_BLOCK_DEVICE_READ_SIZE,
	.prog_size   = LFS3_BLOCK_DEVICE_PROG_SIZE,
	.block_size  = LUAT_LFS3_MEM_BLOCK_SIZE,
	.block_count = LUAT_LFS3_MEM_BLOCK_COUNT,
	.block_recycles = 200,
	.rcache_size    = LFS3_BLOCK_DEVICE_CACHE_SIZE,
	.pcache_size    = LFS3_BLOCK_DEVICE_CACHE_SIZE,
	.fcache_size    = LFS3_BLOCK_DEVICE_CACHE_SIZE,
	.lookahead_size = LFS3_BLOCK_DEVICE_LOOK_AHEAD,
	.rcache_buffer    = lfs3_rcache_buf,
	.pcache_buffer    = lfs3_pcache_buf,
	.lookahead_buffer = lfs3_lookahead_buf,
	.name_limit = 63,
	.file_limit = 0,
};
static void pc_lfs3_mount(void) {
	int ret = lfs3_mount(&lfs3_mem, 0, &lfs3_cfg);
	if (ret) {
		lfs3_format(&lfs3_mem, 0, &lfs3_cfg);
		ret = lfs3_mount(&lfs3_mem, 0, &lfs3_cfg);
		if (ret) {
			LLOGE("挂载/lfs3/失败!!! %d", ret);
			return;
		}
	}
	luat_fs_conf_t conf = {
		.busname = (char*)&lfs3_mem,
		.type = "lfs3",
		.filesystem = "lfs3",
		.mount_point = "/lfs3/",
	};
	luat_fs_mount(&conf);
}
