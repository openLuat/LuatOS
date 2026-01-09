#ifndef LUAT_PINYIN_H
#define LUAT_PINYIN_H

#include "luat_base.h"
#include <stdint.h>
#include <stddef.h>

#include "luat_conf_bsp.h"
#ifdef LUAT_USE_EASYLVGL
#include "lvgl9/src/others/ime/lv_ime_pinyin.h"
#endif

/**
 * @brief 将Unicode码点转换为UTF-8字符串
 * @param codepoint Unicode码点
 * @param utf8_buf 输出缓冲区（至少5字节）
 * @return UTF-8字节数，失败返回0
 */
int luat_pinyin_codepoint_to_utf8(uint32_t codepoint, char *utf8_buf);

/**
 * @brief 初始化pinyin库（预留接口，当前无需初始化）
 * @return 0表示成功
 */
int luat_pinyin_init(void);

/**
 * @brief 查询拼音对应的候选字Unicode码点数组
 * @param pinyin 拼音字符串（小写，无声调）
 * @param codepoints 输出参数：码点数组指针
 * @param count 输出参数：候选字数量
 * @return 0表示找到，-1表示未找到
 */
int luat_pinyin_query(const char *pinyin, const uint32_t **codepoints, uint16_t *count);

/**
 * @brief 查询拼音对应的候选字UTF-8字符串数组
 * @param pinyin 拼音字符串（小写，无声调）
 * @param utf8_strings 输出参数：UTF-8字符串数组，每个字符串最多5字节（4字节UTF-8 + '\0'）
 * @param max_count 最大字符串数量（数组大小）
 * @param count 输出参数：实际返回的字符串数量
 * @return 0表示成功，-1表示失败
 */
int luat_pinyin_query_utf8(const char *pinyin, char (*utf8_strings)[5], uint16_t max_count, uint16_t *count);

/**
 * @brief 根据按键序列查询可能的音节列表（9键输入法）
 * @param key_sequence 按键序列数组，每个元素为按键ID（1-8对应ABC-WXYZ）
 * @param key_count 按键序列长度（最多5个）
 * @param syllables 输出参数：音节字符串数组（调用者需要分配内存）
 * @param max_syllable_count 最大音节数量（数组大小）
 * @param actual_count 输出参数：实际返回的音节数量
 * @return 0表示成功，-1表示失败
 * 
 * 按键ID映射：
 * 1 → ABC   (a, b, c)
 * 2 → DEF   (d, e, f)
 * 3 → GHI   (g, h, i)
 * 4 → JKL   (j, k, l)
 * 5 → MNO   (m, n, o)
 * 6 → PQRS  (p, q, r, s)
 * 7 → TUV   (t, u, v)
 * 8 → WXYZ  (w, x, y, z)
 * 
 * 示例：
 * 输入：key_sequence = [8, 3, 5, 5, 3] (对应 WXYZ, GHI, MNO, MNO, GHI)
 * 输出：可能的音节：["zhong", "zong", ...]（按常用度排序）
 */
int luat_pinyin_query_syllables_by_keys(
    const uint8_t *key_sequence, 
    uint8_t key_count,
    char (*syllables)[8],  // 每个音节最多7个字母+'\0'
    uint16_t max_syllable_count,
    uint16_t *actual_count
);

#ifdef LUAT_USE_EASYLVGL
/**
 * @brief 提供 EASYLVGL 拼音输入法所需的词典数组
 * @param count 输出参数，返回词典条目数量
 * @return 指向 EASYLVGL 词典数组的指针，失败返回 NULL
 */
const lv_pinyin_dict_t * luat_pinyin_get_lv_dict(size_t *count);
#endif  

#endif /* LUAT_PINYIN_H */

