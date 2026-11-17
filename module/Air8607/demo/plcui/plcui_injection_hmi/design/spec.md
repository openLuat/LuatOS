# PLCUI 设计说明 · 智能注塑车间 1# 产线监控总览

> 本文件由 `tools/spec_gen.py` 从 `code/res/main.xml`、`code/ui_vars.lua`、`tools/tiles.py` 机械生成，**数字与烧进设备的 XML 完全一致**，不要手改；改布局请回 `design/index.html` + `design/theme.css`，再重跑导出一遍。

| 项 | 值 |
|---|---|
| 目标平台 | Air8607（Air1603 平台）+ 10 寸 RGB 1024×600 |
| 画布 | 1024×600，1:1 设计，不做响应式 |
| 页面数 | 4（entry = `overview`） |
| 组件数 | 185 / 512 |
| 资源数 | 52 / 256 |
| XML 体积 | 27.6 KB / 256 KB |
| 栅格 | 4px；所有坐标为整数绝对值，不用 z-index（层叠 = 书写顺序） |
| 素材来源 | 全部 `design/theme.css` 自画 → 无头 Chromium 透明底截图 → 按包围盒裁切 |

## 一、色板

| 变量 | 值 | 用途 |
|---|---|---|
| `--m1` | `#43494f` | 机箱拉丝亮面 |
| `--m2` | `#2d3237` | 面板主色 |
| `--m3` | `#1c2024` | 页面底色（XML 的 page background） |
| `--m4` | `#111417` | 凹陷 / 槽底 |
| `--amber` | `#ffb43a` | 温度主色、主数值 |
| `--cyan` | `#48d8d0` | 压力主色、可操作项 |
| `--green` | `#63e08a` | 运行 / 正常 |
| `--red` | `#ff4b40` | 急停 / 严重报警 |
| `--led` | `#ffd15c` | 数码管辉光 |

## 二、页面与组件清单

「烘图」= 质感不随数据变，整块栅格化成 PNG；「活组件」= 随数据变，必须是 PLCUI 组件。

### overview（`background=#1c2024`）

