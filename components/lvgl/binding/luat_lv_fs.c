
#include "luat_base.h"
#include "lvgl.h"
#include "luat_fs.h"

#define LUAT_LOG_TAG "lvgl.fs"
#include "luat_log.h"

typedef  FILE * file_t;

static bool luat_lv_fs_ready(struct _lv_fs_drv_t * drv);

static lv_fs_res_t luat_lv_fs_open(struct _lv_fs_drv_t * drv, void * file_p, const char * path, lv_fs_mode_t mode);
static lv_fs_res_t luat_lv_fs_close(struct _lv_fs_drv_t * drv, void * file_p);
// static lv_fs_res_t luat_lv_fs_remove(struct _lv_fs_drv_t * drv, const char * fn);
static lv_fs_res_t luat_lv_fs_read(struct _lv_fs_drv_t * drv, void * file_p, void * buf, uint32_t btr, uint32_t * br);
// static lv_fs_res_t luat_lv_fs_write(struct _lv_fs_drv_t * drv, void * file_p, const void * buf, uint32_t btw, uint32_t * bw);
static lv_fs_res_t luat_lv_fs_seek(struct _lv_fs_drv_t * drv, void * file_p, uint32_t pos);
static lv_fs_res_t luat_lv_fs_tell(struct _lv_fs_drv_t * drv, void * file_p, uint32_t * pos_p);
// static lv_fs_res_t luat_lv_fs_trunc(struct _lv_fs_drv_t * drv, void * file_p);
static lv_fs_res_t luat_lv_fs_size(struct _lv_fs_drv_t * drv, void * file_p, uint32_t * size_p);
// static lv_fs_res_t luat_lv_fs_rename(struct _lv_fs_drv_t * drv, const char * oldname, const char * newname);
// static lv_fs_res_t luat_lv_fs_free_space(struct _lv_fs_drv_t * drv, uint32_t * total_p, uint32_t * free_p);

// static lv_fs_res_t luat_lv_fs_dir_open(struct _lv_fs_drv_t * drv, void * rddir_p, const char * path);
// static lv_fs_res_t luat_lv_fs_dir_read(struct _lv_fs_drv_t * drv, void * rddir_p, char * fn);
// static lv_fs_res_t luat_lv_fs_dir_close(struct _lv_fs_drv_t * drv, void * rddir_p);

void luat_lv_fs_init(void) {
    lv_fs_drv_t fs_drv = {
        .letter = '/',
        .file_size = sizeof(FILE*),
        .rddir_size = sizeof(FILE*),
        .ready_cb = luat_lv_fs_ready,
        .open_cb = luat_lv_fs_open,
        .close_cb = luat_lv_fs_close,
        .remove_cb = NULL,
        .read_cb = luat_lv_fs_read,
        .write_cb = NULL,
        .seek_cb = luat_lv_fs_seek,
        .tell_cb = luat_lv_fs_tell,
        .trunc_cb = NULL,
        .size_cb = luat_lv_fs_size,
        .rename_cb = NULL,
        .free_space_cb = NULL,
    
        .dir_open_cb = NULL,
        .dir_read_cb = NULL,
        .dir_close_cb = NULL,
    };
    lv_fs_drv_register(&fs_drv);
};

static bool luat_lv_fs_ready(struct _lv_fs_drv_t * drv) {
    return true;
}

static lv_fs_res_t luat_lv_fs_open(struct _lv_fs_drv_t * drv, void * file_p, const char * path, lv_fs_mode_t mode) {
    char rpath[128] = {0};
    if (*path != '/') {
        rpath[0] = '/';
        memcpy(rpath + 1, path, strlen(path) + 1);
    }
    else
        memcpy(rpath, path, strlen(path) + 1);
    FILE* fd = NULL;
    if (mode == LV_FS_MODE_WR)
        fd = luat_fs_fopen(rpath, "wb");
    else
        fd = luat_fs_fopen(rpath, "rb");
    if (fd == NULL) {
        return LV_FS_RES_NOT_EX;
    };
    file_t* fp = file_p;
    *fp = fd;
    return LV_FS_RES_OK;
}

