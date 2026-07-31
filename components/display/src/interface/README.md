# display 接口驱动目录

本目录存放 `display` 组件的底层显示接口驱动。每个接口实现一套 `struct luat_display_funcs`，向上层屏蔽硬件差异。

## 目录内容

| 文件 | 说明 |
|------|------|
| `luat_display_if_comm.h` | 接口公共头文件，声明外部可用的 `rgb_funcs` / `dsi_funcs` / `spi_funcs` / `sdl_funcs` |
| `luat_display_if_rgb.c` | RGB 接口（含并行 RGB + SPI 初始化） |
| `luat_display_if_dsi.c` | MIPI DSI 接口 |
| `luat_display_if_spi.c` | SPI/DBI 接口 |
| `luat_display_if_sdl.c` | PC 模拟器 SDL2 接口 |

## 接口函数结构

每个接口需要填充 `struct luat_display_funcs`：

```c
struct luat_display_funcs {
    const char *name;
    int (*fb_probe)(struct luat_display_panel *panel, struct luat_display_fb_info *info);
    int (*inf_init)(struct luat_display_panel *panel);
    int (*set_layer)(struct luat_display_layer_data *layer_data);
    int (*fb_flush)(struct luat_display_rect *rect, const void *data, enum disp_rotate rotation);
    int (*wait_vsync)(void);
    int (*pan_display)(int index);
};
```

| 成员 | 作用 |
|------|------|
| `fb_probe` | 根据面板参数探测/填充 framebuffer 信息（分辨率、格式、draw_buf 等） |
| `inf_init` | 初始化接口硬件（RGB 配 timing、SDL 创建窗口等） |
| `set_layer` | 配置显示层（可选，SDL 当前为空实现） |
| `fb_flush` | 把绘制好的矩形数据刷新到显示设备 |
| `wait_vsync` | 等待垂直同步，SDL 中用于处理窗口事件 |
| `pan_display` | 交换/显示缓冲区（SDL 中执行 present） |

## 添加新接口

1. 新建 `luat_display_if_xxx.c`
2. 实现上述 6 个回调（空实现可填 `return 0`）
3. 在文件末尾导出：`struct luat_display_funcs xxx_funcs = { ... };`
4. 在 `luat_display_if_comm.h` 中添加 `extern struct luat_display_funcs xxx_funcs;`
5. 在 `binding/luat_lib_display.c` 的 `if_regs[]` 表中注册：`{"xxx", &xxx_funcs}`

## SDL 接口说明

PC 模拟器下，`luat_display_if_sdl.c` 不直接操作 SDL，而是通过独立的 `luat_display_sdl2` 模块（位于 `components/ui/sdl2/`）创建窗口、管理纹理。这样旧版 `luat_sdl2` 单例接口不受影响，SDL 显示也可以按 display 框架的语义工作。
