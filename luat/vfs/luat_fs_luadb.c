
#include "luat_base.h"
#include "luat_luadb.h"
#include "luat_malloc.h"
#include "luat_fs.h"

#define LUAT_LOG_TAG "luadb"
#include "luat_log.h"

#undef LLOGD
#define LLOGD(...) 

extern const uint32_t luat_inline_sys_size;
extern const char luat_inline_sys[];

//---
static uint8_t readU8(const char* ptr, int *index) {
    int val = ptr[*index];
    *index = (*index) + 1;
    return val & 0xFF;
}

static uint16_t readU16(const char* ptr, int *index) {
    return readU8(ptr,index) + (readU8(ptr,index) << 8);
}

static uint32_t readU32(const char* ptr, int *index) {
    return readU16(ptr,index) + (readU16(ptr,index) << 16);
}
//---


int luat_luadb_umount(luadb_fs_t *fs) {
    if (fs)
        luat_heap_free(fs);
    return 0;
}

int luat_luadb_remount(luadb_fs_t *fs, unsigned flags) {
    memset(fs->fds, 0, sizeof(luadb_fd_t)*LUAT_LUADB_MAX_OPENFILE);
    return 0;
}

int luat_luadb_open(luadb_fs_t *fs, const char *path, int flags, int /*mode_t*/ mode) {
    LLOGD("open luadb path = %s flags=%d", path, flags);
    // if (flags & 0x3) { // xie 
    //     return -1;
    // }
    for (size_t i = 0; i < fs->filecount; i++)
    {
        if (!strcmp(path, fs->files[i].name)) {
            for (size_t j = 1; j < LUAT_LUADB_MAX_OPENFILE; j++)
            {
                if (fs->fds[j].file == NULL) {
                    fs->fds[j].fd_pos = 0;
                    fs->fds[j].file = &(fs->files[i]);
                    LLOGD("open luadb path = %s fd=%d", path, j);
                    return j;
                }
            }
            
        }
    }
    return 0;
}


int luat_luadb_close(luadb_fs_t *fs, int fd) {
    if (fd < 0 || fd >= LUAT_LUADB_MAX_OPENFILE)
        return -1;
    if (fs->fds[fd].file != NULL) {
        fs->fds[fd].file = NULL;
        fs->fds[fd].fd_pos = 0;
        return 0;
    }
    return -1;
}

size_t luat_luadb_read(luadb_fs_t *fs, int fd, void *dst, size_t size) {
    if (fd < 0 || fd >= LUAT_LUADB_MAX_OPENFILE || fs->fds[fd].file == NULL)
        return 0;
    luadb_fd_t *fdt = &fs->fds[fd];
    int re = size;
    if (fdt->fd_pos + size > fdt->file->size) {
        re = fdt->file->size - fdt->fd_pos;
    }
    if (re > 0) {
        memcpy(dst, fdt->file->ptr + fdt->fd_pos, re);
        fdt->fd_pos += re;
    }
    //LLOGD("luadb read name %s offset %d size %d ret %d", fdt->file->name, fdt->fd_pos, size, re);
    return re;
}

long luat_luadb_lseek(luadb_fs_t *fs, int fd, long /*off_t*/ offset, int mode) {
    if (fd < 0 || fd >= LUAT_LUADB_MAX_OPENFILE || fs->fds[fd].file == NULL)
        return -1;
    if (mode == SEEK_END) {
        fs->fds[fd].fd_pos = fs->fds[fd].file->size;
    }
    else if (mode == SEEK_CUR) {
        fs->fds[fd].fd_pos += offset;
    }
    else {
        fs->fds[fd].fd_pos = offset;
    }
    return fs->fds[fd].fd_pos;
}

// int luat_luadb_fstat(void *fs, int fd, struct stat *st) {
//     luadb_fs_t *_fs = (luadb_fs_t*)fs;
//     if (fd < 0 || fd >= LUADB2_MAX_OPENFILE || _fs->fds[fd].file == NULL)
//         return -1;
//     st->st_size = _fs->fds[fd].file->size;
//     return 0;
// }

luadb_file_t * luat_luadb_stat(luadb_fs_t *fs, const char *path) {
    for (size_t i = 0; i < fs->filecount; i++)
    {
        if (!strcmp(path, fs->files[i].name)) {
            return &fs->files[i];
        }
    }
    return NULL;
}

