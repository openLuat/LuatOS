#include "luat_common_api.h"
#include "luat_mem.h"


void *luat_llist_traversal(luat_llist_head *head, luat_llist_traversal_fun cb, void *param)
{
	luat_llist_head *node = head->next;
	luat_llist_head *del;
	int result;
	while (!luat_llist_empty(head) && (node != head))
	{
		result = cb((void *)node, param);
		if (result > 0)
		{
			return node;
		}
		else
		{
			del = node;
			node = node->next;
			if (result < 0)
			{
				if (del->prev && del->next)
				{
					__luat_llist_del(del->prev, del->next);
				}
				luat_heap_free(del);
			}
		}
	}
	return NULL;
}

luat_fifo_t *luat_fifo_create(uint32_t size_power)
{
	if (size_power > 31) return NULL;
	uint32_t data_size = 1 << size_power;
	luat_fifo_t *fifo = luat_heap_malloc(data_size + sizeof(luat_fifo_t));
	if (fifo)
	{
		fifo->size = data_size;
		fifo->mask = fifo->size - 1;
		fifo->wpoint = 0;
		fifo->rpoint = 0;
	}
	return fifo;
}
uint32_t luat_fifo_write(luat_fifo_t *fifo, const void *buf, uint32_t size)
{
	uint32_t space = fifo->size - (uint32_t)(fifo->wpoint - fifo->rpoint);
	if (size > space) size = space;
	uint32_t w = fifo->wpoint & fifo->mask;
	uint32_t tail = fifo->size - w;
    if (tail >= size)
    {
        memcpy(fifo->data + w, buf, size);
    }
    else
    {
        memcpy(fifo->data + w, buf, tail);
        memcpy(fifo->data, (uint8_t *)buf + tail, size - tail);
    }
    fifo->wpoint += size;
    return size;
}
uint32_t luat_fifo_fill(luat_fifo_t *fifo, uint8_t value, uint32_t size)
{
	uint32_t space = fifo->size - (uint32_t)(fifo->wpoint - fifo->rpoint);
	if (size > space) size = space;
	uint32_t w = fifo->wpoint & fifo->mask;
	uint32_t tail = fifo->size - w;
    if (tail >= size)
    {
        memset(fifo->data + w, value, size);
    }
    else
    {
    	memset(fifo->data + w, value, tail);
    	memset(fifo->data, value + tail, size - tail);
    }
    fifo->wpoint += size;
    return size;
}
uint32_t luat_fifo_read(luat_fifo_t *fifo, uint8_t *buf, uint32_t size)
{
	uint32_t dummy = luat_fifo_query(fifo, buf, size);
	fifo->rpoint += dummy;
	return dummy;
}
uint32_t luat_fifo_query(luat_fifo_t *fifo, uint8_t *buf, uint32_t size)
{
	uint32_t space = (uint32_t)(fifo->wpoint - fifo->rpoint);
	if (size > space) size = space;
	uint32_t r = fifo->rpoint & fifo->mask;
	uint32_t tail = fifo->size - r;
    if (tail >= size)
    {
        memcpy(buf, fifo->data + r, size);
    }
    else
    {
        memcpy(buf, fifo->data + r, tail);
        memcpy(buf + tail, fifo->data, size - tail);
    }
    return size;
}

void luat_fifo_delete(luat_fifo_t *fifo, uint32_t size)
{
	if (!fifo) return;
	if ((fifo->rpoint + size) >= fifo->wpoint)
	{
		fifo->rpoint = fifo->wpoint;
	}
	else
	{
		fifo->rpoint += size;
	}
}

void luat_fifo_destroy(luat_fifo_t *fifo)
{
	if (!fifo)
		return ;
	luat_heap_free(fifo);
}

int luat_buffer_init(luat_buffer_t *buffer, uint32_t size)
{
	if (!buffer)
		return 0;
	buffer->data = luat_heap_malloc(size);
	if (!buffer->data)
	{
		buffer->max_len = 0;
		buffer->pos = 0;
		return 0;
	}
	buffer->max_len = size;
	buffer->pos = 0;
	return size;
}

void luat_buffer_deinit(luat_buffer_t *buffer)
{
	if (buffer->data)
	{
		luat_heap_free(buffer->data);
	}
	buffer->data = NULL;
	buffer->max_len = 0;
	buffer->pos = 0;
}

int luat_buffer_reinit(luat_buffer_t *buffer, uint32_t len)
{
	if (!buffer)
		return 0;

	if (buffer->data)
	{
		luat_heap_free(buffer->data);
	}
	buffer->data = luat_heap_malloc(len);
	if (!buffer->data)
	{
		buffer->max_len = 0;
		buffer->pos = 0;
		return 0;
	}
	buffer->max_len = len;
	buffer->pos = 0;
	return len;
}

