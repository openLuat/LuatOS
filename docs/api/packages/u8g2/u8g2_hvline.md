---
title: u8g2_hvline
path: u8g2/u8g2_hvline.c
---
--------------------------------------------------
# u8g2_clip_intersection

```c
static uint8_t u8g2_clip_intersection(u8g2_uint_t *ap, u8g2_uint_t *bp, u8g2_uint_t d)
```

static uint8_t u8g2_clip_intersection(u8g2_uint_t *ap, u8g2_uint_t *bp, u8g2_uint_t c, u8g2_uint_t d)

## 参数表

Name | Type | Description
-----|------|--------------
**ap**|`u8g2_uint_t*`| *无*
**bp**|`u8g2_uint_t*`| *无*
**d**|`u8g2_uint_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`uint8_t`| *无*


--------------------------------------------------
# u8g2_draw_hv_line_2dir

```c
static void u8g2_draw_hv_line_2dir(u8g2_t *u8g2, u8g2_uint_t x, u8g2_uint_t y, u8g2_uint_t len, uint8_t dir)
```

  x,y		Upper left position of the line within the pixel buffer 
  len		length of the line in pixel, len must not be 0
  dir		0: horizontal line (left to right)
		1: vertical line (top to bottom)
  This function first adjusts the y position to the local buffer. Then it
  will clip the line and call u8g2_draw_low_level_hv_line()


## 参数表

Name | Type | Description
-----|------|--------------
**u8g2**|`u8g2_t*`| *无*
**x**|`u8g2_uint_t`| *无*
**y**|`u8g2_uint_t`| *无*
**len**|`u8g2_uint_t`| *无*
**dir**|`uint8_t`| *无*

## 返回值

> *无返回值*


