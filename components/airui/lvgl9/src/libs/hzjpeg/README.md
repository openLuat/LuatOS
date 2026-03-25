# hzjpeg

`hzjpeg` 是 AirUI/LVGL 使用的 baseline JPEG 解码器，适用于 LVGL 需要拿到完整解码图像缓冲区，而不是 MCU/块级输出的场景。

## 为什么要有 hzjpeg

LVGL 里现有的 `tjpgd` 接入方式偏向低内存分块解码，但在 AirUI 场景下有一个明显限制：

- 它通过 `get_area_cb` 输出局部解码块
- LVGL 会按块逐步绘制图像
- 后续整图级能力，例如缩放、旋转、recolor、不透明度处理，以及其他依赖完整图像缓冲区的变换流程，无法完整复用标准解码路径

`hzjpeg` 的目标就是解决这个问题：在 `open_cb` 阶段直接把 baseline JPEG 完整解码为一张 `lv_draw_buf_t`，再交给 LVGL 后续处理。

## 当前目标

- 支持 baseline JPEG
- 向 LVGL 输出完整的 `RGB888` 图像缓冲区
- 让 LVGL 可以继续走标准的图像变换和后处理链路
- 与 `tjpgd` 实现解耦，保持独立维护

## 当前限制

- 暂不支持 progressive JPEG
- 当前实现重点支持文件型 JPEG 解码

## 目录结构

- `lv_hzjpeg.c`：LVGL 图像解码器接入层
- `lv_hzjpeg.h`：初始化与反初始化声明
- `hz_tjpgd.c`：仅供 `hzjpeg` 使用的私有 baseline JPEG 解码核心
- `hz_tjpgd.h`：私有解码器声明与符号重映射
- `hz_tjpgdcnf.h`：私有解码器配置

## 设计说明

- `hzjpeg` 作为标准 LVGL 图像解码器注册
- 图像头信息在 `decoder_info()` 中解析
- 整图解码在 `decoder_open()` 中完成
- 解码后的像素写入完整的 `lv_draw_buf_t`
- EXIF 方向信息会在交给 LVGL 前完成处理
- 解码完成后，LVGL 可以继续使用自己的缓存与后处理流程

## 配置方式

启用方式如下：

```c
#define LV_USE_HZJPEG 1
```

如果同时启用 `LV_USE_HZJPEG` 和 `LV_USE_TJPGD`，两者是相互独立的实现，不共享解码核心。

## 后续计划

- 支持 progressive JPEG
- 支持变量源 JPEG（`LV_IMAGE_SRC_VARIABLE`）
- 优化大图场景下的内存占用
