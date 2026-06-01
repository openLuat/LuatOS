/*
 * nfs_inode.c — Object (inode) lifecycle for NFS
 */

#include "nfs_inode.h"
#include "nfs_block.h"
#include "nfs_tnode.h"
#include "../inc/nfs_config.h"

#include <string.h>

/*===================================================================
 *  Allocate / free
 *===================================================================*/

nfs_obj_t *nfs_obj_create(nfs_dev_t *dev, nfs_u32 obj_id,
                          nfs_obj_type_t type)
{
    nfs_obj_t *obj;

    obj = (nfs_obj_t *)dev->drv.malloc(dev->drv.ctx, sizeof(nfs_obj_t));
    if (!obj)
        return NFS_NULL;

    memset(obj, 0, sizeof(nfs_obj_t));

    obj->obj_id   = obj_id;
    obj->obj_type = (nfs_u32)type;
    obj->my_dev   = dev;

    nfs_list_init(&obj->hash_link);
    nfs_list_init(&obj->hard_links);
    nfs_list_init(&obj->siblings);

    if (type == NFS_OBJ_TYPE_DIR) {
        nfs_list_init(&obj->var.dir.children);
        nfs_list_init(&obj->var.dir.dirty);
    }

    dev->n_obj++;
    dev->n_obj_created++;

    return obj;
}

void nfs_obj_free(nfs_dev_t *dev, nfs_obj_t *obj)
{
    if (!obj)
        return;

    if (obj->obj_type == NFS_OBJ_TYPE_FILE) {
        /* Free tnode tree */
        nfs_tnode_free_tree(dev, obj->var.file.top,
                            obj->var.file.top_level);
        obj->var.file.top = NFS_NULL;
    } else if (obj->obj_type == NFS_OBJ_TYPE_SYMLINK) {
        if (obj->var.symlink.alias) {
            dev->drv.free(dev->drv.ctx, obj->var.symlink.alias);
            obj->var.symlink.alias = NFS_NULL;
        }
    }

    dev->drv.free(dev->drv.ctx, obj);
    dev->n_obj--;
    dev->n_obj_deleted++;
}

/*===================================================================
 *  Hash table
 *===================================================================*/

void nfs_obj_insert(nfs_dev_t *dev, nfs_obj_t *obj)
{
    nfs_u32            bucket = nfs_obj_hash(obj->obj_id);
    nfs_obj_bucket_t  *bkt    = &dev->obj_bucket[bucket];

    nfs_list_add(&bkt->list, &obj->hash_link);
    bkt->count++;
}

void nfs_obj_remove(nfs_dev_t *dev, nfs_obj_t *obj)
{
    nfs_u32           bucket = nfs_obj_hash(obj->obj_id);
    nfs_obj_bucket_t *bkt    = &dev->obj_bucket[bucket];

    nfs_list_del(&obj->hash_link);
    nfs_list_init(&obj->hash_link);
    if (bkt->count > 0)
        bkt->count--;
}

nfs_obj_t *nfs_obj_find(nfs_dev_t *dev, nfs_u32 obj_id)
{
    nfs_u32           bucket = nfs_obj_hash(obj_id);
    nfs_obj_bucket_t *bkt    = &dev->obj_bucket[bucket];
    nfs_obj_t        *obj;

    nfs_list_for_each_entry(obj, &bkt->list, hash_link) {
        if (obj->obj_id == obj_id)
            return obj;
    }
    return NFS_NULL;
}

