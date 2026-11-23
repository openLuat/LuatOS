# 版面与素材清单（制品，由 tools/gen_xml.py 从 ui_spec.py 生成）

目标机型 Air8607（Air1603）+ 10 寸 RGB 1024×600 + GT911 电容触摸；
画布 1024×600 固定分辨率，绝对定位，坐标全部落在 4px 栅格。

| 项 | 值 |
| --- | --- |
| 页面数 | 3（run / man / test） |
| 组件累计 | 152 / 512（整份文档跨页相加） |
| 资源数 | 图片 107 + 字体 1 / 256 |
| 事件处理函数 | 20 个 |

## 素材清单

| 资源 ID | 尺寸 | 像素占用 | 用途 |
| --- | --- | --- | --- |
| `bg_run` | 1024×600 | 2400 KB | 运行总览页背景：工艺流程图 + 电磁阀/步进/加热三块操作面板 + 实时状态面板 |
| `bg_man` | 1024×600 | 2400 KB | 环节手动页背景：六张环节卡片 + 状态摘要条 |
| `bg_test` | 1024×600 | 2400 KB | 膨胀参数页背景：表格框 + 曲线面板 + 四个结果框 |
| `im_alarm` | 264×36 | 37 KB | 急停告警胶囊（与状态文字同位互斥显示） |
| `im_car` | 248×24 | 23 KB | 活塞软塞（横向填满腔体，11 个预置位置共用这一张） |
| `im_valve_o` | 36×36 | 5 KB | 电磁阀指示灯-开 |
| `im_valve_c` | 36×36 | 5 KB | 电磁阀指示灯-关 |
| `im_lamp_idle` | 32×32 | 4 KB | 状态灯-待机 |
| `im_lamp_run` | 32×32 | 4 KB | 状态灯-运行 |
| `im_lamp_done` | 32×32 | 4 KB | 状态灯-已完成 |
| `im_lamp_alarm` | 32×32 | 4 KB | 状态灯-告警 |
| `im_liq00` | 248×178 | 172 KB | 腔体液面 0 mm（腔高 0%，整块素材，运行时按级 set_src） |
| `im_rod00` | 12×168 | 7 KB | 活塞杆 0 mm 档（电机底到软塞顶，11 张长度配套软塞档位） |
| `im_liq01` | 248×178 | 172 KB | 腔体液面 11 mm（腔高 6%，整块素材，运行时按级 set_src） |
| `im_rod01` | 12×157 | 7 KB | 活塞杆 11 mm 档（电机底到软塞顶，11 张长度配套软塞档位） |
| `im_liq02` | 248×178 | 172 KB | 腔体液面 22 mm（腔高 12%，整块素材，运行时按级 set_src） |
| `im_rod02` | 12×146 | 6 KB | 活塞杆 22 mm 档（电机底到软塞顶，11 张长度配套软塞档位） |
| `im_liq03` | 248×178 | 172 KB | 腔体液面 33 mm（腔高 19%，整块素材，运行时按级 set_src） |
| `im_rod03` | 12×135 | 6 KB | 活塞杆 33 mm 档（电机底到软塞顶，11 张长度配套软塞档位） |
| `im_liq04` | 248×178 | 172 KB | 腔体液面 44 mm（腔高 25%，整块素材，运行时按级 set_src） |
| `im_rod04` | 12×124 | 5 KB | 活塞杆 44 mm 档（电机底到软塞顶，11 张长度配套软塞档位） |
| `im_liq05` | 248×178 | 172 KB | 腔体液面 55 mm（腔高 31%，整块素材，运行时按级 set_src） |
| `im_rod05` | 12×113 | 5 KB | 活塞杆 55 mm 档（电机底到软塞顶，11 张长度配套软塞档位） |
| `im_liq06` | 248×178 | 172 KB | 腔体液面 66 mm（腔高 37%，整块素材，运行时按级 set_src） |
| `im_rod06` | 12×102 | 4 KB | 活塞杆 66 mm 档（电机底到软塞顶，11 张长度配套软塞档位） |
| `im_liq07` | 248×178 | 172 KB | 腔体液面 77 mm（腔高 43%，整块素材，运行时按级 set_src） |
| `im_rod07` | 12×91 | 4 KB | 活塞杆 77 mm 档（电机底到软塞顶，11 张长度配套软塞档位） |
| `im_liq08` | 248×178 | 172 KB | 腔体液面 88 mm（腔高 49%，整块素材，运行时按级 set_src） |
| `im_rod08` | 12×80 | 3 KB | 活塞杆 88 mm 档（电机底到软塞顶，11 张长度配套软塞档位） |
| `im_liq09` | 248×178 | 172 KB | 腔体液面 99 mm（腔高 56%，整块素材，运行时按级 set_src） |
| `im_rod09` | 12×69 | 3 KB | 活塞杆 99 mm 档（电机底到软塞顶，11 张长度配套软塞档位） |
| `im_liq10` | 248×178 | 172 KB | 腔体液面 110 mm（腔高 62%，整块素材，运行时按级 set_src） |
| `im_rod10` | 12×58 | 2 KB | 活塞杆 110 mm 档（电机底到软塞顶，11 张长度配套软塞档位） |
| `st1_g` | 158×34 | 20 KB | 步骤条-未开始 |
| `st1_a` | 158×34 | 20 KB | 步骤条-进行中 |
| `st1_d` | 158×34 | 20 KB | 步骤条-已完成 |
| `st2_g` | 158×34 | 20 KB | 步骤条-未开始 |
| `st2_a` | 158×34 | 20 KB | 步骤条-进行中 |
| `st2_d` | 158×34 | 20 KB | 步骤条-已完成 |
| `st3_g` | 158×34 | 20 KB | 步骤条-未开始 |
| `st3_a` | 158×34 | 20 KB | 步骤条-进行中 |
| `st3_d` | 158×34 | 20 KB | 步骤条-已完成 |
| `st4_g` | 158×34 | 20 KB | 步骤条-未开始 |
| `st4_a` | 158×34 | 20 KB | 步骤条-进行中 |
| `st4_d` | 158×34 | 20 KB | 步骤条-已完成 |
| `st5_g` | 158×34 | 20 KB | 步骤条-未开始 |
| `st5_a` | 158×34 | 20 KB | 步骤条-进行中 |
| `st5_d` | 158×34 | 20 KB | 步骤条-已完成 |
| `st6_g` | 158×34 | 20 KB | 步骤条-未开始 |
| `st6_a` | 158×34 | 20 KB | 步骤条-进行中 |
| `st6_d` | 158×34 | 20 KB | 步骤条-已完成 |
| `bt_auto` / `bt_auto_p` | 140×56 | 30 KB | 按钮 自动运行（green） |
| `bt_auto_p` | 140×56 | 30 KB | 按钮 自动运行 按下态 |
| `bt_pause` / `bt_pause_p` | 96×56 | 21 KB | 按钮 暂停（gray） |
| `bt_pause_p` | 96×56 | 21 KB | 按钮 暂停 按下态 |
| `bt_reset` / `bt_reset_p` | 96×56 | 21 KB | 按钮 复位（gray） |
| `bt_reset_p` | 96×56 | 21 KB | 按钮 复位 按下态 |
| `bt_estop` / `bt_estop_p` | 112×56 | 24 KB | 按钮 急停（red） |
| `bt_estop_p` | 112×56 | 24 KB | 按钮 急停 按下态 |
| `bt_back` / `bt_back_p` | 112×56 | 24 KB | 按钮 返回运行（blue） |
| `bt_back_p` | 112×56 | 24 KB | 按钮 返回运行 按下态 |
| `bt_gman` / `bt_gman_p` | 112×56 | 24 KB | 按钮 手动控制（blue） |
| `bt_gman_p` | 112×56 | 24 KB | 按钮 手动控制 按下态 |
| `bt_gtest` / `bt_gtest_p` | 112×56 | 24 KB | 按钮 膨胀参数（blue） |
| `bt_gtest_p` | 112×56 | 24 KB | 按钮 膨胀参数 按下态 |
| `bt_tstart` / `bt_tstart_p` | 128×56 | 28 KB | 按钮 开始测试（green） |
| `bt_tstart_p` | 128×56 | 28 KB | 按钮 开始测试 按下态 |
| `bt_tstop` / `bt_tstop_p` | 112×56 | 24 KB | 按钮 停止测试（red） |
| `bt_tstop_p` | 112×56 | 24 KB | 按钮 停止测试 按下态 |
| `bt_recalc` / `bt_recalc_p` | 112×56 | 24 KB | 按钮 重新计算（gray） |
| `bt_recalc_p` | 112×56 | 24 KB | 按钮 重新计算 按下态 |
| `bt_go` / `bt_go_p` | 112×48 | 21 KB | 按钮 启动（green） |
| `bt_go_p` | 112×48 | 21 KB | 按钮 启动 按下态 |
| `bt_halt` / `bt_halt_p` | 112×48 | 21 KB | 按钮 停止（gray） |
| `bt_halt_p` | 112×48 | 21 KB | 按钮 停止 按下态 |
| `bt_v1o` / `bt_v1o_p` | 112×48 | 21 KB | 按钮 阀1开（green） |
| `bt_v1o_p` | 112×48 | 21 KB | 按钮 阀1开 按下态 |
| `bt_v1c` / `bt_v1c_p` | 112×48 | 21 KB | 按钮 阀1关（gray） |
| `bt_v1c_p` | 112×48 | 21 KB | 按钮 阀1关 按下态 |
| `bt_v2o` / `bt_v2o_p` | 112×48 | 21 KB | 按钮 阀2开（green） |
| `bt_v2o_p` | 112×48 | 21 KB | 按钮 阀2开 按下态 |
| `bt_v2c` / `bt_v2c_p` | 112×48 | 21 KB | 按钮 阀2关（gray） |
| `bt_v2c_p` | 112×48 | 21 KB | 按钮 阀2关 按下态 |
| `bt_up` / `bt_up_p` | 112×48 | 21 KB | 按钮 上行（blue） |
| `bt_up_p` | 112×48 | 21 KB | 按钮 上行 按下态 |
| `bt_down` / `bt_down_p` | 112×48 | 21 KB | 按钮 下行（gray） |
| `bt_down_p` | 112×48 | 21 KB | 按钮 下行 按下态 |
| `bt_mstop` / `bt_mstop_p` | 120×48 | 22 KB | 按钮 步进停（gray） |
| `bt_mstop_p` | 120×48 | 22 KB | 按钮 步进停 按下态 |
| `bt_s5` / `bt_s5_p` | 72×48 | 13 KB | 按钮 5mm（gray） |
| `bt_s5_p` | 72×48 | 13 KB | 按钮 5mm 按下态 |
| `bt_s10` / `bt_s10_p` | 72×48 | 13 KB | 按钮 10mm（gray） |
| `bt_s10_p` | 72×48 | 13 KB | 按钮 10mm 按下态 |
| `bt_s25` / `bt_s25_p` | 72×48 | 13 KB | 按钮 25mm（gray） |
| `bt_s25_p` | 72×48 | 13 KB | 按钮 25mm 按下态 |
| `bt_nup` / `bt_nup_p` | 68×48 | 12 KB | 按钮 上移（blue） |
| `bt_nup_p` | 68×48 | 12 KB | 按钮 上移 按下态 |
| `bt_ndn` / `bt_ndn_p` | 68×48 | 12 KB | 按钮 下移（gray） |
| `bt_ndn_p` | 68×48 | 12 KB | 按钮 下移 按下态 |
| `bt_heat_on` / `bt_heat_on_p` | 100×48 | 18 KB | 按钮 加热开（green） |
| `bt_heat_on_p` | 100×48 | 18 KB | 按钮 加热开 按下态 |
| `bt_heat_off` / `bt_heat_off_p` | 100×48 | 18 KB | 按钮 加热关（gray） |
| `bt_heat_off_p` | 100×48 | 18 KB | 按钮 加热关 按下态 |
| `bt_minus` / `bt_minus_p` | 72×48 | 13 KB | 按钮 -0.5（gray） |
| `bt_minus_p` | 72×48 | 13 KB | 按钮 -0.5 按下态 |
| `bt_plus` / `bt_plus_p` | 72×48 | 13 KB | 按钮 +0.5（blue） |
| `bt_plus_p` | 72×48 | 13 KB | 按钮 +0.5 按下态 |