| # | id | 组件 | x | y | w | h | 资源 / 内容 | 性质 | 绑定变量 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `bg` | image | 0 | 0 | 1024 | 600 | bg_ov | 烘图 | — |
| 2 | `shift` | label | 381 | 32 | 74 | 12 | 白班 A 组 | 活组件 | `shift`（text） |
| 3 | `clock` | label | 474 | 21 | 188 | 20 | 2026-11-16 16:36:02 | 活组件 | `clock`（text） |
| 4 | `lamp` | image | 673 | 20 | 20 | 20 | lamp_run | 烘图 | `lamp`（src） |
| 5 | `status_text` | label | 698 | 30 | 80 | 14 | 运行中 | 活组件 | `status_text`（text） |
| 6 | `estop_flag` | image | 796 | 21 | 84 | 22 | flag | 烘图 | `estop`（hidden_invert） |
| 7 | `kpi1` | label | 26 | 77 | 150 | 22 | 1 286 | 活组件 | `kpi1`（text） |
| 8 | `foot1` | label | 21 | 103 | 225 | 10 | 当班目标 1600 件 · 达成 80.4% | 活组件 | `foot1`（text） |
| 9 | `kpi2` | label | 279 | 77 | 150 | 22 | 89.4 | 活组件 | `kpi2`（text） |
| 10 | `kpi3` | label | 532 | 77 | 150 | 22 | 222.8 | 活组件 | `kpi3`（text） |
| 11 | `foot3` | label | 527 | 103 | 225 | 10 | 设定值 220 ℃ · 上限 245 ℃ | 活组件 | `foot3`（text） |
| 12 | `kpi4` | label | 785 | 77 | 150 | 22 | 28.4 | 活组件 | `kpi4`（text） |
| 13 | `foot4` | label | 780 | 103 | 225 | 10 | 标准节拍 28.0 s · 偏差 +1.4% | 活组件 | `foot4`（text） |
| 14 | `btn_start` | image | 15 | 487 | 76 | 66 | btnstart_n / btnstart_p | 烘图·按钮 | 事件 `line_start` |
| 15 | `btn_stop` | image | 89 | 487 | 76 | 66 | btnstop_n / btnstop_p | 烘图·按钮 | 事件 `line_stop` |
| 16 | `btn_reset` | image | 163 | 487 | 76 | 66 | btnreset_n / btnreset_p | 烘图·按钮 | 事件 `line_reset` |
| 17 | `btn_estop` | image | 242 | 480 | 74 | 74 | estop_n / estop_p | 烘图·按钮 | 事件 `line_estop` |
| 18 | `flow0` | image | 334 | 503 | 96 | 14 | flow_0 | 烘图 | — |
| 19 | `flow1` | image | 452 | 503 | 96 | 14 | flow_0 | 烘图 | — |
| 20 | `flow2` | image | 570 | 503 | 96 | 14 | flow_0 | 烘图 | — |
| 21 | `pipe_txt` | label | 334 | 534 | 340 | 12 | 阀门 开 · 介质流动 · DN40 · 16 MPa | 活组件 | `pipe_txt`（text） |
| 22 | `knob_sp` | image | 714 | 484 | 66 | 66 | knobsp | 烘图 | `knob_angle`（angle） |
| 23 | `sp_val` | label | 794 | 488 | 102 | 20 | 220 | 活组件 | `sp_val`（text） |
| 24 | `sl_sp` | slider | 790 | 510 | 170 | 24 | 180 ~ 260，值 220 | 活组件 | `sp` → `sp_change` |
| 25 | `total_out` | label | 66 | 570 | 80 | 16 | 86 542 | 活组件 | `total_out`（text） |
| 26 | `comm_led` | image | 149 | 572 | 13 | 13 | dot_run | 烘图 | `comm_led`（src） |
| 27 | `comm_txt` | label | 164 | 572 | 260 | 12 | PROFINET · 通讯正常 · 延迟 4 ms | 活组件 | `comm_txt`（text） |
| 28 | `tab_ov` | image | 724 | 567 | 66 | 24 | tab_ov_n / ✓tab_ov_c | 烘图·按钮 | 事件 `go_overview` |
| 29 | `tab_tr` | image | 796 | 567 | 66 | 24 | tab_tr_n / ✓tab_tr_c | 烘图·按钮 | 事件 `go_trend` |
| 30 | `tab_al` | image | 868 | 567 | 66 | 24 | tab_al_n / ✓tab_al_c | 烘图·按钮 | 事件 `go_alarm` |
| 31 | `tab_st` | image | 940 | 567 | 66 | 24 | tab_st_n / ✓tab_st_c | 烘图·按钮 | 事件 `go_settings` |
| 32 | `tab_badge` | image | 924 | 561 | 16 | 16 | badge | 烘图 | `tab_num`（badge_hidden） |
| 33 | `tab_num` | label | 924 | 562 | 16 | 14 | 3 | 活组件 | `tab_num`（text） |
| 34 | `ch_ov` | chart | 52 | 148 | 536 | 148 | line，60 点，3 系列 | 活组件 | — |
| 35 | `nd_t` | image | 33 | 334 | 96 | 96 | nd_needle | 烘图 | `nd_t`（angle） |
| 36 | `cap_t` | image | 75 | 376 | 12 | 12 | g_cap | 烘图 | — |
| 37 | `v_t` | label | 33 | 432 | 96 | 15 | 222.8 | 活组件 | `v_t`（text） |
| 38 | `nd_p` | image | 205 | 334 | 96 | 96 | nd_needle | 烘图 | `nd_p`（angle） |
| 39 | `cap_p` | image | 247 | 376 | 12 | 12 | g_cap | 烘图 | — |
| 40 | `v_p` | label | 205 | 432 | 96 | 15 | 92.0 | 活组件 | `v_p`（text） |
| 41 | `dev_title` | label | 362 | 334 | 256 | 12 | ■ 全线综合参数 / LINE | 活组件 | `dev_title`（text） |
| 42 | `dt1` | label | 368 | 364 | 114 | 14 | 222.8 ℃ | 活组件 | `dt1`（text） |
| 43 | `dt2` | label | 500 | 364 | 114 | 14 | 92.0 MPa | 活组件 | `dt2`（text） |
| 44 | `dt3` | label | 368 | 398 | 114 | 14 | 220 ℃ | 活组件 | `dt3`（text） |
| 45 | `dt4` | label | 500 | 398 | 114 | 14 | 89.4 % | 活组件 | `dt4`（text） |
| 46 | `dt5` | label | 368 | 432 | 114 | 14 | 2 / 3 台 | 活组件 | `dt5`（text） |
| 47 | `dt6` | label | 500 | 432 | 114 | 14 | 1286 件 | 活组件 | `dt6`（text） |
| 48 | `led0` | image | 647 | 153 | 16 | 16 | dot_run | 烘图 | `led0`（src） |
| 49 | `st0` | label | 666 | 169 | 52 | 12 | 运行 | 活组件 | `st0`（state_color） |
| 50 | `ld0` | label | 920 | 168 | 36 | 12 | 82 % | 活组件 | `ld0`（text） |
| 51 | `bar0` | image | 666 | 181 | 243 | 6 | barfill_g | 烘图 | `bar0`（size） |
| 52 | `sel0` | image | 958 | 159 | 24 | 22 | arr_n / ✓arr_c | 烘图·按钮 | `sel0` → `dev_sel0` |
| 53 | `led1` | image | 647 | 199 | 16 | 16 | dot_run | 烘图 | `led1`（src） |
| 54 | `st1` | label | 666 | 215 | 52 | 12 | 待机 | 活组件 | `st1`（state_color） |
| 55 | `ld1` | label | 920 | 214 | 36 | 12 | 15 % | 活组件 | `ld1`（text） |
| 56 | `bar1` | image | 666 | 227 | 44 | 6 | barfill_g | 烘图 | `bar1`（size） |
| 57 | `sel1` | image | 958 | 205 | 24 | 22 | arr_n / ✓arr_c | 烘图·按钮 | `sel1` → `dev_sel1` |
| 58 | `led2` | image | 647 | 245 | 16 | 16 | dot_run | 烘图 | `led2`（src） |
| 59 | `st2` | label | 666 | 261 | 52 | 12 | 故障 | 活组件 | `st2`（state_color） |
| 60 | `ld2` | label | 920 | 260 | 36 | 12 | 0 % | 活组件 | `ld2`（text） |
| 61 | `bar2` | image | 666 | 273 | 1 | 6 | barfill_g | 烘图 | `bar2`（size） |
| 62 | `sel2` | image | 958 | 251 | 24 | 22 | arr_n / ✓arr_c | 烘图·按钮 | `sel2` → `dev_sel2` |
| 63 | `al_cnt` | label | 940 | 306 | 58 | 11 | 2 未确认 | 活组件 | `al_cnt`（text） |
| 64 | `ad0` | image | 648 | 334 | 14 | 14 | dot_run | 烘图 | `ad0`（src） |
| 65 | `alv0` | label | 664 | 328 | 30 | 11 | 严重 | 活组件 | `alv0`（level_color） |
| 66 | `alt0` | label | 698 | 329 | 56 | 10 | 14:12:30 | 活组件 | `alt0`（text） |
| 67 | `ald0` | label | 664 | 341 | 242 | 12 | 液压系统压力低于安全阈值 62 MPa | 活组件 | `ald0`（text） |
| 68 | `ak0` | image | 950 | 329 | 48 | 22 | ack_n / ack_p | 烘图·按钮 | `ak0` → `ack0` |
| 69 | `ad1` | image | 648 | 372 | 14 | 14 | dot_run | 烘图 | `ad1`（src） |
| 70 | `alv1` | label | 664 | 366 | 30 | 11 | 警告 | 活组件 | `alv1`（level_color） |
| 71 | `alt1` | label | 698 | 367 | 56 | 10 | 13:58:02 | 活组件 | `alt1`（text） |
| 72 | `ald1` | label | 664 | 379 | 242 | 12 | 2# 模温偏差 +4.5 ℃，接近上限 | 活组件 | `ald1`（text） |
| 73 | `ak1` | image | 950 | 367 | 48 | 22 | ack_n / ack_p | 烘图·按钮 | `ak1` → `ack1` |
| 74 | `ad2` | image | 648 | 410 | 14 | 14 | dot_run | 烘图 | `ad2`（src） |
| 75 | `alv2` | label | 664 | 404 | 30 | 11 | 警告 | 活组件 | `alv2`（level_color） |
| 76 | `alt2` | label | 698 | 405 | 56 | 10 | 13:40:11 | 活组件 | `alt2`（text） |
| 77 | `ald2` | label | 664 | 417 | 242 | 12 | 润滑油脂位偏低，建议补充 | 活组件 | `ald2`（text） |
| 78 | `ak2` | image | 950 | 405 | 48 | 22 | ack_n / ack_p | 烘图·按钮 | `ak2` → `ack2` |