luadb_fs_t* luat_luadb_mount(const char* _ptr) {
    int index = 0;
    int headok = 0;
    int dbver = 0;
    int headsize = 0;
    int filecount = 0;

    const char * ptr = (const char *)_ptr;

    //LLOGD("LuaDB ptr = %p", ptr);
    uint16_t magic1 = 0;
    uint16_t magic2 = 0;

    for (size_t i = 0; i < 128; i++)
    {
        int type = readU8(ptr, &index);
        int len = readU8(ptr, &index);
        //LLOGD("PTR: %d %d %d", type, len, index);
        switch (type) {
            case 1: {// Magic, 肯定是4个字节
                if (len != 4) {
                    LLOGD("Magic len != 4");
                    goto _after_head;
                }
                magic1 = readU16(ptr, &index);
                magic2 = readU16(ptr, &index);
                if (magic1 != magic2 || magic1 != 0xA55A) {
                    LLOGD("Magic not match 0x%04X%04X", magic1, magic2);
                    goto _after_head;
                }
                break;
            }
            case 2: {
                if (len != 2) {
                    LLOGD("Version len != 2");
                    goto _after_head;
                }
                dbver = readU16(ptr, &index);
                LLOGD("LuaDB version = %d", dbver);
                break;
            }
            case 3: {
                if (len != 4) {
                    LLOGD("Header full len != 4");
                    goto _after_head;
                }
                headsize = readU32(ptr, &index);
                break;
            }
            case 4 : {
                if (len != 2) {
                    LLOGD("Lua File Count len != 4");
                    goto _after_head;
                }
                filecount = readU16(ptr, &index);
                LLOGD("LuaDB file count %d", filecount);
                break;
            }
            case 0xFE : {
                if (len != 2) {
                    LLOGD("CRC len != 4");
                    goto _after_head;
                }
                index += len;
                headok = 1;
                goto _after_head;
            }
            default: {
                index += len;
                LLOGD("skip unkown type %d", type);
                break;
            }
        }
    }

_after_head:

    if (headok == 0) {
        LLOGW("Bad LuaDB");
        return NULL;
    }
    if (dbver == 0) {
        LLOGW("miss DB version");
        return NULL;
    }
    if (headsize == 0) {
        LLOGW("miss DB headsize");
        return NULL;
    }
    if (filecount == 0) {
        LLOGW("miss DB filecount");
        return NULL;
    }
    if (filecount > 256) {
        LLOGW("too many file in LuaDB");
        return NULL;
    }

    LLOGD("LuaDB head seem ok");

    // 由于luadb_fs_t带了一个luadb_file_t元素的,所以多出一个luadb_file_t, 方便存放sys.luac
    size_t msize = sizeof(luadb_fs_t) + filecount*sizeof(luadb_file_t);
    LLOGD("malloc fo luadb fs size=%d", msize);
    luadb_fs_t *fs = (luadb_fs_t*)luat_heap_malloc(msize);
    if (fs == NULL) {
        LLOGD("malloc for luadb fail!!!");
        return NULL;
    }
    memset(fs, 0, msize);
    LLOGD("LuaDB check files ....");

    fs->version = dbver;
    fs->filecount = filecount;
    //fs->ptrpos = initpos;

    int fail = 0;
    uint8_t type = 0;
    uint32_t len = 0;
    int hasSys = 0;
    // 读取每个文件的头部
    for (size_t i = 0; i < filecount; i++)
    {
        
        LLOGD("LuaDB check files .... %d", i+1);
        
        type = ptr[index++];
        len = ptr[index++];
        if (type != 1 || len != 4) {
            LLOGD("bad file data 1 : %d %d %d", type, len, index);
            fail = 1;
            break;
        }
        // skip magic
        index += 4;

        // 2. 然后是名字
        type = ptr[index++];
        len = ptr[index++];
        if (type != 2) {
            LLOGD("bad file data 2 : %d %d %d", type, len, index);
            fail = 1;
            break;
        }
        // 拷贝文件名
        LLOGD("LuaDB file name len = %d", len);

        memcpy(fs->files[i].name, &(ptr[index]), len);

        fs->files[i].name[len] = 0x00;

        index += len;

        LLOGD("LuaDB file name %s", fs->files[i].name);

        // 3. 文件大小
        type = ptr[index++];
        len = ptr[index++];
        if (type != 3 || len != 4) {
            LLOGD("bad file data 3 : %d %d %d", type, len, index);
            fail = 1;
            break;
        }
        fs->files[i].size = readU32(ptr, &index);

        // 0xFE校验码
        type = ptr[index++];
        len = ptr[index++];
        if (type != 0xFE || len != 2) {
            LLOGD("bad file data 4 : %d %d %d", type, len, index);
            fail = 1;
            break;
        }
        // 校验码就跳过吧
        index += len;
        
        fs->files[i].ptr = (const char*)(index + ptr); // 绝对地址
        index += fs->files[i].size;

        if (hasSys == 0) {
            if (!strcmp("sys.lua", fs->files[i].name) || !strcmp("sys.luac", fs->files[i].name))
                hasSys = 1;
        }
        LLOGD("LuaDB: %s %d", fs->files[i].name, fs->files[i].size);
    }

    if (fail == 0 && hasSys == 0) {
        memcpy(fs->files[filecount].name, "sys.luac", strlen("sys.luac")+1);
        fs->files[filecount].size = luat_inline_sys_size;
        fs->files[filecount].ptr = luat_inline_sys;
        fs->filecount ++;
    }

    if (fail == 0) {
        LLOGD("LuaDB check files .... ok");
        return fs;
    }
    else {
        LLOGD("LuaDB check files .... fail");
        luat_heap_free(fs);
        return NULL;
    }
}

#ifdef LUAT_USE_FS_VFS

FILE* luat_vfs_luadb_fopen(void* userdata, const char *filename, const char *mode) {
    return (FILE*)luat_luadb_open((luadb_fs_t*)userdata, filename, 0, 0);
}


