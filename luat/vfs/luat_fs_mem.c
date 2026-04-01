#include "luat_base.h"
#include "luat_fs.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "fs"
#include "luat_log.h"

#define BLOCK_SIZE 4096
#define MEMFS_MAX_FILE_NAME 63

#define RAM_NODE_TYPE_FILE 0
#define RAM_NODE_TYPE_DIR 1

#define RAM_NODE_MAX (64)

typedef struct ram_file_block
{
    uint8_t data[BLOCK_SIZE];
    struct ram_file_block* next;
} ram_file_block_t;

typedef struct ram_node
{
    uint8_t type;
    size_t size;
    char name[MEMFS_MAX_FILE_NAME + 1];
    ram_file_block_t* head;
} ram_node_t;

typedef struct luat_ram_fd
{
    int fid;
    uint32_t offset;
    uint8_t readonly;
} luat_raw_fd_t;

static ram_node_t* nodes[RAM_NODE_MAX];

size_t luat_vfs_ram_fread(void* userdata, void *ptr, size_t size, size_t nmemb, FILE *stream);

static int ram_normalize_path(const char* path, char* out) {
    size_t len = 0;
    size_t segment_len = 0;

    if (path == NULL || out == NULL) {
        return -1;
    }

    while (*path == '/' || *path == '\\') {
        path++;
    }

    while (*path) {
        char c = *path++;
        if (c == '\\') {
            c = '/';
        }
        if (c == '/') {
            if (segment_len == 1 && len > 0 && out[len - 1] == '.') {
                return -1;
            }
            if (segment_len == 2 && len > 1 && out[len - 1] == '.' && out[len - 2] == '.') {
                return -1;
            }
            if (len == 0 || out[len - 1] == '/') {
                segment_len = 0;
                continue;
            }
            if (len >= MEMFS_MAX_FILE_NAME) {
                return -1;
            }
            out[len++] = '/';
            segment_len = 0;
            continue;
        }
        if (len >= MEMFS_MAX_FILE_NAME) {
            return -1;
        }
        out[len++] = c;
        segment_len++;
    }

    if (segment_len == 1 && len > 0 && out[len - 1] == '.') {
        return -1;
    }
    if (segment_len == 2 && len > 1 && out[len - 1] == '.' && out[len - 2] == '.') {
        return -1;
    }
    while (len > 0 && out[len - 1] == '/') {
        len--;
    }
    out[len] = '\0';
    return 0;
}

static void ram_get_parent_path(const char* path, char* parent) {
    const char* pos = strrchr(path, '/');
    if (pos == NULL) {
        parent[0] = '\0';
        return;
    }
    memcpy(parent, path, pos - path);
    parent[pos - path] = '\0';
}

static int ram_find_entry(const char* path) {
    for (size_t i = 0; i < RAM_NODE_MAX; i++) {
        if (nodes[i] == NULL) {
            continue;
        }
        if (!strcmp(nodes[i]->name, path)) {
            return (int)i;
        }
    }
    return -1;
}

static int ram_find_free_slot(void) {
    for (size_t i = 0; i < RAM_NODE_MAX; i++) {
        if (nodes[i] == NULL) {
            return (int)i;
        }
    }
    return -1;
}

static int ram_path_is_directory(const char* path) {
    if (path[0] == '\0') {
        return 1;
    }
    int idx = ram_find_entry(path);
    return idx >= 0 && nodes[idx]->type == RAM_NODE_TYPE_DIR;
}

static int ram_path_is_file(const char* path) {
    int idx = ram_find_entry(path);
    return idx >= 0 && nodes[idx]->type == RAM_NODE_TYPE_FILE;
}

static int ram_parent_exists(const char* path) {
    char parent[MEMFS_MAX_FILE_NAME + 1] = {0};
    ram_get_parent_path(path, parent);
    return ram_path_is_directory(parent);
}

static void ram_free_blocks(ram_node_t* node) {
    ram_file_block_t* block = node->head;
    while (block) {
        ram_file_block_t* next = block->next;
        luat_heap_free(block);
        block = next;
    }
    node->head = NULL;
}

static void ram_free_node(ram_node_t* node) {
    if (node == NULL) {
        return;
    }
    if (node->type == RAM_NODE_TYPE_FILE) {
        ram_free_blocks(node);
    }
    luat_heap_free(node);
}

