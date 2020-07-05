---
title: u8g2_font
path: u8g2/u8g2_font.c
---
--------------------------------------------------
# u8g2_font_get_byte

```c
static uint8_t u8g2_font_get_byte(const uint8_t *font, uint8_t offset)
```

static uint8_t u8g2_font_get_byte(const uint8_t *font, uint8_t offset) U8G2_NOINLINE;

## 参数表

Name | Type | Description
-----|------|--------------
**font**|`uint8_t*`| *无*
**offset**|`uint8_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`uint8_t`| *无*


--------------------------------------------------
# u8g2_font_get_word

```c
static uint16_t u8g2_font_get_word(const uint8_t *font, uint8_t offset)
```


## 参数表

Name | Type | Description
-----|------|--------------
**font**|`uint8_t*`| *无*
**offset**|`uint8_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`uint16_t`| *无*


--------------------------------------------------
# u8g2_font_get_word

```c
static uint16_t u8g2_font_get_word(const uint8_t *font, uint8_t offset)
```


## 参数表

Name | Type | Description
-----|------|--------------
**font**|`uint8_t*`| *无*
**offset**|`uint8_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`uint16_t`| *无*


--------------------------------------------------
# u8g2_add_vector_y

```c
static u8g2_uint_t u8g2_add_vector_y(u8g2_uint_t dy, int8_t x, int8_t y, uint8_t dir)
```


## 参数表

Name | Type | Description
-----|------|--------------
**dy**|`u8g2_uint_t`| *无*
**x**|`int8_t`| *无*
**y**|`int8_t`| *无*
**dir**|`uint8_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`u8g2_uint_t`| *无*


--------------------------------------------------
# u8g2_add_vector_y

```c
static u8g2_uint_t u8g2_add_vector_y(u8g2_uint_t dy, int8_t x, int8_t y, uint8_t dir)
```


## 参数表

Name | Type | Description
-----|------|--------------
**dy**|`u8g2_uint_t`| *无*
**x**|`int8_t`| *无*
**y**|`int8_t`| *无*
**dir**|`uint8_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`u8g2_uint_t`| *无*


--------------------------------------------------
# u8g2_add_vector_x

```c
static u8g2_uint_t u8g2_add_vector_x(u8g2_uint_t dx, int8_t x, int8_t y, uint8_t dir)
```


## 参数表

Name | Type | Description
-----|------|--------------
**dx**|`u8g2_uint_t`| *无*
**x**|`int8_t`| *无*
**y**|`int8_t`| *无*
**dir**|`uint8_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`u8g2_uint_t`| *无*


--------------------------------------------------
# u8g2_add_vector_x

```c
static u8g2_uint_t u8g2_add_vector_x(u8g2_uint_t dx, int8_t x, int8_t y, uint8_t dir)
```


## 参数表

Name | Type | Description
-----|------|--------------
**dx**|`u8g2_uint_t`| *无*
**x**|`int8_t`| *无*
**y**|`int8_t`| *无*
**dir**|`uint8_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`u8g2_uint_t`| *无*


--------------------------------------------------
# u8g2_font_draw_glyph

```c
static u8g2_uint_t u8g2_font_draw_glyph(u8g2_t *u8g2, u8g2_uint_t x, u8g2_uint_t y, uint16_t encoding)
```


## 参数表

Name | Type | Description
-----|------|--------------
**u8g2**|`u8g2_t*`| *无*
**x**|`u8g2_uint_t`| *无*
**y**|`u8g2_uint_t`| *无*
**encoding**|`uint16_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`u8g2_uint_t`| *无*


--------------------------------------------------
# u8g2_draw_string

```c
static u8g2_uint_t u8g2_draw_string(u8g2_t *u8g2, u8g2_uint_t x, u8g2_uint_t y, const char *str)
```


## 参数表

Name | Type | Description
-----|------|--------------
**u8g2**|`u8g2_t*`| *无*
**x**|`u8g2_uint_t`| *无*
**y**|`u8g2_uint_t`| *无*
**str**|`char*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`u8g2_uint_t`| *无*


--------------------------------------------------
# u8g2_draw_string

```c
static u8g2_uint_t u8g2_draw_string(u8g2_t *u8g2, u8g2_uint_t x, u8g2_uint_t y, const char *str)
```


## 参数表

Name | Type | Description
-----|------|--------------
**u8g2**|`u8g2_t*`| *无*
**x**|`u8g2_uint_t`| *无*
**y**|`u8g2_uint_t`| *无*
**str**|`char*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`u8g2_uint_t`| *无*


--------------------------------------------------
# u8g2_GetGlyphHorizontalProperties

```c
static void u8g2_GetGlyphHorizontalProperties(u8g2_t *u8g2, uint16_t requested_encoding, uint8_t *w, int8_t *ox, int8_t *dx)
```


## 参数表

Name | Type | Description
-----|------|--------------
**u8g2**|`u8g2_t*`| *无*
**requested_encoding**|`uint16_t`| *无*
**w**|`uint8_t*`| *无*
**ox**|`int8_t*`| *无*
**dx**|`int8_t*`| *无*

## 返回值

> *无返回值*


