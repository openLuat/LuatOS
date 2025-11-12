/*
 * pinyin库核心实现
 */

#include "luat_base.h"
#include "luat_pinyin.h"
#include "pinyin_dict.h"
#include "valid_syllables.h"
#include <string.h>

#define LUAT_LOG_TAG "pinyin"
#include "luat_log.h"

/**
 * @brief 二分查找拼音条目（数组已按拼音排序）
 * @param pinyin 拼音字符串
 * @return 找到返回条目指针，未找到返回NULL
 */
static const pinyin_entry_t *find_pinyin_entry(const char *pinyin)
{
    if (!pinyin || !*pinyin) {
        return NULL;
    }
    
    int left = 0;
    int right = PINYIN_DICT_SIZE - 1;
    
    while (left <= right) {
        int mid = (left + right) / 2;
        int cmp = strcmp(pinyin_dict[mid].pinyin, pinyin);
        
        if (cmp == 0) {
            return &pinyin_dict[mid];
        } else if (cmp < 0) {
            left = mid + 1;
        } else {
            right = mid - 1;
        }
    }
    
    return NULL;  // 未找到
}

/**
 * @brief 初始化pinyin库（预留接口）
 */
int luat_pinyin_init(void)
{
    // 当前无需初始化，数据是静态的
    return 0;
}

/**
 * @brief 将Unicode码点转换为UTF-8字符串
 * @param codepoint Unicode码点
 * @param utf8_buf 输出缓冲区（至少5字节）
 * @return UTF-8字节数，失败返回0
 */
int luat_pinyin_codepoint_to_utf8(uint32_t codepoint, char *utf8_buf)
{
    if (!utf8_buf) {
        return 0;
    }
    
    if (codepoint <= 0x7F) {
        // 1字节：0xxxxxxx
        utf8_buf[0] = (char)codepoint;
        utf8_buf[1] = '\0';
        return 1;
    } else if (codepoint <= 0x7FF) {
        // 2字节：110xxxxx 10xxxxxx
        utf8_buf[0] = (char)(0xC0 | (codepoint >> 6));
        utf8_buf[1] = (char)(0x80 | (codepoint & 0x3F));
        utf8_buf[2] = '\0';
        return 2;
    } else if (codepoint <= 0xFFFF) {
        // 3字节：1110xxxx 10xxxxxx 10xxxxxx
        utf8_buf[0] = (char)(0xE0 | (codepoint >> 12));
        utf8_buf[1] = (char)(0x80 | ((codepoint >> 6) & 0x3F));
        utf8_buf[2] = (char)(0x80 | (codepoint & 0x3F));
        utf8_buf[3] = '\0';
        return 3;
    } else if (codepoint <= 0x10FFFF) {
        // 4字节：11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
        utf8_buf[0] = (char)(0xF0 | (codepoint >> 18));
        utf8_buf[1] = (char)(0x80 | ((codepoint >> 12) & 0x3F));
        utf8_buf[2] = (char)(0x80 | ((codepoint >> 6) & 0x3F));
        utf8_buf[3] = (char)(0x80 | (codepoint & 0x3F));
        utf8_buf[4] = '\0';
        return 4;
    }
    
    return 0;  // 无效的码点
}

/**
 * @brief 查询拼音对应的候选字Unicode码点数组
 */
int luat_pinyin_query(const char *pinyin, const uint32_t **codepoints, uint16_t *count)
{
    if (!pinyin || !codepoints || !count) {
        return -1;
    }
    
    const pinyin_entry_t *entry = find_pinyin_entry(pinyin);
    if (!entry) {
        *codepoints = NULL;
        *count = 0;
        return -1;
    }
    
    *codepoints = entry->codepoints;
    *count = entry->count;
    return 0;
}

/**
 * @brief 查询拼音对应的候选字UTF-8字符串数组
 * @param pinyin 拼音字符串（小写，无声调）
 * @param utf8_strings 输出参数：UTF-8字符串数组（需要调用者分配内存）
 * @param max_count 最大字符串数量（数组大小）
 * @param count 输出参数：实际返回的字符串数量
 * @return 0表示成功，-1表示失败
 * 
 * 注意：调用者需要分配足够的内存来存储UTF-8字符串。
 * 每个字符串最多4字节UTF-8编码 + 1字节'\0' = 5字节
 * 建议分配: char utf8_strings[max_count][5]
 */
int luat_pinyin_query_utf8(const char *pinyin, char (*utf8_strings)[5], uint16_t max_count, uint16_t *count)
{
    if (!pinyin || !utf8_strings || !count || max_count == 0) {
        return -1;
    }
    
    const uint32_t *codepoints = NULL;
    uint16_t codepoint_count = 0;
    
    int ret = luat_pinyin_query(pinyin, &codepoints, &codepoint_count);
    if (ret != 0 || !codepoints || codepoint_count == 0) {
        *count = 0;
        return -1;
    }
    
    // 转换码点为UTF-8字符串
    uint16_t actual_count = (codepoint_count < max_count) ? codepoint_count : max_count;
    for (uint16_t i = 0; i < actual_count; i++) {
        luat_pinyin_codepoint_to_utf8(codepoints[i], utf8_strings[i]);
    }
    
    *count = actual_count;
    return 0;
}

/**
 * @brief 检查字符串是否在valid_syllables数组中（线性查找）
 * @param syllable 要查找的音节字符串
 * @return 如果找到返回1，否则返回0
 * 
 * 注意：valid_syllables数组是按常用度排序的，不是按字母顺序，
 * 因此不能使用二分查找，必须使用线性查找
 */
