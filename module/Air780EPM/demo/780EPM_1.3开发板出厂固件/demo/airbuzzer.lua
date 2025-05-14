local airbuzzer = {}

local pwid = 4

function airbuzzer.start_buzzer()
    pwm.setup(pwid, 1000, 50)
    pwm.start(pwid)
    --pwm.open(pwid,1000,50)
end

function airbuzzer.stop_buzzer()
    pwm.stop(pwid)  
    --pwm.close(pwid)
end

return airbuzzer

