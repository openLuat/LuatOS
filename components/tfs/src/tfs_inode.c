/*
 * tfs_inode.c — Object (inode) lifecycle for TFS
 */

#include "tfs_inode.h"
#include "tfs_block.h"
#include "tfs_tnode.h"
#include "../inc/tfs_config.h"

#include <string.h>

#ifndef TFS_WRITE_RETRY_BLOCKS
#define TFS_WRITE_RETRY_BLOCKS 4
#endif

/*===================================================================
 *  Allocate / free
 *===================================================================*/

tfs_obj_t *tfs_obj_create(tfs_dev_t *dev, uint32_t obj_id,
                          tfs_obj_type_t type)
{
    tfs_obj_t *obj;

    obj = (tfs_obj_t *)dev->drv.malloc(dev->drv.ctx, sizeof(tfs_obj_t));
    if (!obj)
        return NULL;

    memset(obj, 0, sizeof(tfs_obj_t));

    obj->obj_id   = obj_id;
    obj->obj_type = (uint32_t)type;
    obj->my_dev   = dev;

    tfs_list_init(&obj->hash_link);
    tfs_list_init(&obj->hard_links);
    tfs_list_init(&obj->siblings);

    if (type == TFS_OBJ_TYPE_DIR) {
        tfs_list_init(&obj->var.dir.children);
        tfs_list_init(&obj->var.dir.dirty);
    }

    dev->n_obj++;
    dev->n_obj_created++;

    return obj;
}

void tfs_obj_free(tfs_dev_t *dev, tfs_obj_t *obj)
{
    if (!obj)
        return;

    if (obj->full_name) {
        dev->drv.free(dev->drv.ctx, obj->full_name);
        obj->full_name = NULL;
    }

    if (obj->obj_type == TFS_OBJ_TYPE_FILE) {
        /* Free tnode tree */
        tfs_tnode_free_tree(dev, obj->var.file.top,
                            obj->var.file.top_level);
        obj->var.file.top = NULL;
    } else if (obj->obj_type == TFS_OBJ_TYPE_SYMLINK) {
        if (obj->var.symlink.alias) {
            dev->drv.free(dev->drv.ctx, obj->var.symlink.alias);
            obj->var.symlink.alias = NULL;
        }
    }

    dev->drv.free(dev->drv.ctx, obj);
    dev->n_obj--;
    dev->n_obj_deleted++;
}

/*===================================================================
 *  Hash table
 *===================================================================*/

void tfs_obj_insert(tfs_dev_t *dev, tfs_obj_t *obj)
{
    uint32_t            bucket = tfs_obj_hash(obj->obj_id);
    tfs_obj_bucket_t  *bkt    = &dev->obj_bucket[bucket];

    tfs_list_add(&obj->hash_link, &bkt->list);
    bkt->count++;
}

void tfs_obj_remove(tfs_dev_t *dev, tfs_obj_t *obj)
{
    uint32_t           bucket = tfs_obj_hash(obj->obj_id);
    tfs_obj_bucket_t *bkt    = &dev->obj_bucket[bucket];

    tfs_list_del(&obj->hash_link);
    tfs_list_init(&obj->hash_link);
    if (bkt->count > 0)
        bkt->count--;
}

tfs_obj_t *tfs_obj_find(tfs_dev_t *dev, uint32_t obj_id)
{
    uint32_t           bucket = tfs_obj_hash(obj_id);
    tfs_obj_bucket_t *bkt    = &dev->obj_bucket[bucket];
    tfs_obj_t        *obj;

    tfs_list_for_each_entry(obj, &bkt->list, hash_link) {
        if (obj->obj_id == obj_id)
            return obj;
    }
    return NULL;
}

uint32_t tfs_obj_new_id(tfs_dev_t *dev)
{
    uint32_t start = dev->bucket_finder;
    uint32_t id;

    for (id = start; id < TFS_MAX_OBJ_ID; id++) {
        if (!tfs_obj_find(dev, id))
            goto found;
    }
    for (id = TFS_OBJ_ID_FIRST_USER; id < start; id++) {
        if (!tfs_obj_find(dev, id))
            goto found;
    }
    return 0;  /* no free IDs */

found:
    dev->bucket_finder = id + 1;
    return id;
}