### trend（`background=#1c2024`）

| # | id | 组件 | x | y | w | h | 资源 / 内容 | 性质 | 绑定变量 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `bg` | image | 0 | 0 | 1024 | 600 | bg_tr | 烘图 | — |
| 2 | `shift` | label | 381 | 32 | 74 | 12 | 白班 A 组 | 活组件 | `shift`（text） |
| 3 | `clock` | label | 474 | 21 | 188 | 20 | 2026-11-16 16:36:11 | 活组件 | `clock`（text） |
| 4 | `lamp` | image | 673 | 20 | 20 | 20 | lamp_run | 烘图 | `lamp`（src） |
| 5 | `status_text` | label | 698 | 30 | 80 | 14 | 运行中 | 活组件 | `status_text`（text） |
| 6 | `estop_flag` | image | 796 | 21 | 84 | 22 | flag | 烘图 | `estop`（hidden_invert） |
| 7 | `btn_start` | image | 15 | 487 | 76 | 66 | btnstart_n / btnstart_p | 烘图·按钮 | 事件 `line_start` |
| 8 | `btn_stop` | image | 89 | 487 | 76 | 66 | btnstop_n / btnstop_p | 烘图·按钮 | 事件 `line_stop` |
| 9 | `btn_reset` | image | 163 | 487 | 76 | 66 | btnreset_n / btnreset_p | 烘图·按钮 | 事件 `line_reset` |
| 10 | `btn_estop` | image | 242 | 480 | 74 | 74 | estop_n / estop_p | 烘图·按钮 | 事件 `line_estop` |
| 11 | `flow0` | image | 334 | 503 | 96 | 14 | flow_0 | 烘图 | — |
| 12 | `flow1` | image | 452 | 503 | 96 | 14 | flow_0 | 烘图 | — |
| 13 | `flow2` | image | 570 | 503 | 96 | 14 | flow_0 | 烘图 | — |
| 14 | `pipe_txt` | label | 334 | 534 | 340 | 12 | 阀门 开 · 介质流动 · DN40 · 16 MPa | 活组件 | `pipe_txt`（text） |
| 15 | `knob_sp` | image | 714 | 484 | 66 | 66 | knobsp | 烘图 | `knob_angle`（angle） |
| 16 | `sp_val` | label | 794 | 488 | 102 | 20 | 220 | 活组件 | `sp_val`（text） |
| 17 | `sl_sp` | slider | 790 | 510 | 170 | 24 | 180 ~ 260，值 220 | 活组件 | `sp` → `sp_change` |
| 18 | `total_out` | label | 66 | 570 | 80 | 16 | 86 542 | 活组件 | `total_out`（text） |
| 19 | `comm_led` | image | 149 | 572 | 13 | 13 | dot_run | 烘图 | `comm_led`（src） |
| 20 | `comm_txt` | label | 164 | 572 | 260 | 12 | PROFINET · 通讯正常 · 延迟 4 ms | 活组件 | `comm_txt`（text） |
| 21 | `tab_ov` | image | 724 | 567 | 66 | 24 | tab_ov_n / ✓tab_ov_c | 烘图·按钮 | 事件 `go_overview` |
| 22 | `tab_tr` | image | 796 | 567 | 66 | 24 | tab_tr_n / ✓tab_tr_c | 烘图·按钮 | 事件 `go_trend` |
| 23 | `tab_al` | image | 868 | 567 | 66 | 24 | tab_al_n / ✓tab_al_c | 烘图·按钮 | 事件 `go_alarm` |
| 24 | `tab_st` | image | 940 | 567 | 66 | 24 | tab_st_n / ✓tab_st_c | 烘图·按钮 | 事件 `go_settings` |
| 25 | `tab_badge` | image | 924 | 561 | 16 | 16 | badge | 烘图 | `tab_num`（badge_hidden） |
| 26 | `tab_num` | label | 924 | 562 | 16 | 14 | 3 | 活组件 | `tab_num`（text） |
| 27 | `ch_tr` | chart | 70 | 172 | 924 | 232 | line，80 点，3 系列 | 活组件 | — |
| 28 | `st_t` | label | 22 | 392 | 150 | 26 | 222.6 | 活组件 | `st_t`（text） |
| 29 | `st_p` | label | 275 | 392 | 150 | 26 | 91.5 | 活组件 | `st_p`（text） |
| 30 | `st_sp` | label | 528 | 392 | 150 | 26 | 220 | 活组件 | `st_sp`（text） |
| 31 | `st_d` | label | 781 | 392 | 150 | 26 | +2.6 | 活组件 | `st_d`（text） |

