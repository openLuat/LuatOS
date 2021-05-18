
#
#include "luat_base.h"
#include "luat_sfd.h"
#include "luat_spi.h"
#include "luat_gpio.h"
#include "luat_malloc.h"

#include "lfs.h"

#define LUAT_LOG_TAG "lfs2"
#include "luat_log.h"

int lfs_sfd_read(const struct lfs_config *c, lfs_block_t block, lfs_off_t off, void *buffer, lfs_size_t size) {
    sfd_w25q_t *w25q = (sfd_w25q_t *)c->context;
    return w25q->opts->read(w25q, buffer, block*4096+off, size);
}

    // Program a region in a block. The block must have previously
    // been erased. Negative error codes are propogated to the user.
    // May return LFS_ERR_CORRUPT if the block should be considered bad.
int lfs_sfd_prog(const struct lfs_config *c, lfs_block_t block, lfs_off_t off, const void *buffer, lfs_size_t size) {
    sfd_w25q_t *w25q = (sfd_w25q_t *)c->context;
    return w25q->opts->write(w25q, buffer, block*4096+off, size);
}

    // Erase a block. A block must be erased before being programmed.
    // The state of an erased block is undefined. Negative error codes
    // are propogated to the user.
    // May return LFS_ERR_CORRUPT if the block should be considered bad.
int lfs_sfd_erase(const struct lfs_config *c, lfs_block_t block) {
    sfd_w25q_t *w25q = (sfd_w25q_t *)c->context;
    return w25q->opts->erase(w25q, block*4096, 4096);
}

    // Sync the state of the underlying block device. Negative error codes
    // are propogated to the user.
int lfs_sfd_sync(const struct lfs_config *c) {
    sfd_w25q_t *w25q = (sfd_w25q_t *)c->context;
    //w25q->opts->ioctl(w25q, ???);
    return 0;
}
