#include "luat_base.h"
#include "luat_fs.h"
#include "luat_malloc.h"

extern const struct luat_vfs_filesystem vfs_fs_posix;

int luat_fs_init(void) {
	#ifdef LUAT_USE_FS_VFS
	// vfs进行必要的初始化
	luat_vfs_init(NULL);
	// 注册vfs for posix 实现
	luat_vfs_reg(&vfs_fs_posix);

	luat_fs_conf_t conf = {
		.busname = "",
		.type = "posix",
		.filesystem = "posix",
		.mount_point = "", // window环境下, 需要支持任意路径的读取,不能强制要求必须是/
	};
	luat_fs_mount(&conf);
	#endif
	return 0;
}