### alarm（`background=#1c2024`）

| # | id | 组件 | x | y | w | h | 资源 / 内容 | 性质 | 绑定变量 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `bg` | image | 0 | 0 | 1024 | 600 | bg_al | 烘图 | — |
| 2 | `shift` | label | 381 | 32 | 74 | 12 | 白班 A 组 | 活组件 | `shift`（text） |
| 3 | `clock` | label | 474 | 21 | 188 | 20 | 2026-11-16 16:36:26 | 活组件 | `clock`（text） |
| 4 | `lamp` | image | 673 | 20 | 20 | 20 | lamp_run | 烘图 | `lamp`（src） |
| 5 | `status_text` | label | 698 | 30 | 80 | 14 | 运行中 | 活组件 | `status_text`（text） |
| 6 | `estop_flag` | image | 796 | 21 | 84 | 22 | flag | 烘图 | `estop`（hidden_invert） |
| 7 | `btn_start` | image | 15 | 487 | 76 | 66 | btnstart_n / btnstart_p | 烘图·按钮 | 事件 `line_start` |
| 8 | `btn_stop` | image | 89 | 487 | 76 | 66 | btnstop_n / btnstop_p | 烘图·按钮 | 事件 `line_stop` |
| 9 | `btn_reset` | image | 163 | 487 | 76 | 66 | btnreset_n / btnreset_p | 烘图·按钮 | 事件 `line_reset` |
| 10 | `btn_estop` | image | 242 | 480 | 74 | 74 | estop_n / estop_p | 烘图·按钮 | 事件 `line_estop` |
| 11 | `flow0` | image | 334 | 503 | 96 | 14 | flow_0 | 烘图 | — |
| 12 | `flow1` | image | 452 | 503 | 96 | 14 | flow_0 | 烘图 | — |
| 13 | `flow2` | image | 570 | 503 | 96 | 14 | flow_0 | 烘图 | — |
| 14 | `pipe_txt` | label | 334 | 534 | 340 | 12 | 阀门 开 · 介质流动 · DN40 · 16 MPa | 活组件 | `pipe_txt`（text） |
| 15 | `knob_sp` | image | 714 | 484 | 66 | 66 | knobsp | 烘图 | `knob_angle`（angle） |
| 16 | `sp_val` | label | 794 | 488 | 102 | 20 | 220 | 活组件 | `sp_val`（text） |
| 17 | `sl_sp` | slider | 790 | 510 | 170 | 24 | 180 ~ 260，值 220 | 活组件 | `sp` → `sp_change` |
| 18 | `total_out` | label | 66 | 570 | 80 | 16 | 86 542 | 活组件 | `total_out`（text） |
| 19 | `comm_led` | image | 149 | 572 | 13 | 13 | dot_run | 烘图 | `comm_led`（src） |
| 20 | `comm_txt` | label | 164 | 572 | 260 | 12 | PROFINET · 通讯正常 · 延迟 4 ms | 活组件 | `comm_txt`（text） |
| 21 | `tab_ov` | image | 724 | 567 | 66 | 24 | tab_ov_n / ✓tab_ov_c | 烘图·按钮 | 事件 `go_overview` |
| 22 | `tab_tr` | image | 796 | 567 | 66 | 24 | tab_tr_n / ✓tab_tr_c | 烘图·按钮 | 事件 `go_trend` |
| 23 | `tab_al` | image | 868 | 567 | 66 | 24 | tab_al_n / ✓tab_al_c | 烘图·按钮 | 事件 `go_alarm` |
| 24 | `tab_st` | image | 940 | 567 | 66 | 24 | tab_st_n / ✓tab_st_c | 烘图·按钮 | 事件 `go_settings` |
| 25 | `tab_badge` | image | 924 | 561 | 16 | 16 | badge | 烘图 | `tab_num`（badge_hidden） |
| 26 | `tab_num` | label | 924 | 562 | 16 | 14 | 3 | 活组件 | `tab_num`（text） |
| 27 | `al_stat` | label | 24 | 70 | 340 | 16 | 未确认报警 3 条 · 累计记录 4 条 | 活组件 | `al_stat`（text） |
| 28 | `b_ackall` | image | 740 | 59 | 134 | 40 | btnackall_n / btnackall_p | 烘图·按钮 | 事件 `alarm_ack_all` |
| 29 | `b_clr` | image | 874 | 59 | 130 | 40 | btnclr_n / btnclr_p | 烘图·按钮 | 事件 `alarm_clear` |
| 30 | `tb_al` | table | 22 | 140 | 980 | 300 | 7 行 × 6 列（含表头） | 活组件 | — |

### settings（`background=#1c2024`）

