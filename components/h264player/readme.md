不使用第三方库, 实现 h264 数据流解码（嵌入式）

1. 仅 I 帧和 P 帧
2. SPS、PPS 信息随 Annex-B 数据流输入
3. 编译期固定分辨率
4. 输出格式默认 RGB565，编译期可切换到 RGB8888

## 编译期配置

- LUAT_H264PLAYER_FRAME_WIDTH：图像宽度，默认 640
- LUAT_H264PLAYER_FRAME_HEIGHT：图像高度，默认 480
- LUAT_H264PLAYER_MAX_PIXELS：像素数上限，默认 300000
- LUAT_H264PLAYER_OUTPUT_RGB565：默认启用
- LUAT_H264PLAYER_OUTPUT_RGB8888：可选启用（与 RGB565 互斥）

## 输入格式

- Annex-B bytestream（包含起始码 0x000001 或 0x00000001）
- 支持 NAL 类型：SPS(7)、PPS(8)、IDR(5)、P(1)

## API 位置

- 头文件：components/h264player/luat_h264player.h
- 源文件：components/h264player/luat_h264player.c

## 说明

- 该模块为解码器实现起点，已包含 NAL 解析与 SPS/PPS 管理。
- 宏块解码与运动补偿将按 I/P 帧逐步补齐。