static int ram_create_node(const char* path, uint8_t type) {
    int slot;
    ram_node_t* node;

    if (path == NULL || path[0] == '\0') {
        return -1;
    }
    if (ram_find_entry(path) >= 0) {
        return -1;
    }
    if (!ram_parent_exists(path)) {
        return -1;
    }

    slot = ram_find_free_slot();
    if (slot < 0) {
        LLOGE("too many ram nodes >= %d", RAM_NODE_MAX);
        return -1;
    }

    node = luat_heap_malloc(sizeof(ram_node_t));
    if (node == NULL) {
        LLOGE("out of memory when malloc ram_node_t");
        return -1;
    }
    memset(node, 0, sizeof(ram_node_t));
    node->type = type;
    strcpy(node->name, path);
    nodes[slot] = node;
    return slot;
}

static int ram_mode_is_readonly(const char* mode) {
    return !strcmp("r", mode) || !strcmp("rb", mode);
}

static int ram_mode_is_truncate(const char* mode) {
    return !strcmp("w", mode) || !strcmp("wb", mode)
        || !strcmp("w+", mode) || !strcmp("wb+", mode) || !strcmp("w+b", mode);
}

static int ram_mode_is_update(const char* mode) {
    return !strcmp("r+", mode) || !strcmp("rb+", mode) || !strcmp("r+b", mode);
}

static int ram_mode_is_append(const char* mode) {
    return !strcmp("a", mode) || !strcmp("ab", mode)
        || !strcmp("a+", mode) || !strcmp("ab+", mode) || !strcmp("a+b", mode);
}

static int ram_ensure_capacity(ram_node_t* node, size_t needed_size) {
    size_t current_blocks = 0;
    size_t needed_blocks;
    ram_file_block_t* block;
    ram_file_block_t* last = NULL;

    if (node == NULL || node->type != RAM_NODE_TYPE_FILE) {
        return -1;
    }
    needed_blocks = (needed_size + BLOCK_SIZE - 1) / BLOCK_SIZE;
    if (needed_blocks == 0) {
        return 0;
    }

    block = node->head;
    while (block) {
        current_blocks++;
        last = block;
        block = block->next;
    }

    while (current_blocks < needed_blocks) {
        ram_file_block_t* nb = luat_heap_malloc(sizeof(ram_file_block_t));
        if (nb == NULL) {
            LLOGW("out of memory when malloc ram_file_block_t");
            return -1;
        }
        memset(nb, 0, sizeof(ram_file_block_t));
        if (node->head == NULL) {
            node->head = nb;
        }
        else {
            last->next = nb;
        }
        last = nb;
        current_blocks++;
    }
    return 0;
}

static int ram_is_direct_child(const char* dir, const char* path, const char** name) {
    const char* child_name;
    size_t dir_len = strlen(dir);

    if (dir_len == 0) {
        child_name = path;
    }
    else {
        if (strncmp(path, dir, dir_len) != 0 || path[dir_len] != '/') {
            return 0;
        }
        child_name = path + dir_len + 1;
    }
    if (child_name[0] == '\0' || strchr(child_name, '/') != NULL) {
        return 0;
    }
    if (name != NULL) {
        *name = child_name;
    }
    return 1;
}

static int ram_is_descendant(const char* dir, const char* path) {
    size_t dir_len = strlen(dir);
    if (dir_len == 0) {
        return path[0] != '\0';
    }
    return strncmp(path, dir, dir_len) == 0 && path[dir_len] == '/' && path[dir_len + 1] != '\0';
}

static int ram_path_in_subtree(const char* dir, const char* path) {
    return !strcmp(dir, path) || ram_is_descendant(dir, path);
}

static int ram_dir_is_empty(const char* path) {
    for (size_t i = 0; i < RAM_NODE_MAX; i++) {
        if (nodes[i] == NULL) {
            continue;
        }
        if (ram_is_descendant(path, nodes[i]->name)) {
            return 0;
        }
    }
    return 1;
}

static void ram_delete_entry(int idx) {
    if (idx < 0 || idx >= RAM_NODE_MAX || nodes[idx] == NULL) {
        return;
    }
    ram_free_node(nodes[idx]);
    nodes[idx] = NULL;
}