| # | id | 组件 | x | y | w | h | 资源 / 内容 | 性质 | 绑定变量 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `bg` | image | 0 | 0 | 1024 | 600 | bg_st | 烘图 | — |
| 2 | `shift` | label | 381 | 32 | 74 | 12 | 白班 A 组 | 活组件 | `shift`（text） |
| 3 | `clock` | label | 474 | 21 | 188 | 20 | 2026-11-16 16:36:42 | 活组件 | `clock`（text） |
| 4 | `lamp` | image | 673 | 20 | 20 | 20 | lamp_run | 烘图 | `lamp`（src） |
| 5 | `status_text` | label | 698 | 30 | 80 | 14 | 运行中 | 活组件 | `status_text`（text） |
| 6 | `estop_flag` | image | 796 | 21 | 84 | 22 | flag | 烘图 | `estop`（hidden_invert） |
| 7 | `btn_start` | image | 15 | 487 | 76 | 66 | btnstart_n / btnstart_p | 烘图·按钮 | 事件 `line_start` |
| 8 | `btn_stop` | image | 89 | 487 | 76 | 66 | btnstop_n / btnstop_p | 烘图·按钮 | 事件 `line_stop` |
| 9 | `btn_reset` | image | 163 | 487 | 76 | 66 | btnreset_n / btnreset_p | 烘图·按钮 | 事件 `line_reset` |
| 10 | `btn_estop` | image | 242 | 480 | 74 | 74 | estop_n / estop_p | 烘图·按钮 | 事件 `line_estop` |
| 11 | `flow0` | image | 334 | 503 | 96 | 14 | flow_0 | 烘图 | — |
| 12 | `flow1` | image | 452 | 503 | 96 | 14 | flow_0 | 烘图 | — |
| 13 | `flow2` | image | 570 | 503 | 96 | 14 | flow_0 | 烘图 | — |
| 14 | `pipe_txt` | label | 334 | 534 | 340 | 12 | 阀门 开 · 介质流动 · DN40 · 16 MPa | 活组件 | `pipe_txt`（text） |
| 15 | `knob_sp` | image | 714 | 484 | 66 | 66 | knobsp | 烘图 | `knob_angle`（angle） |
| 16 | `sp_val` | label | 794 | 488 | 102 | 20 | 220 | 活组件 | `sp_val`（text） |
| 17 | `sl_sp` | slider | 790 | 510 | 170 | 24 | 180 ~ 260，值 220 | 活组件 | `sp` → `sp_change` |
| 18 | `total_out` | label | 66 | 570 | 80 | 16 | 86 542 | 活组件 | `total_out`（text） |
| 19 | `comm_led` | image | 149 | 572 | 13 | 13 | dot_run | 烘图 | `comm_led`（src） |
| 20 | `comm_txt` | label | 164 | 572 | 260 | 12 | PROFINET · 通讯正常 · 延迟 4 ms | 活组件 | `comm_txt`（text） |
| 21 | `tab_ov` | image | 724 | 567 | 66 | 24 | tab_ov_n / ✓tab_ov_c | 烘图·按钮 | 事件 `go_overview` |
| 22 | `tab_tr` | image | 796 | 567 | 66 | 24 | tab_tr_n / ✓tab_tr_c | 烘图·按钮 | 事件 `go_trend` |
| 23 | `tab_al` | image | 868 | 567 | 66 | 24 | tab_al_n / ✓tab_al_c | 烘图·按钮 | 事件 `go_alarm` |
| 24 | `tab_st` | image | 940 | 567 | 66 | 24 | tab_st_n / ✓tab_st_c | 烘图·按钮 | 事件 `go_settings` |
| 25 | `tab_badge` | image | 924 | 561 | 16 | 16 | badge | 烘图 | `tab_num`（badge_hidden） |
| 26 | `tab_num` | label | 924 | 562 | 16 | 14 | 3 | 活组件 | `tab_num`（text） |
| 27 | `p1` | textarea | 156 | 99 | 94 | 18 | 初始 `245`，键盘 `kb_num` | 活组件 | `p1` → `param_submit` |
| 28 | `p2` | textarea | 156 | 153 | 94 | 18 | 初始 `195`，键盘 `kb_num` | 活组件 | `p2` → `param_submit` |
| 29 | `p3` | textarea | 156 | 207 | 94 | 18 | 初始 `12.0`，键盘 `kb_num` | 活组件 | `p3` → `param_submit` |
| 30 | `p4` | textarea | 156 | 261 | 94 | 18 | 初始 `45`，键盘 `kb_num` | 活组件 | `p4` → `param_submit` |
| 31 | `p5` | textarea | 156 | 315 | 94 | 18 | 初始 `250`，键盘 `kb_num` | 活组件 | `p5` → `param_submit` |
| 32 | `p6` | textarea | 156 | 369 | 94 | 18 | 初始 `115`，键盘 `kb_num` | 活组件 | `p6` → `param_submit` |
| 33 | `sw1` | image | 766 | 96 | 48 | 22 | sw_off / ✓sw_on | 烘图·按钮 | `sw1` → `sw1` |
| 34 | `sw2` | image | 766 | 150 | 48 | 22 | sw_off / ✓sw_on | 烘图·按钮 | `sw2` → `sw2` |
| 35 | `sw3` | image | 766 | 204 | 48 | 22 | sw_off / ✓sw_on | 烘图·按钮 | `sw3` → `sw3` |
| 36 | `st_br` | label | 866 | 264 | 60 | 16 | 70% | 活组件 | `st_br`（text） |
| 37 | `sl_br` | slider | 648 | 264 | 200 | 24 | 0 ~ 100，值 70 | 活组件 | `bright` → `bright_change` |
| 38 | `b_save` | image | 18 | 410 | 138 | 40 | btnsave_n / btnsave_p | 烘图·按钮 | 事件 `param_save` |
| 39 | `st_msg` | label | 168 | 422 | 600 | 14 | 最近保存：本班次未写入 · 校验码 0x1A4F | 活组件 | `st_msg`（text） |
| 40 | `kb_num` | keyboard | 214 | 250 | 596 | 190 | layout=number | 活组件 | — |

