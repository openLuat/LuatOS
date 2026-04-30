PROJECT = "OTHELLO"
VERSION = "1.0.0"


log.info("main", PROJECT, VERSION)

require "auto_play"
require "game_othello_win"

sys.publish("OPEN_GAME_OTHELLO_WIN")

sys.run()