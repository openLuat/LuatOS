#include "luat_base.h"
#include "luat_display.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "display_fb"
#include "luat_log.h"

int luat_display_fb_probe_default(luat_display_t *disp, luat_display_fb_info_t *info) {
    if (info == NULL) {
        return -1;
    }
    if (disp->fb_info.addr != NULL) {
        memcpy(info, &disp->fb_info, sizeof(luat_display_fb_info_t));
        return 0;
    }
    memset(info, 0, sizeof(luat_display_fb_info_t));
    return 0;
}

int luat_display_fb_allocate_default(luat_display_t *disp, uint32_t num_buffers) {
    if (num_buffers == 0) {
        num_buffers = 1;
    }
    uint32_t buf_size = disp->width * disp->height * (disp->bpp / 8);
    if (buf_size == 0) {
        buf_size = disp->width * disp->height * 2;
    }

    disp->fb_info.addr = luat_heap_opt_malloc(LUAT_HEAP_PSRAM, buf_size);
    if (disp->fb_info.addr == NULL) {
        LLOGW("psram alloc FB failed, try sram");
        disp->fb_info.addr = luat_heap_opt_malloc(LUAT_HEAP_SRAM, buf_size);
    }
    if (disp->fb_info.addr == NULL) {
        LLOGE("FB alloc failed");
        return -1;
    }
    memset(disp->fb_info.addr, 0, buf_size);

    disp->fb_info.size = buf_size;
    disp->fb_info.count = 1;
    disp->fb_info.stride = disp->width * (disp->bpp / 8);
    disp->fb_info.active_idx = 0;

    if (num_buffers > 1) {
        disp->fb_info.addr_ex = luat_heap_opt_malloc(LUAT_HEAP_PSRAM, buf_size);
        if (disp->fb_info.addr_ex == NULL) {
            LLOGW("second FB alloc failed, single buffer mode");
        } else {
            memset(disp->fb_info.addr_ex, 0, buf_size);
            disp->fb_info.count = 2;
        }
    }

    return 0;
}