static int ram_ensure_directory(const char* path) {
    char current[MEMFS_MAX_FILE_NAME + 1] = {0};
    size_t len;

    if (path == NULL) {
        return -1;
    }
    if (path[0] == '\0') {
        return 0;
    }

    len = strlen(path);
    for (size_t i = 0; i <= len; i++) {
        int idx;

        if (path[i] != '/' && path[i] != '\0') {
            continue;
        }
        memcpy(current, path, i);
        current[i] = '\0';
        idx = ram_find_entry(current);
        if (idx < 0) {
            if (ram_create_node(current, RAM_NODE_TYPE_DIR) < 0) {
                return -1;
            }
            continue;
        }
        if (nodes[idx]->type != RAM_NODE_TYPE_DIR) {
            return -1;
        }
    }
    return 0;
}

static FILE* ram_make_fd(int fid, uint32_t offset, uint8_t readonly) {
    luat_raw_fd_t* fd = luat_heap_malloc(sizeof(luat_raw_fd_t));
    if (fd == NULL) {
        LLOGE("out of memory when malloc luat_raw_fd_t");
        return NULL;
    }
    fd->fid = fid;
    fd->offset = offset;
    fd->readonly = readonly;
    return (FILE*)fd;
}

FILE* luat_vfs_ram_fopen(void* userdata, const char *filename, const char *mode) {
    char path[MEMFS_MAX_FILE_NAME + 1] = {0};
    int idx;

    (void)userdata;
    if (filename == NULL || mode == NULL || ram_normalize_path(filename, path)) {
        return NULL;
    }
    if (path[0] == '\0') {
        return NULL;
    }

    idx = ram_find_entry(path);
    if (ram_mode_is_readonly(mode)) {
        if (idx < 0 || nodes[idx]->type != RAM_NODE_TYPE_FILE) {
            return NULL;
        }
        return ram_make_fd(idx, 0, 1);
    }
    if (ram_mode_is_truncate(mode)) {
        if (idx < 0) {
            idx = ram_create_node(path, RAM_NODE_TYPE_FILE);
            if (idx < 0) {
                return NULL;
            }
        }
        else if (nodes[idx]->type != RAM_NODE_TYPE_FILE) {
            return NULL;
        }
        nodes[idx]->size = 0;
        ram_free_blocks(nodes[idx]);
        return ram_make_fd(idx, 0, 0);
    }
    if (ram_mode_is_update(mode)) {
        if (idx < 0 || nodes[idx]->type != RAM_NODE_TYPE_FILE) {
            return NULL;
        }
        return ram_make_fd(idx, 0, 0);
    }
    if (ram_mode_is_append(mode)) {
        if (idx < 0) {
            idx = ram_create_node(path, RAM_NODE_TYPE_FILE);
            if (idx < 0) {
                return NULL;
            }
        }
        else if (nodes[idx]->type != RAM_NODE_TYPE_FILE) {
            return NULL;
        }
        return ram_make_fd(idx, (uint32_t)nodes[idx]->size, 0);
    }
    LLOGE("unkown open mode %s", mode);
    return NULL;
}

int luat_vfs_ram_getc(void* userdata, FILE* stream) {
    uint8_t c = 0;
    size_t len = luat_vfs_ram_fread(userdata, &c, 1, 1, stream);
    if (len == 1) {
            return c;
    }
    return -1;
}

int luat_vfs_ram_fseek(void* userdata, FILE* stream, long int offset, int origin) {
    (void)userdata;
    luat_raw_fd_t* fd = (luat_raw_fd_t*)stream;
    ram_node_t* node;
    long long new_offset;

    if (fd == NULL || fd->fid < 0 || fd->fid >= RAM_NODE_MAX || nodes[fd->fid] == NULL) {
        return -1;
    }
    node = nodes[fd->fid];
    if (origin == SEEK_CUR) {
        new_offset = (long long)fd->offset + offset;
    }
    else if (origin == SEEK_SET) {
        new_offset = offset;
    }
    else {
        new_offset = (long long)node->size + offset;
    }
    if (new_offset < 0) {
        new_offset = 0;
    }
    if ((size_t)new_offset > node->size) {
        new_offset = (long long)node->size;
    }
    fd->offset = (uint32_t)new_offset;
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
    if (fd == NULL || fd->fid < 0 || fd->fid >= RAM_NODE_MAX || nodes[fd->fid] == NULL) {
        return 1;
    }
    return fd->offset >= nodes[fd->fid]->size ? 1 : 0;
}

int luat_vfs_ram_ferror(void* userdata, FILE *stream) {
    (void)userdata;
    (void)stream;
    return 0;
}

