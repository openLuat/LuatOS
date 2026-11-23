# 验证记录 · 水处理加药间 PLC 控制屏

> G5 收口记录。验证分两档：沙箱内可验的部分已跑；必须上设备才验的项列在最后，未打勾。

## 一、静态自检（已跑）

命令（工程根目录）：

```powershell
$env:PYTHONIOENCODING='utf-8'; python tools/check.py
```

结果：**通过 44 / 失败 0 / 警告 0**，完整输出见 `build_check.txt`。新增「叠加层素材必须是透明 RGBA」校验（含负向用例：把 flow_a0 转成 RGB 会被拦）。

覆盖：
- Lua 语法解析（luaparser，Lua 5.3 文法）7 个文件全通过。
- 代码规范：无匿名函数 / 无闭包 / require 全是文件名 / main.lua 纯加载器且末尾 sys.run()。
- main.xml：根元素 `<ui version="0.1">`、1024×600、单页 `main`、72 资源 ID 唯一、74 组件（上限 512）、组件 ID 页内唯一、10 个事件全部在 handlers 注册、src 引用资源全部声明。
- PLCUI 1.0.2 schema 取值域（属性白名单、整型域、成对/互斥约束）。
- 字形覆盖：未使用 `— ▣ ⚠ ▶ ✓`（hzfont 实测无字形）。
- 绑定表：ui_vars.BIND 全部组件存在，变量全部由 data_app.get() 以标量产出。
- 交付文档齐备。

## 二、0.5 秒判读测试（原型阶段已做）

对 `design/index.html` 缩到 30% 后自检三问：
1. **我在看什么**：左上角「加药间监控」28 号页名 + 状态徽标，右上 6 态切换器，一眼可辨。
2. **数据在哪**：主区 PID 面板 PV 40 号全页唯一最大数值（NTU 同行紧邻），SP/MV 28 号次之。
3. **我能按哪里**：底部固定操作带 5 个 84×48 按钮，主操作与故障复位（告警色）错开一格。

## 三、六态矩阵核对（原型 ↔ XML ↔ Lua）

| 态 | index.html | main.xml 资源 | data_app.get() 变量 | 核对 |
|---|---|---|---|---|
| 停机 | s-stop | bdg_stop/bn_stop/flow_stop | state=stop | 一致 |
| 就地手动 | s-local | bdg_local/bn_local/flow_local | state=localm | 一致 |
| 远程手动 | s-remote | bdg_remote/bn_remote/flow_remote | state=remote | 一致 |
| 自动运行 | s-auto | bdg_auto/bn_auto/flow_auto + flow_a0..3 | state=auto | 一致 |
| 故障 | s-fault | bdg_fault/bn_fault/flow_fault | state=fault | 一致 |
| 维护检修 | s-maint | bdg_maint/bn_maint/flow_maint + overlay_maint | state=maint | 一致 |

## 四、交互点核对（六项）

- [x] 页面切换：本项目单页，改为 6 态整屏切换（状态切换器 6 键）。
- [x] 按钮三态：普通 / 按下 / 选中（状态键）+ 禁用（操作键），图已烘。
- [x] 输入确认：手自动切换走两级按（替代弹窗，见 fallback.md）。
- [x] 数据刷新：data_app.step() 每秒推进，ui_app.refresh() 按绑定表刷屏。
- [x] 软键盘：本项目无输入项，不适用。
- [x] 动画：自动态 flow_a0..3 四帧 200ms 轮播（set_src，非 animimg 组件）。

## 四b、上机前修正记录

- **流动帧透明通道**：首版 `gen_assets.py` 的 `save()` 用 `convert("RGB")`，把 `flow_a0..3` / `lv0..4` 的透明背景拍成不透明白，自动态下白底流动帧盖住整张工艺流程图，只剩绿线在动。已改为保留 RGBA （`flow_a0.png` 透明像素 `(255,255,255,0)`，与基准 demo `flow_0.png` 一致），并用 PIL 层叠合成复核：白底 → `flow_auto` 底图 → 液位 → 透明流动帧，设备元素全部可见。已同步到 `dist/luadb`，自检仍全绿。

## 五、未跑项（需真机）

- [ ] PC 模拟器真跑（沙箱环境无 SDL2/无头浏览器；JS 逻辑已过 node --check，Lua 已过 luaparser，XML 已过 schema 自检）。
- [ ] 上真机看 HZFont 字宽与可读性（尤其 18 号按钮文字）。
- [ ] 触摸响应、按钮手感、流动帧顺滑度。
- [ ] 真机刷新率、输出条 `set_size` / 液位换图是否卡顿、图片缓存峰值。
- [ ] 接真 PLC 数据后的联锁逻辑与长时间稳定性。

> 未跑项不计入「沙箱已验证」；按 §7 两档验证规则如实登记，不在自检清单里打勾假装过了。
