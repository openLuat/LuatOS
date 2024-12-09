#ifndef LUAT_ROTSTR_H
#define LUAT_ROTSTR_H

#include "luat_base.h"
#include "lstring.h"

typedef struct luat_rostr
{
    // 标准头部, 12字节
    char magic[4];   // 魔数，固定为"ROST"
    uint8_t version; // 版本信息,从version 1开始, 1字节
    uint8_t revert[3];// 预留空间

    // 以下是版本1的定义
    // 首先是短字符串的信息
    uint32_t short_str_count; // 短字符串的总数量
    uint32_t short_str_len;   // 短字符串的总长度
    // 然后是长字符串的信息, 当前均为0, 后续再考虑
    uint32_t long_str_count;  // 长字符串的总数量
    uint32_t long_str_len;    // 长字符串的总长度
    
    //  每种长度的短字符串的字符串数量, 每个元素为uint16_t
    uint16_t short_str_len_count[40];
    
    // 后续是具体数据, 需要通过运算得到具体的区域,然后遍历里面的字符串
}luat_rostr_t;

typedef struct luat_rostr_short {
    TString str;
    char data[4]; // 注意, 实际长度为str.len + 1, 末尾必须是\0
    // 后面是字符串数据, 需要对其到4字节
    // 例如 存储 "abcd" 4个字符, 那么实际长度为 16字节(TString头部) + 4字节(实际数据) + 1字节(\0) = 24字节(21字节对齐到4字节)
}luat_rostr_short_t;

typedef struct luat_rostr_short8 {
    TString str;
    char data[8];
}luat_rostr_short8_t;
typedef struct luat_rostr_short12 {
    TString str;
    char data[12];
}luat_rostr_short12_t;
typedef struct luat_rostr_short16 {
    TString str;
    char data[16];
}luat_rostr_short16_t;
typedef struct luat_rostr_short20 {
    TString str;
    char data[20];
}luat_rostr_short20_t;
typedef struct luat_rostr_short24 {
    TString str;
    char data[24];
}luat_rostr_short24_t;
typedef struct luat_rostr_short44 {
    TString str;
    char data[44];
}luat_rostr_short44_t;

TString* luat_rostr_get(const char *val_str, size_t len);
GCObject* luat_rostr_get_gc(const char *val_str, size_t len);

#endif
