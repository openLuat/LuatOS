#include "luat_audio_driver.h"
#include "luat_rtos.h"
#include "luat_mem.h"

int luat_audio_driver_fill_default(struct luat_audio_driver_ctrl *ctrl, uint8_t *play_buff, uint32_t len_bytes, uint8_t is_signed, uint8_t align)
{
    luat_data_union_t data;
    uint32_t data_address = (uint32_t)play_buff;
    uint32_t data_len;
    data.p8 = (uint8_t *)data_address;
    if (is_signed) {
        memset(play_buff, 0, len_bytes);
    } else {
        switch (align) {
            case 2:
                data_address &= ~0x1;
                data.p16 = (uint16_t *)data_address;
                data_len = len_bytes >> 1;
                for(uint32_t i = 0; i < data_len; i++)
                {
                    data.p16[i] = 0x8000;
                }
                break;
            case 3:
            case 4:
                data_address &= ~0x3;
                data.p32 = (uint32_t *)data_address;
                data_len = len_bytes >> 2;
                uint32_t fill_data = align == 4 ? 0x80000000 : 0x00800000;
                for(uint32_t i = 0; i < data_len; i++)
                {
                    data.p32[i] = fill_data;
                }
                break;
            default:
                memset(play_buff, 0x80, len_bytes);
                break;
        }
    }
    return 0;
}