int luat_vfs_luadb_fseek(void* userdata, FILE* stream, long int offset, int origin) {
    int ret = luat_luadb_lseek((luadb_fs_t*)userdata, (int)stream, offset, origin);
    if (ret < 0)
        return -1;
    return 0;
}

int luat_vfs_luadb_ftell(void* userdata, FILE* stream) {
    return luat_luadb_lseek((luadb_fs_t*)userdata, (int)stream, 0, SEEK_CUR);
}

int luat_vfs_luadb_fclose(void* userdata, FILE* stream) {
    return luat_luadb_close((luadb_fs_t*)userdata, (int)stream);
}
int luat_vfs_luadb_feof(void* userdata, FILE* stream) {
    int cur = luat_luadb_lseek((luadb_fs_t*)userdata, (int)stream, 0, SEEK_CUR);
    int end = luat_luadb_lseek((luadb_fs_t*)userdata, (int)stream, 0, SEEK_END);
    luat_luadb_lseek((luadb_fs_t*)userdata, (int)stream, cur, SEEK_SET);
    return cur >= end ? 1 : 0;
}
int luat_vfs_luadb_ferror(void* userdata, FILE *stream) {
    return 0;
}
size_t luat_vfs_luadb_fread(void* userdata, void *ptr, size_t size, size_t nmemb, FILE *stream) {
    return luat_luadb_read((luadb_fs_t*)userdata, (int)stream, ptr, size * nmemb);
}

int luat_vfs_luadb_getc(void* userdata, FILE* stream) {
    char c = 0;
    size_t ret = luat_vfs_luadb_fread((luadb_fs_t*)userdata, &c, 1, 1, stream);
    if (ret > 0) {
        return (int)c;
    }
    return -1;
}
size_t luat_vfs_luadb_fwrite(void* userdata, const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    return 0;
}
int luat_vfs_luadb_remove(void* userdata, const char *filename) {
    return -1;
}
int luat_vfs_luadb_rename(void* userdata, const char *old_filename, const char *new_filename) {
    return -1;
}
int luat_vfs_luadb_fexist(void* userdata, const char *filename) {
    FILE* fd = luat_vfs_luadb_fopen(userdata, filename, "rb");
    if (fd) {
        luat_vfs_luadb_fclose(userdata, fd);
        return 1;
    }
    return 0;
}

size_t luat_vfs_luadb_fsize(void* userdata, const char *filename) {
    FILE *fd;
    size_t size = 0;
    fd = luat_vfs_luadb_fopen(userdata, filename, "rb");
    if (fd) {
        luat_vfs_luadb_fseek(userdata, fd, 0, SEEK_END);
        size = luat_vfs_luadb_ftell(userdata, fd); 
        luat_vfs_luadb_fclose(userdata, fd);
    }
    return size;
}

int luat_vfs_luadb_mkfs(void* userdata, luat_fs_conf_t *conf) {
    //LLOGE("not support yet : mkfs");
    return -1;
}
int luat_vfs_luadb_mount(void** userdata, luat_fs_conf_t *conf) {
    luadb_fs_t* fs = luat_luadb_mount((const char*)conf->busname);
    if (fs == NULL)
        return  -1;
    *userdata = fs;
    return 0;
}
int luat_vfs_luadb_umount(void* userdata, luat_fs_conf_t *conf) {
    //LLOGE("not support yet : umount");
    return 0;
}

int luat_vfs_luadb_mkdir(void* userdata, char const* _DirName) {
    //LLOGE("not support yet : mkdir");
    return -1;
}
int luat_vfs_luadb_rmdir(void* userdata, char const* _DirName) {
    //LLOGE("not support yet : rmdir");
    return -1;
}
int luat_vfs_luadb_info(void* userdata, const char* path, luat_fs_info_t *conf) {
    memcpy(conf->filesystem, "luadb", strlen("luadb")+1);
    conf->type = 0;
    conf->total_block = 0;
    conf->block_used = 0;
    conf->block_size = 512;
    return 0;
}

const char* luat_vfs_luadb_mmap(void* userdata, int fd) {
    luadb_fs_t* fs = (luadb_fs_t*)userdata;
    if (fd < 0 || fd >= LUAT_LUADB_MAX_OPENFILE || fs->fds[fd].file == NULL)
        return 0;
    luadb_fd_t *fdt = &fs->fds[fd];
    if (fdt != NULL) {
        return fdt->file->ptr;
    }
    return NULL;
}

#define T(name) .name = luat_vfs_luadb_##name
const struct luat_vfs_filesystem vfs_fs_luadb = {
    .name = "luadb",
    .opts = {
        T(mkfs),
        T(mount),
        T(umount),
        T(mkdir),
        T(rmdir),
        T(remove),
        T(rename),
        T(fsize),
        T(fexist),
        T(info)
    },
    .fopts = {
        T(fopen),
        T(getc),
        T(fseek),
        T(ftell),
        T(fclose),
        T(feof),
        T(ferror),
        T(fread),
        T(fwrite)
    }
};
#endif
