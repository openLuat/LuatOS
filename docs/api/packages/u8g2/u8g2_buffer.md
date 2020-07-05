---
title: u8g2_buffer
path: u8g2/u8g2_buffer.c
---
--------------------------------------------------
# u8g2_send_buffer

```c
static void u8g2_send_buffer(u8g2_t *u8g2)
```

============================================*/
void u8g2_ClearBuffer(u8g2_t *u8g2)
{
  size_t cnt;
  cnt = u8g2_GetU8x8(u8g2)->display_info->tile_width;
  cnt *= u8g2->tile_buf_height;
  cnt *= 8;
  memset(u8g2->tile_buf_ptr, 0, cnt);
}

============================================*/

static void u8g2_send_tile_row(u8g2_t *u8g2, uint8_t src_tile_row, uint8_t dest_tile_row)
{
  uint8_t *ptr;
  uint16_t offset;
  uint8_t w;
  
  w = u8g2_GetU8x8(u8g2)->display_info->tile_width;
  offset = src_tile_row;
  ptr = u8g2->tile_buf_ptr;
  offset *= w;
  offset *= 8;
  ptr += offset;
  u8x8_DrawTile(u8g2_GetU8x8(u8g2), 0, dest_tile_row, w, ptr);
}


  write the buffer to the display RAM. 
  For most displays, this will make the content visible to the user.
  Some displays (like the SSD1606) require a u8x8_RefreshDisplay()

## 参数表

Name | Type | Description
-----|------|--------------
**u8g2**|`u8g2_t*`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# u8g2_send_buffer

```c
static void u8g2_send_buffer(u8g2_t *u8g2)
```


## 参数表

Name | Type | Description
-----|------|--------------
**u8g2**|`u8g2_t*`| *无*

## 返回值

> *无返回值*


