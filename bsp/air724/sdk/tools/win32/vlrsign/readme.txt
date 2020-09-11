1 RSAKeyGen.exe
  RSAKeyGen.exe 是签名秘钥生成工具，双击运行就可以了。

参数说明：
	password  输入口令，8 位ASCII码,以后VLRSign.exe，根据读取签名秘钥时回去校验口令是否正确。
	Product Name 输入产品名称，不超过49个字符，以后VLRSign.exe根据输入的产品名称检索相应的签名秘钥。



2 VLRSign.exe

VLRSign.exe 本签名工具直针对8910平台,需要在命令行窗口中运行。

选项说明：
	-pw 	是使用RSAKeyGen.exe 生成签名秘钥时输入的密码，该密码是读取签名秘钥的口令。
	-pn 	是RSAKeyGen.exe 生成签名秘钥时输入的产品名称，用于检索签名秘钥。
	-plen 	是针对要签名的对象填充的长度。针对8910平台 nor_fdl1.img nor_bootloader.img -plen 固定为0xbce0。
	-ha   	是签名中使用何种hash算法。针对8910平台 nor_fdl1.img nor_bootloader.img -ha 固定使用Blake2。
		nor_fdl.bin 以及 系统文件（例如：UIX8910_UIS8910C_128X128_320X240_refphone_stone_MX.bin）使用 SHA1-32
	-img  	指定签名的文件路径和文件名。
	-out  	制定签名完成后的输出文件路径和文件名。
	-pw2	此版中跟 “-pw” 一致 仅在对 nor_fdl.bin签名时需要。
	-pn2	此版中跟 “-pn”一致仅在对 nor_fdl.bin签名时需要。
	-ipbk   此参数仅在对 nor_fdl.bin签名时需要须指定为true。
	
例子：

.\VLRSign.exe  -pw 12345678 -pn test -plen 0xbce0 -ha Blake2 -img ..\test\data\nor_bootloader.img -out ..\test\data\nor_bootloader_signed.img
.\VLRSign.exe  -pw 12345678 -pn test -plen 0xbce0 -ha Blake2 -img ..\test\data\nor_fdl1.img -out ..\test\data\nor_fdl1_signed.img
.\VLRSign.exe -pw 12345678 -pn test  -ha SHA1-32 -ipbk true -pw2 12345678 -pn2 test -img  ..\test\data\nor_fdl.bin -out ..\test\data\nor_fdl_signed.bin
.\VLRSign.exe  -pw 12345678 -pn test  -ha SHA1-32 -slen 0x100000 -img ..\test\data\UIX8910_UIS8910C_128X128_320X240_refphone_stone_MX.bin -out ..\test\data\UIX8910_UIS8910C_128X128_320X240_refphone_stone_MX_signed.bin

3 8910DM 平台

.\VLRSign.exe  -pw 12345678 -pn test  -ha Blake2 -img ..\test\data\bbapp\fdl1.img -out ..\test\data\bbapp\fdl1_signed.img
.\VLRSign.exe  -pw 12345678 -pn test  -ha Blake2 -img ..\test\data\bbapp\fdl2.img -out ..\test\data\bbapp\fdl2_signed.img
.\VLRSign.exe  -pw 12345678 -pn test  -ha Blake2 -plen 0xbce0 -img ..\test\data\bbapp\boot.img -out ..\test\data\bbapp\boot_signed.img
.\VLRSign.exe  -pw 12345678 -pn test  -ha Blake2 -img ..\test\data\bbapp\8915DM.img -out ..\test\data\bbapp\8915DM_signed.img