int luat_buffer_resize(luat_buffer_t *buffer, uint32_t len)
{

	if (!buffer)
		return 0;

	void *new = luat_heap_realloc(buffer->data, len);
	if (new)
	{
		buffer->data = new;
		buffer->max_len = len;
	}
	return len;
}

int luat_buffer_write(luat_buffer_t *buffer, const void *data, uint32_t len)
{
	uint32_t write_len;
	if (!len)
	{
		return LUAT_ERROR_NONE;
	}
	if (!buffer)
	{
		return -LUAT_ERROR_PARAM_INVALID;
	}
	if (!buffer->data)
	{
		buffer->data = luat_heap_malloc(len);
		if (!buffer->data)
		{
			return -LUAT_ERROR_NO_MEMORY;
		}
		buffer->pos = 0;
		buffer->max_len = len;
	}
	write_len = buffer->pos + len;
	if (write_len > buffer->max_len)
	{
		if (!luat_buffer_resize(buffer, write_len))
		{
			return -LUAT_ERROR_NO_MEMORY;
		}
	}
	memcpy(&buffer->data[buffer->pos], data, len);
	buffer->pos += len;
	return LUAT_ERROR_NONE;
}

void luat_buffer_remove_data(luat_buffer_t *buffer, uint32_t len)
{
	uint32_t RestLen;
	if (!buffer)
		return ;
	if (!buffer->data)
		return ;
	if (len >= buffer->pos)
	{
		buffer->pos = 0;
		return ;
	}
	RestLen = buffer->pos - len;
	memmove(buffer->data, buffer->data + len, RestLen);
	buffer->pos = RestLen;
}

uint32_t luat_hex_string_to_hex_byte(const uint8_t *src, uint8_t *dst, uint32_t src_len, uint32_t dst_max_len)
{
	uint32_t i;
	uint32_t dst_len;
	uint32_t finish_len = 0;
	uint8_t high, low;
	dst_len = src_len >> 1;
	if (dst_len > dst_max_len) {
		dst_len = dst_max_len;
	}
	finish_len = dst_len;
	for (i = 0; i < dst_len; i++) {
		high = src[i * 2];
		low = src[i * 2 + 1];
		if (LUAT_IS_DIGIT(high)) {
			high -= '0';
		} else if ((high >= 'A') && (high <= 'F')) {
			high -= 'A';
			high += 10;
		} else if ((high >= 'a') && (high <= 'f')) {
			high -= 'a';
			high += 10;
		} else {
			finish_len = i;
			break;
		}
		if (LUAT_IS_DIGIT(low)) {
			low -= '0';
		} else if ((low >= 'A') && (low <= 'F')) {
			low -= 'A';
			low += 10;
		} else if ((low >= 'a') && (low <= 'f')) {
			low -= 'a';
			low += 10;
		} else {
			finish_len = i;
			break;
		}
		dst[i] = (high << 4) | low;
	}
	return finish_len;
}

static const uint8_t _byte_to_hex_char[16] = {'0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F'};

uint32_t luat_hex_byte_to_hex_string(const uint8_t *src, uint8_t *dst, uint32_t src_len, uint32_t dst_max_len)
{
	uint32_t i = 0;
	uint32_t j = 0;
	uint32_t finish_len;
	if (src_len > (dst_max_len >> 1)) {
		src_len = dst_max_len >> 1;
	}
	finish_len = (src_len * 2);
	while (i < src_len) {
		dst[j++] = _byte_to_hex_char[(src[i] & 0xf0) >> 4];
		dst[j++] = _byte_to_hex_char[src[i++] & 0x0f];
	}
	if (finish_len < dst_max_len) {
		dst[finish_len] = '\0';
	}
	return finish_len;
}

void luat_string_upper(uint8_t *src, uint32_t length)
{
	uint32_t i;
	for(i = 0; i < length; i++) {
		if ( (src[i] >= 'a') && (src[i] <= 'z') )  {
			src[i] = src[i] - 'a' + 'A';
		}
	}
}

void luat_string_lower(uint8_t *src, uint32_t length)
{
	uint32_t i;
	for(i = 0; i < length; i++) {
		if ( (src[i] >= 'A') && (src[i] <= 'Z') )  {
			src[i] = src[i] - 'A' + 'z';
		}
	}
}

uint8_t luat_bytes_get_u8(const void *ptr)
{
	const uint8_t *data = (const uint8_t *)ptr;
	return data[0];
}

