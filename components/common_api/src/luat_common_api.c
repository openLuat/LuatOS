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

int luat_data_point_fifo_static_init(luat_data_point_fifo_t *fifo, uint32_t size_power, void *static_data)
{
	if (!fifo)
		return -LUAT_ERROR_PARAM_INVALID;
	if (!static_data)
		return -LUAT_ERROR_PARAM_INVALID;
	if (size_power > 31)
		return -LUAT_ERROR_PARAM_INVALID;
	fifo->size = 1 << size_power;
	fifo->mask = fifo->size - 1;
	fifo->wpoint = 0;
	fifo->rpoint = 0;
	fifo->u_data = (luat_data_union_t *)static_data;
	return LUAT_ERROR_NONE;
}

int luat_data_point_fifo_put(luat_data_point_fifo_t *fifo, const void *p)
{
	if (!fifo)
		return -LUAT_ERROR_PARAM_INVALID;
	if (fifo->size - ((uint32_t)(fifo->wpoint - fifo->rpoint)) < 1) {
		return -LUAT_ERROR_NO_MEMORY;
	}
	uint32_t w = fifo->wpoint & fifo->mask;
	fifo->u_data[w].p = p;
    fifo->wpoint++;
	return LUAT_ERROR_NONE;
}

int luat_data_point_fifo_get(luat_data_point_fifo_t *fifo, void **p, uint8_t get_and_delete)
{
	if (!fifo)
		return -LUAT_ERROR_PARAM_INVALID;
	if (fifo->rpoint >= fifo->wpoint) {
		return -LUAT_ERROR_NO_MEMORY;
	}
	if (p) {
		uint32_t r = fifo->rpoint & fifo->mask;
		*p = (void *)fifo->u_data[r].p;
	}
	if (get_and_delete) {
		fifo->rpoint++;
	}
	return LUAT_ERROR_NONE;
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
