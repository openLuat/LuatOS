# mGBA GBA模拟器演示

这是一个在 LuatOS-PC 上运行 GBA 游戏的演示程序。

## 使用方法

### 1. 准备 ROM 文件

将您的 GBA ROM 文件复制到此目录，并重命名为 `game.gba`

支持的格式：
- `.gba` - Game Boy Advance 游戏
- `.gb` - Game Boy 游戏
- `.gbc` - Game Boy Color 游戏

### 2. 运行程序

```bash
cd bsp/pc
./build/out/luatos-lua.exe test/066.mgba/
```

或指定 ROM 路径：
```bash
./build/out/luatos-lua.exe test/066.mgba/ /path/to/your/game.gba
```

### 3. 游戏控制

| 按键 | 功能 |
|------|------|
| X | A 按钮 |
| Z | B 按钮 |
| Enter | START |
| Shift | SELECT |
| ↑↓←→ | 方向键 |
| A | L 肩键 |
| S | R 肩键 |
| ESC | 退出游戏 |

## 技术说明

- 模拟器基于 mGBA 0.11
- 使用 SDL2 进行视频和音频输出
- 默认分辨率：480x320 (2x 缩放)
- 音频：44.1kHz 立体声

## 注意事项

1. ROM 文件需要是合法备份的个人游戏
2. 部分游戏可能存在兼容性问题
3. 性能取决于您的硬件配置

## 故障排除

**问题：gba 模块未加载**
- 确保固件编译时启用了 `LUAT_USE_MGBA`
- 使用 `build_windows_64bit_msvc_mgba.bat` 构建固件

**问题：ROM 文件不存在**
- 检查 ROM 文件路径是否正确
- 确保 ROM 文件名和路径没有中文或特殊字符

**问题：游戏运行缓慢**
- 尝试禁用音频：修改 main.lua 中 `audio = false`
- 降低分辨率缩放：修改 `scale = 1`

## 许可证

- mGBA: MPL 2.0
- LuatOS: MIT