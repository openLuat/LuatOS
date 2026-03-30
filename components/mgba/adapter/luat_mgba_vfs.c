/**
 * @file luat_mgba_vfs.c
 * @brief LuatOS mGBA VFS 桥接实现
 * 
 * 将 LuatOS 的虚拟文件系统桥接到 mGBA 的 VFS
 * 
 * 重要: 此实现提供完整的VFile函数指针，使mGBA核心能够自动管理存档文件
 */

#include "luat_conf_bsp.h"

#ifdef LUAT_USE_MGBA

#include "luat_mgba.h"
#include "luat_fs.h"
#include "luat_mem.h"
#include "luat_log.h"

#define LUAT_LOG_TAG "mgba.vfs"

#include <mgba-util/vfs.h>
#include <mgba-util/memory.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

/* ========== LuatOS VFile 包装器结构 ========== */

typedef struct {
	struct VFile d;
	FILE* file;
	bool writable;
} VFileLuatFS;

/* ========== 前向声明 ========== */

static bool _vlClose(struct VFile* vf);
static off_t _vlSeek(struct VFile* vf, off_t offset, int whence);
static ssize_t _vlRead(struct VFile* vf, void* buffer, size_t size);
static ssize_t _vlWrite(struct VFile* vf, const void* buffer, size_t size);
static void* _vlMap(struct VFile* vf, size_t size, int flags);
static void _vlUnmap(struct VFile* vf, void* memory, size_t size);
static void _vlTruncate(struct VFile* vf, size_t size);
static ssize_t _vlSize(struct VFile* vf);
static bool _vlSync(struct VFile* vf, void* buffer, size_t size);

/* ========== VFile 包装器实现 ========== */

/**
 * @brief 从LuatOS FILE*创建VFile
 * @param file LuatOS文件句柄
 * @return VFile指针，失败返回NULL
 */
static struct VFile* VFileFromLuatFILE(FILE* file) {
	if (!file) {
		return NULL;
	}

	VFileLuatFS* vl = (VFileLuatFS*)malloc(sizeof(VFileLuatFS));
	if (!vl) {
		luat_fs_fclose(file);
		return NULL;
	}

	vl->file = file;
	vl->writable = false;
	
	/* 设置所有VFile函数指针 */
	vl->d.close = _vlClose;
	vl->d.seek = _vlSeek;
	vl->d.read = _vlRead;
	vl->d.readline = VFileReadline;  /* 使用mGBA提供的通用实现 */
	vl->d.write = _vlWrite;
	vl->d.map = _vlMap;
	vl->d.unmap = _vlUnmap;
	vl->d.truncate = _vlTruncate;
	vl->d.size = _vlSize;
	vl->d.sync = _vlSync;

	return &vl->d;
}

static bool _vlClose(struct VFile* vf) {
	VFileLuatFS* vl = (VFileLuatFS*)vf;
	if (!vl) {
		return false;
	}
	
	int ret = luat_fs_fclose(vl->file);
	free(vl);
	return ret == 0;
}

static off_t _vlSeek(struct VFile* vf, off_t offset, int whence) {
	VFileLuatFS* vl = (VFileLuatFS*)vf;
	if (!vl || !vl->file) {
		return -1;
	}
	
	luat_fs_fseek(vl->file, offset, whence);
	return luat_fs_ftell(vl->file);
}

static ssize_t _vlRead(struct VFile* vf, void* buffer, size_t size) {
	VFileLuatFS* vl = (VFileLuatFS*)vf;
	if (!vl || !vl->file || !buffer) {
		return -1;
	}
	
	return luat_fs_fread(buffer, 1, size, vl->file);
}

static ssize_t _vlWrite(struct VFile* vf, const void* buffer, size_t size) {
	VFileLuatFS* vl = (VFileLuatFS*)vf;
	if (!vl || !vl->file || !buffer) {
		return -1;
	}
	
	size_t written = luat_fs_fwrite(buffer, 1, size, vl->file);
	if (written > 0) {
		vl->writable = true;
	}
	return written;
}

static void* _vlMap(struct VFile* vf, size_t size, int flags) {
	VFileLuatFS* vl = (VFileLuatFS*)vf;
	if (!vl || !vl->file) {
		return NULL;
	}
	
	if (flags & MAP_WRITE) {
		vl->writable = true;
	}
	
	/* 分配内存映射区域 */
	void* mem = anonymousMemoryMap(size);
	if (!mem) {
		LLOGE("_vlMap: failed to allocate memory");
		return NULL;
	}
	
	/* 保存当前位置，读取文件内容到内存 */
	long pos = luat_fs_ftell(vl->file);
	luat_fs_fseek(vl->file, 0, SEEK_SET);
	luat_fs_fread(mem, 1, size, vl->file);
	luat_fs_fseek(vl->file, pos, SEEK_SET);
	
	return mem;
}

static void _vlUnmap(struct VFile* vf, void* memory, size_t size) {
	VFileLuatFS* vl = (VFileLuatFS*)vf;
	if (!vl || !memory) {
		return;
	}
	
	/* 如果可写，将内存数据写回文件 */
	if (vl->writable) {
		long pos = luat_fs_ftell(vl->file);
		luat_fs_fseek(vl->file, 0, SEEK_SET);
		luat_fs_fwrite(memory, 1, size, vl->file);
		luat_fs_fseek(vl->file, pos, SEEK_SET);
		luat_fs_fflush(vl->file);
	}
	
	mappedMemoryFree(memory, size);
}

