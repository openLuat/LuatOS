一、支持型号  
irtu_basic支持以下型号模块：  
Air780EPM,Air780EHM,Air780EGP,Air780EGG,Air780EGH,Air780EHV,Air700ECP,Air700ECH

二、使用说明  
在irtu_main.lua中，default.init()，driver.init()，create.start()为初始化函数。该功能所有型号默认支持，如果需要使用其他功能，请打开对应功能注释部分。

如果要加入GNSS部分需要打开gnss.init()的注释部分，Air780EGP/Air780EGG/Air780EGH支持GNSS功能，Air780EPM,Air780EHM,Air780EHV,Air700ECP/Air700ECH不支持GNSS功能，如果使用GNSS功能，请确保模块支持GNSS功能，并且模块的GNSS功能已打开。

如果要加入音频部分的指令功能，需要打开audio_config.init()的注释部分，目前仅有Air780EHV支持音频。