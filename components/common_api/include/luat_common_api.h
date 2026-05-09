#ifndef __LUAT_COMMON_API_H__
#define __LUAT_COMMON_API_H__

/**
 * @file luat_common_api.h
 * @brief LuatOS 通用 API 头文件
 *
 * 本文件提供 LuatOS 核心的通用数据结构实现，包括：
 * - 双向链表（doubly linked list）操作
 * - FIFO 队列（环形缓冲区实现）
 * - 动态缓冲区（可增长的字节缓冲区）
 *
 * @author openLuat
 * @date 2024
 * @version 1.0
 *
* @note 所有链表操作都是 O(1) 复杂度，适合嵌入式实时系统
 * @note FIFO 和缓冲区使用动态内存分配，需在结束时调用对应的销毁函数
 */

#include "string.h"
#include "stdint.h"
#include "stdio.h"

enum {
	LUAT_ERROR_NONE,
	LUAT_ERROR_NO_SUCH_ID,
	LUAT_ERROR_PERMISSION_DENIED,
	LUAT_ERROR_PARAM_INVALID,
	LUAT_ERROR_PARAM_OVERFLOW,
	LUAT_ERROR_DEVICE_BUSY,
	LUAT_ERROR_OPERATION_FAILED,
	LUAT_ERROR_BUFFER_FULL,
	LUAT_ERROR_NO_MEMORY,
	LUAT_ERROR_CMD_NOT_SUPPORT,
	LUAT_ERROR_NO_DATA,
	LUAT_ERROR_NO_FLASH,
	LUAT_ERROR_NO_TIMER,
	LUAT_ERROR_TIMEOUT,
	LUAT_ERROR_SSL_HANDSHAKE,
	LUAT_ERROR_PROTOCL,
	LUAT_ERROR_ID_INVALID,
	LUAT_ERROR_MID_INVALID,
	LUAT_ERROR_RETRY_TOO_MUCH,
	LUAT_ERROR_CMD_BLOCK,
	LUAT_LIST_FIND = 1,
	LUAT_LIST_PASS = 0,
	LUAT_LIST_DEL = -1,
};
typedef union {
	uint8_t u8[4];
	uint16_t u16[2];
	uint32_t u32;
    uint8_t *p8;
    uint16_t *p16;
    uint32_t *p32;
	void *p;
}luat_data_union_t;

typedef int(*luat_llist_traversal_fun)(void *node, void *param);
/**
 * @brief 双向链表节点结构
 *
 * 双向链表节点，包含指向前驱和后继节点的指针。
 * 使用此结构可以将任意类型的数据组织成双向链表。
 *
 * @note 这是一个嵌入到其他结构中的链表节点，需要在宿主结构中声明此成员
 * @par 使用示例:
 * @code
 * typedef struct my_data {
 *     int value;
 *     luat_llist_head list;  // 链表节点
 * } my_data_t;
 * @endcode
 */
typedef struct luat_llist_head_t{
    struct luat_llist_head_t *next, *prev;
}luat_llist_head;

/**
 * @brief 初始化链表头
 *
 * 将链表头节点初始化为指向自身的循环链表（空链表）
 * @param ptr 指向链表头节点的指针
 *
 * @note 初始化后链表中只有头节点本身，next 和 prev 都指向自己
 */
#define LUAT_INIT_LLIST_HEAD(ptr) do { \
	(ptr)->next = (ptr); (ptr)->prev = (ptr); \
} while (0)

/**
 * @brief 内部链表添加函数
 * 
 * 在 prev 和 next 节点之间插入新节点 p
 * @param p 要插入的新节点
 * @param prev 前驱节点
 * @param next 后继节点
 */
static inline void __luat_llist_add(luat_llist_head *p,
                         luat_llist_head *prev,
                         luat_llist_head *next)
{
	next->prev = p;
	p->next = next;
	p->prev = prev;
	prev->next = p;
}

