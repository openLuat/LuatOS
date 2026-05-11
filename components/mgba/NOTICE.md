# mGBA 组件声明

本目录下的 `src/` 包含 mGBA 模拟器核心源码的精简版本，只提供模拟器核心功能，不提供任何游戏ROM。

- **原始项目**: mGBA (https://mgba.io/)
- **原始仓库**: https://github.com/mgba-emu/mgba
- **许可证**: Mozilla Public License Version 2.0 (见 `src/LICENSE`)
- **修改内容**: 删除了平台前端、调试器、测试 ROM、文档、第三方库等非核心文件，
  仅保留 GBA/GB 模拟器核心编译所需的最小源码集。

删减后的源码仍受 MPL 2.0 许可证约束。
LuatOS 对 mGBA 的适配层代码（`adapter/`、`binding/`）采用 MIT 许可证。