nfs_u32 nfs_obj_new_id(nfs_dev_t *dev)
{
    nfs_u32 start = dev->bucket_finder;
    nfs_u32 id;

    for (id = start; id < NFS_MAX_OBJ_ID; id++) {
        if (!nfs_obj_find(dev, id))
            goto found;
    }
    for (id = NFS_OBJ_ID_FIRST_USER; id < start; id++) {
        if (!nfs_obj_find(dev, id))
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

int nfs_obj_read_hdr(nfs_dev_t *dev, int chunk_in_nand,
                     nfs_obj_hdr_t *hdr, nfs_ext_tags_t *ext)
{
    return nfs_chunk_read(dev, chunk_in_nand,
                          hdr ? (nfs_u8 *)hdr : NFS_NULL,
                          hdr ? (int)sizeof(nfs_obj_hdr_t) : 0,
                          ext);
}

int nfs_obj_write_hdr(nfs_dev_t *dev, nfs_obj_t *obj,
                      nfs_obj_hdr_t *hdr, int old_chunk)
{
    nfs_ext_tags_t ext;
    int            new_chunk;
    int            rc;

    memset(&ext, 0, sizeof(ext));
    ext.chunk_used       = 1;
    ext.obj_id           = obj->obj_id;
    ext.chunk_id         = 0;            /* object header */
    ext.n_bytes          = 0xffff;
    ext.extra_available  = 1;
    ext.extra_obj_type   = (nfs_obj_type_t)obj->obj_type;
    ext.extra_parent_id  = obj->parent ? obj->parent->obj_id : 0;

    if (obj->obj_type == NFS_OBJ_TYPE_FILE) {
        ext.extra_file_size = obj->var.file.stored_size;
    }

    new_chunk = nfs_alloc_chunk(dev, 0);
    if (new_chunk < 0)
        return NFS_ENOSPC;

    rc = nfs_chunk_write(dev, new_chunk,
                         (const nfs_u8 *)hdr,
                         (int)sizeof(nfs_obj_hdr_t),
                         &ext);
    if (rc != NFS_OK)
        return rc;

    if (old_chunk > 0)
        nfs_chunk_delete(dev, old_chunk, 1);

    obj->hdr_chunk = new_chunk;
    return NFS_OK;
}

void nfs_obj_make_hdr(const nfs_dev_t *dev, const nfs_obj_t *obj,
                      nfs_obj_hdr_t *hdr)
{
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

    strncpy(hdr->name, obj->short_name, NFS_MAX_NAME_LEN);
    hdr->name[NFS_MAX_NAME_LEN] = '\0';

    if (obj->obj_type == NFS_OBJ_TYPE_FILE) {
        hdr->file_size_low  = (nfs_u32)(obj->var.file.stored_size & 0xffffffffu);
        hdr->file_size_high = (nfs_u32)(obj->var.file.stored_size >> 32);
    } else if (obj->obj_type == NFS_OBJ_TYPE_SYMLINK) {
        if (obj->var.symlink.alias)
            strncpy(hdr->alias, obj->var.symlink.alias, NFS_MAX_ALIAS_LEN);
        hdr->alias[NFS_MAX_ALIAS_LEN] = '\0';
    } else if (obj->obj_type == NFS_OBJ_TYPE_HARDLINK) {
        hdr->equiv_id = (nfs_s32)obj->var.hardlink.equiv_id;
    }
}

void nfs_obj_load_hdr(nfs_dev_t *dev, nfs_obj_t *obj,
                      const nfs_obj_hdr_t *hdr,
                      const nfs_ext_tags_t *ext,
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

    nfs_obj_cache_name(obj, hdr->name);

    if (obj->obj_type == NFS_OBJ_TYPE_FILE) {
        nfs_off_t sz = (nfs_off_t)hdr->file_size_high << 32
                       | (nfs_off_t)hdr->file_size_low;
        obj->var.file.stored_size = sz;
        obj->var.file.file_size   = sz;
    } else if (obj->obj_type == NFS_OBJ_TYPE_SYMLINK) {
        /* Alias stored in hdr.alias */
        size_t len = strlen(hdr->alias) + 1;
        obj->var.symlink.alias = (char *)dev->drv.malloc(dev->drv.ctx, len);
        if (obj->var.symlink.alias)
            memcpy(obj->var.symlink.alias, hdr->alias, len);
    } else if (obj->obj_type == NFS_OBJ_TYPE_HARDLINK) {
        obj->var.hardlink.equiv_id = (nfs_u32)hdr->equiv_id;
    }

    (void)ext;
}

int nfs_obj_update_hdr(nfs_dev_t *dev, nfs_obj_t *obj)
{
    nfs_obj_hdr_t hdr;
    int           old = obj->hdr_chunk;

    nfs_obj_make_hdr(dev, obj, &hdr);
    return nfs_obj_write_hdr(dev, obj, &hdr, old);
}

/*===================================================================
 *  Object hierarchy
 *===================================================================*/

void nfs_obj_add_child(nfs_obj_t *parent, nfs_obj_t *obj)
{
    if (!parent || parent->obj_type != NFS_OBJ_TYPE_DIR)
        return;
    obj->parent = parent;
    nfs_list_add_tail(&parent->var.dir.children, &obj->siblings);
}

void nfs_obj_remove_child(nfs_obj_t *parent, nfs_obj_t *obj)
{
    if (!parent)
        return;
    nfs_list_del(&obj->siblings);
    nfs_list_init(&obj->siblings);
    obj->parent = NFS_NULL;
}

nfs_obj_t *nfs_obj_find_by_name(nfs_dev_t *dev, nfs_obj_t *parent,
                                const char *name)
{
    nfs_obj_t *child;

    if (!parent || parent->obj_type != NFS_OBJ_TYPE_DIR)
        return NFS_NULL;

    nfs_list_for_each_entry(child, &parent->var.dir.children, siblings) {
        const char *cname = nfs_obj_get_name(dev, child);
        if (cname && strcmp(cname, name) == 0)
            return child;
    }
    return NFS_NULL;
}

/*===================================================================
 *  Name handling
 *===================================================================*/

void nfs_obj_cache_name(nfs_obj_t *obj, const char *name)
{
    if (!name)
        return;
    strncpy(obj->short_name, name, NFS_SHORT_NAME_LEN);
    obj->short_name[NFS_SHORT_NAME_LEN] = '\0';
}

const char *nfs_obj_get_name(nfs_dev_t *dev, nfs_obj_t *obj)
{
    (void)dev;
    return obj->short_name;
}