/**
 * @brief 添加新节点到链表头部
 *
 * 在指定头节点之后插入新节点，相当于添加到链表头部。
 * @param p 要添加的新节点
 * @param head 链表头节点
 *
 * @note 如果需要在链表头部插入，使用 luat_llist_add_tail
 * @par 示例:
 * @code
 * luat_llist_add(new_node, &queue_head);  // 添加到头部
 * @endcode
 */
static inline void luat_llist_add(luat_llist_head *p, luat_llist_head *head)
{
	__luat_llist_add(p, head, head->next);
}

/**
 * @brief 添加新节点到链表尾部
 *
 * 在链表尾部（头节点之前）插入新节点。
 * @param p 要添加的新节点
 * @param head 链表头节点
 *
 * @note 这对实现 FIFO 队列（从尾部取数据）很有用
 * @par 示例:
 * @code
 * luat_llist_add_tail(new_node, &queue_head);  // 添加到尾部
 * @endcode
 */
static inline void luat_llist_add_tail(luat_llist_head *p, luat_llist_head *head)
{
	__luat_llist_add(p, head->prev, head);
}

/**
 * @brief 内部链表删除函数
 *
 * 通过使前驱和后继节点互相指向来删除链表节点。
 * @param prev 前驱节点
 * @param next 后继节点
 *
 * @note 这是内部函数，仅在已知前驱和后继节点时使用
 */
static inline void __luat_llist_del(luat_llist_head * prev, luat_llist_head * next)
{
	next->prev = prev;
	prev->next = next;
}

/**
 * @brief 从链表中删除节点
 *
 * 从链表中移除指定节点，但不对节点进行重新初始化。
 * 删除后节点仍保留原始指针值，需要手动置空。
 * @param entry 要删除的节点
 *
 * @note 删除后节点处于未定义状态，需要手动设置 prev 和 next 为 NULL
 * @warning 如果节点不在链表中，此函数不会执行任何操作
 * @par 示例:
 * @code
 * luat_llist_del(node);
 * node->prev = NULL;  // 需要手动置空
 * node->next = NULL;
 * @endcode
 */
static inline void luat_llist_del(luat_llist_head *entry)
{
	if (entry->prev && entry->next)
	{
		__luat_llist_del(entry->prev, entry->next);
	}
	entry->next = NULL;
	entry->prev = NULL;
}

/**
 * @brief 从链表中删除节点并重新初始化
 *
 * 从链表中删除节点，并将节点重新初始化为空链表。
 * 删除后节点可以重新添加到其他链表。
 * @param entry 要删除的节点
 *
 * @note 与 luat_llist_del 不同，此函数会将节点重新初始化
 * @par 示例:
 * @code
 * luat_llist_del_init(node);  // 删除并初始化为环
 * @endcode
 */
static inline void luat_llist_del_init(luat_llist_head *entry)
{
	__luat_llist_del(entry->prev, entry->next);
	LUAT_INIT_LLIST_HEAD(entry);
}

/**
 * @brief 将节点从一个链表移动到另一个链表的头部
 *
 * 从源链表中删除节点，并添加到目标链表的头部（head->next 位置）。
 * @param llist 要移动的节点
 * @param head 目标链表的头节点
 *
 * @note 这实际上是先删除再添加到头部的快捷操作
 * @par 示例:
 * @code
 * luat_llist_move(node, &target_queue);  // 移动到目标链表头部
 * @endcode
 */
static inline void luat_llist_move(luat_llist_head *llist, luat_llist_head *head)
{
	__luat_llist_del(llist->prev, llist->next);
	luat_llist_add(llist, head);
}

/**
 * @brief 将节点从一个链表移动到另一个链表的尾部
 *
 * 从源链表中删除节点，并添加到目标链表的尾部（head->prev 位置）。
 * @param llist 要移动的节点
 * @param head 目标链表的头节点
 *
 * @note 这实际上是先删除再添加到尾部的快捷操作
 * @par 示例:
 * @code
 * luat_llist_move_tail(node, &target_queue);  // 移动到目标链表尾部
 * @endcode
 */
static inline void luat_llist_move_tail(luat_llist_head *llist,
				  luat_llist_head *head)
{
	__luat_llist_del(llist->prev, llist->next);
	luat_llist_add_tail(llist, head);
}