## 三、资源清单

文件名（含扩展名）≤ 23 字节；`src` 写资源 ID 不写路径；全部平铺在 `code/res/`，烧录时与 `main.xml` 同级。

| 资源 ID | 文件 | 尺寸 | 解码内存 | 显示尺寸（去 pad） |
|---|---|---|---|---|
| `bg_ov` | `bg_ov.jpg` | 1024×600 | 2400.0 KB | 整页背景 |
| `lamp_run` | `lamp_run.png` | 20×20 | 1.6 KB | 14×14 |
| `lamp_idle` | `lamp_idle.png` | 20×20 | 1.6 KB | 14×14 |
| `lamp_alarm` | `lamp_alarm.png` | 20×20 | 1.6 KB | 14×14 |
| `flag` | `flag.png` | 84×22 | 7.2 KB | 84×22 |
| `btnstart_n` | `btnstart_n.png` | 76×66 | 19.6 KB | 66×56 |
| `btnstart_p` | `btnstart_p.png` | 76×66 | 19.6 KB | 66×56 |
| `btnstop_n` | `btnstop_n.png` | 76×66 | 19.6 KB | 66×56 |
| `btnstop_p` | `btnstop_p.png` | 76×66 | 19.6 KB | 66×56 |
| `btnreset_n` | `btnreset_n.png` | 76×66 | 19.6 KB | 66×56 |
| `btnreset_p` | `btnreset_p.png` | 76×66 | 19.6 KB | 66×56 |
| `estop_n` | `estop_n.png` | 74×74 | 21.4 KB | 66×66 |
| `estop_p` | `estop_p.png` | 74×74 | 21.4 KB | 66×66 |
| `flow_0` | `flow_0.png` | 96×14 | 5.2 KB | 96×14 |
| `flow_1` | `flow_1.png` | 96×14 | 5.2 KB | 96×14 |
| `flow_2` | `flow_2.png` | 96×14 | 5.2 KB | 96×14 |
| `flow_3` | `flow_3.png` | 96×14 | 5.2 KB | 96×14 |
| `knobsp` | `knobsp.png` | 66×66 | 17.0 KB | 62×62 |
| `thumb` | `thumb.png` | 24×24 | 2.2 KB | 24×24 |
| `dot_run` | `dot_run.png` | 16×16 | 1.0 KB | 10×10 |
| `dot_idle` | `dot_idle.png` | 16×16 | 1.0 KB | 10×10 |
| `dot_fault` | `dot_fault.png` | 16×16 | 1.0 KB | 10×10 |
| `tab_ov_n` | `tab_ov_n.png` | 66×24 | 6.2 KB | 66×24 |
| `tab_ov_c` | `tab_ov_c.png` | 66×24 | 6.2 KB | 66×24 |
| `tab_tr_n` | `tab_tr_n.png` | 66×24 | 6.2 KB | 66×24 |
| `tab_tr_c` | `tab_tr_c.png` | 66×24 | 6.2 KB | 66×24 |
| `tab_al_n` | `tab_al_n.png` | 66×24 | 6.2 KB | 66×24 |
| `tab_al_c` | `tab_al_c.png` | 66×24 | 6.2 KB | 66×24 |
| `tab_st_n` | `tab_st_n.png` | 66×24 | 6.2 KB | 66×24 |
| `tab_st_c` | `tab_st_c.png` | 66×24 | 6.2 KB | 66×24 |
| `badge` | `badge.png` | 16×16 | 1.0 KB | 16×16 |
| `nd_needle` | `nd_needle.png` | 96×96 | 36.0 KB | 96×96 |
| `g_cap` | `g_cap.png` | 14×14 | 0.8 KB | 14×14 |
| `barfill_g` | `barfill_g.png` | 296×6 | 6.9 KB | 296×6 |
| `barfill_i` | `barfill_i.png` | 296×6 | 6.9 KB | 296×6 |
| `barfill_f` | `barfill_f.png` | 296×6 | 6.9 KB | 296×6 |
| `arr_n` | `arr_n.png` | 24×22 | 2.1 KB | 20×18 |
| `arr_c` | `arr_c.png` | 24×22 | 2.1 KB | 20×18 |
| `ack_n` | `ack_n.png` | 48×22 | 4.1 KB | 44×18 |
| `ack_p` | `ack_p.png` | 48×22 | 4.1 KB | 44×18 |
| `ack_d` | `ack_d.png` | 48×22 | 4.1 KB | 44×18 |
| `bg_tr` | `bg_tr.jpg` | 1024×600 | 2400.0 KB | 整页背景 |
| `bg_al` | `bg_al.jpg` | 1024×600 | 2400.0 KB | 整页背景 |
| `btnackall_n` | `btnackall_n.png` | 134×40 | 20.9 KB | 126×32 |
| `btnackall_p` | `btnackall_p.png` | 134×40 | 20.9 KB | 126×32 |
| `btnclr_n` | `btnclr_n.png` | 130×40 | 20.3 KB | 122×32 |
| `btnclr_p` | `btnclr_p.png` | 130×40 | 20.3 KB | 122×32 |
| `bg_st` | `bg_st.jpg` | 1024×600 | 2400.0 KB | 整页背景 |
| `sw_on` | `sw_on.png` | 48×22 | 4.1 KB | 48×22 |
| `sw_off` | `sw_off.png` | 48×22 | 4.1 KB | 48×22 |
| `btnsave_n` | `btnsave_n.png` | 138×40 | 21.6 KB | 130×32 |
| `btnsave_p` | `btnsave_p.png` | 138×40 | 21.6 KB | 130×32 |

