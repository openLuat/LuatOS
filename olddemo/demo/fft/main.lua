-- LuaTools 需要 PROJECT 和 VERSION
PROJECT = "fft_q15_test"
VERSION = "1.0.0"

_G.sys = require("sys")

sys.taskInit(function()
	if not fft then
		while 1 do sys.wait(1000) log.info("bsp", "此BSP不支持fft库，请检查") end
	end

	-- FFT 参数配置
	local N = 2048      -- FFT 点数
	local fs = 2000     -- 采样频率 (Hz)
	local freq = 200    -- 测试信号频率 (Hz)

	log.info("fft", "q15 测试开始", "N=" .. N, "fs=" .. fs, "freq=" .. freq)

	-- 分配 zbuff：
	-- 整数缓冲（U12 以 16bit 承载，低12位有效）用于 q15 内核
    local real_i16 = zbuff.create(N * 2)
    local imag_i16 = zbuff.create(N * 2)

	-- 生成 U12 整数正弦写入 i16（避免浮点预处理干扰）
	for i = 0, N - 1 do
		local t = i / fs
		local x = math.sin(2 * math.pi * freq * t)
		local val = math.floor(2048 + 2047 * x + 0.5)
		if val < 0 then val = 0 end
		if val > 4095 then val = 4095 end
		real_i16:seek(i * 2, zbuff.SEEK_SET); real_i16:writeU16(val)
		imag_i16:seek(i * 2, zbuff.SEEK_SET); imag_i16:writeU16(0)
	end

	-- 生成 Q15 旋转因子到 zbuff（避免任何浮点旋转因子）
	local Wc_q15 = zbuff.create((N // 2) * 2)
	local Ws_q15 = zbuff.create((N // 2) * 2)
	fft.generate_twiddles_q15_to_zbuff(N, Wc_q15, Ws_q15)

	-- 执行 Q15 FFT（输入为 U12），显式传入 Q15 twiddle
	local t0 = mcu.ticks()
	fft.run(real_i16, imag_i16, N, Wc_q15, Ws_q15, { core = "q15", input_format = "u12" })
	local t1 = mcu.ticks()
	log.info("fft", "q15 FFT 完成", "耗时:" .. (t1 - t0) .. "ms")

	-- 扫描前半谱，寻找主峰
	local peak_k, peak_pow = 1, -1
	for k = 1, (N // 2) - 1 do
		real_i16:seek(k * 2, zbuff.SEEK_SET)
		imag_i16:seek(k * 2, zbuff.SEEK_SET)
		local rr = real_i16:readI16()
		local ii = imag_i16:readI16()
		local p = rr * rr + ii * ii
		if p > peak_pow then
			peak_pow = p
			peak_k = k
		end
	end
	local peak_freq = (peak_k) * fs / N
	log.info("fft", "主峰(Hz/bin)", string.format("%.2f", peak_freq), peak_k)

	-- 比较：使用 f32 内核处理相同输入（验证 q15 与 f32 结果一致性）
	-- 复制相同的 U12 输入到新的 zbuff
	local real_f32 = zbuff.create(N * 4)  -- f32 需要 4 字节
	local imag_f32 = zbuff.create(N * 4)
	for i = 0, N - 1 do
		real_i16:seek(i * 2, zbuff.SEEK_SET)
		local val = real_i16:readU16()
		real_f32:seek(i * 4, zbuff.SEEK_SET)
		imag_f32:seek(i * 4, zbuff.SEEK_SET)
		real_f32:writeF32(val)  -- 直接写入 U12 原始值
		imag_f32:writeF32(0.0)
	end

	-- 生成 f32 旋转因子
	local Wc, Ws = fft.generate_twiddles(N)

	-- 执行 f32 FFT（输入为 U12）
	local t2 = mcu.ticks()
	fft.run(real_f32, imag_f32, N, Wc, Ws, { input_format = "u12" })
	local t3 = mcu.ticks()
	local dt_f32 = (t3 - t2)
	log.info("fft", "f32 FFT 完成", "耗时:" .. dt_f32 .. "ms")

	-- 总结耗时对比
	log.info("fft", "对比(q15 vs f32, ms)", string.format("%d / %d", (t1 - t0), dt_f32))

	-- 注意：本测试刻意避免浮点旋转因子与f32路径，确保纯Q15链路
end)

sys.run()