/*===================================================================
 *  Object header I/O
 *===================================================================*/

int tfs_obj_read_hdr(tfs_dev_t *dev, int chunk_in_nand,
                     tfs_obj_hdr_t *hdr, tfs_ext_tags_t *ext)
{
    return tfs_chunk_read(dev, chunk_in_nand,
                          hdr ? (uint8_t *)hdr : NULL,
                          hdr ? (int)sizeof(tfs_obj_hdr_t) : 0,
                          ext);
}

int tfs_obj_write_hdr(tfs_dev_t *dev, tfs_obj_t *obj,
                      tfs_obj_hdr_t *hdr, int old_chunk)
{
    tfs_ext_tags_t ext;
    int            new_chunk = -1;
    int            rc = TFS_EFLASH;
    int            attempt;

    memset(&ext, 0, sizeof(ext));
    ext.chunk_used       = 1;
    ext.obj_id           = obj->obj_id;
    ext.chunk_id         = 0;            /* object header */
    ext.n_bytes          = 0xffff;
    ext.extra_available  = 1;
    ext.extra_obj_type   = (tfs_obj_type_t)obj->obj_type;
    ext.extra_parent_id  = obj->parent ? obj->parent->obj_id : 0;

    if (obj->obj_type == TFS_OBJ_TYPE_FILE) {
        ext.extra_file_size = obj->var.file.stored_size;
    }

    for (attempt = 0; attempt < TFS_WRITE_RETRY_BLOCKS; attempt++) {
        new_chunk = tfs_alloc_chunk(dev, 0);
        if (new_chunk < 0)
            return TFS_ENOSPC;

        rc = tfs_chunk_write(dev, new_chunk,
                             (const uint8_t *)hdr,
                             (int)sizeof(tfs_obj_hdr_t),
                             &ext);
        if (rc == TFS_OK)
            break;
        if (rc != TFS_EFLASH)
            return rc;
    }
    if (rc != TFS_OK)
        return rc;

    if (old_chunk > 0)
        tfs_chunk_delete(dev, old_chunk, 1);

    obj->hdr_chunk = new_chunk;
    return TFS_OK;
}

void tfs_obj_make_hdr(const tfs_dev_t *dev, const tfs_obj_t *obj,
                      tfs_obj_hdr_t *hdr)
{
    const char *name;

    (void)dev;
    memset(hdr, 0xff, sizeof(*hdr));

    hdr->type          = obj->obj_type;
    hdr->parent_obj_id = obj->parent ? obj->parent->obj_id : 0;
    hdr->mode          = obj->mode;
    hdr->uid           = obj->uid;
    hdr->gid           = obj->gid;
    hdr->atime         = obj->atime;
    hdr->mtime         = obj->mtime;
    hdr->ctime         = obj->ctime;
    hdr->rdev          = obj->rdev;

    name = obj->full_name ? obj->full_name : obj->short_name;
    strncpy(hdr->name, name ? name : "", TFS_MAX_NAME_LEN);
    hdr->name[TFS_MAX_NAME_LEN] = '\0';

    if (obj->obj_type == TFS_OBJ_TYPE_FILE) {
        hdr->file_size_low  = (uint32_t)(obj->var.file.stored_size & 0xffffffffu);
        hdr->file_size_high = (uint32_t)(obj->var.file.stored_size >> 32);
    } else if (obj->obj_type == TFS_OBJ_TYPE_SYMLINK) {
        if (obj->var.symlink.alias)
            strncpy(hdr->alias, obj->var.symlink.alias, TFS_MAX_ALIAS_LEN);
        hdr->alias[TFS_MAX_ALIAS_LEN] = '\0';
    } else if (obj->obj_type == TFS_OBJ_TYPE_HARDLINK) {
        hdr->equiv_id = (int32_t)obj->var.hardlink.equiv_id;
    }
}

