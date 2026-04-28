PROJECT = "CHESS"
VERSION = "001.000.000"

log.info("main", PROJECT, VERSION)

require "chess_win"
sys.publish("OPEN_CHESS_WIN")
if chess_open then
    chess_open()
end

sys.run()