void luat_bytes_put_u8(void *ptr, uint8_t value)
{
	uint8_t *data = (uint8_t *)ptr;
	data[0] = value;
}

uint16_t luat_bytes_get_be16(const void *ptr)
{
	const uint8_t *data = (const uint8_t *)ptr;
	return ((uint16_t)data[0] << 8) | (uint16_t)data[1];
}

void luat_bytes_put_be16(void *ptr, uint16_t value)
{
	uint8_t *data = (uint8_t *)ptr;
	data[0] = (uint8_t)(value >> 8);
	data[1] = (uint8_t)value;
}

uint32_t luat_bytes_get_be32(const void *ptr)
{
	const uint8_t *data = (const uint8_t *)ptr;
	return ((uint32_t)data[0] << 24) |
		((uint32_t)data[1] << 16) |
		((uint32_t)data[2] << 8) |
		(uint32_t)data[3];
}

void luat_bytes_put_be32(void *ptr, uint32_t value)
{
	uint8_t *data = (uint8_t *)ptr;
	data[0] = (uint8_t)(value >> 24);
	data[1] = (uint8_t)(value >> 16);
	data[2] = (uint8_t)(value >> 8);
	data[3] = (uint8_t)value;
}

uint16_t luat_bytes_get_le16(const void *ptr)
{
	const uint8_t *data = (const uint8_t *)ptr;
	return (uint16_t)data[0] | ((uint16_t)data[1] << 8);
}

void luat_bytes_put_le16(void *ptr, uint16_t value)
{
	uint8_t *data = (uint8_t *)ptr;
	data[0] = (uint8_t)value;
	data[1] = (uint8_t)(value >> 8);
}

uint32_t luat_bytes_get_le32(const void *ptr)
{
	const uint8_t *data = (const uint8_t *)ptr;
	return (uint32_t)data[0] |
		((uint32_t)data[1] << 8) |
		((uint32_t)data[2] << 16) |
		((uint32_t)data[3] << 24);
}

void luat_bytes_put_le32(void *ptr, uint32_t value)
{
	uint8_t *data = (uint8_t *)ptr;
	data[0] = (uint8_t)value;
	data[1] = (uint8_t)(value >> 8);
	data[2] = (uint8_t)(value >> 16);
	data[3] = (uint8_t)(value >> 24);
}

uint64_t luat_bytes_get_le64(const void *ptr)
{
	const uint8_t *data = (const uint8_t *)ptr;
	return (uint64_t)luat_bytes_get_le32(data) |
		((uint64_t)luat_bytes_get_le32(data + 4) << 32);
}

void luat_bytes_put_le64(void *ptr, uint64_t value)
{
	uint8_t *data = (uint8_t *)ptr;
	luat_bytes_put_le32(data, (uint32_t)value);
	luat_bytes_put_le32(data + 4, (uint32_t)(value >> 32));
}

int luat_image_crop(const uint8_t *src_data, uint32_t bytes_per_pixel,
                    uint32_t src_width, uint32_t src_height,
                    uint8_t *dst_data,
                    uint32_t dst_width, uint32_t dst_height,
                    uint32_t crop_x, uint32_t crop_y)
{
	uint32_t row;
	uint32_t src_row_bytes;
	uint32_t dst_row_bytes;
	const uint8_t *src_row_start;

	// 参数校验：空指针或尺寸为零
	if (!src_data || !dst_data || bytes_per_pixel == 0 ||
		src_width == 0 || src_height == 0 ||
		dst_width == 0 || dst_height == 0)
	{
		return -LUAT_ERROR_PARAM_INVALID;
	}

	// 检查裁剪区域是否超出原始图像边界
	if (((crop_x + dst_width) > src_width) || ((crop_y + dst_height) > src_height))
	{
		return -LUAT_ERROR_PARAM_INVALID;
	}

	src_row_bytes = src_width * bytes_per_pixel;
	dst_row_bytes = dst_width * bytes_per_pixel;

	// 优化：当裁剪宽度与原图宽度一致时，数据在内存中连续，只需一次拷贝
	if (src_width == dst_width)
	{
		memcpy(dst_data, src_data + crop_y * src_row_bytes, dst_height * dst_row_bytes);
		return LUAT_ERROR_NONE;
	}

	// 逐行复制裁剪区域数据
	for (row = 0; row < dst_height; row++)
	{
		src_row_start = src_data + ((crop_y + row) * src_width + crop_x) * bytes_per_pixel;
		memcpy(dst_data + row * dst_row_bytes, src_row_start, dst_row_bytes);
	}

	return LUAT_ERROR_NONE;
}