size_t luat_vfs_ram_fread(void* userdata, void *ptr, size_t size, size_t nmemb, FILE *stream) {
    (void)userdata;
    luat_raw_fd_t* fd = (luat_raw_fd_t*)stream;
    ram_node_t* node;
    size_t read_size = size * nmemb;

    if (fd == NULL || fd->fid < 0 || fd->fid >= RAM_NODE_MAX || nodes[fd->fid] == NULL) {
        return 0;
    }
    node = nodes[fd->fid];
    if (node->type != RAM_NODE_TYPE_FILE || fd->offset >= node->size) {
        return 0;
    }

    if (fd->offset + read_size > node->size) {
        read_size = node->size - fd->offset;
    }

    ram_file_block_t* block = node->head;
    size_t offset = fd->offset;
    while (block != NULL && offset >= BLOCK_SIZE) {
        offset -= BLOCK_SIZE;
        block = block->next;
    }

    if (block == NULL) {
        LLOGW("no block for offset %d", fd->offset);
        return 0;
    }

    uint8_t* dst = (uint8_t*)ptr;
    size_t bytes_read = 0;
    while (block != NULL && read_size > 0) {
        size_t copy_size = BLOCK_SIZE - (offset % BLOCK_SIZE);
        if (copy_size > read_size) {
            copy_size = read_size;
        }
        memcpy(dst, block->data + (offset % BLOCK_SIZE), copy_size);
        dst += copy_size;
        read_size -= copy_size;
        offset += copy_size;
        bytes_read += copy_size;
        if (offset % BLOCK_SIZE == 0) {
            block = block->next;
        }
    }

    fd->offset += bytes_read;
    return bytes_read;
}

