PROJECT = "SOKOBAN"
VERSION = "001.000.000"

log.info("main", PROJECT, VERSION)

require "sokoban_win"
sys.publish("OPEN_SOKOBAN_WIN")
if sokoban_open then
    sokoban_open()
end

sys.run()
