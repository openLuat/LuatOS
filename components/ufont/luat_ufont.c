#include "luat_base.h"
#include "luat_ufont.h"

#define LUAT_LOG_TAG "fonts"
#include "luat_log.h"

extern const uint16_t luat_font_map_gb2312_data[];

static int binsearch(const uint16_t *sortedSeq, int seqLength, uint16_t keyData) {
    int low = 0, mid, high = seqLength - 1;
    while (low <= high) {
        mid = (low + high)>>1;//右移1位等于是/2，奇数，无论奇偶，有个值就行
        if (keyData < sortedSeq[mid]) {
            high = mid - 1;//是mid-1，因为mid已经比较过了
        }
        else if (keyData > sortedSeq[mid]) {
            low = mid + 1;
        }
        else {
            return mid;
        }
    }
    return -1;
}

int luat_font_get_bitmap(luat_font_header_t *font, luat_font_char_desc_t *dsc_out, uint32_t letter) {
    if (font == NULL) {
        LLOGW("font is NULL");
        return -1;
    }
    if (dsc_out == NULL) {
        LLOGW("dsc_out is NULL");
        return -2;
    }
    
    // 暂时只支持内存访问模式, 就先拦截掉其他的吧
    //LLOGD("font search letter %04X", letter);
    //LLOGD("font access_mode %02X", font->access_mode);
    //LLOGD("font font_data_count %02X", font->font_data_count);
    if (font->access_mode != 0x01) {
        LLOGW("only ram access mode is supported, for now");
        return -3;
    }
    int data_count = font->font_data_count;
    luat_font_data_t* font_data = ((luat_font_desc_t*)font)->datas;

    // 准备2个指针数组, 把map和bitmap的位置先指出来
    // uint8_t *map_ptr[4] = {0};
    // uint8_t *bitmap_ptr = NULL;
    // size_t map_data_count = 0;
    // for (size_t i = 0; i < data_count; i++)
    // {
    //     if (font_data->map_type == 0x0001) {
    //         // 仅map_type == 1 时自带映射数据
    //         map_data_count += font_data->unicode_size * font_data->count;
    //     }
    // }
    // bitmap_ptr = ((uint8_t*)font + sizeof(luat_font_header_t) + sizeof(luat_font_data_t) * data_count + map_data_count);

    // 根据unicode的范围, 看看letter在哪个
    int map_offset = 0;
    for (size_t i = 0; i < data_count; i++)
    {
        // 暂时只支持2字节的unicode map
        //LLOGD("font_data->unicode_min %04X", font_data->unicode_min);
        //LLOGD("font_data->unicode_max %04X", font_data->unicode_max);
        //LLOGD("font_data->map_type %04X", font_data->map_type);
        if (font_data->unicode_min <= letter && font_data->unicode_max >= letter) {
            // 范围以内, 开始找索引值
            if (font_data->map_type == 0x01) {
                LLOGD("map_type 0x01 not support yet");
                return -12;
            }
            // 英文字符
            else if (font_data->map_type == 0x02) {
                // letter必然在 32 ~ 127 之间, 直接索引到点阵数据就行
                //dsc_out->data = bitmap_ptr + (font_data->bitmap_size * (letter - 32));
                dsc_out->len = font_data->bitmap_size;
                dsc_out->char_w = font_data->char_w_bit;
                dsc_out->data = font_data->bitmap_data + (font_data->bitmap_size * (letter - 32));
                return 0;
            }
            else if (font_data->map_type == 0x03) {
                map_offset = binsearch(luat_font_map_gb2312_data, font_data->count, (uint16_t)letter);
                if (map_offset < 0) {
                    LLOGD("font map-data NOT match %04X", letter);
                    return -11;
                }
                // else {
                //     LLOGD("font gb2312 %04X %04X", letter, map_offset);
                // }
                dsc_out->len = font_data->bitmap_size;
                dsc_out->char_w = font_data->char_w_bit;
                dsc_out->data = font_data->bitmap_data + (map_offset * ((font->line_height * font->line_height + 7) / 8));
                return 0;
            }
            else {
                LLOGD("map_type 0x%02X not support yet", font_data->map_type);
                return -33;
            }
        }

        // bitmap_ptr += font_data->count * font_data->bitmap_size;
        font_data ++;
    }
    //LLOGW("not such unicode in font %p %04X", font, letter);
    // 找不到
    return -32;
}


uint16_t luat_utf8_next(uint8_t b, uint8_t *utf8_state, uint16_t *encoding)
{
  if ( b == 0 )  /* '\n' terminates the string to support the string list procedures */
    return 0x0ffff; /* end of string detected, pending UTF8 is discarded */
  if ( *utf8_state == 0 )
  {
    if ( b >= 0xfc )  /* 6 byte sequence */
    {
      *utf8_state = 5;
      b &= 1;
    }
    else if ( b >= 0xf8 )
    {
      *utf8_state = 4;
      b &= 3;
    }
    else if ( b >= 0xf0 )
    {
      *utf8_state = 3;
      b &= 7;
    }
    else if ( b >= 0xe0 )
    {
      *utf8_state = 2;
      b &= 15;
    }
    else if ( b >= 0xc0 )
    {
      *utf8_state = 1;
      b &= 0x01f;
    }
    else
    {
      /* do nothing, just use the value as encoding */
      return b;
    }
    *encoding = b;
    return 0x0fffe;
  }
  else
  {
    *utf8_state = *utf8_state - 1;
    /* The case b < 0x080 (an illegal UTF8 encoding) is not checked here. */
    *encoding= (*encoding) << 6;
    b &= 0x03f;
    *encoding = (*encoding) | b;
    if ( *utf8_state != 0 )
      return 0x0fffe; /* nothing to do yet */
  }
  return *encoding;
}