static void _vlTruncate(struct VFile* vf, size_t size) {
	VFileLuatFS* vl = (VFileLuatFS*)vf;
	if (!vl || !vl->file) {
		return;
	}
	
	long pos = luat_fs_ftell(vl->file);
	
	/* 获取当前文件大小 */
	luat_fs_fseek(vl->file, 0, SEEK_END);
	long currentSize = luat_fs_ftell(vl->file);
	
	if (currentSize < 0) {
		luat_fs_fseek(vl->file, pos, SEEK_SET);
		return;
	}
	
	/* 如果当前大小小于目标大小，填充零 */
	if ((size_t)currentSize < size) {
		static const char zeros[128] = {0};
		while ((size_t)currentSize < size) {
			size_t diff = size - currentSize;
			if (diff > sizeof(zeros)) {
				diff = sizeof(zeros);
			}
			luat_fs_fwrite(zeros, 1, diff, vl->file);
			currentSize += diff;
		}
	}
	
	luat_fs_fseek(vl->file, pos, SEEK_SET);
}

static ssize_t _vlSize(struct VFile* vf) {
	VFileLuatFS* vl = (VFileLuatFS*)vf;
	if (!vl || !vl->file) {
		return -1;
	}
	
	long pos = luat_fs_ftell(vl->file);
	luat_fs_fseek(vl->file, 0, SEEK_END);
	long size = luat_fs_ftell(vl->file);
	luat_fs_fseek(vl->file, pos, SEEK_SET);
	
	return size;
}

static bool _vlSync(struct VFile* vf, void* buffer, size_t size) {
	VFileLuatFS* vl = (VFileLuatFS*)vf;
	if (!vl || !vl->file) {
		return false;
	}
	
	/* 如果有缓冲区数据，先写入 */
	if (buffer && size > 0) {
		long pos = luat_fs_ftell(vl->file);
		luat_fs_fseek(vl->file, 0, SEEK_SET);
		size_t written = luat_fs_fwrite(buffer, 1, size, vl->file);
		luat_fs_fseek(vl->file, pos, SEEK_SET);
		if (written != size) {
			LLOGE("_vlSync: failed to write buffer");
			return false;
		}
	}
	
	/* 刷新文件缓冲区 */
	return luat_fs_fflush(vl->file) == 0;
}

/* ========== 路径转换辅助函数 ========== */

/**
 * @brief 转换路径，处理虚拟路径到本地路径
 * @param input_path 输入路径（可能是虚拟路径如 /luadb/game.gba）
 * @param output_path 输出路径缓冲区
 * @param size 输出缓冲区大小
 * @param for_write 是否为写操作
 */
static void _convert_path(const char* input_path, char* output_path, size_t size, int for_write) {
	if (!input_path || !output_path || size == 0) {
		return;
	}
	
	/* 对于写操作，需要转换 /luadb/ 等只读虚拟路径 */
	if (for_write && strncmp(input_path, "/luadb/", 7) == 0) {
		/* 跳过 /luadb/ 前缀，使用相对路径 */
		snprintf(output_path, size, "%s", input_path + 7);
	} else if (for_write && strncmp(input_path, "/", 1) == 0 && 
			   strncmp(input_path, "/lfs2/", 6) != 0 &&
			   strncmp(input_path, "/ram/", 5) != 0) {
		/* 其他虚拟路径（除了/lfs2/和/ram/）也跳过前导斜杠 */
		snprintf(output_path, size, "%s", input_path + 1);
	} else {
		/* 读操作或已经是可写路径，直接使用 */
		snprintf(output_path, size, "%s", input_path);
	}
}

/* ========== 公共API ========== */

/**
 * @brief 使用LuatOS VFS打开文件
 * @param path 文件路径
 * @param mode 打开模式 ("rb", "wb", "r+b"等)
 * @return VFile指针，失败返回NULL
 */
struct VFile* luat_mgba_vfs_open(const char* path, const char* mode) {
	if (!path || !mode) {
		return NULL;
	}
	
	/* 判断是否为写操作 */
	int for_write = (strchr(mode, 'w') != NULL) || (strchr(mode, '+') != NULL);
	
	/* 转换路径 */
	char converted_path[256];
	_convert_path(path, converted_path, sizeof(converted_path), for_write);
	
	FILE* file = luat_fs_fopen(converted_path, mode);
	if (!file) {
		LLOGD("luat_mgba_vfs_open: failed to open %s (mode: %s)", converted_path, mode);
		return NULL;
	}
	
	struct VFile* vf = VFileFromLuatFILE(file);
	if (!vf) {
		LLOGE("luat_mgba_vfs_open: failed to create VFile wrapper");
		luat_fs_fclose(file);
		return NULL;
	}
	
	LLOGD("luat_mgba_vfs_open: opened %s", converted_path);
	return vf;
}

/**
 * @brief 从LuatOS VFS创建VFile（只读模式）
 * @param path 文件路径
 * @return VFile指针
 */
struct VFile* VFileFromLuatFS(const char* path) {
	return luat_mgba_vfs_open(path, "rb");
}

#endif /* LUAT_USE_MGBA */
