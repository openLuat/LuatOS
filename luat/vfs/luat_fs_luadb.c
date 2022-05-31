
#include "luat_base.h"
#include "luat_luadb.h"
#include "luat_malloc.h"
#include "luat_fs.h"

#define LUAT_LOG_TAG "luadb"
#include "luat_log.h"

#undef LLOGD
#define LLOGD(...) 

extern const luadb_file_t luat_inline2_libs[];

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

static luadb_file_t* find_by_name(luadb_fs_t *fs, const char *path) {
    for (size_t i = 0; i < fs->filecount; i++)
    {
        if (!strcmp(path, fs->files[i].name)) {
            return &(fs->files[i]);
        }
    }
    luadb_file_t *ext = fs->inlines;
    while (ext->ptr != NULL)
    {
        if (!strcmp(path, ext->name)) {
            return ext;
        }
        ext += 1;
    }
    return NULL;
}

int luat_luadb_open(luadb_fs_t *fs, const char *path, int flags, int /*mode_t*/ mode) {
    LLOGD("open luadb path = %s flags=%d", path, flags);
    int fd = -1;
    for (size_t j = 1; j < LUAT_LUADB_MAX_OPENFILE; j++)
    {
        if (fs->fds[j].file == NULL) {
            fd = j;
            break;
        }
    }
    if (fd == -1) {
        LLOGD("too many open files for luadb");
        return 0;
    }
    luadb_file_t* f = find_by_name(fs, path);
    if (f != NULL) {
        fs->fds[fd].fd_pos = 0;
        fs->fds[fd].file = f;
        LLOGD("open luadb path = %s fd=%d", path, j);
        return fd;
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

luadb_file_t * luat_luadb_stat(luadb_fs_t *fs, const char *path) {
    return find_by_name(fs, path);
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
    if (filecount > 1024) {
        LLOGW("too many file in LuaDB");
        return NULL;
    }

    LLOGD("LuaDB head seem ok");

    // 由于luadb_fs_t带了一个luadb_file_t元素的
    size_t msize = sizeof(luadb_fs_t) + (filecount - 1)*sizeof(luadb_file_t);
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
    // int hasSys = 0;
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

        LLOGD("LuaDB: %s %d", fs->files[i].name, fs->files[i].size);
    }

    if (fail == 0) {
        LLOGD("LuaDB check files .... ok");
        fs->inlines = (luadb_file_t *)luat_inline2_libs;
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

int luat_vfs_luadb_lsdir(void* userdata, char const* _DirName, luat_fs_dirent_t* ents, size_t offset, size_t len) {
    luadb_fs_t* fs = (luadb_fs_t*)userdata;
    if (fs->filecount > offset) {
        if (offset + len > fs->filecount)
            len = fs->filecount - offset;
        for (size_t i = 0; i < len; i++)
        {
            ents[i].d_type = 0;
            strcpy(ents[i].d_name, fs->files[i+offset].name);
        }
        return len;
    }
    return 0;
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
        .mkfs = NULL,
        T(mount),
        T(umount),
        .mkdir = NULL,
        .rmdir = NULL,
        .lsdir = NULL,
        .remove = NULL,
        .rename = NULL,
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
        .fwrite = NULL
    }
};
#endif

#include "luat_crypto.h"

int luat_luadb_checkfile(const char* path) {
    size_t binsize = luat_fs_fsize(path);
    if (binsize < 1024 || binsize > 1024*1024) {
        LLOGD("%s is too small/big %d", path, binsize);
        return -1;
    } 
    uint8_t* binbuff = NULL;
    FILE * fd = luat_fs_fopen(path, "rb");
    int res = -1;
    if (fd) {

        binbuff = (uint8_t*)luat_heap_malloc(binsize * sizeof(uint8_t));
        if (binbuff == NULL) {
            LLOGD("update.bin is TOO BIG, not OK");
            goto _close;
        }
        memset(binbuff, 0, binsize);

        luat_fs_fread(binbuff, sizeof(uint8_t), binsize, fd);
        //做一下校验
        if (binbuff[0] != 0x01 || binbuff[1] != 0x04 || binbuff[2]+(binbuff[3]<<8) != 0xA55A || binbuff[4]+(binbuff[5]<<8) != 0xA55A){
            LLOGI("Magic error");
            goto _close;
        }
        LLOGI("Magic OK");
        if (binbuff[6] != 0x02 || binbuff[7] != 0x02 || binbuff[8] != 0x02 || binbuff[9] != 0x00){
            LLOGI("Version error");
            goto _close;
        }
        uint16_t version = binbuff[8]+(binbuff[9]<<8);
        LLOGI("Version:%d",version);
        if (binbuff[10] != 0x03 || binbuff[11] != 0x04){
            LLOGI("Header error");
            goto _close;
        }
        uint32_t headsize = binbuff[12]+(binbuff[13]<<8)+(binbuff[14]<<16)+(binbuff[15]<<24);
        LLOGI("headers:%08x",headsize);
        if (binbuff[16] != 0x04 || binbuff[17] != 0x02){
            LLOGI("file count error");
            goto _close;
        }
        uint16_t filecount = binbuff[18]+(binbuff[19]<<8);
        LLOGI("file count:%d",filecount);
        if (binbuff[20] != 0xFE || binbuff[21] != 0x02){
            LLOGI("CRC16 error");
            goto _close;
        }
        uint16_t crc16 = binbuff[22]+(binbuff[23]<<8);
        int index = 24;
        uint8_t type = 0;
        uint32_t len = 0;
        for (size_t i = 0; i < (int)filecount; i++){
            LLOGD("LuaDB check files .... %d", i+1);
            type = binbuff[index++];
            len = binbuff[index++];
            if (type != 1 || len != 4) {
                LLOGD("bad file data 1 : %d %d %d", type, len, index);
                goto _close;
            }
            index += 4;
            // 2. 然后是名字
            type = binbuff[index++];
            len = binbuff[index++];
            if (type != 2) {
                LLOGD("bad file data 2 : %d %d %d", type, len, index);
                goto _close;
            }
            // 拷贝文件名
            LLOGD("LuaDB file name len = %d", len);
            char test[10];
            memcpy(test, &(binbuff[index]), len);
            test[len] = 0x00;
            index += len;
            LLOGD("LuaDB file name %s", test);
            if (strcmp(".airm2m_all_crc#.bin", test)==0){
                LLOGD(".airm2m_all_crc#.bin");
                // 3. 文件大小
                type = binbuff[index++];
                len = binbuff[index++];
                if (type != 3 || len != 4) {
                    LLOGD("bad file data 3 : %d %d %d", type, len, index);
                    goto _close;
                }
                uint32_t fssize = binbuff[index]+(binbuff[index+1]<<8)+(binbuff[index+2]<<16)+(binbuff[index+3]<<24);
                index+=4;
                // 0xFE校验码
                type = binbuff[index++];
                len = binbuff[index++];
                if (type != 0xFE || len != 2) {
                    LLOGD("bad file data 4 : %d %d %d", type, len, index);
                    goto _close;
                }
                index += len;
                uint8_t md5data[16];
                luat_crypto_md5_simple((const char*)binbuff, index, md5data);
                for (size_t i = 0; i < 16; i++){
                    if (md5data[i]!=binbuff[index++]){
                        LLOGD("md5data error");
                        goto _close;
                    }
                }
                res = 0;
                break;
            }
            // 3. 文件大小
            type = binbuff[index++];
            len = binbuff[index++];
            if (type != 3 || len != 4) {
                LLOGD("bad file data 3 : %d %d %d", type, len, index);
                goto _close;
            }
            uint32_t fssize = binbuff[index]+(binbuff[index+1]<<8)+(binbuff[index+2]<<16)+(binbuff[index+3]<<24);
            index+=4;
            // 0xFE校验码
            type = binbuff[index++];
            len = binbuff[index++];
            if (type != 0xFE || len != 2) {
                LLOGD("bad file data 4 : %d %d %d", type, len, index);
                goto _close;
            }
            index += len;
            index += fssize;
        }
_close:
        luat_heap_free(binbuff);
        luat_fs_fclose(fd);
    }
    return res;
}
