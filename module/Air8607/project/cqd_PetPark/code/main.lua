PROJECT="AIR8601_PET_PARK"
VERSION="001.003.000"
sys=require "sys"
log.info("main",PROJECT,VERSION)
sys.taskInit(function()
    local ok,err=pcall(function()
        local C=require "config"
        local board=require "board"
        board.init()
        local animation=require "animation"
        local now=animation.clock()
        local seed=C.SEED or ((os.time() or 1)+now())
        local scene=require "scene"
        scene.create(seed)
        local ui=require "ui"
        ui.create(animation.elapsed)
        sys.wait(100)
        board.backlight_on()
        animation.start(function(elapsed)
            scene.update(elapsed)
            ui.refresh()
        end,now)
        log.info("main","猫狗公园启动完成", "4 cats + 4 dogs", "24fps target", "seed",seed)
    end)
    if not ok then log.error("main","初始化失败",err) end
end)
sys.run()
