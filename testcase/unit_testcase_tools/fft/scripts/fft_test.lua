local fft_tests = {}

function fft_tests.create_u12_signal(N, fs, freq, amplitude, offset)
    local real_i16 = zbuff.create(N * 2)
    local imag_i16 = zbuff.create(N * 2)

    for i = 0, N - 1 do
        local t = i / fs
        local x = math.sin(2 * math.pi * freq * t)
        local val = math.floor(offset + amplitude * x + 0.5)
        if val < 0 then
            val = 0
        end
        if val > 4095 then
            val = 4095
        end

        real_i16:seek(i * 2, zbuff.SEEK_SET)
        real_i16:writeU16(val)

        imag_i16:seek(i * 2, zbuff.SEEK_SET)
        imag_i16:writeU16(0)
    end

    return real_i16, imag_i16
end

function fft_tests.test_fft_generate_twiddle()
    -- 范围内测试：
    -- 选择数据2,2⁵ = 32,2¹⁰ = 1024,2¹⁴ = 16384等
    local test_data = {2, 32, 1024, 16384}
    for i, num in ipairs(test_data) do
        -- 直接调用，不使用pcall
        local Wc, Ws = fft.generate_twiddles(num)

        -- 检查返回值是否存在
        assert(Wc ~= nil, string.format("N=%d: Wc为nil", num))
        assert(Ws ~= nil, string.format("N=%d: Ws为nil", num))

        -- 验证返回值类型
        assert(type(Wc) == "table", string.format("N=%d: Wc类型错误: 应为table, 实际为%s", num, type(Wc)))
        assert(type(Ws) == "table", string.format("N=%d: Ws类型错误: 应为table, 实际为%s", num, type(Ws)))

        -- 验证返回值长度
        local expected_length = math.floor(num / 2)
        assert(#Wc == expected_length,
            string.format("N=%d: Wc长度错误: 预期长度：%d, 实际长度：%d", num, expected_length, #Wc))
        assert(#Ws == expected_length,
            string.format("N=%d: Ws长度错误: 预期长度：%d, 实际长度：%d", num, expected_length, #Ws))

        -- 验证所有元素在单位圆上（抽样检查）
        if #Wc > 0 then
            local indices_to_check = {}
            -- 总是检查第一个元素
            table.insert(indices_to_check, 1)

            -- 检查中间元素（如果有）
            local mid_index = math.floor((#Wc + 1) / 2)
            if mid_index > 1 and mid_index <= #Wc then
                table.insert(indices_to_check, mid_index)
            end

            -- 检查最后一个元素（如果不是第一个）
            if #Wc > 1 then
                table.insert(indices_to_check, #Wc)
                -- 最后一个旋转因子对应角度接近180°
            end

            for _, idx in ipairs(indices_to_check) do
                -- 检查数组元素是否存在
                local wc_val = Wc[idx] -- cos值
                local ws_val = Ws[idx] -- -sin值

                assert(wc_val ~= nil, string.format("N=%d: Wc[%d]为nil", num, idx))
                assert(ws_val ~= nil, string.format("N=%d: Ws[%d]为nil", num, idx))
                assert(type(wc_val) == "number",
                    string.format("N=%d: Wc[%d]不是数字类型: %s", num, idx, type(wc_val)))
                assert(type(ws_val) == "number",
                    string.format("N=%d: Ws[%d]不是数字类型: %s", num, idx, type(ws_val)))

                -- 关键检查：计算模长的平方
                -- 旋转因子公式：W(k) = cos(θ) - j·sin(θ)
                -- 单位圆要求：cos² + sin² = 1
                local magnitude_sq = wc_val * wc_val + ws_val * ws_val
                assert(math.abs(magnitude_sq - 1.0) < 0.001,
                    string.format("N=%d: W[%d] 不在单位圆上: |W|² = %.6f", num, idx, magnitude_sq))
            end
        end

        print(string.format("N=%d: 旋转因子测试通过", num))
    end

    print("所有旋转因子测试通过！")
end

function fft_tests.test_fft_generate_twiddles_error()
    -- 边界情况测试,增加额外的错误测试
    -- 选择数据不满足这个条件：必须为 2 的幂次方
    local invalid_test_data = {0, 3, 100}
    for i, num in ipairs(invalid_test_data) do
        local success, Wc, Ws = pcall(fft.generate_twiddles, num)
        assert(success ~= true, string.format("N=%d: 应该失败（非2的幂次），但成功返回了", num))
    end
end

function fft_tests.test_fft_run_q15_u12()
    log.info("FFT测试", "开始测试 fft.run (q15模式 U12输入)")

    local test_cases = {{
        N = 64,
        fs = 2000,
        freq = 200
    }, {
        N = 128,
        fs = 1000,
        freq = 100
    }, {
        N = 256,
        fs = 2000,
        freq = 300
    }}

    local passed = 0
    local total = #test_cases

    for _, test in ipairs(test_cases) do
        log.info("测试", string.format("N=%d, 频率=%dHz", test.N, test.freq))

        -- 生成U12测试信号
        local real_i16, imag_i16 = fft_tests.create_u12_signal(test.N, test.fs, test.freq, 1000, 2048)

        -- 生成Q15旋转因子
        local Wc_q15 = zbuff.create((test.N // 2) * 2)
        local Ws_q15 = zbuff.create((test.N // 2) * 2)
        assert(Wc_q15 ~= nil, "Wc_q15 zbuff创建失败")
        assert(Ws_q15 ~= nil, "Ws_q15 zbuff创建失败")

        -- 调用fft.generate_twiddles_q15_to_zbuff并添加判断
        local success, err = pcall(function()
            fft.generate_twiddles_q15_to_zbuff(test.N, Wc_q15, Ws_q15)
        end)

        -- 断言2: 检查旋转因子生成是否成功
        assert(success, string.format("旋转因子生成失败: %s", err or "未知错误"))

        -- 执行FFT

        local fft_success, fft_err = pcall(function()
            fft.run(real_i16, imag_i16, test.N, Wc_q15, Ws_q15, {
                core = "q15",
                input_format = "u12"
            })
        end)

        -- 断言4: 检查FFT执行是否成功
        assert(fft_success, string.format("FFT执行失败: %s", fft_err or "未知错误"))
    end
end

-- ==================== fft.fft_integral 测试函数组 ====================

-- 测试1: 正常情况
function fft_tests.test_fft_integral_normal()
    log.info("fft_integral测试", "测试1: 正常情况")

    local N = 64
    local fs = 1000
    local df = fs / N

    local real = zbuff.create(N * 4)
    local imag = zbuff.create(N * 4)

    -- 生成简单信号
    for i = 0, N - 1 do
        real:seek(i * 4, zbuff.SEEK_SET)
        imag:seek(i * 4, zbuff.SEEK_SET)
        real:writeF32(math.sin(2 * math.pi * 50 * i / fs))
        imag:writeF32(0.0)
    end

    -- 执行FFT
    local Wc, Ws = fft.generate_twiddles(N)
    fft.run(real, imag, N, Wc, Ws)

    -- 调用频域积分
    local success, err = pcall(fft.fft_integral, real, imag, N, df)

    -- 断言
    assert(success, string.format("正常调用失败: %s", err or "未知错误"))

    log.info("结果", "√ n不是2的幂次测试通过 (正确拒绝) 正常情况测试通过")
end

-- 测试2: n不是2的幂次
function fft_tests.test_fft_integral_n_not_power_of_two()
    log.info("fft_integral测试", "测试2: n不是2的幂次")

    local N = 64
    local fs = 1000
    local df = fs / N
    local real = zbuff.create(N * 4)
    local imag = zbuff.create(N * 4)

    -- 执行FFT
    local Wc, Ws = fft.generate_twiddles(N)
    fft.run(real, imag, N, Wc, Ws)

    -- 调用频域积分，n=100（不是2的幂次）
    local success, err = pcall(fft.fft_integral, real, imag, 100, df)

    -- 断言：应该失败
    assert(success ~= true, "n不是2的幂次应该失败但成功了")

    log.info("结果", "√ n不是2的幂次测试通过 (正确拒绝)")
end

-- 测试3: n为0
function fft_tests.test_fft_integral_n_zero()
    log.info("fft_integral测试", "测试3: n为0")

    local N = 64
    local fs = 1000
    local df = fs / N
    local real = zbuff.create(N * 4)
    local imag = zbuff.create(N * 4)

    -- 执行FFT
    local Wc, Ws = fft.generate_twiddles(N)
    fft.run(real, imag, N, Wc, Ws)

    -- 调用频域积分，n=0
    local success, err = pcall(fft.fft_integral, real, imag, 0, df)

    -- 断言：应该失败
    assert(success ~= true, "n为0应该失败但成功了")

    log.info("结果", "√ n为0测试通过 (正确拒绝)")

end

-- 测试4: 参数类型错误（table代替zbuff）
function fft_tests.test_fft_integral_wrong_param_type()
    log.info("fft_integral测试", "测试4: 参数类型错误")

    local N = 64
    local fs = 1000
    local df = fs / N

    -- 使用table而不是zbuff
    local table_real = {1.0, 2.0, 3.0}
    local table_imag = {0.0, 0.0, 0.0}

    -- 调用频域积分
    local success, err = pcall(fft.fft_integral, table_real, table_imag, N, df)

    -- 断言：应该失败
    assert(success ~= true, "参数类型错误应该失败但成功了")

    log.info("结果", "√ 参数类型错误测试通过 (正确拒绝)")

end

-- 测试5: real参数为nil
function fft_tests.test_fft_integral_real_nil()
    log.info("fft_integral测试", "测试5: real参数为nil")

    local N = 64
    local fs = 1000
    local df = fs / N
    local imag = zbuff.create(N * 4)

    -- 调用频域积分，real=nil
    local success, err = pcall(fft.fft_integral, nil, imag, N, df)

    -- 断言：应该失败
    assert(success ~= true, "real参数为nil应该失败但成功了")

    log.info("结果", "√ real参数为nil测试通过 (正确拒绝)")

end

-- 测试6: n参数为nil
function fft_tests.test_fft_integral_n_nil()
    log.info("fft_integral测试", "测试6: n参数为nil")

    local N = 64
    local fs = 1000
    local df = fs / N
    local real = zbuff.create(N * 4)
    local imag = zbuff.create(N * 4)

    -- 调用频域积分，n=nil
    local success, err = pcall(fft.fft_integral, real, imag, nil, df)

    -- 断言：应该失败
    assert(success ~= true, "n参数为nil应该失败但成功了")

    log.info("结果", "√ n参数为nil测试通过 (正确拒绝)")

end

-- 测试7: df参数为nil
function fft_tests.test_fft_integral_df_nil()
    log.info("fft_integral测试", "测试7: df参数为nil")

    local N = 64
    local real = zbuff.create(N * 4)
    local imag = zbuff.create(N * 4)

    -- 执行FFT
    local Wc, Ws = fft.generate_twiddles(N)
    fft.run(real, imag, N, Wc, Ws)

    -- 调用频域积分，df=nil
    local success, err = pcall(fft.fft_integral, real, imag, N, nil)

    -- 断言：应该失败
    assert(success ~= true, "df参数为nil应该失败但成功了")

    log.info("结果", "√ df参数为nil测试通过 (正确拒绝)")

end

function fft_tests.test_ifft_normal()
    log.info("ifft测试", "测试1: 正常情况")

    local N = 64
    local real = zbuff.create(N * 4)
    local imag = zbuff.create(N * 4)
    local Wc, Ws = fft.generate_twiddles(N)

    -- 断言1: zbuff创建成功
    assert(real ~= nil, "real zbuff创建失败")
    assert(imag ~= nil, "imag zbuff创建失败")

    -- 断言2: 旋转因子生成成功
    assert(Wc ~= nil, "Wc生成失败")
    assert(Ws ~= nil, "Ws生成失败")

    -- 生成简单信号
    for i = 0, N - 1 do
        real:seek(i * 4, zbuff.SEEK_SET)
        imag:seek(i * 4, zbuff.SEEK_SET)
        real:writeF32(1.0) -- 直流信号
        imag:writeF32(0.0)
    end

    -- 正常调用
    local success, err = pcall(fft.ifft, real, imag, N, Wc, Ws)

    -- 断言3: 正常调用应该成功
    assert(success, string.format("正常调用失败: %s", err or "未知错误"))

    log.info("结果", "√ 正常情况测试通过")
end

-- 测试2: N不是2的幂次
function fft_tests.test_ifft_n_not_power_of_two()
    log.info("ifft测试", "测试2: N不是2的幂次")

    local invalid_N = 100
    local real = zbuff.create(invalid_N * 4)
    local imag = zbuff.create(invalid_N * 4)
    local Wc, Ws = fft.generate_twiddles(64) -- 使用有效的旋转因子

    -- 调用ifft，N=100（不是2的幂次）
    local success, err = pcall(fft.ifft, real, imag, invalid_N, Wc, Ws)

    -- 断言：应该失败
    assert(success ~= true, "N不是2的幂次应该失败但成功了")

    log.info("结果", "√ N不是2的幂次测试通过 (正确拒绝)")
end

-- 测试3: N参数为nil
function fft_tests.test_ifft_n_nil()
    log.info("ifft测试", "测试3: N参数为nil")

    local N = 32
    local real = zbuff.create(N * 4)
    local imag = zbuff.create(N * 4)
    local Wc, Ws = fft.generate_twiddles(N)

    -- 调用ifft，N=nil
    local success, err = pcall(fft.ifft, real, imag, nil, Wc, Ws)

    -- 断言：应该失败
    assert(success ~= true, "N参数为nil应该失败但成功了")

    log.info("结果", "√ N参数为nil测试通过 (正确拒绝)")
end

-- 测试4: 所有参数为nil
function fft_tests.test_ifft_all_params_nil()
    log.info("ifft测试", "测试4: 所有参数为nil")
    local device_name = rtos.bsp()
    if device_name == "Air8101" then
        log.info("AIR8101不支持会死机，所以跳过")
        return
    end

    -- 调用ifft，所有参数为nil
    local success, err = pcall(fft.ifft, nil, nil, nil, nil, nil)

    -- 断言：应该失败
    assert(success ~= true, "所有参数为nil应该失败但成功了")

    log.info("结果", "√ 所有参数为nil测试通过 (正确拒绝)")
end

-- 测试5: N为0
function fft_tests.test_ifft_n_zero()
    log.info("ifft测试", "测试5: N为0")

    local real = zbuff.create(10)
    local imag = zbuff.create(10)
    local Wc, Ws = fft.generate_twiddles(32)

    -- 调用ifft，N=0
    local success, err = pcall(fft.ifft, real, imag, 0, Wc, Ws)

    -- 断言：应该失败
    assert(success ~= true, "N为0应该失败但成功了")

    log.info("结果", "√ N为0测试通过 (正确拒绝)")
end

return fft_tests
