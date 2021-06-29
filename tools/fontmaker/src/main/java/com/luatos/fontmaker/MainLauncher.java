package com.luatos.fontmaker;

import java.io.BufferedReader;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

import org.nutz.lang.Encoding;
import org.nutz.lang.Files;
import org.nutz.lang.Lang;
import org.nutz.log.Log;
import org.nutz.log.Logs;

// 请把FontMaker也克隆下来 https://gitee.com/kerndev/FontMaker.git
/*
这个类是干啥的? 配合FontMaker维护/生成字库c和对应的map文件.
主要关系是怎样的:
1. FontMaker依赖cst文件生成字库c文件.
2. FontMaker自带的cst多少有点缺陷, 本类提供了扩展的方法的.
3. FontMaker生成字库.c文件后, 第一行是数量,第二行是map,实际上无法编译,需要删除掉, 然后用本类的main1重新生成map.
4. 严格来说字库.c文件能编译,但它是乱序的,无法使用二分法进行查找, 重新生产的map可以解决这个问题.
 */
public class MainLauncher {

	private static final Log log = Logs.get();
	
	public static void main(String[] args) throws Exception{
		// 取消注释以执行相关功能
		//main1(args);
		//main2(args);
		//main4(args);
		log.info("Good Day");
	}

	// 关于 chinese_gb2312_16p.c . 使用FontMaker选择字体和字号后,输出的文件就是.c文件,格式如下
	/*
const unsigned char  char_bits_gb2312_16p[][32]=
{
//U+2500(─)
0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x7F,0xFC,0x00,0x00,
0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	 */
	// 以下的代码就是按照//U+分析出汉字编码, 然后得出映射表chinese_map
	public static void main1(String[] args) throws Exception {
		FileReader fr = new FileReader("D:\\github\\LuatOS\\luat\\packages\\fonts\\chinese_gb2312_16p.c", Encoding.CHARSET_UTF8);
		BufferedReader br = new BufferedReader(fr);
		StringBuilder sb = new StringBuilder("static const uint16_t fontmap[7571]={");
		int count = 0;
		while (br.ready()) {
			String line = br.readLine();
			if (line == null)
				break;
			line = line.trim();
			if (line.startsWith("//U+")) {
				int val = Integer.parseInt(line.substring(4, 8), 16);
				if (count % 16 == 0)
					sb.append("\r\n\t");
				sb.append("0x");
				sb.append(Lang.fixedHexString(new byte[] {(byte) (val & 0xFF), (byte) (val >> 8)}));
				sb.append(",");
				count ++;
			}
		}
		sb.setCharAt(sb.length() - 1, '}');
		sb.append(";\r\n");
		System.out.println(sb);
		System.out.println("count=" + count);
		Files.write("D://gb2312_map.c", sb);
		br.close();
	}
	
	/*
	 * 这个方法是在FontMaker原有的GB2312基础上, 将原有数据进行排序,得出有序的GB2312_fix.cst
	 */
	public static void main2(String[] args) throws Exception {
		File f = new File("D:/github/FontMaker/bin/charset/GB2312.cst");
		DataInputStream ins = new DataInputStream(new FileInputStream(f));
		DataOutputStream out = new DataOutputStream(new FileOutputStream("D:/github/FontMaker/bin/charset/GB2312_fix.cst"));
		List<Integer> unicodes = new ArrayList<>(9000);
		
		// 首先, 把ASCII填入
		
		while (ins.available() > 0) {
			unicodes.add(ins.readUnsignedShort());
		}
		Collections.sort(unicodes);
		
		for (int i = 1; i <= 0x7F; i++) {
			out.writeShort(i);
		}
		for (Integer val : unicodes) {
			System.out.println(Integer.toHexString(val));
			out.writeShort(val);
		}
		System.out.println(unicodes.size());
		out.flush();
		out.close();
		ins.close();
	}
	
	// 读取gb2312k里面的编码, 然后补齐ASIIC码,排序后输出gb2312k2.cst
	// 得出的gb2312k2.cst供FontMaker生成字库c文件
	public static void main4(String[] args) throws Exception {
		DataOutputStream out = new DataOutputStream(new FileOutputStream("D://github/FontMaker/bin/charset/gb2312k2.cst"));
		BufferedReader br = new BufferedReader(new FileReader(new File("D://github/FontMaker/doc/gb2312k.txt")));
		List<Integer> vals = new ArrayList<>();
		while (br.ready()) {
			String line = br.readLine();
			if (line == null)
				break;
			if (line.length() == 0)
				continue;
			int val = Integer.parseInt(line, 16);
			if (val < 0x7E)
				continue;
			//out.writeShort(val);
			int H = (val >> 8) & 0xFF;
			int L = val & 0xFF;
			val = (L << 8) + H;
			vals.add(val);
		}

		// 插入ASCII字符
		for (int i = 1; i <= 0x7E; i++) {
			vals.add(i << 8);
		}
		
		Collections.sort(vals);
		
		
		for (Integer val : vals) {
			//out.writeByte((val & 0xFF));
			//out.writeByte(((val >> 8) & 0xFF));
			out.writeShort(val);
		}
		out.flush();
		out.close();
	}

}
