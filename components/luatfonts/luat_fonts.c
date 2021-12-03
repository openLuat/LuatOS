#include "luat_base.h"
#include "luat_fonts.h"

#define LUAT_FONT_CUSTOM_FONT_MAX 8

#define LUAT_LOG_TAG "fonts"
#include "luat_log.h"

extern const luat_fonts_t luat_fonts_8p;
extern const luat_fonts_t luat_fonts_12p;
extern const luat_fonts_t luat_fonts_16p;
extern const luat_fonts_t luat_fonts_20p;
extern const luat_fonts_t luat_fonts_24p;
extern const luat_fonts_t luat_fonts_28p;

static const luat_fonts_t* const_fonts[] = {
#ifdef LUAT_FONTS_BASE_8P
    &luat_fonts_8p,
#endif
#ifdef LUAT_FONTS_BASE_12P
    &luat_fonts_12p,
#endif
#ifdef LUAT_FONTS_BASE_16P
    &luat_fonts_16p,
#endif
#ifdef LUAT_FONTS_BASE_20P
    &luat_fonts_20p,
#endif
#ifdef LUAT_FONTS_BASE_24P
    &luat_fonts_24p,
#endif
#ifdef LUAT_FONTS_BASE_28P
    &luat_fonts_28p,
#endif
    NULL
};

static luat_fonts_t dym_fonts[LUAT_FONT_CUSTOM_FONT_MAX] = {0};

int luat_font_get(int font_id, const uint32_t chr, luat_font_data_t* data) {
    if (font_id < 0)
        return -1;
    if (font_id < 64) {
        for (size_t i = 0; i < 64; i++)
        {
            if (const_fonts[i] == NULL)
                break;
            return const_fonts[i]->loader(chr, data, const_fonts[i]->font_size, const_fonts[i]);
        }
        return -1;
    }
    font_id -= 64;
    for (size_t i = 0; i < LUAT_FONT_CUSTOM_FONT_MAX; i++)
    {
        if (dym_fonts[i].loader) {
            return dym_fonts[i].loader(chr, data, dym_fonts[i].font_size, dym_fonts[i].userdata);
        }
    }
    return -1;
}

int luat_font_register(luat_font_loader_get loader, void* ptr) {
    for (size_t i = 0; i < LUAT_FONT_CUSTOM_FONT_MAX; i++)
    {
        if (dym_fonts[i].loader == NULL) {
            dym_fonts[i].loader = loader;
            dym_fonts[i].userdata = ptr;
            return i + 64;
        }
    }
    return -1;
}

int const_gb2312_font_loader(const uint32_t chr, luat_font_data_t* data, size_t font_size, void* ptr) {
    const luat_fonts_t* font = (const luat_fonts_t*)ptr;
    // 当前仅支持UNICODE, TODO 在这里做UTF转UNICODE
    //uint16_t unicode = (uint16_t)chr; 

    // 然后, 转gb2312
    //uint16_t gb2312 = luat_font_unicode_gb2312((unsigned short)unicode);

    // 直接输入gb2312, 测试一下可行性
    uint16_t gb2312 = (uint16_t)chr;

    font_size = font->font_size; // 固定大小, 需要覆盖掉

    // 检查是否合法

    
    // 计算 - 区
    uint8_t zone = gb2312 >> 8;
    if (zone <= 0xA0) {
        LLOGW("bad gb2312 code? %04X", gb2312);
        return -1;
    }
    zone = zone - 0xA0;

    if (zone < 0x10) {
        // TODO 支持 ASCII的可见字符集.
        LLOGW("only chinese yet. %04X", gb2312);
        return -2;
    }

    // 计算 - 位
    uint8_t zpos = gb2312 & 0xFF;
    if (zpos <= 0xA0) {
        LLOGW("bad gb2312 code? %04X", gb2312);
        return -1;
    }
    zpos -= 0xA0;
    LLOGD("gb2312 zone %d pos %d", zone, zpos);

#if 0
    if (zone < 10) { // 非汉字区, 1区 ~ 9区
        // 原样
    }
    else {
        zone -= 6; // 汉字区, 16区~87区, 往前对齐到11区
    }
#else
    zone = zone - (0x10 - 1); // 仅汉字.
#endif

    // 所以, 区/位均以1开始, 而偏移量从0开始,所以总的偏移量
    // 因为当前仅汉字区,而汉字从0xB0开始
    size_t pos = (zone - 1) * 94 + zpos - 1;

    LLOGD("gb2312 pos 0x%04X", pos);

    // 然后按照字体的像素, 计算每个字的bit位
    pos = pos * font_size * font_size / 8;

    data->w = font_size;
    data->len = font_size*font_size/8;

    LLOGD("gb2312 pos 0x%04X w %d len %d font_size %d", pos, data->w, data->len, font_size);

    memcpy(data->buff, (uint8_t*)(((uint8_t*)font->userdata) + pos), data->len);
    return 0;
}