合计解码内存约 **9.8 MB**（PC 侧缓存 4MB，单片最大 2.3 MB）。

## 四、数据控件参数

### chart `ch_ov`（页 `overview`）

| 属性 | 值 | 说明 |
|---|---|---|
| point-count | 60 | Lua 侧 `set_values` 的数组长度必须精确等于它 |
| y-min / y-max | 0 / 100 | 传入值为归一化后的 0~100 |
| hdiv / vdiv | 0 / 0 | 网格线全靠背景图，组件网格关掉 |
| bg-opacity | 0 | 0 = 透明，露出底图的刻度与网格 |

| 系列 | 颜色 | 物理量 | 换算（视图层） |
|---|---|---|---|
| `t` | `#ffb43a` | 料筒温度 | (实测 − 180) / (260 − 180) × 100 |
| `p` | `#48d8d0` | 注射压力 | (实测 − 60) / (120 − 60) × 100 |
| `s` | `#ff7a3c` | 设定值 | (设定 − 180) / (260 − 180) × 100 |

> 换算是 `data_app.norm_t` / `norm_p` 做的，**数据层仍存真实单位（℃ / MPa）**；整条数组原子更新，任一值越界则整条不改。

### slider `sl_sp`（页 `overview`）

180 ~ 260，step=1，knob-src=`thumb`，track-color=`#0d1113`。

旋钮图必须是**正方形**，边长等于滑块短边（横向滑块取 `h`=24），换滑块高度要同步重出 `thumb.png`。

### chart `ch_tr`（页 `trend`）

| 属性 | 值 | 说明 |
|---|---|---|
| point-count | 80 | Lua 侧 `set_values` 的数组长度必须精确等于它 |
| y-min / y-max | 0 / 100 | 传入值为归一化后的 0~100 |
| hdiv / vdiv | 0 / 0 | 网格线全靠背景图，组件网格关掉 |
| bg-opacity | 0 | 0 = 透明，露出底图的刻度与网格 |

| 系列 | 颜色 | 物理量 | 换算（视图层） |
|---|---|---|---|
| `t` | `#ffb43a` | 料筒温度 | (实测 − 180) / (260 − 180) × 100 |
| `p` | `#48d8d0` | 注射压力 | (实测 − 60) / (120 − 60) × 100 |
| `s` | `#ff7a3c` | 设定值 | (设定 − 180) / (260 − 180) × 100 |

> 换算是 `data_app.norm_t` / `norm_p` 做的，**数据层仍存真实单位（℃ / MPa）**；整条数组原子更新，任一值越界则整条不改。

### slider `sl_sp`（页 `trend`）

180 ~ 260，step=1，knob-src=`thumb`，track-color=`#0d1113`。

旋钮图必须是**正方形**，边长等于滑块短边（横向滑块取 `h`=24），换滑块高度要同步重出 `thumb.png`。

### table `tb_al`（页 `alarm`）

rows=7（**含表头**）× columns=6，row-height=42，组件高 300 → 7×42 = 294 ≤ 300，不溢出。

列宽 `80,150,180,380,110,80`，列对齐 `left,left,left,left,center,center`。单元格文本由 `data_app.alarm_rows()` 提供，每格 ≤ 511 字节。

### slider `sl_sp`（页 `alarm`）

180 ~ 260，step=1，knob-src=`thumb`，track-color=`#0d1113`。

旋钮图必须是**正方形**，边长等于滑块短边（横向滑块取 `h`=24），换滑块高度要同步重出 `thumb.png`。

### slider `sl_sp`（页 `settings`）

180 ~ 260，step=1，knob-src=`thumb`，track-color=`#0d1113`。

旋钮图必须是**正方形**，边长等于滑块短边（横向滑块取 `h`=24），换滑块高度要同步重出 `thumb.png`。

### slider `sl_br`（页 `settings`）

0 ~ 100，step=1，knob-src=`thumb`，track-color=`#0d1113`。

旋钮图必须是**正方形**，边长等于滑块短边（横向滑块取 `h`=24），换滑块高度要同步重出 `thumb.png`。

## 五、事件对照

`main.xml` 里每个 `on-*` 都必须在 `code/ui_app.lua` 的 `H` 表里同名注册，否则 load 报 `E_HANDLER`。