## 页面元素

### run（76 个组件）

| 组件 | ID | x | y | w | h | 说明 |
| --- | --- | --- | --- | --- | --- | --- |
| image | `tb_bg` | 0 | 0 | 1024 | 600 | bg_run |
| label | `tb_title` | 22 | 8 | 380 | 44 | 蒸气压测定仪 |
| image | `tb_lamp` | 392 | 18 | 32 | 32 | im_lamp_idle |
| label | `tb_badge` | 434 | 20 | 300 | 32 | 待机 |
| image | `tb_alarm` | 430 | 14 | 264 | 36 | im_alarm |
| label | `tb_cd` | 768 | 12 | 232 | 20 | 2026/11/17 |
| label | `tb_ct` | 768 | 30 | 232 | 28 | 12:00:00 |
| image | `stp1` | 16 | 76 | 158 | 34 | st1_g |
| image | `stp2` | 180 | 76 | 158 | 34 | st2_g |
| image | `stp3` | 344 | 76 | 158 | 34 | st3_g |
| image | `stp4` | 508 | 76 | 158 | 34 | st4_g |
| image | `stp5` | 672 | 76 | 158 | 34 | st5_g |
| image | `stp6` | 836 | 76 | 158 | 34 | st6_g |
| image | `pv_liq` | 190 | 166 | 248 | 178 | im_liq10 |
| image | `pv_rod0` | 308 | 154 | 12 | 168 | im_rod00 |
| image | `pv_rod1` | 308 | 154 | 12 | 157 | im_rod01 |
| image | `pv_rod2` | 308 | 154 | 12 | 146 | im_rod02 |
| image | `pv_rod3` | 308 | 154 | 12 | 135 | im_rod03 |
| image | `pv_rod4` | 308 | 154 | 12 | 124 | im_rod04 |
| image | `pv_rod5` | 308 | 154 | 12 | 113 | im_rod05 |
| image | `pv_rod6` | 308 | 154 | 12 | 102 | im_rod06 |
| image | `pv_rod7` | 308 | 154 | 12 | 91 | im_rod07 |
| image | `pv_rod8` | 308 | 154 | 12 | 80 | im_rod08 |
| image | `pv_rod9` | 308 | 154 | 12 | 69 | im_rod09 |
| image | `pv_rod10` | 308 | 154 | 12 | 58 | im_rod10 |
| image | `pv_car0` | 190 | 320 | 248 | 24 | im_car |
| image | `pv_car1` | 190 | 309 | 248 | 24 | im_car |
| image | `pv_car2` | 190 | 298 | 248 | 24 | im_car |
| image | `pv_car3` | 190 | 287 | 248 | 24 | im_car |
| image | `pv_car4` | 190 | 276 | 248 | 24 | im_car |
| image | `pv_car5` | 190 | 265 | 248 | 24 | im_car |
| image | `pv_car6` | 190 | 254 | 248 | 24 | im_car |
| image | `pv_car7` | 190 | 243 | 248 | 24 | im_car |
| image | `pv_car8` | 190 | 232 | 248 | 24 | im_car |
| image | `pv_car9` | 190 | 221 | 248 | 24 | im_car |
| image | `pv_car10` | 190 | 210 | 248 | 24 | im_car |
| image | `pv_v1` | 232 | 372 | 36 | 36 | im_valve_c |
| image | `pv_v2` | 364 | 372 | 36 | 36 | im_valve_c |
| label | `pv_pv` | 26 | 170 | 70 | 40 | 0.0 |
| label | `pv_pu` | 96 | 178 | 60 | 22 | kPa |
| label | `pv_tv` | 26 | 234 | 70 | 36 | 25.0 |
| label | `pv_tu` | 96 | 242 | 60 | 22 | ℃ |
| label | `pv_lv` | 452 | 208 | 140 | 24 | 液面高度 0.0 mm |
| label | `pv_cv` | 452 | 240 | 140 | 24 | 软塞高度 0.0 mm |
| label | `pv_xv` | 452 | 272 | 140 | 24 | 体积比 1.000 |
| image | `dv_v1o` | 628 | 156 | 112 | 48 | bt_v1o |
| image | `dv_v1c` | 748 | 156 | 112 | 48 | bt_v1c |
| label | `ds_v1` | 872 | 166 | 120 | 24 | 阀1:关 |
| image | `dv_v2o` | 628 | 208 | 112 | 48 | bt_v2o |
| image | `dv_v2c` | 748 | 208 | 112 | 48 | bt_v2c |
| label | `ds_v2` | 872 | 218 | 120 | 24 | 阀2:关 |
| image | `dv_up` | 628 | 304 | 112 | 48 | bt_up |
| image | `dv_down` | 748 | 304 | 112 | 48 | bt_down |
| image | `dv_mstop` | 868 | 304 | 120 | 48 | bt_mstop |
| label | `ds_step` | 862 | 273 | 132 | 22 | 步长 10 |
| image | `dv_s5` | 628 | 358 | 72 | 48 | bt_s5 |
| image | `dv_s10` | 702 | 358 | 72 | 48 | bt_s10 |
| image | `dv_s25` | 776 | 358 | 72 | 48 | bt_s25 |
| image | `dv_nup` | 850 | 358 | 68 | 48 | bt_nup |
| image | `dv_ndn` | 920 | 358 | 68 | 48 | bt_ndn |
| label | `hs_temp` | 628 | 433 | 180 | 22 | 设定 37.5℃ |
| image | `hs_on` | 628 | 460 | 100 | 48 | bt_heat_on |
| image | `hs_off` | 736 | 460 | 100 | 48 | bt_heat_off |
| image | `hs_minus` | 844 | 460 | 72 | 48 | bt_minus |
| image | `hs_plus` | 924 | 460 | 72 | 48 | bt_plus |
| label | `rs_1` | 30 | 456 | 180 | 22 | 环节 -- |
| label | `rs_2` | 222 | 456 | 180 | 22 | 阀1:关 阀2:关 |
| label | `rs_3` | 414 | 456 | 176 | 22 | 步进 0.0 mm |
| label | `rs_4` | 30 | 484 | 180 | 22 | 液位 0% |
| label | `rs_5` | 222 | 484 | 180 | 22 | 加热 关 |
| label | `rs_6` | 414 | 484 | 176 | 22 | 蒸气压 -- kPa |
| image | `bd_auto` | 16 | 532 | 140 | 56 | bt_auto |
| image | `bd_pause` | 164 | 532 | 96 | 56 | bt_pause |
| image | `bd_reset` | 268 | 532 | 96 | 56 | bt_reset |
| image | `bd_estop` | 372 | 532 | 112 | 56 | bt_estop |
| image | `bd_test` | 504 | 532 | 112 | 56 | bt_gtest |