size_t luat_vfs_ram_fwrite(void* userdata, const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    (void)userdata;
    luat_raw_fd_t* fd = (luat_raw_fd_t*)stream;
    ram_node_t* node;
    size_t write_size = size * nmemb;

    if (fd == NULL || fd->fid < 0 || fd->fid >= RAM_NODE_MAX || nodes[fd->fid] == NULL) {
        return 0;
    }
    node = nodes[fd->fid];
    if (fd->readonly) {
        LLOGW("readonly fd %d!! path %s", fd->fid, node->name);
        return 0;
    }
    if (node->type != RAM_NODE_TYPE_FILE) {
        return 0;
    }

    size_t old_size = node->size;
    size_t needed_size = fd->offset + write_size;

    if (ram_ensure_capacity(node, needed_size)) {
        return 0;
    }

    ram_file_block_t* block = node->head;
    size_t offset = fd->offset;
    while (block != NULL && offset >= BLOCK_SIZE) {
        offset -= BLOCK_SIZE;
        block = block->next;
    }

    const uint8_t* src = (const uint8_t*)ptr;
    while (write_size > 0) {
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
    if (needed_size > old_size) {
        node->size = needed_size;
    }
    return (size_t)(src - (const uint8_t*)ptr);
}

int luat_vfs_ram_remove(void* userdata, const char *filename) {
    char path[MEMFS_MAX_FILE_NAME + 1] = {0};
    int idx;

    (void)userdata;
    if (filename == NULL || ram_normalize_path(filename, path)) {
        return -1;
    }
    idx = ram_find_entry(path);
    if (idx < 0 || nodes[idx]->type != RAM_NODE_TYPE_FILE) {
        return -1;
    }
    ram_free_node(nodes[idx]);
    nodes[idx] = NULL;
    return 0;
}

int luat_vfs_ram_rename(void* userdata, const char *old_filename, const char *new_filename) {
    char old_path[MEMFS_MAX_FILE_NAME + 1] = {0};
    char new_path[MEMFS_MAX_FILE_NAME + 1] = {0};
    size_t old_len;
    int idx;
    int target_idx;

    (void)userdata;
    if (old_filename == NULL || new_filename == NULL) {
        return -1;
    }
    if (ram_normalize_path(old_filename, old_path) || ram_normalize_path(new_filename, new_path)) {
        return -1;
    }
    if (old_path[0] == '\0' || new_path[0] == '\0') {
        return -1;
    }
    idx = ram_find_entry(old_path);
    if (idx < 0 || !ram_parent_exists(new_path)) {
        return -1;
    }
    if (!strcmp(old_path, new_path)) {
        return 0;
    }
    if (nodes[idx]->type == RAM_NODE_TYPE_DIR
        && strncmp(new_path, old_path, strlen(old_path)) == 0
        && new_path[strlen(old_path)] == '/') {
        return -1;
    }

    target_idx = ram_find_entry(new_path);
    if (target_idx >= 0) {
        if (nodes[idx]->type != nodes[target_idx]->type) {
            return -1;
        }
        if (nodes[target_idx]->type == RAM_NODE_TYPE_DIR && !ram_dir_is_empty(new_path)) {
            return -1;
        }
    }

    old_len = strlen(old_path);
    for (size_t i = 0; i < RAM_NODE_MAX; i++) {
        char renamed[MEMFS_MAX_FILE_NAME + 1] = {0};
        const char* suffix;
        int conflict = 0;

        if (nodes[i] == NULL) {
            continue;
        }
        if (strcmp(nodes[i]->name, old_path) != 0 && !ram_is_descendant(old_path, nodes[i]->name)) {
            continue;
        }
        suffix = nodes[i]->name + old_len;
        if (strlen(new_path) + strlen(suffix) > MEMFS_MAX_FILE_NAME) {
            return -1;
        }
        strcpy(renamed, new_path);
        strcat(renamed, suffix);
        for (size_t j = 0; j < RAM_NODE_MAX; j++) {
            if (nodes[j] == NULL || j == i) {
                continue;
            }
            if (ram_path_in_subtree(old_path, nodes[j]->name)) {
                continue;
            }
            if (target_idx >= 0 && ram_path_in_subtree(new_path, nodes[j]->name)) {
                continue;
            }
            if (!strcmp(nodes[j]->name, renamed)) {
                conflict = 1;
                break;
            }
        }
        if (conflict) {
            return -1;
        }
    }

    if (target_idx >= 0) {
        ram_delete_entry(target_idx);
    }

    for (size_t i = 0; i < RAM_NODE_MAX; i++) {
        char renamed[MEMFS_MAX_FILE_NAME + 1] = {0};
        const char* suffix;

        if (nodes[i] == NULL) {
            continue;
        }
        if (!ram_path_in_subtree(old_path, nodes[i]->name)) {
            continue;
        }
        suffix = nodes[i]->name + old_len;
        strcpy(renamed, new_path);
        strcat(renamed, suffix);
        strcpy(nodes[i]->name, renamed);
    }
    return 0;
}

int luat_vfs_ram_fexist(void* userdata, const char *filename) {
    char path[MEMFS_MAX_FILE_NAME + 1] = {0};
    (void)userdata;
    if (filename == NULL || ram_normalize_path(filename, path)) {
        return 0;
    }
    return ram_path_is_file(path);
}

size_t luat_vfs_ram_fsize(void* userdata, const char *filename) {
    char path[MEMFS_MAX_FILE_NAME + 1] = {0};
    int idx;

    (void)userdata;
    if (filename == NULL || ram_normalize_path(filename, path)) {
        return 0;
    }
    idx = ram_find_entry(path);
    if (idx < 0 || nodes[idx]->type != RAM_NODE_TYPE_FILE) {
        return 0;
    }
    return nodes[idx]->size;
}

void* luat_vfs_ram_mmap(void* userdata, FILE *stream) {
    (void)userdata;
    luat_raw_fd_t *fd = (luat_raw_fd_t*)(stream);
    if (fd == NULL || fd->fid < 0 || fd->fid >= RAM_NODE_MAX || nodes[fd->fid] == NULL) {
        return NULL;
    }
    if (nodes[fd->fid]->type != RAM_NODE_TYPE_FILE || nodes[fd->fid]->head == NULL) {
        return NULL;
    }
    return nodes[fd->fid]->head->data;
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
    char path[MEMFS_MAX_FILE_NAME + 1] = {0};
    (void)userdata;
    if (_DirName == NULL || ram_normalize_path(_DirName, path)) {
        return -1;
    }
    if (path[0] == '\0') {
        return 0;
    }
    return ram_ensure_directory(path);
}

int luat_vfs_ram_rmdir(void* userdata, char const* _DirName) {
    char path[MEMFS_MAX_FILE_NAME + 1] = {0};
    int idx;

    (void)userdata;
    if (_DirName == NULL || ram_normalize_path(_DirName, path)) {
        return -1;
    }
    if (path[0] == '\0') {
        return -1;
    }
    idx = ram_find_entry(path);
    if (idx < 0 || nodes[idx]->type != RAM_NODE_TYPE_DIR || !ram_dir_is_empty(path)) {
        return -1;
    }
    ram_free_node(nodes[idx]);
    nodes[idx] = NULL;
    return 0;
}

int luat_vfs_ram_lsdir(void* userdata, char const* _DirName, luat_fs_dirent_t* ents, size_t offset, size_t len) {
    char dir[MEMFS_MAX_FILE_NAME + 1] = {0};
    (void)userdata;
    if (ents == NULL || len == 0 || _DirName == NULL || ram_normalize_path(_DirName, dir)) {
        return 0;
    }
    if (!ram_path_is_directory(dir)) {
        return 0;
    }
    size_t count = 0;
    for (size_t i = 0; i < RAM_NODE_MAX; i++) {
        const char* child_name;
        if (count >= len) {
            break;
        }
        if (nodes[i] == NULL || !ram_is_direct_child(dir, nodes[i]->name, &child_name)) {
            continue;
        }
        if (offset > 0) {
            offset--;
            continue;
        }
        ents[count].d_type = nodes[i]->type;
        ents[count].d_size = 0;
        strcpy(ents[count].d_name, child_name);
        count++;
    }
    return (int)count;
}

int luat_vfs_ram_info(void* userdata, const char* path, luat_fs_info_t *conf) {
    (void)userdata;
    (void)path;
    memcpy(conf->filesystem, "ram", strlen("ram")+1);
    size_t ftotal = 0;
    for (size_t i = 0; i < RAM_NODE_MAX; i++) {
        if (nodes[i] == NULL || nodes[i]->type != RAM_NODE_TYPE_FILE) {
            continue;
        }
        ftotal += nodes[i]->size;
    }
    size_t total; size_t used; size_t max_used;
    luat_meminfo_sys(&total, &used, &max_used);
    
    conf->type = 0;
    conf->total_block = 64;
    conf->block_used = (ftotal + BLOCK_SIZE - 1) / BLOCK_SIZE;
    conf->block_size = BLOCK_SIZE;
    return 0;
}

int luat_vfs_ram_truncate(void* fsdata, char const* path, size_t nsize) {
    char file_path[MEMFS_MAX_FILE_NAME + 1] = {0};
    ram_node_t* node;
    size_t needed_blocks;
    size_t current_index = 0;
    ram_file_block_t* block;

    (void)fsdata;
    if (path == NULL || ram_normalize_path(path, file_path)) {
        return -1;
    }
    if (!ram_path_is_file(file_path)) {
        return -1;
    }

    node = nodes[ram_find_entry(file_path)];
    if (nsize > node->size && ram_ensure_capacity(node, nsize)) {
        return -1;
    }

    needed_blocks = (nsize + BLOCK_SIZE - 1) / BLOCK_SIZE;
    if (needed_blocks == 0) {
        ram_free_blocks(node);
        node->size = 0;
        return 0;
    }

    block = node->head;
    while (block) {
        current_index++;
        if (current_index == needed_blocks) {
            if (nsize % BLOCK_SIZE) {
                memset(block->data + (nsize % BLOCK_SIZE), 0, BLOCK_SIZE - (nsize % BLOCK_SIZE));
            }
            if (block->next) {
                ram_file_block_t* next = block->next;
                block->next = NULL;
                while (next) {
                    ram_file_block_t* nn = next->next;
                    luat_heap_free(next);
                    next = nn;
                }
            }
            break;
        }
        block = block->next;
    }
    node->size = nsize;
    return 0;
}

void* luat_vfs_ram_opendir(void* userdata, char const* _DirName) {
    char path[MEMFS_MAX_FILE_NAME + 1] = {0};
    (void)userdata;
    if (_DirName == NULL || ram_normalize_path(_DirName, path)) {
        return NULL;
    }
    if (path[0] == '\0') {
        return nodes;
    }
    if (!ram_path_is_directory(path)) {
        return NULL;
    }
    return nodes[ram_find_entry(path)];
}

int luat_vfs_ram_closedir(void* userdata, void* dir) {
    (void)userdata;
    (void)dir;
    return 0;
}


#define T(name) .name = luat_vfs_ram_##name
const struct luat_vfs_filesystem vfs_fs_ram = {
    .name = "ram",
    .opts = {
        .mkfs = NULL,
        T(mount),
        T(umount),
        T(mkdir),
        T(rmdir),
        T(lsdir),
        T(remove),
        T(rename),
        T(fsize),
        T(fexist),
        T(info),
        T(opendir),
        T(closedir),
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

