---
title: u8log
path: u8g2/u8log.c
---
--------------------------------------------------
# u8log_clear_screen

```c
static void u8log_clear_screen(u8log_t *u8log)
```


## 参数表

Name | Type | Description
-----|------|--------------
**u8log**|`u8log_t*`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# u8log_cursor_on_screen

```c
static void u8log_cursor_on_screen(u8log_t *u8log)
```

scroll the content of the complete buffer, set redraw_line to 255 */
static void u8log_scroll_up(u8log_t *u8log)
{
  uint8_t *dest = u8log->screen_buffer;
  uint8_t *src = dest+u8log->width;
  uint16_t cnt = u8log->height;
  cnt--;
  cnt *= u8log->width;
  do
  {
    *dest++ = *src++;
    cnt--;
  } while( cnt > 0 );
  cnt = u8log->width;
  do
  {
    *dest++ = ' ';
    cnt--;
  } while(cnt > 0);
  
  if ( u8log->is_redraw_line_for_each_char )
    u8log->is_redraw_all = 1;
  else
    u8log->is_redraw_all_required_for_next_nl = 1;
}


  Place the cursor on the screen. This will also scroll, if required 

## 参数表

Name | Type | Description
-----|------|--------------
**u8log**|`u8log_t*`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# u8log_write_to_screen

```c
static void u8log_write_to_screen(u8log_t *u8log, uint8_t c)
```

  Write a printable, single char on the screen, do any kind of scrolling

## 参数表

Name | Type | Description
-----|------|--------------
**u8log**|`u8log_t*`| *无*
**c**|`uint8_t`| *无*

## 返回值

> *无返回值*