void tfs_obj_load_hdr(tfs_dev_t *dev, tfs_obj_t *obj,
                      const tfs_obj_hdr_t *hdr,
                      const tfs_ext_tags_t *ext,
                      int chunk_in_nand)
{
    obj->obj_type   = hdr->type;
    obj->mode       = hdr->mode;
    obj->uid        = hdr->uid;
    obj->gid        = hdr->gid;
    obj->atime      = hdr->atime;
    obj->mtime      = hdr->mtime;
    obj->ctime      = hdr->ctime;
    obj->rdev       = hdr->rdev;
    obj->hdr_chunk  = chunk_in_nand;

    tfs_obj_cache_name(obj, hdr->name);

    if (obj->obj_type == TFS_OBJ_TYPE_FILE) {
        tfs_off_t sz = (tfs_off_t)hdr->file_size_high << 32
                       | (tfs_off_t)hdr->file_size_low;
        obj->var.file.stored_size = sz;
        obj->var.file.file_size   = sz;
    } else if (obj->obj_type == TFS_OBJ_TYPE_SYMLINK) {
        /* Alias stored in hdr.alias */
        size_t len = strlen(hdr->alias) + 1;
        obj->var.symlink.alias = (char *)dev->drv.malloc(dev->drv.ctx, len);
        if (obj->var.symlink.alias)
            memcpy(obj->var.symlink.alias, hdr->alias, len);
    } else if (obj->obj_type == TFS_OBJ_TYPE_HARDLINK) {
        obj->var.hardlink.equiv_id = (uint32_t)hdr->equiv_id;
    }

    (void)ext;
}

int tfs_obj_update_hdr(tfs_dev_t *dev, tfs_obj_t *obj)
{
    tfs_obj_hdr_t hdr;
    int           old = obj->hdr_chunk;

    tfs_obj_make_hdr(dev, obj, &hdr);
    return tfs_obj_write_hdr(dev, obj, &hdr, old);
}

/*===================================================================
 *  Object hierarchy
 *===================================================================*/

void tfs_obj_add_child(tfs_obj_t *parent, tfs_obj_t *obj)
{
    if (!parent || parent->obj_type != TFS_OBJ_TYPE_DIR)
        return;
    obj->parent = parent;
    tfs_list_add_tail(&obj->siblings, &parent->var.dir.children);
}

void tfs_obj_remove_child(tfs_obj_t *parent, tfs_obj_t *obj)
{
    if (!parent)
        return;
    tfs_list_del(&obj->siblings);
    tfs_list_init(&obj->siblings);
    obj->parent = NULL;
}

tfs_obj_t *tfs_obj_find_by_name(tfs_dev_t *dev, tfs_obj_t *parent,
                                const char *name)
{
    tfs_obj_t *child;

    if (!parent || parent->obj_type != TFS_OBJ_TYPE_DIR)
        return NULL;

    tfs_list_for_each_entry(child, &parent->var.dir.children, siblings) {
        const char *cname = tfs_obj_get_name(dev, child);
        if (cname && strcmp(cname, name) == 0)
            return child;
    }
    return NULL;
}

/*===================================================================
 *  Name handling
 *===================================================================*/

void tfs_obj_cache_name(tfs_obj_t *obj, const char *name)
{
    tfs_dev_t *dev;
    size_t len;

    if (!obj || !name)
        return;

    dev = obj->my_dev;
    if (obj->full_name) {
        if (dev) {
            dev->drv.free(dev->drv.ctx, obj->full_name);
        }
        obj->full_name = NULL;
    }

    strncpy(obj->short_name, name, TFS_SHORT_NAME_LEN);
    obj->short_name[TFS_SHORT_NAME_LEN] = '\0';

    len = strlen(name);
    if (len > TFS_MAX_NAME_LEN) {
        len = TFS_MAX_NAME_LEN;
    }
    if (len > TFS_SHORT_NAME_LEN && dev && dev->drv.malloc) {
        obj->full_name = (char *)dev->drv.malloc(dev->drv.ctx, len + 1);
        if (obj->full_name) {
            memcpy(obj->full_name, name, len);
            obj->full_name[len] = '\0';
        }
    }
}

const char *tfs_obj_get_name(tfs_dev_t *dev, tfs_obj_t *obj)
{
    (void)dev;
    if (!obj) {
        return NULL;
    }
    return obj->full_name ? obj->full_name : obj->short_name;
}