static int is_valid_syllable(const char *syllable)
{
    if (!syllable || !*syllable) {
        return 0;
    }
    
    // 线性查找（因为valid_syllables按常用度排序，不是按字母顺序）
    for (int i = 0; i < VALID_SYLLABLES_SIZE; i++) {
        if (strcmp(valid_syllables[i], syllable) == 0) {
            return 1;  // 找到
        }
    }
    
    return 0;  // 未找到
}

/**
 * @brief 递归枚举所有可能的字母组合
 * @param key_sequence 按键序列
 * @param key_count 按键序列长度
 * @param depth 当前深度（递归参数）
 * @param buffer 当前组合缓冲区
 * @param buffer_pos 缓冲区当前位置
 * @param syllables 输出音节数组
 * @param syllable_count 当前音节数量（输入输出参数）
 * @param max_syllable_count 最大音节数量
 */
static void enumerate_combinations(
    const uint8_t *key_sequence,
    uint8_t key_count,
    uint8_t depth,
    char *buffer,
    uint8_t buffer_pos,
    char (*syllables)[8],
    uint16_t *syllable_count,
    uint16_t max_syllable_count
)
{
    // 如果已经达到最大音节数量，停止枚举
    if (*syllable_count >= max_syllable_count) {
        return;
    }
    
    // 如果已经处理完所有按键
    if (depth >= key_count) {
        if (buffer_pos > 0) {
            // 检查当前组合是否是合法音节
            buffer[buffer_pos] = '\0';
            if (is_valid_syllable(buffer)) {
                // 检查是否已存在（避免重复）
                int found = 0;
                for (uint16_t i = 0; i < *syllable_count; i++) {
                    if (strcmp(syllables[i], buffer) == 0) {
                        found = 1;
                        break;
                    }
                }
                if (!found) {
                    strncpy(syllables[*syllable_count], buffer, 7);
                    syllables[*syllable_count][7] = '\0';
                    (*syllable_count)++;
                }
            }
        }
        return;
    }
    
    // 获取当前按键对应的字母串
    uint8_t key_id = key_sequence[depth];
    if (key_id < 1 || key_id > 8) {
        return;  // 无效按键ID
    }
    
    const char *letters = KEY_TO_LETTERS[key_id];
    if (!letters) {
        return;
    }
    
    // 枚举当前按键对应的所有字母
    for (const char *p = letters; *p != '\0'; p++) {
        // 缓冲区空间检查（最多7个字母）
        if (buffer_pos >= 7) {
            continue;
        }
        
        buffer[buffer_pos] = *p;
        
        // 递归处理下一个按键
        enumerate_combinations(
            key_sequence,
            key_count,
            depth + 1,
            buffer,
            buffer_pos + 1,
            syllables,
            syllable_count,
            max_syllable_count
        );
    }
}

/**
 * @brief 根据按键序列查询可能的音节列表（9键输入法）
 */
int luat_pinyin_query_syllables_by_keys(
    const uint8_t *key_sequence, 
    uint8_t key_count,
    char (*syllables)[8],
    uint16_t max_syllable_count,
    uint16_t *actual_count
)
{
    if (!key_sequence || !syllables || !actual_count || max_syllable_count == 0) {
        return -1;
    }
    
    // 限制按键序列最大长度为5
    if (key_count == 0 || key_count > 5) {
        *actual_count = 0;
        return -1;
    }
    
    // 验证按键ID有效性
    for (uint8_t i = 0; i < key_count; i++) {
        if (key_sequence[i] < 1 || key_sequence[i] > 8) {
            *actual_count = 0;
            return -1;
        }
    }
    
    // 初始化输出
    *actual_count = 0;
    
    // 枚举所有可能的字母组合
    char buffer[8] = {0};  // 临时缓冲区（最多7个字母+'\0'）
    enumerate_combinations(
        key_sequence,
        key_count,
        0,
        buffer,
        0,
        syllables,
        actual_count,
        max_syllable_count
    );
    
    // 按valid_syllables数组中的顺序排序结果（常用度排序）
    // 先构建索引映射，然后使用简单排序
    if (*actual_count > 1) {
        // 为每个匹配的音节查找索引
        int16_t indices[100];  // 假设最多100个音节
        if (*actual_count <= 100) {
            for (uint16_t i = 0; i < *actual_count; i++) {
                indices[i] = -1;
                // 二分查找索引
                int left = 0;
                int right = VALID_SYLLABLES_SIZE - 1;
                while (left <= right) {
                    int mid = (left + right) / 2;
                    int cmp = strcmp(valid_syllables[mid], syllables[i]);
                    if (cmp == 0) {
                        indices[i] = mid;
                        break;
                    } else if (cmp < 0) {
                        left = mid + 1;
                    } else {
                        right = mid - 1;
                    }
                }
            }
            
            // 使用简单冒泡排序按索引排序
            for (uint16_t i = 0; i < *actual_count - 1; i++) {
                for (uint16_t j = 0; j < *actual_count - 1 - i; j++) {
                    if (indices[j] > indices[j + 1] && indices[j] >= 0 && indices[j + 1] >= 0) {
                        // 交换索引
                        int16_t temp_idx = indices[j];
                        indices[j] = indices[j + 1];
                        indices[j + 1] = temp_idx;
                        // 交换音节
                        char temp[8];
                        strncpy(temp, syllables[j], 8);
                        strncpy(syllables[j], syllables[j + 1], 8);
                        strncpy(syllables[j + 1], temp, 8);
                    }
                }
            }
        }
    }
    
    return 0;
}

