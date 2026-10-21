local C={}
C.WIDTH,C.HEIGHT=1024,600
C.BOARD_PROFILE="existing" -- 沿用已在同板验证的屏幕/触摸接线
C.ANIM_FPS=24
C.REPORT_MS=10000
C.SEED=nil -- 填整数可固定随机序列；nil由启动时钟生成
C.PET_SCALE=1.5 -- 相对最初版本的显示倍率；复用64x64源PNG
C.INITIAL_PET_COUNT=8 -- 左上角1~8按钮可在运行中调整，无需重启
C.X_MIN,C.X_MAX=80,944 -- 为1.5倍显示后的宠物预留屏幕边缘空间
C.LANE_DRIFT=8
C.MIN_DISTANCE,C.MAX_DISTANCE=160,440
C.DURATION_MIN,C.DURATION_MAX=5,10 -- 跑动、静止分别随机5~10整秒
C.RUN_POSE_MS=125 -- 跑姿8次/秒切换；移动仍目标24次/秒
C.HQ_MAX_COUNT=4 -- 不超过4只时，前四只使用新增连续跑姿
C.HQ_RUN_FRAMES=6
C.HQ_FPS=24 -- 6姿态每250ms循环；超过4只恢复原2姿态/8Hz
C.PETS={
    {id=1,kind="cat",variant=1,lane=232,zoom=256},
    {id=2,kind="dog",variant=1,lane=272,zoom=264},
    {id=3,kind="cat",variant=2,lane=312,zoom=272},
    {id=4,kind="dog",variant=2,lane=352,zoom=280},
    {id=5,kind="cat",variant=3,lane=392,zoom=288},
    {id=6,kind="dog",variant=3,lane=432,zoom=296},
    {id=7,kind="cat",variant=4,lane=472,zoom=304},
    {id=8,kind="dog",variant=4,lane=512,zoom=320},
}
return C