static lv_fs_res_t luat_lv_fs_close(struct _lv_fs_drv_t * drv, void * file_p) {
    if (file_p != NULL) {
        file_t* fp = file_p;
        luat_fs_fclose(*fp);
        return LV_FS_RES_OK;
    }
    return LV_FS_RES_NOT_EX;
}

// static lv_fs_res_t luat_lv_fs_remove(struct _lv_fs_drv_t * drv, const char * fn) {
//     luat_fs_remove(fn);
//     return LV_FS_RES_OK;
// }

static lv_fs_res_t luat_lv_fs_read(struct _lv_fs_drv_t * drv, void * file_p, void * buf, uint32_t btr, uint32_t * br) {
    file_t* fp = file_p;
    *br = luat_fs_fread(buf, 1, btr, *fp);
    //LLOGD("luat_fs_fread expect %ld act %ld", btr, *br);
    if (*br > 0)
        return LV_FS_RES_OK;
    return LV_FS_RES_FS_ERR;
}


// static lv_fs_res_t luat_lv_fs_write(struct _lv_fs_drv_t * drv, void * file_p, const void * buf, uint32_t btw, uint32_t * bw) {
//     file_t* fp = file_p;
//     *bw = luat_fs_fwrite(buf, btw, 1, *fp);
//     if (*bw > 0)
//         return LV_FS_RES_OK;
//     return LV_FS_RES_FS_ERR;
// }

static lv_fs_res_t luat_lv_fs_seek(struct _lv_fs_drv_t * drv, void * file_p, uint32_t pos) {
    file_t* fp = file_p;
    int ret = luat_fs_fseek(*fp, pos, SEEK_SET);
    if (ret == 0)
        return LV_FS_RES_OK;
    return LV_FS_RES_FS_ERR;
}

static lv_fs_res_t luat_lv_fs_tell(struct _lv_fs_drv_t * drv, void * file_p, uint32_t * pos_p) {
    file_t* fp = file_p;
    int ret = luat_fs_ftell(*fp);
    if (ret >= 0) {
        *pos_p = ret;
        return LV_FS_RES_OK;
    }
    return LV_FS_RES_FS_ERR;
}

// static lv_fs_res_t luat_lv_fs_trunc(struct _lv_fs_drv_t * drv, void * file_p) {
//     return LV_FS_RES_NOT_IMP;
// }

static lv_fs_res_t luat_lv_fs_size(struct _lv_fs_drv_t * drv, void * file_p, uint32_t * size_p) {
    file_t* fp = file_p;
    int curr = luat_fs_ftell(*fp);
    luat_fs_fseek(*fp, 0, SEEK_END);
    *size_p = luat_fs_ftell(*fp);
    luat_fs_fseek(*fp, curr, SEEK_SET);
    return LV_FS_RES_OK;
}

// static lv_fs_res_t luat_lv_fs_rename(struct _lv_fs_drv_t * drv, const char * oldname, const char * newname) {
//     int ret = luat_fs_rename(oldname, newname);
//     if (ret == 0)
//         return LV_FS_RES_OK;
//     return LV_FS_RES_FS_ERR;
// }

// static lv_fs_res_t luat_lv_fs_free_space(struct _lv_fs_drv_t * drv, uint32_t * total_p, uint32_t * free_p) {
//     return LV_FS_RES_NOT_IMP;
// }

// static lv_fs_res_t luat_lv_fs_dir_open(struct _lv_fs_drv_t * drv, void * rddir_p, const char * path) {
//     return LV_FS_RES_NOT_IMP;
// }

// static lv_fs_res_t luat_lv_fs_dir_read(struct _lv_fs_drv_t * drv, void * rddir_p, char * fn) {
//     return LV_FS_RES_NOT_IMP;
// }

// static lv_fs_res_t luat_lv_fs_dir_close(struct _lv_fs_drv_t * drv, void * rddir_p) {
//     return LV_FS_RES_NOT_IMP;
// }

