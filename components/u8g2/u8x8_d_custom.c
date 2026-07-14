/*
  LuatOS generic custom display driver for u8g2.
*/

#include <string.h>
#include "luat_u8g2.h"
#include "luat_timer.h"

static luat_u8g2_conf_t *u8x8_custom_get_conf(u8x8_t *u8x8)
{
  return (luat_u8g2_conf_t *)u8x8->user_ptr;
}

static luat_u8g2_custom_t *u8x8_custom_get_data(u8x8_t *u8x8)
{
  luat_u8g2_conf_t *conf = u8x8_custom_get_conf(u8x8);
  return conf == NULL ? NULL : (luat_u8g2_custom_t *)conf->userdata;
}

static void u8x8_custom_send_data(u8x8_t *u8x8, uint8_t *ptr, size_t len)
{
  while (len > 0) {
    uint8_t chunk = len > 248 ? 248 : (uint8_t)len;
    u8x8_cad_SendData(u8x8, chunk, ptr);
    ptr += chunk;
    len -= chunk;
  }
}

static uint8_t u8x8_custom_draw_page(u8x8_t *u8x8, u8x8_tile_t *tile, uint8_t with_page_arg)
{
  uint16_t x;
  size_t len;

  if (tile == NULL || tile->tile_ptr == NULL || tile->cnt == 0)
    return 0;

  x = (uint16_t)tile->x_pos * 8u + u8x8->x_offset;
  len = (size_t)tile->cnt * 8u;

  u8x8_cad_StartTransfer(u8x8);
  u8x8_cad_SendCmd(u8x8, 0x10u | (uint8_t)(x >> 4));
  u8x8_cad_SendCmd(u8x8, (uint8_t)(x & 0x0fu));
  if (with_page_arg) {
    u8x8_cad_SendCmd(u8x8, 0xb0);
    u8x8_cad_SendArg(u8x8, tile->y_pos);
  }
  else {
    u8x8_cad_SendCmd(u8x8, 0xb0u | tile->y_pos);
  }
  u8x8_custom_send_data(u8x8, tile->tile_ptr, len);
  u8x8_cad_EndTransfer(u8x8);
  return 1;
}

static void u8x8_custom_gray4_convert(const uint8_t *src, uint8_t *dest)
{
  uint8_t i;
  uint8_t j;

  for (j = 0; j < 4; j++) {
    uint8_t a = *src++;
    uint8_t b = *src++;
    uint8_t *out = dest + j;
    for (i = 0; i < 8; i++) {
      uint8_t v = 0;
      if (a & 1u)
        v |= 0xf0;
      if (b & 1u)
        v |= 0x0f;
      *out = v;
      out += 4;
      a >>= 1;
      b >>= 1;
    }
  }
}

static uint8_t u8x8_custom_draw_window_gray4(u8x8_t *u8x8, u8x8_tile_t *tile)
{
  uint16_t x;
  uint16_t y;
  uint8_t count;
  uint8_t *ptr;
  uint8_t converted[32];

  if (tile == NULL || tile->tile_ptr == NULL || tile->cnt == 0)
    return 0;

  x = (uint16_t)tile->x_pos * 2u + u8x8->x_offset;
  y = (uint16_t)tile->y_pos * 8u;
  count = tile->cnt;
  ptr = tile->tile_ptr;

  u8x8_cad_StartTransfer(u8x8);
  u8x8_cad_SendCmd(u8x8, 0x75);
  u8x8_cad_SendArg(u8x8, (uint8_t)y);
  u8x8_cad_SendArg(u8x8, (uint8_t)(y + 7u));

  while (count > 0) {
    u8x8_cad_SendCmd(u8x8, 0x15);
    u8x8_cad_SendArg(u8x8, (uint8_t)x);
    u8x8_cad_SendArg(u8x8, (uint8_t)(x + 1u));
    u8x8_cad_SendCmd(u8x8, 0x5c);
    u8x8_custom_gray4_convert(ptr, converted);
    u8x8_cad_SendData(u8x8, sizeof(converted), converted);
    ptr += 8;
    x += 2;
    count--;
  }

  u8x8_cad_EndTransfer(u8x8);
  return 1;
}

static void u8x8_custom_2row_convert(const uint8_t *row0, const uint8_t *row1,
                                     uint8_t available, uint8_t *dest)
{
  static const uint8_t map0[16] = {
    0x00, 0x02, 0x08, 0x0a, 0x20, 0x22, 0x28, 0x2a,
    0x80, 0x82, 0x88, 0x8a, 0xa0, 0xa2, 0xa8, 0xaa
  };
  static const uint8_t map1[16] = {
    0x00, 0x01, 0x04, 0x05, 0x10, 0x11, 0x14, 0x15,
    0x40, 0x41, 0x44, 0x45, 0x50, 0x51, 0x54, 0x55
  };
  uint8_t a[3] = {0, 0, 0};
  uint8_t b[3] = {0, 0, 0};
  uint8_t i;

  for (i = 0; i < available && i < 3; i++) {
    a[i] = row0[i];
    b[i] = row1[i];
  }

  dest[0] = map0[a[0] >> 4] | map1[b[0] >> 4];
  dest[1] = map0[a[0] & 0x0f] | map1[b[0] & 0x0f];
  dest[2] = map0[a[1] >> 4] | map1[b[1] >> 4];
  dest[3] = map0[a[1] & 0x0f] | map1[b[1] & 0x0f];
  dest[4] = map0[a[2] >> 4] | map1[b[2] >> 4];
  dest[5] = map0[a[2] & 0x0f] | map1[b[2] & 0x0f];
}