### man（47 个组件）

| 组件 | ID | x | y | w | h | 说明 |
| --- | --- | --- | --- | --- | --- | --- |
| image | `tb_bg` | 0 | 0 | 1024 | 600 | bg_man |
| label | `tb_title` | 22 | 8 | 380 | 44 | 环节手动 |
| image | `tb_lamp` | 392 | 18 | 32 | 32 | im_lamp_idle |
| label | `tb_badge` | 434 | 20 | 300 | 32 | 待机 |
| image | `tb_alarm` | 430 | 14 | 264 | 36 | im_alarm |
| label | `tb_cd` | 768 | 12 | 232 | 20 | 2026/11/17 |
| label | `tb_ct` | 768 | 30 | 232 | 28 | 12:00:00 |
| image | `stp1` | 16 | 76 | 158 | 34 | st1_g |
| image | `stp2` | 180 | 76 | 158 | 34 | st2_g |
| image | `stp3` | 344 | 76 | 158 | 34 | st3_g |
| image | `stp4` | 508 | 76 | 158 | 34 | st4_g |
| image | `stp5` | 672 | 76 | 158 | 34 | st5_g |
| image | `stp6` | 836 | 76 | 158 | 34 | st6_g |
| image | `mv_l1` | 32 | 162 | 32 | 32 | im_lamp_idle |
| label | `mv_s1` | 74 | 164 | 240 | 26 | 待机 |
| image | `mv_g1` | 30 | 204 | 112 | 48 | bt_go |
| image | `mv_h1` | 156 | 204 | 112 | 48 | bt_halt |
| image | `mv_l2` | 364 | 162 | 32 | 32 | im_lamp_idle |
| label | `mv_s2` | 406 | 164 | 240 | 26 | 待机 |
| image | `mv_g2` | 362 | 204 | 112 | 48 | bt_go |
| image | `mv_h2` | 488 | 204 | 112 | 48 | bt_halt |
| image | `mv_l3` | 696 | 162 | 32 | 32 | im_lamp_idle |
| label | `mv_s3` | 738 | 164 | 240 | 26 | 待机 |
| image | `mv_g3` | 694 | 204 | 112 | 48 | bt_go |
| image | `mv_h3` | 820 | 204 | 112 | 48 | bt_halt |
| image | `mv_l4` | 32 | 310 | 32 | 32 | im_lamp_idle |
| label | `mv_s4` | 74 | 312 | 240 | 26 | 待机 |
| image | `mv_g4` | 30 | 352 | 112 | 48 | bt_go |
| image | `mv_h4` | 156 | 352 | 112 | 48 | bt_halt |
| image | `mv_l5` | 364 | 310 | 32 | 32 | im_lamp_idle |
| label | `mv_s5` | 406 | 312 | 240 | 26 | 待机 |
| image | `mv_g5` | 362 | 352 | 112 | 48 | bt_go |
| image | `mv_h5` | 488 | 352 | 112 | 48 | bt_halt |
| image | `mv_l6` | 696 | 310 | 32 | 32 | im_lamp_idle |
| label | `mv_s6` | 738 | 312 | 240 | 26 | 待机 |
| image | `mv_g6` | 694 | 352 | 112 | 48 | bt_go |
| image | `mv_h6` | 820 | 352 | 112 | 48 | bt_halt |
| label | `ms_1` | 30 | 452 | 300 | 22 | 当前环节 -- |
| label | `ms_2` | 350 | 452 | 300 | 22 | 腔体压力 0.0 kPa |
| label | `ms_3` | 670 | 452 | 320 | 22 | 腔体温度 25.0 ℃ |
| label | `ms_4` | 30 | 482 | 300 | 22 | 步进位置 0.0 mm |
| label | `ms_5` | 350 | 482 | 300 | 22 | 加热 关 / 阀1:关 阀2:关 |
| label | `ms_6` | 670 | 482 | 320 | 22 | 蒸气压 -- kPa |
| image | `bd_back` | 16 | 532 | 112 | 56 | bt_back |
| image | `bd_test` | 136 | 532 | 112 | 56 | bt_gtest |
| image | `bd_reset` | 744 | 532 | 96 | 56 | bt_reset |
| image | `bd_estop` | 856 | 532 | 112 | 56 | bt_estop |

