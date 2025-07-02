#include "luat_base.h"
#include "luat_fs.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "fs"
#include "luat_log.h"

#define BLOCK_SIZE 4096

typedef struct ram_file_block
{
    uint8_t data[BLOCK_SIZE];
    struct ram_file_block* next;
} ram_file_block_t;

typedef struct ram_file
{
    size_t size;     // 当前文件大小
    char name[32];   // 文件名称
    ram_file_block_t* head; // 链表头指针
} ram_file_t;

typedef struct luat_ram_fd
{
    int fid;
    uint32_t offset;
    uint8_t readonly;
} luat_raw_fd_t;

#define RAM_FILE_MAX (64)
static ram_file_t* files[RAM_FILE_MAX];


FILE* luat_vfs_ram_fopen(void* userdata, const char *filename, const char *mode) {
    (void)userdata;
    // LLOGD("ram fs open %s %s", filename, mode);
    if (filename == NULL || mode == NULL || strlen(filename) > 31)
        return NULL;
    // 读文件
    if (!strcmp("r", mode) || !strcmp("rb", mode)) {
        for (size_t i = 0; i < RAM_FILE_MAX; i++)
        {
            if (files[i] == NULL)
                continue;
            if (!strcmp(files[i]->name, filename)) {
                luat_raw_fd_t* fd = luat_heap_malloc(sizeof(luat_raw_fd_t));
                if (fd == NULL) {
                    LLOGE("out of memory when malloc luat_raw_fd_t");
                    return NULL;
                }
                fd->fid = i;
                fd->offset = 0;
                fd->readonly = 1;
                return (FILE*)fd;
            }
        }
        return NULL;
    }
    // 写文件
    else if (!strcmp("w", mode) || !strcmp("wb", mode) || !strcmp("w+", mode) || !strcmp("wb+", mode) || !strcmp("w+b", mode) || !strcmp("r+", mode) || !strcmp("rb+", mode) || !strcmp("r+b", mode)) {
        // 先看看是否存在, 如果存在就重用老的
        for (size_t i = 0; i < RAM_FILE_MAX; i++)
        {
            if (files[i] == NULL)
                continue;
            if (!strcmp(files[i]->name, filename)) {
                luat_raw_fd_t* fd = luat_heap_malloc(sizeof(luat_raw_fd_t));
                if (fd == NULL) {
                    LLOGE("out of memory when malloc luat_raw_fd_t");
                    return NULL;
                }
                fd->fid = i;
                fd->readonly = 0;
                fd->offset = 0;
                if (!strcmp("w+", mode) || !strcmp("wb+", mode) || !strcmp("w+b", mode)) {
                    // 截断模式
                    files[i]->size = 0;
                    ram_file_block_t* block = files[i]->head;
                    while (block) {
                        ram_file_block_t* next = block->next;
                        luat_heap_free(block);
                        block = next;
                    }
                    files[i]->head = NULL;
                }
                return (FILE*)fd;
            }
        }
        for (size_t i = 0; i < RAM_FILE_MAX; i++)
        {
            if (files[i] != NULL)
                continue;
            ram_file_t *file = luat_heap_malloc(sizeof(ram_file_t));
            if (file == NULL) {
                LLOGE("out of memory when malloc ram_file_t");
                return NULL;
            }
            memset(file, 0, sizeof(ram_file_t));
            strcpy(file->name, filename);
            files[i] = file;
            luat_raw_fd_t* fd = luat_heap_malloc(sizeof(luat_raw_fd_t));
            if (fd == NULL) {
                LLOGE("out of memory when malloc luat_raw_fd_t");
                return NULL;
            }
            fd->fid = i;
            fd->offset = 0;
            fd->readonly = 0;
            return (FILE*)fd;
        }
    }
    // 追加模式
    else if (!strcmp("a", mode) || !strcmp("ab", mode) || !strcmp("a+", mode) || !strcmp("ab+", mode) || !strcmp("a+b", mode) ) {
        // 先看看是否存在, 如果存在就重用老的
        for (size_t i = 0; i < RAM_FILE_MAX; i++)
        {
            if (files[i] == NULL)
                continue;
            if (!strcmp(files[i]->name, filename)) {
                luat_raw_fd_t* fd = luat_heap_malloc(sizeof(luat_raw_fd_t));
                if (fd == NULL) {
                    LLOGE("out of memory when malloc luat_raw_fd_t");
                    return NULL;
                }
                fd->fid = i;
                fd->offset = files[i]->size;
                fd->readonly = 0;
                return (FILE*)fd;
            }
        }
    }
    else {
        LLOGE("unkown open mode %s", mode);
        return NULL;
    }
    LLOGE("too many ram files >= %d", RAM_FILE_MAX);
    return NULL;
}