/**
 * @brief 检查链表是否为空
 * @param head 链表头节点
 * @return 如果链表为空返回 1，否则返回 0
 */
static inline int luat_llist_empty(const luat_llist_head *head)
{
	return head->next == head;
}

void *luat_llist_traversal(luat_llist_head *head, luat_llist_traversal_fun cb, void *param);
/**
 * @brief FIFO 队列结构
 * 
 * 使用环形缓冲区实现的先进先出队列
 */
typedef struct
{
	uint64_t wpoint;    ///< 写指针位置
	uint64_t rpoint;    ///< 读指针位置
	uint64_t mask;      ///< 掩码，用于计算索引
	uint32_t size;      ///< 缓冲区实际大小（2的幂）
	uint8_t data[];     ///< 数据缓冲区
}luat_fifo_t;

/**
 * @brief 创建FIFO 队列
 * @param size_power 队列大小的幂（实际大小为 2^size_power）
 * @return 成功返回指向 FIFO 结构的指针，失败返回 NULL
 */
luat_fifo_t *luat_fifo_create(uint32_t size_power);

/**
 * @brief 向 FIFO 队列写入数据
 * @param fifo FIFO 队列指针
 * @param buf 要写入的数据缓冲区
 * @param size 要写入的数据大小（字节）
 * @return 实际写入的数据大小
 */
uint32_t luat_fifo_write(luat_fifo_t *fifo, const void *buf, uint32_t size);

/**
 * @brief 向 FIFO 队列填充指定值
 *
 * 将 FIFO 队列中的数据填充为指定值（常用于清零）。
 * @param fifo FIFO 队列指针
 * @param value 要填充的值（0-255）
 * @param size 要填充的字节数
 * @return 实际填充的字节数
 *
 * @note 当队列中数据不足 size 时，只填充实际存在的数据
 */
uint32_t luat_fifo_fill(luat_fifo_t *fifo, uint8_t value, uint32_t size);

/**
 * @brief 从 FIFO 队列读取数据
 *
 * 从 FIFO 队列读取数据，读取后数据会从队列中移除。
 * @param fifo FIFO 队列指针
 * @param buf 存储读取数据的缓冲区
 * @param size 要读取的字节数
 * @return 实际读取的字节数
 *
 * @note 读取后读指针向前移动，数据不再保留在队列中
 * @note 使用 luat_fifo_query 可以查看数据而不移除
 */
uint32_t luat_fifo_read(luat_fifo_t *fifo, uint8_t *buf, uint32_t size);

/**
 * @brief 查询 FIFO 队列中的数据（不移动读指针）
 *
 * 查看 FIFO 队列头部的数据，但不影响队列状态。
 * @param fifo FIFO 队列指针
 * @param buf 存储查询结果的缓冲区
 * @param size 要查询的字节数
 * @return 实际查询的字节数
 *
 * @note 与 luat_fifo_read 不同，此函数不会移除数据
 * @note 适合用于预览数据后再决定是否读取
 */
uint32_t luat_fifo_query(luat_fifo_t *fifo, uint8_t *buf, uint32_t size);

/**
 * @brief 检查 FIFO 队列剩余可用空间
 *
 * 查询 FIFO 队列还可以写入多少数据。
 * @param fifo FIFO 队列指针
 * @return 剩余可用空间大小（字节）
 *
 */
static inline uint32_t luat_fifo_check_free_space(luat_fifo_t *fifo)
{
	return (fifo->size - ((uint32_t)(fifo->wpoint - fifo->rpoint)));
}

static inline uint32_t luat_fifo_check_used_space(luat_fifo_t *fifo)
{
	return ((uint32_t)(fifo->wpoint - fifo->rpoint));
}

/**
 * @brief 删除 FIFO 队列中的数据（仅移动读指针）
 *
 * 跳过指定长度的数据，相当于丢弃队列头部数据。
 * @param fifo FIFO 队列指针
 * @param size 要删除的字节数
 *
 * @note 这只是移动读指针，不会真正删除数据区内容
 * @note 用于实现丢弃过期的数据
 */
void luat_fifo_delete(luat_fifo_t *fifo, uint32_t size);

