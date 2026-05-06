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

luat_fifo_t *luat_create_fifo(uint32_t size_power)
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
uint32_t luat_write_fifo(luat_fifo_t *fifo, const void *buf, uint32_t size)
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
        memcpy(fifo->data, buf + tail, size - tail);
    }
    fifo->wpoint += size;
    return size;
}
uint32_t luat_set_fifo(luat_fifo_t *fifo, uint8_t value, uint32_t size)
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
uint32_t luat_read_fifo(luat_fifo_t *fifo, uint8_t *buf, uint32_t size)
{
	uint32_t dummy = luat_query_fifo(fifo, buf, size);
	fifo->rpoint += dummy;
	return dummy;
}
uint32_t luat_query_fifo(luat_fifo_t *fifo, uint8_t *buf, uint32_t size)
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

uint32_t luat_check_fifo_free_space(luat_fifo_t *fifo)
{
	return (fifo->size - ((uint32_t)(fifo->wpoint - fifo->rpoint)));
}

void luat_delete_fifo(luat_fifo_t *fifo, uint32_t size)
{
	if ((fifo->rpoint + size) >= fifo->wpoint)
	{
		fifo->rpoint = 0;
		fifo->wpoint = 0;
	}
	else
	{
		fifo->rpoint += size;
	}
}

void luat_clear_fifo(luat_fifo_t *fifo)
{
	fifo->rpoint = 0;
	fifo->wpoint = 0;
}

void luat_deinit_fifo(luat_fifo_t *fifo)
{
	if (!fifo)
		return ;
	luat_heap_free(fifo);
}

int luat_init_buffer(luat_buffer_t *buffer, uint32_t size)
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
void luat_deinit_buffer(luat_buffer_t *buffer)
{
	if (buffer->data)
	{
		luat_heap_free(buffer->data);
	}
	buffer->data = NULL;
	buffer->max_len = 0;
	buffer->pos = 0;
}
int luat_reinit_buffer(luat_buffer_t *buffer, uint32_t len)
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
int luat_resize_buffer(luat_buffer_t *buffer, uint32_t len)
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
int luat_write_buffer(luat_buffer_t *buffer, const void *data, uint32_t len)
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
		if (!luat_resize_buffer(buffer, write_len))
		{
			return -LUAT_ERROR_NO_MEMORY;
		}
	}
	memcpy(&buffer->data[buffer->pos], data, len);
	buffer->pos += len;
	return LUAT_ERROR_NONE;
}
void luat_remove_data_from_buffer(luat_buffer_t *buffer, uint32_t len)
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