int luat_vfs_ram_getc(void* userdata, FILE* stream) {
    (void)userdata;
    //LLOGD("getc %p %p", userdata, stream);
    luat_raw_fd_t* fd = (luat_raw_fd_t*)stream;
    //LLOGD("getc %p %p %d %d", userdata, stream, fd->offset, fd->size);
    if (fd->fid < 0 || fd->fid >= RAM_FILE_MAX) {
        return -1;
    }
    if (files[fd->fid] == NULL) {
        return -1;
    }
    ram_file_block_t* block = files[fd->fid]->head;
    size_t offset = fd->offset;
    while (block) {
        if (offset < BLOCK_SIZE) {
            uint8_t c = block->data[offset];
            if (c == '\0') {
                return -1;
            }
            fd->offset++;
            return c;
        }
        offset -= BLOCK_SIZE;
        block = block->next;
    }
    return -1;
}

int luat_vfs_ram_fseek(void* userdata, FILE* stream, long int offset, int origin) {
    (void)userdata;
    luat_raw_fd_t* fd = (luat_raw_fd_t*)stream;
    // LLOGE("luat_vfs_ram_fseek seek %p %p %d %d", userdata, stream, offset, origin);
    if (origin == SEEK_CUR) {
        fd->offset += offset;
    }
    else if (origin == SEEK_SET) {
        fd->offset = offset;
    }
    else {
        fd->offset = files[fd->fid]->size - offset;
    }
    return 0;
}

int luat_vfs_ram_ftell(void* userdata, FILE* stream) {
    (void)userdata;
    luat_raw_fd_t* fd = (luat_raw_fd_t*)stream;
    // LLOGD("tell %p %p offset %d", userdata, stream, fd->offset);
    return fd->offset;
}

int luat_vfs_ram_fclose(void* userdata, FILE* stream) {
    (void)userdata;
    luat_raw_fd_t* fd = (luat_raw_fd_t*)stream;
    //LLOGD("fclose %p %p %d %d", userdata, stream, fd->size, fd->offset);
    luat_heap_free(fd);
    return 0;
}

int luat_vfs_ram_feof(void* userdata, FILE* stream) {
    (void)userdata;
    luat_raw_fd_t* fd = (luat_raw_fd_t*)stream;
    //LLOGD("feof %p %p %d %d", userdata, stream, fd->size, fd->offset);
    return fd->offset >= files[fd->fid]->size ? 1 : 0;
}

int luat_vfs_ram_ferror(void* userdata, FILE *stream) {
    (void)userdata;
    (void)stream;
    return 0;
}