/**
 * @brief 清空 FIFO 队列
 *
 * 重置读写指针，丢弃队列中的所有数据。
 * @param fifo FIFO 队列指针
 *
 * @note 清空后读写指针都回到起点，但数据内容仍然存在
 * @note 如果需要释放内存，使用 luat_fifo_destroy
 */
void luat_fifo_clear(luat_fifo_t *fifo);

/**
 * @brief 销毁 FIFO 队列
 *
 * 释放 FIFO 队列占用的内存。
 * @param fifo FIFO 队列指针
 *
 * @warning 调用此函数后不能再使用该 fifo 指针
 * @note 在程序结束或不再需要 FIFO 时调用
 */
void luat_fifo_destroy(luat_fifo_t *fifo);

/**
 * @brief 动态缓冲区结构
 *
 * 支持动态增长的字节缓冲区，用于存储二进制数据。
 * @note 内部使用 realloc 实现自动扩容
 * @par 使用示例:
 * @code
 * luat_buffer_t buf;
 * luat_buffer_init(&buf, 1024);  // 初始容量 1KB
 * luat_write_buffer(&buf, data, data_len);
 * // 使用 buf.data 和 buf.pos
 * luat_buffer_deinit(&buf);
 * @endcode
 */
typedef struct
{
	uint8_t *data;      ///< 实际数据缓冲区指针
	uint32_t pos;       ///< 当前数据位置/长度
	uint32_t max_len;   ///< 缓冲区总容量
}luat_buffer_t;

/**
 * @brief 初始化动态缓冲区
 *
 * 分配指定大小的缓冲区。
 * @param buffer 缓冲区结构指针
 * @param size 初始容量（字节）
 * @return 0 成功，-1 失败
 *
 * @note 使用完后必须调用 luat_buffer_deinit 释放内存
 */
int luat_buffer_init(luat_buffer_t *buffer, uint32_t size);

/**
 * @brief 销毁动态缓冲区
 *
 * 释放缓冲区占用的内存。
 * @param buffer 缓冲区结构指针
 *
 * @warning 调用后 buffer->data 将变为 NULL
 * @note 调用此函数后不能再使用该 buffer
 */
void luat_buffer_deinit(luat_buffer_t *buffer);

/**
 * @brief 重新初始化动态缓冲区
 *
 * 清空现有数据并重置缓冲区状态。
 * @param buffer 缓冲区结构指针
 * @param len 新的容量（字节）
 * @return 0 成功，-1 失败
 *
 * @note 与 luat_buffer_deinit + luat_buffer_init 等效，但更高效
 * @note 如果 len 小于当前数据长度，数据会被截断
 */
int luat_buffer_reinit(luat_buffer_t *buffer, uint32_t len);

/**
 * @brief 调整动态缓冲区容量
 *
 * 增大或减小缓冲区容量。
 * @param buffer 缓冲区结构指针
 * @param len 新的容量（字节）
 * @return 0 成功，-1 失败
 *
 * @note 即使失败，原有数据也会保留
 * @note 如果 len 小于当前数据长度，可能返回错误
 */
int luat_buffer_resize(luat_buffer_t *buffer, uint32_t len);

/**
 * @brief 向动态缓冲区写入数据
 *
 * 将数据追加到缓冲区末尾，自动扩容。
 * @param buffer 缓冲区结构指针
 * @param data 要写入的数据
 * @param len 要写入的数据长度
 * @return 0 成功，-1 失败
 *
 * @note 如果容量不足会自动扩容
 * @note 写入后数据追加到当前 pos 位置
 */
int luat_write_buffer(luat_buffer_t *buffer, const void *data, uint32_t len);

/**
 * @brief 从动态缓冲区移除头部数据
 *
 * 移除缓冲区开头的指定长度数据。
 * @param buffer 缓冲区结构指针
 * @param len 要移除的长度
 *
 * @note 数据会左移，pos 会相应减少
 * @note 如果 len >= pos，则清空整个缓冲区
 */
void luat_buffer_remove_data(luat_buffer_t *buffer, uint32_t len);
#endif
