
#include "luat_base.h"
#include "luat_fs.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "fatfs"
#include "luat_log.h"

#ifdef LUAT_USE_FS_VFS

#include "ff.h"
#include "diskio.h"

FILE* luat_vfs_fatfs_fopen(void* userdata, const char *filename, const char *mode) {
    LLOGD("f_open %s %s", filename, mode);
    //FATFS *fs = (FATFS*)userdata;
    FIL* fp = luat_heap_malloc(sizeof(FIL));
    int flag = 0;
    for (size_t i = 0; i < strlen(mode); i++)
    {
        char m = *(mode + i);
        switch (m)
        {
        case 'r':
            flag |= FA_READ;
            break;
        case 'w':
            flag |= FA_WRITE | FA_CREATE_ALWAYS;
            break;
        case 'a':
            flag |= FA_OPEN_APPEND | FA_WRITE;
            break;
        case '+':
            flag |= FA_OPEN_APPEND;
            break;
        
        default:
            break;
        }
    }
    FRESULT ret = f_open(fp, filename, flag);
    if (ret != FR_OK) {
        LLOGD("f_open %s %d", filename, ret);
        luat_heap_free(fp);
        return 0; 
    }
    return (FILE*)fp;
}

int luat_vfs_fatfs_getc(void* userdata, FILE* stream) {
    //FATFS *fs = (FATFS*)userdata;
    FIL* fp = (FIL*)stream;
    char buff = 0;
    UINT result = 0;
    FRESULT ret = f_read(fp, (void*)&buff, 1, &result);
    if (ret == FR_OK && result == 1) {
        return buff;
    }
    return -1;
}

int luat_vfs_fatfs_fseek(void* userdata, FILE* stream, long int offset, int origin) {
    //FATFS *fs = (FATFS*)userdata;
    FIL* fp = (FIL*)stream;
    int npos = f_tell(fp);
    if (origin == SEEK_SET) {
        npos = offset;
    } else if (origin == SEEK_CUR) {
        npos += offset;
    } else if (origin == SEEK_END) {
        npos = f_size(fp);
    }
    FRESULT ret = f_lseek(fp, npos);
    if (ret == FR_OK) {
        return 0;
    }
    return -1;
}

int luat_vfs_fatfs_ftell(void* userdata, FILE* stream) {
    //FATFS *fs = (FATFS*)userdata;
    FIL* fp = (FIL*)stream;
    return f_tell(fp);
}

int luat_vfs_fatfs_fclose(void* userdata, FILE* stream) {
    //FATFS *fs = (FATFS*)userdata;
    FIL* fp = (FIL*)stream;
    if (fp != NULL) {
        f_close(fp);
        luat_heap_free(fp);
    }
    return 0;
}
int luat_vfs_fatfs_feof(void* userdata, FILE* stream) {
    //FATFS *fs = (FATFS*)userdata;
    FIL* fp = (FIL*)stream;
    return f_eof(fp);
}
int luat_vfs_fatfs_ferror(void* userdata, FILE *stream) {
    //FATFS *fs = (FATFS*)userdata;
    FIL* fp = (FIL*)stream;
    return f_error(fp);
}
size_t luat_vfs_fatfs_fread(void* userdata, void *ptr, size_t size, size_t nmemb, FILE *stream) {
    //FATFS *fs = (FATFS*)userdata;
    FIL* fp = (FIL*)stream;
    UINT result = 0;
    FRESULT ret = f_read(fp, ptr, size*nmemb, &result);
    if (ret == FR_OK) {
        return result;
    }
    return 0;
}
size_t luat_vfs_fatfs_fwrite(void* userdata, const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    //FATFS *fs = (FATFS*)userdata;
    FIL* fp = (FIL*)stream;
    UINT result = 0;
    FRESULT ret = f_write(fp, ptr, size*nmemb, &result);
    if (ret == FR_OK) {
        return result;
    }
    return 0;
}
int luat_vfs_fatfs_remove(void* userdata, const char *filename) {
    return f_unlink(filename);
}
int luat_vfs_fatfs_rename(void* userdata, const char *old_filename, const char *new_filename) {
    return f_rename(old_filename + (old_filename[0] == '/' ? 1 : 0), new_filename + (new_filename[0] == '/' ? 1 : 0));
}

int luat_vfs_fatfs_fexist(void* userdata, const char *filename) {
    FILINFO fno = {0};
    FRESULT ret = f_stat(filename, &fno);
    if (ret == FR_OK) {
        return 1;
    }
    return 0;
}

size_t luat_vfs_fatfs_fsize(void* userdata, const char *filename) {
    FILINFO fno = {0};
    FRESULT ret = f_stat(filename, &fno);
    if (ret == FR_OK) {
        return fno.fsize;
    }
    return 0;
}

int luat_vfs_fatfs_mkfs(void* userdata, luat_fs_conf_t *conf) {
    LLOGE("not support yet : mkfs");
    return -1;
}
int luat_vfs_fatfs_mount(void** userdata, luat_fs_conf_t *conf) {
    *userdata = (void*)conf->busname;
    return 0;
}
int luat_vfs_fatfs_umount(void* userdata, luat_fs_conf_t *conf) {
    //LLOGE("not support yet : umount");
    return 0;
}

int luat_vfs_fatfs_mkdir(void* userdata, char const* _DirName) {
    LLOGE("not support yet : mkdir");
    return -1;
}
int luat_vfs_fatfs_rmdir(void* userdata, char const* _DirName) {
    LLOGE("not support yet : rmdir");
    return -1;
}

int luat_vfs_fatfs_lsdir(void* userdata, char const* _DirName) {
    LLOGE("not support yet : lsdir");
    return 0;
}

int luat_vfs_fatfs_info(void* userdata, const char* path, luat_fs_info_t *conf) {
    // DWORD fre_clust = 0;
    // DWORD fre_sect = 0
    // DWORD tot_sect = 0;
    FATFS *fs = (FATFS*)userdata;

    // tot_sect = (fs->n_fatent - 2) * fs->csize;
    // fre_sect = (fs->free_clst) * fs->csize;

    memcpy(conf->filesystem, "fatfs", strlen("fatfs")+1);
    conf->type = 0;
    conf->total_block = (fs->n_fatent - 2);
    conf->block_used = fs->free_clst;
    conf->block_size = fs->csize;
    return 0;
}

#define T(name) .name = luat_vfs_fatfs_##name
const struct luat_vfs_filesystem vfs_fs_fatfs = {
    .name = "fatfs",
    .opts = {
        T(mkfs),
        T(mount),
        T(umount),
        T(mkdir),
        T(rmdir),
        T(lsdir),
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