size_t luat_vfs_ram_fread(void* userdata, void *ptr, size_t size, size_t nmemb, FILE *stream) {
    (void)userdata;
    luat_raw_fd_t* fd = (luat_raw_fd_t*)stream;
    size_t read_size = size * nmemb;
    if (fd->offset >= files[fd->fid]->size) {
        return 0;
    }
    if (fd->offset + read_size >= files[fd->fid]->size) {
        read_size = files[fd->fid]->size - fd->offset;
    }
    ram_file_block_t* block = files[fd->fid]->head;
    size_t offset = fd->offset;
    uint8_t* dst = (uint8_t*)ptr;
    size_t bytes_read = 0; // 用于记录实际读取的字节数
    while (block && read_size > 0) {
        size_t copy_size = BLOCK_SIZE - (offset % BLOCK_SIZE);
        if (copy_size > read_size) {
            copy_size = read_size;
        }
        memcpy(dst, block->data + (offset % BLOCK_SIZE), copy_size);
        dst += copy_size;
        read_size -= copy_size;
        offset += copy_size;
        bytes_read += copy_size; // 累加读取的字节数
        if (offset % BLOCK_SIZE == 0) {
            block = block->next;
        }
    }
    fd->offset += bytes_read; // 更新文件偏移量
    return bytes_read; // 返回实际读取的字节数
}

size_t luat_vfs_ram_fwrite(void* userdata, const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    (void)userdata;
    luat_raw_fd_t* fd = (luat_raw_fd_t*)stream;
    size_t write_size = size * nmemb;
    if (fd->readonly) {
        LLOGW("readonly fd %d!! path %s", fd->fid, files[fd->fid]->name);
        return 0;
    }
    ram_file_block_t* block = files[fd->fid]->head;
    size_t offset = fd->offset;
    const uint8_t* src = (const uint8_t*)ptr;
    while (write_size > 0) {
        if (block == NULL || offset % BLOCK_SIZE == 0) {
            if (block == NULL) {
                block = luat_heap_malloc(sizeof(ram_file_block_t));
                if (block == NULL) {
                    LLOGW("out of memory when malloc ram_file_block_t");
                    return 0;
                }
                memset(block, 0, sizeof(ram_file_block_t));
                block->next = NULL;
                if (files[fd->fid]->head == NULL) {
                    files[fd->fid]->head = block;
                } else {
                    ram_file_block_t* last = files[fd->fid]->head;
                    while (last->next) {
                        last = last->next;
                    }
                    last->next = block;
                }
            }
        }
        size_t copy_size = BLOCK_SIZE - (offset % BLOCK_SIZE);
        if (copy_size > write_size) {
            copy_size = write_size;
        }
        memcpy(block->data + (offset % BLOCK_SIZE), src, copy_size);
        src += copy_size;
        write_size -= copy_size;
        offset += copy_size;
        if (offset % BLOCK_SIZE == 0) {
            block = block->next;
        }
    }
    fd->offset += (size_t)(src - (const uint8_t*)ptr);
    files[fd->fid]->size = offset > files[fd->fid]->size ? offset : files[fd->fid]->size;
    // 打印一下写入的数据
    // LLOGD("write data %s", (char*)ptr);
    return (size_t)(src - (const uint8_t*)ptr);
}

int luat_vfs_ram_remove(void* userdata, const char *filename) {
    (void)userdata;
    for (size_t i = 0; i < RAM_FILE_MAX; i++)
    {
        if (files[i] == NULL)
            continue;
        if (!strcmp(filename, files[i]->name)) {
            ram_file_block_t* block = files[i]->head;
            while (block) {
                ram_file_block_t* next = block->next;
                luat_heap_free(block);
                block = next;
            }
            luat_heap_free(files[i]);
            files[i] = NULL;
            return 0;
        }
    }
    return 0;
}

int luat_vfs_ram_rename(void* userdata, const char *old_filename, const char *new_filename) {
    (void)userdata;
    if (old_filename == NULL || new_filename == NULL)
        return -1;
    if (strlen(old_filename) > 31 || strlen(new_filename) > 31)
        return -2;
    for (size_t i = 0; i < RAM_FILE_MAX; i++)
    {
        if (files[i] == NULL)
            continue;
        if (!strcmp(old_filename, files[i]->name)) {
            strcpy(files[i]->name, new_filename);
            return 0;
        }
    }
    return 0;
}

int luat_vfs_ram_fexist(void* userdata, const char *filename) {
    (void)userdata;
    for (size_t i = 0; i < RAM_FILE_MAX; i++)
    {
        if (files[i] == NULL)
            continue;
        if (!strcmp(filename, files[i]->name)) {
            return 1;
        }
    }
    return 0;
}

