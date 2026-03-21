# videoplayer - 视频播放库

## 概述

`videoplayer` 是 LuatOS 的视频播放组件，支持 MJPG 格式的视频解码与播放。设计上预留了 MP4+H264、AVI+MJPG 等封装格式的扩展接口。

### 特性

- **MJPG 解码播放**: 支持 raw MJPG 视频流的逐帧解码与显示
- **软解/硬解切换**: MJPG 解码支持软件解码（基于 tjpgd）和硬件解码两种方案，可在运行时切换
- **LCD 渲染**: 解码后的帧可直接绘制到 LCD 屏幕
- **帧数据访问**: 支持读取解码后的 RGB565 帧数据供用户自行处理
- **可扩展格式**: 预留 AVI+MJPG、MP4+H264 容器格式的解析接口

## 编译开关

在 BSP 的 `luat_conf_bsp.h` 中添加：

```c
#define LUAT_USE_VIDEOPLAYER 1
```

依赖 `LUAT_USE_TJPGD`（软件解码时需要）。

## 目录结构

```
components/videoplayer/
├── README.md                           # 本文档
├── binding/
│   └── luat_lib_videoplayer.c          # Lua 绑定层 (API注释)
├── include/
│   └── luat_videoplayer.h              # 核心头文件 (C API)
└── src/
    ├── luat_videoplayer.c              # 播放器核心逻辑
    ├── luat_videoplayer_mjpg_sw.c      # MJPG 软件解码 (基于 tjpgd)
    └── luat_videoplayer_mjpg_hw.c      # MJPG 硬件解码 (弱函数, 平台可覆写)
```

## 架构设计

### 分层架构

```
┌─────────────────────────────────┐
│         Lua 脚本层               │
│   videoplayer.open / play / ...  │
├─────────────────────────────────┤
│       Lua Binding 层             │
│   luat_lib_videoplayer.c         │
├─────────────────────────────────┤
│        播放器核心层               │
│   luat_videoplayer.c             │
│   - 文件格式解析 (MJPG/AVI/MP4)  │
│   - 帧管理                       │
│   - 解码器调度                    │
├──────────┬──────────────────────┤
│  软件解码  │     硬件解码          │
│  tjpgd    │   平台HAL (弱函数)    │
└──────────┴──────────────────────┘
```

### 解码器抽象

解码器通过 `luat_vp_decoder_ops_t` 接口进行抽象：

```c
typedef struct luat_vp_decoder_ops {
    int (*init)(void **ctx);
    int (*decode)(void *ctx, const uint8_t *data, size_t size, luat_vp_frame_t *frame);
    void (*deinit)(void *ctx);
} luat_vp_decoder_ops_t;
```

- **软件解码** (`luat_vp_mjpg_sw_ops`): 使用 tjpgd 库进行 JPEG 解码，纯 CPU 运算
- **硬件解码** (`luat_vp_mjpg_hw_ops`): 通过弱函数定义，由具体平台 BSP 覆写实现

可在运行时通过 `videoplayer.set_decode_mode()` 切换解码方案。

### MJPG 流格式解析

MJPG (Motion JPEG) 是最简单的视频封装：每帧是一个独立的 JPEG 图片，以 SOI 标记 (`0xFF 0xD8`) 开始、EOI 标记 (`0xFF 0xD9`) 结束。

播放器的 MJPG 解析器会：
1. 在文件流中扫描 SOI/EOI 标记对
2. 提取单帧 JPEG 数据
3. 调用当前解码器 (软解/硬解) 进行解码
4. 输出 RGB565 格式的帧数据

## Lua API

### 基本播放流程

```lua
local vp = videoplayer

-- 打开MJPG视频文件
local player = vp.open("/sdcard/video.mjpg")
if not player then
    log.error("vp", "打开视频失败")
    return
end

-- 获取视频信息
local info = vp.info(player)
log.info("vp", "分辨率", info.width, info.height)

-- 逐帧读取并显示到LCD
while true do
    local ok, err = vp.draw_frame(player, 0, 0)
    if err == "eof" then
        log.info("vp", "播放完成")
        break
    end
    sys.wait(33)  -- 约30fps
end

-- 关闭释放资源
vp.close(player)
```

### 软解/硬解切换

```lua
-- 切换到硬件解码
videoplayer.set_decode_mode(player, videoplayer.DECODE_HW)

-- 切换回软件解码
videoplayer.set_decode_mode(player, videoplayer.DECODE_SW)
```

### 手动读取帧数据

```lua
-- 读取解码后的帧数据 (RGB565)
local frame, err = videoplayer.read_frame(player)
if frame then
    log.info("vp", "帧大小", frame.width, frame.height)
    -- frame.data 为 RGB565 格式的字符串
end
```

### API 列表

| API | 说明 |
|-----|------|
| `videoplayer.open(path)` | 打开视频文件，返回播放器对象 |
| `videoplayer.close(player)` | 关闭播放器，释放资源 |
| `videoplayer.read_frame(player)` | 读取并解码下一帧，返回帧数据表 |
| `videoplayer.draw_frame(player, x, y)` | 读取下一帧并绘制到LCD |
| `videoplayer.info(player)` | 获取视频信息 (宽/高/格式) |
| `videoplayer.set_decode_mode(player, mode)` | 设置解码模式 (软解/硬解) |
| `videoplayer.debug(on_off)` | 开关调试输出 |

### 常量

| 常量 | 说明 |
|------|------|
| `videoplayer.DECODE_SW` | 软件解码模式 |
| `videoplayer.DECODE_HW` | 硬件解码模式 |
| `videoplayer.FMT_MJPG` | MJPG 格式 |
| `videoplayer.FMT_AVI_MJPG` | AVI+MJPG 格式 (预留) |
| `videoplayer.FMT_MP4_H264` | MP4+H264 格式 (预留) |

## C API

### 核心函数

```c
// 打开视频文件
luat_vp_ctx_t* luat_videoplayer_open(const char *path);

// 关闭播放器
void luat_videoplayer_close(luat_vp_ctx_t *ctx);

// 读取下一帧
int luat_videoplayer_read_frame(luat_vp_ctx_t *ctx, luat_vp_frame_t *frame);

// 获取视频信息
int luat_videoplayer_get_info(luat_vp_ctx_t *ctx, luat_vp_info_t *info);

// 设置解码模式
int luat_videoplayer_set_decode_mode(luat_vp_ctx_t *ctx, luat_vp_decode_mode_t mode);
```

### 平台适配 (硬件解码)

硬件平台需要覆写以下弱函数以实现硬件 JPEG 解码：

```c
// 初始化硬件JPEG解码器
int luat_vp_mjpg_hw_init(void **ctx);

// 使用硬件解码JPEG帧
int luat_vp_mjpg_hw_decode(void *ctx, const uint8_t *data, size_t size,
                            luat_vp_frame_t *frame);

// 释放硬件解码器
void luat_vp_mjpg_hw_deinit(void *ctx);
```

## 后续扩展计划

1. **AVI+MJPG 容器**: 解析 AVI 文件头和索引，从中提取 MJPG 帧数据
2. **MP4+H264**: 集成现有 `h264` 组件，解析 MP4 容器并调用 H264 解码器
3. **音视频同步**: 基于时间戳的音视频同步播放
4. **缓冲播放**: 支持网络流的缓冲播放