| 页面 | 组件 id | 事件 | handler | 行为 |
|---|---|---|---|---|
| overview | `btn_start` | `on-click` | `H.line_start` | 产线启动，恢复正常配色与流动 |
| overview | `btn_stop` | `on-click` | `H.line_stop` | 产线停止，管路条纹定格第 0 帧 |
| overview | `btn_reset` | `on-click` | `H.line_reset` | 故障复位，清急停旗标 |
| overview | `btn_estop` | `on-click` | `H.line_estop` | 急停：首按进「待确认」（按钮切 pressed 态 + 5s 超时），再按才停机 |
| overview | `sl_sp` | `on-change` | `H.sp_change` | 温度设定滑块改动 → 写 data_app.set_setpoint |
| overview | `tab_ov` | `on-click` | `H.go_overview` | 切到总览页（延 40ms 再刷） |
| overview | `tab_tr` | `on-click` | `H.go_trend` | 切到趋势页 |
| overview | `tab_al` | `on-click` | `H.go_alarm` | 切到报警页 |
| overview | `tab_st` | `on-click` | `H.go_settings` | 切到参数页 |
| overview | `sel0` | `on-click` | `H.dev_sel0` | 选中 1# 设备，详情面板换数据 |
| overview | `sel1` | `on-click` | `H.dev_sel1` | 选中 2# 设备 |
| overview | `sel2` | `on-click` | `H.dev_sel2` | 选中 3# 设备 |
| overview | `ak0` | `on-click` | `H.ack0` | 确认第 1 条报警 |
| overview | `ak1` | `on-click` | `H.ack1` | 确认第 2 条报警 |
| overview | `ak2` | `on-click` | `H.ack2` | 确认第 3 条报警 |
| trend | `btn_start` | `on-click` | `H.line_start` | 产线启动，恢复正常配色与流动 |
| trend | `btn_stop` | `on-click` | `H.line_stop` | 产线停止，管路条纹定格第 0 帧 |
| trend | `btn_reset` | `on-click` | `H.line_reset` | 故障复位，清急停旗标 |
| trend | `btn_estop` | `on-click` | `H.line_estop` | 急停：首按进「待确认」（按钮切 pressed 态 + 5s 超时），再按才停机 |
| trend | `sl_sp` | `on-change` | `H.sp_change` | 温度设定滑块改动 → 写 data_app.set_setpoint |
| trend | `tab_ov` | `on-click` | `H.go_overview` | 切到总览页（延 40ms 再刷） |
| trend | `tab_tr` | `on-click` | `H.go_trend` | 切到趋势页 |
| trend | `tab_al` | `on-click` | `H.go_alarm` | 切到报警页 |
| trend | `tab_st` | `on-click` | `H.go_settings` | 切到参数页 |
| alarm | `btn_start` | `on-click` | `H.line_start` | 产线启动，恢复正常配色与流动 |
| alarm | `btn_stop` | `on-click` | `H.line_stop` | 产线停止，管路条纹定格第 0 帧 |
| alarm | `btn_reset` | `on-click` | `H.line_reset` | 故障复位，清急停旗标 |
| alarm | `btn_estop` | `on-click` | `H.line_estop` | 急停：首按进「待确认」（按钮切 pressed 态 + 5s 超时），再按才停机 |
| alarm | `sl_sp` | `on-change` | `H.sp_change` | 温度设定滑块改动 → 写 data_app.set_setpoint |
| alarm | `tab_ov` | `on-click` | `H.go_overview` | 切到总览页（延 40ms 再刷） |
| alarm | `tab_tr` | `on-click` | `H.go_trend` | 切到趋势页 |
| alarm | `tab_al` | `on-click` | `H.go_alarm` | 切到报警页 |
| alarm | `tab_st` | `on-click` | `H.go_settings` | 切到参数页 |
| alarm | `b_ackall` | `on-click` | `H.alarm_ack_all` | 一键确认全部未确认报警 |
| alarm | `b_clr` | `on-click` | `H.alarm_clear` | 清除已确认记录 |
| settings | `btn_start` | `on-click` | `H.line_start` | 产线启动，恢复正常配色与流动 |
| settings | `btn_stop` | `on-click` | `H.line_stop` | 产线停止，管路条纹定格第 0 帧 |
| settings | `btn_reset` | `on-click` | `H.line_reset` | 故障复位，清急停旗标 |
| settings | `btn_estop` | `on-click` | `H.line_estop` | 急停：首按进「待确认」（按钮切 pressed 态 + 5s 超时），再按才停机 |
| settings | `sl_sp` | `on-change` | `H.sp_change` | 温度设定滑块改动 → 写 data_app.set_setpoint |
| settings | `tab_ov` | `on-click` | `H.go_overview` | 切到总览页（延 40ms 再刷） |
| settings | `tab_tr` | `on-click` | `H.go_trend` | 切到趋势页 |
| settings | `tab_al` | `on-click` | `H.go_alarm` | 切到报警页 |
| settings | `tab_st` | `on-click` | `H.go_settings` | 切到参数页 |
| settings | `p1` | `on-submit` | `H.param_submit` | 参数框确认，越界不落盘并回滚显示 |
| settings | `p1` | `on-cancel` | `H.param_cancel` | 参数框取消，回滚到上次落盘值 |
| settings | `p2` | `on-submit` | `H.param_submit` | 参数框确认，越界不落盘并回滚显示 |
| settings | `p2` | `on-cancel` | `H.param_cancel` | 参数框取消，回滚到上次落盘值 |
| settings | `p3` | `on-submit` | `H.param_submit` | 参数框确认，越界不落盘并回滚显示 |
| settings | `p3` | `on-cancel` | `H.param_cancel` | 参数框取消，回滚到上次落盘值 |
| settings | `p4` | `on-submit` | `H.param_submit` | 参数框确认，越界不落盘并回滚显示 |
| settings | `p4` | `on-cancel` | `H.param_cancel` | 参数框取消，回滚到上次落盘值 |
| settings | `p5` | `on-submit` | `H.param_submit` | 参数框确认，越界不落盘并回滚显示 |
| settings | `p5` | `on-cancel` | `H.param_cancel` | 参数框取消，回滚到上次落盘值 |
| settings | `p6` | `on-submit` | `H.param_submit` | 参数框确认，越界不落盘并回滚显示 |
| settings | `p6` | `on-cancel` | `H.param_cancel` | 参数框取消，回滚到上次落盘值 |
| settings | `sw1` | `on-click` | `H.sw1` | 报警蜂鸣器 开 / 关 |
| settings | `sw2` | `on-click` | `H.sw2` | 班次自动切换 开 / 关（08:00 / 20:00） |
| settings | `sw3` | `on-click` | `H.sw3` | 趋势历史存储 开 / 关（本地 24h 环形缓冲） |
| settings | `sl_br` | `on-change` | `H.bright_change` | 背光亮度滑块 → 写 st.bright（含 PWM 输出） |
| settings | `b_save` | `on-click` | `H.param_save` | 参数落盘并提示已下发 |

