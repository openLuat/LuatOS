# pwm_step_pulse — PWM 多步脉冲演示

演示 `pwm.step_add / step_start / step_stop / step_clear`（多步脉冲）与 `pwm.open(..., pnum)`（单段定数脉冲），
并通过 `pwm.on` 接收 `EV_PULSE_DONE / EV_STEP_DONE` 完成事件。

## 一、适用平台

| 项目 | 说明 |
|---|---|
| step pulse | 依赖 BSP 实现 `luat_pwm_step_pulse_add/clear/start/stop` + `luat_pwm_set_isr_callback`，目前仅 **Air160X 系列（Air1601/Air1602 等）** |
| 其它平台 | `step_add` 返回 `false`，脚本自动降级为 `pnum` 定数脉冲演示 |
| PC 模拟器 | 不支持（`luat_pwm_step_pulse_*` 为 weak 实现，直接返回 -1） |

## 二、通道与引脚

| 模组 | 可用通道 | 备注 |
|---|---|---|
| Air1601 | PWM1、PWM3 | 本 demo 默认 PWM3 |
| Air1602 | PWM1、PWM2、PWM3 | 本 demo 默认 PWM3 |

- PWM3 输出在 **43 脚（GPIO13 复用）**，可直接用示波器/逻辑分析仪抓取，无需额外飞线改动。
- PWM1 的引脚复用见《Air1601/1602 管脚复用表》，使用前需按复用表配置（未在本 demo 中固化，属待实测项）。
- 其它平台按 `rtos.bsp()` 自动落到 `demo/pwm` 的默认通道：EC618 → ch4（GPIO27/NetLed），EC718 → ch2（GPIO25）。

## 三、预期现象

1. **单段定数脉冲**：1kHz、占空比 50%、20 个脉冲 → 逻辑分析仪上 20 个 1ms 周期方波（高电平 0.5ms），
   输出完自动停止，日志出现 `事件 EV_PULSE_DONE`。
2. **多步脉冲**：一组 7 段共 220 个脉冲，周期由 2ms 逐步缩短到 0.25ms（500Hz → 4kHz）再回到 2ms，
   理论总时长约 165ms，结束后日志出现 `事件 EV_STEP_DONE`。
3. **重复启动**：不重新 `step_add`，直接再 `step_start`，波形与上一轮一致 —— 验证 `step_start` 不清除步骤。
4. **中途停止**：1kHz × 1000 个（1s）启动后 200ms 调 `step_stop`，波形立即截止。

## 四、参数单位（关键）

| 接口 | 占空比单位 | 脉冲数 |
|---|---|---|
| `pwm.open/setup(ch, freq, duty, pnum, precision)` | `duty/precision`，默认 precision=100，即 50 = 50% | `pnum`：0 持续，1 单次，≥2 指定个数 |
| `pwm.setDuty(ch, duty)` | 同上，依赖 setup 时的 precision | — |
| `pwm.step_add(ch, freq, duty, num)` | **千分比**，500 = 50% | `num` 不能为 0 |
| `pwm.step_clear/step_start/step_stop(ch)` | — | — |

## 五、已知限制

- `step_start` 不清步骤；`step_stop` 与 `step_clear` 都会清空该通道已添加的步骤。
- 脉冲输出期间执行 Flash 擦写（FOTA / FSKV / 文件系统操作）可能因中断延迟导致脉冲失真，测试时避开。
- 完成事件只在 `pnum ≠ 0`（或 step 整组输出结束）时触发，持续输出不会回调。
- 实际频率精度受 PWM 分频器限制，高频段（>100kHz）误差会明显增大，本 demo 的 500Hz~4kHz 属于可靠区间。

## 六、验证要点

1. 上电 1s 后看日志：`step pulse 能力探测(step_add) -> true` 说明 BSP 支持，进入完整流程。
2. 若为 `false`，确认固件是否为 Air160X 且已实现 step pulse（`luat_pwm.c` 中 `luat_pwm_step_pulse_add` 的 weak 实现被覆盖）。
3. 抓波形时注意 `step_stop` 后引脚电平取决于停止时的电平，必要时用 `gpio.setup` 拉回确定电平。
4. 时长偏差：日志中的"理论 xxx ms"与示波器实测值的差值主要由分段切换开销造成，属正常。
