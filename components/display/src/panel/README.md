# display 面板驱动目录

本目录存放 `display` 组件支持的具体液晶面板驱动。每个面板以 `struct luat_display_panel` 描述，包含名称、接口参数、时序、引脚配置和面板控制回调。

## 目录内容

| 文件 | 说明 |
|------|------|
| `luat_display_panel_comm.h` | 面板公共头文件，声明所有面板变量和面板通用辅助函数 |
| `luat_display_panel_comm.c` | 面板通用辅助函数：`luat_display_find_panel`、复位、上下电等 |
| `luat_display_panel_rgb_custom.c` | 通用 RGB 面板模板（custom） |
| `luat_display_panel_rgb_st7701s.c` | ST7701S RGB 面板 |
| `luat_display_panel_dsi_st7701s.c` | ST7701S DSI 面板 |
| `luat_display_panel_dsi_custom.c` | 通用 DSI 面板模板（custom） |
| `luat_display_panel_lvds_custom.c` | 通用 LVDS 面板模板（custom） |
| `luat_display_panel_spi_st7789.c` | ST7789 SPI 面板 |
| `luat_display_panel_spi_ili9341.c` | ILI9341 SPI 面板 |

## 面板数据结构

```c
struct luat_display_panel {
    const char *name;                       // 面板名称，如 "st7789"
    const char *desc;                       // 面板描述

    struct luat_display_panel_funcs *panel_funcs;  // 面板控制回调
    struct luat_display_timing *timing;     // 时序参数
    struct luat_display_rect *screen_win;   // 屏幕有效区域

    union {                                 // 接口专用参数
        struct panel_rgb  *rgb;
        struct panel_lvds *lvds;
        struct panel_dsi  *dsi;
        struct panel_dbi  *dbi;
    };

    struct panel_pin_device *pin;           // 引脚配置
    unsigned int connector_type;            // 连接器类型
};
```

## 面板控制回调

```c
struct luat_display_panel_funcs {
    int (*panel_init)(struct luat_display_panel *panel);
    int (*panel_deinit)(struct luat_display_panel *panel);
    int (*panel_ctrl)(struct luat_display_panel *panel, enum display_ctrl_cmd cmd, void *arg);
};
```

| 回调 | 说明 |
|------|------|
| `panel_init` | 面板上电、复位、发送初始化命令序列 |
| `panel_deinit` | 面板关闭 |
| `panel_ctrl` | 面板控制命令，如 `LUAT_DISPLAY_POWER_ON` / `LUAT_DISPLAY_POWER_OFF` |

## 常用初始化命令序列宏

SPI/DSI/RGB 面板通常用宏简化命令发送：

```c
#define panel_spi_send_seq(panel, ...) do {                 \
        static const unsigned char d[] = { __VA_ARGS__ };   \
        spi_panel_send_sequence(panel, d, ARRAY_SIZE(d));   \
    } while (0)
```

> 注意：Windows/MSVC 下请使用 `__VA_ARGS__` 格式，不要使用 GCC 扩展 `seq...`。

## 添加新面板

1. 复制一份最接近的模板（如 `*_custom.c`）
2. 修改面板名称、时序、接口参数、初始化序列
3. 在 `luat_display_panel_comm.c` 的 `panels[]` 表中注册
4. 在 `luat_display_panel_comm.h` 中声明外部变量
5. 在 `binding/luat_lib_display.c` 的 `panel_regs[]` 表中按 `(name, interface)` 注册

## custom 面板

`custom` 面板用于没有现成驱动的屏幕。通过 Lua 配置表传入分辨率、时序、引脚等参数，运行时动态填充 `panel->timing` 和 `panel->pin`。