static uint8_t u8x8_custom_draw_window_2row_lut(u8x8_t *u8x8, u8x8_tile_t *tile,
                                                 luat_u8g2_custom_t *custom)
{
  uint16_t column_start;
  uint16_t column_count;
  uint16_t y;
  uint8_t pair;

  if (tile == NULL || tile->tile_ptr == NULL || tile->cnt == 0 || custom == NULL)
    return 0;
  if ((tile->x_pos % 3u) != 0)
    return 0;

  column_start = custom->column_start + ((uint16_t)tile->x_pos / 3u) * 2u;
  column_count = ((uint16_t)tile->cnt + 2u) / 3u * 2u;
  y = (uint16_t)tile->y_pos * 4u + custom->row_offset;

  u8x8_cad_StartTransfer(u8x8);
  for (pair = 0; pair < 4; pair++) {
    const uint8_t *row0 = tile->tile_ptr + (size_t)custom->tile_w * pair * 2u;
    const uint8_t *row1 = row0 + custom->tile_w;
    uint8_t remaining = tile->cnt;
    uint8_t offset = 0;

    u8x8_cad_SendCmd(u8x8, 0x2a);
    u8x8_cad_SendArg(u8x8, (uint8_t)column_start);
    u8x8_cad_SendArg(u8x8, (uint8_t)(column_start + column_count - 1u));
    u8x8_cad_SendCmd(u8x8, 0x2b);
    u8x8_cad_SendArg(u8x8, (uint8_t)(y + pair));
    u8x8_cad_SendArg(u8x8, (uint8_t)(y + pair));
    u8x8_cad_SendCmd(u8x8, 0x2c);

    while (remaining > 0) {
      uint8_t available = remaining > 3 ? 3 : remaining;
      uint8_t converted[6];
      u8x8_custom_2row_convert(row0 + offset, row1 + offset, available, converted);
      u8x8_cad_SendData(u8x8, sizeof(converted), converted);
      offset += available;
      remaining -= available;
    }
  }
  u8x8_cad_EndTransfer(u8x8);
  return 1;
}

static void u8x8_custom_send_init(u8x8_t *u8x8, luat_u8g2_custom_t *custom)
{
  size_t i;

  if (custom == NULL || custom->initcmd == NULL || custom->init_cmd_count == 0)
    return;

  u8x8_cad_StartTransfer(u8x8);
  for (i = 0; i < custom->init_cmd_count; i++) {
    uint32_t value = custom->initcmd[i];
    uint8_t type = (uint8_t)((value >> 16) & 0xffu);
    uint8_t data = (uint8_t)value;
    switch (type) {
      case 0:
      case 2:
        u8x8_cad_SendCmd(u8x8, data);
        break;
      case 1:
        luat_timer_mdelay((uint16_t)value);
        break;
      case 3:
        u8x8_cad_SendData(u8x8, 1, &data);
        break;
      default:
        break;
    }
  }
  u8x8_cad_EndTransfer(u8x8);
}

uint8_t u8x8_d_custom_noname(u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr)
{
  luat_u8g2_conf_t *conf = u8x8_custom_get_conf(u8x8);
  luat_u8g2_custom_t *custom = u8x8_custom_get_data(u8x8);
  (void)arg_int;

  if (conf == NULL || custom == NULL)
    return 0;

  switch (msg) {
    case U8X8_MSG_DISPLAY_SETUP_MEMORY:
      u8x8_d_helper_display_setup_memory(u8x8, &custom->display_info);
      return 1;
    case U8X8_MSG_DISPLAY_INIT:
      u8x8_d_helper_display_init(u8x8);
      u8x8_custom_send_init(u8x8, custom);
      return 1;
    case U8X8_MSG_DISPLAY_SET_POWER_SAVE:
      if ((arg_int == 0 && custom->has_wakecmd) ||
          (arg_int != 0 && custom->has_sleepcmd)) {
        u8x8_cad_StartTransfer(u8x8);
        u8x8_cad_SendCmd(u8x8, arg_int == 0 ? conf->wakecmd : conf->sleepcmd);
        u8x8_cad_EndTransfer(u8x8);
      }
      return 1;
    case U8X8_MSG_DISPLAY_SET_FLIP_MODE:
      u8x8->x_offset = arg_int == 0 ? custom->display_info.default_x_offset
                                    : custom->display_info.flipmode_x_offset;
      return 1;
    case U8X8_MSG_DISPLAY_DRAW_TILE:
      switch (custom->flush_mode) {
        case LUAT_U8G2_FLUSH_PAGE:
          return u8x8_custom_draw_page(u8x8, (u8x8_tile_t *)arg_ptr, 0);
        case LUAT_U8G2_FLUSH_PAGE_ARG:
          return u8x8_custom_draw_page(u8x8, (u8x8_tile_t *)arg_ptr, 1);
        case LUAT_U8G2_FLUSH_WINDOW_GRAY4:
          return u8x8_custom_draw_window_gray4(u8x8, (u8x8_tile_t *)arg_ptr);
        case LUAT_U8G2_FLUSH_WINDOW_2ROW_LUT:
          return u8x8_custom_draw_window_2row_lut(u8x8, (u8x8_tile_t *)arg_ptr, custom);
        default:
          return 0;
      }
    default:
      return 0;
  }
}