### test（29 个组件）

| 组件 | ID | x | y | w | h | 说明 |
| --- | --- | --- | --- | --- | --- | --- |
| image | `tb_bg` | 0 | 0 | 1024 | 600 | bg_test |
| label | `tb_title` | 22 | 8 | 380 | 44 | 膨胀参数 |
| image | `tb_lamp` | 392 | 18 | 32 | 32 | im_lamp_idle |
| label | `tb_badge` | 434 | 20 | 300 | 32 | 待机 |
| image | `tb_alarm` | 430 | 14 | 264 | 36 | im_alarm |
| label | `tb_cd` | 768 | 12 | 232 | 20 | 2026/11/17 |
| label | `tb_ct` | 768 | 30 | 232 | 28 | 12:00:00 |
| image | `stp1` | 16 | 76 | 158 | 34 | st1_g |
| image | `stp2` | 180 | 76 | 158 | 34 | st2_g |
| image | `stp3` | 344 | 76 | 158 | 34 | st3_g |
| image | `stp4` | 508 | 76 | 158 | 34 | st4_g |
| image | `stp5` | 672 | 76 | 158 | 34 | st5_g |
| image | `stp6` | 836 | 76 | 158 | 34 | st6_g |
| table | `ts_tbl` | 16 | 120 | 600 | 200 |  |
| chart | `ts_chart` | 26 | 392 | 580 | 108 |  |
| label | `ts_a` | 632 | 162 | 200 | 60 | 0.0 |
| label | `ts_au` | 838 | 182 | 80 | 28 | kPa |
| label | `ts_b` | 632 | 288 | 200 | 52 | 0.0 |
| label | `ts_bu` | 838 | 300 | 80 | 26 | kPa |
| label | `ts_c` | 632 | 400 | 200 | 52 | 0.0 |
| label | `ts_cu` | 838 | 412 | 80 | 26 | kPa |
| label | `ts_r` | 760 | 474 | 220 | 28 | 0.00 kPa |
| image | `bd_tstart` | 16 | 532 | 128 | 56 | bt_tstart |
| image | `bd_tstop` | 152 | 532 | 112 | 56 | bt_tstop |
| image | `bd_calc` | 272 | 532 | 112 | 56 | bt_recalc |
| image | `bd_man` | 392 | 532 | 112 | 56 | bt_gman |
| image | `bd_back` | 512 | 532 | 112 | 56 | bt_back |
| image | `bd_reset` | 744 | 532 | 96 | 56 | bt_reset |
| image | `bd_estop` | 856 | 532 | 112 | 56 | bt_estop |