size_t luat_vfs_ram_fsize(void* userdata, const char *filename) {
    (void)userdata;
    for (size_t i = 0; i < RAM_FILE_MAX; i++)
    {
        if (files[i] == NULL)
            continue;
        if (!strcmp(filename, files[i]->name)) {
            return files[i]->size;
        }
    }
    return 0;
}

void* luat_vfs_ram_mmap(void* userdata, FILE *stream) {
    (void)userdata;
    luat_raw_fd_t *fd = (luat_raw_fd_t*)(stream);
    //LLOGD("fsize %p %p %d %d", userdata, fd);
    return files[fd->fid]->head->data;
}

int luat_vfs_ram_mkfs(void* userdata, luat_fs_conf_t *conf) {
    (void)userdata;
    (void)conf;
    return -1;
}

int luat_vfs_ram_mount(void** userdata, luat_fs_conf_t *conf) {
    (void)userdata;
    (void)conf;
    return 0;
}

int luat_vfs_ram_umount(void* userdata, luat_fs_conf_t *conf) {
    (void)userdata;
    (void)conf;
    return 0;
}

int luat_vfs_ram_mkdir(void* userdata, char const* _DirName) {
    (void)userdata;
    (void)_DirName;
    return -1;
}

int luat_vfs_ram_rmdir(void* userdata, char const* _DirName) {
    (void)userdata;
    (void)_DirName;
    return -1;
}

int luat_vfs_ram_lsdir(void* userdata, char const* _DirName, luat_fs_dirent_t* ents, size_t offset, size_t len) {
    (void)userdata;
    (void)_DirName;
    size_t count = 0;
    for (size_t i = 0; i < RAM_FILE_MAX; i++)
    {
        if (count >= len)
            break;
        if (files[i] == NULL)
            continue;
        if (offset > 0) {
            offset --;
            continue;
        }
        ents[count].d_type = 0;
        strcpy(ents[count].d_name, files[i]->name);
        count ++;
    }
    return count;
}

int luat_vfs_ram_info(void* userdata, const char* path, luat_fs_info_t *conf) {
    (void)userdata;
    (void)path;
    memcpy(conf->filesystem, "ram", strlen("ram")+1);
    size_t ftotal = 0;
    for (size_t i = 0; i < RAM_FILE_MAX; i++)
    {
        if (files[i] == NULL)
            continue;
        ftotal += files[i]->size;
    }
    size_t total; size_t used; size_t max_used;
    luat_meminfo_sys(&total, &used, &max_used);
    
    conf->type = 0;
    conf->total_block = 64;
    conf->block_used = (ftotal + BLOCK_SIZE) / BLOCK_SIZE;
    conf->block_size = BLOCK_SIZE;
    return 0;
}

int luat_vfs_ram_truncate(void* fsdata, char const* path, size_t nsize) {
    for (size_t i = 0; i < RAM_FILE_MAX; i++)
    {
        if (files[i] == NULL)
            continue;
        if (!strcmp(files[i]->name, path)) {
            ram_file_block_t* block = files[i]->head;
            size_t offset = 0;
            while (block) {
                if (offset + BLOCK_SIZE > nsize) {
                    memset(block->data + (nsize - offset), 0, BLOCK_SIZE - (nsize - offset));
                }
                offset += BLOCK_SIZE;
                block = block->next;
            }
            files[i]->size = nsize;
            return 0;
        }
    }
    return 0;
}

#define T(name) .name = luat_vfs_ram_##name
const struct luat_vfs_filesystem vfs_fs_ram = {
    .name = "ram",
    .opts = {
        .mkfs = NULL,
        T(mount),
        T(umount),
        .mkdir = NULL,
        .rmdir = NULL,
        T(lsdir),
        T(remove),
        T(rename),
        T(fsize),
        T(fexist),
        T(info),
        T(truncate)
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

