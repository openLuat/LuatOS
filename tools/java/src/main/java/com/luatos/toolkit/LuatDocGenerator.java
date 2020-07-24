package com.luatos.toolkit;

import java.io.File;
import java.io.FileFilter;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

import org.nutz.json.Json;
import org.nutz.lang.Files;
import org.nutz.lang.Lang;
import org.nutz.lang.Stopwatch;
import org.nutz.lang.Strings;
import org.nutz.lang.util.Disks;
import org.nutz.lang.util.FileVisitor;
import org.nutz.log.Log;
import org.nutz.log.Logs;

import com.luatos.toolkit.api.LuDocParser;
import com.luatos.toolkit.bean.LuDocument;
import com.luatos.toolkit.bean.LuatDocSet;
import com.luatos.toolkit.impl.CLuDocParser;
import com.luatos.toolkit.impl.ComboDocSetRender;
import com.luatos.toolkit.util.ComboLuDocRender;

public class LuatDocGenerator {

    private static final String HR0 = Strings.dup('#', 60);
    private static final String HR = Strings.dup('-', 60);

    private static final Log log = Logs.get();

    private static final LuDocParser docParser = new CLuDocParser();

    public static void main(String[] args) throws IOException {
        // .....................................................
        log.info(HR0);
        log.infof("# Luat Document Generator");
        log.infof("# v1.0");
        log.infof("# @auth LuatOS Team");
        log.infof("# @since 2020");
        log.info(HR0);
        // .....................................................
        List<String> inputs = new ArrayList<>(args.length);
        String conf = null;
        String outdir = null;
        String outas = null;
        Stopwatch sw = Stopwatch.begin();
        // .....................................................
        // 分析参数
        for (int i = 0; i < args.length; i++) {
            String arg = args[i];
            // 配置文件
            if ("-conf".equals(arg)) {
                conf = args[++i];
            }
            // 指定了输出目录
            else if ("-out".equals(arg)) {
                outdir = args[++i];
            }
            // 指定了输出类型
            else if ("-as".equals(arg)) {
                outas = args[++i];
            }
            // 那就是输入文件咯
            else {
                inputs.add(arg);
            }
        }
        // .....................................................
        // 渲染类型拆一下数组

        // .....................................................
        // 指定了每个输入文件
        if (!inputs.isEmpty()) {
            genForFiles(inputs, outdir, outas);
        }
        // 要扫描工作目录
        else if (null != conf) {
            File fConf = Files.checkFile(conf);
            String json = Files.read(fConf);
            LuatDocSetup setup = Json.fromJson(LuatDocSetup.class, json);
            genForSetup(setup, outdir, outas);
        }
        // 靠
        else {
            throw Lang.makeThrow("No inputs or config");
        }

        // .....................................................
        // 全部搞定
        sw.stop();
        log.info(HR);
        log.infof("All done %s", sw.toString());
    }

    private static void genForSetup(LuatDocSetup setup, String outdir, String outas)
            throws IOException {
        // .....................................................
        // 覆盖默认值
        if (!Strings.isBlank(outdir)) {
            setup.setOutput(outdir);
        }
        if (!Strings.isBlank(outas)) {
            setup.setAs(Strings.splitIgnoreBlank(outas));
        }

        log.infof("# Scan %d entries << %s:", setup.getEntryCount(), setup.getWorkdir());

        // 防守一下
        if (0 == setup.getEntryCount()) {
            log.info("No Entries!");
            return;
        }

        // 准备文档集的渲染器
        ComboDocSetRender dr = new ComboDocSetRender(setup);

        // .....................................................
        // 解析文档集
        for (LuatDocEntry en : setup.getEntries()) {
            // 输出
            log.info(HR);
            log.infof("%s", en.toString());

            // 准备文档集
            LuatDocSet ds = new LuatDocSet(en.getTitle2());
            ds.setEntry(en);

            // 建立文档集合
            for (String ph : en.getPaths()) {
                // 文档集主目录
                String aph = Disks.appendPath(setup.getWorkdir(), ph);
                File dirHome = Files.checkFile(aph);
                if (!dirHome.isDirectory()) {
                    throw Lang.makeThrow("path '%s' must be DIR", aph);
                }

                log.infof("scan files in %s", ph);
                joinDocSet(ds, dirHome, en);
            }

            // 渲染文档
            log.info("");
            log.infof("render %d files ...", ds.getDocumentsCount());
            dr.render(ds);
        }
    }

    private static LuatDocSet joinDocSet(LuatDocSet ds, File dirHome, LuatDocEntry en)
            throws IOException {
        // 准备索引模板
        if (null == ds.getReadme()) {
            File fReadme = Files.getFile(dirHome, en.getReadmeFilePath());
            if (!fReadme.exists()) {
                fReadme = Files.findFile("dft_readme.md");
            }
            String tmpl = "${index}";
            if (null != fReadme) {
                tmpl = Files.read(fReadme);
            }
            ds.setReadme(tmpl);
        }

        // 递归的解析文档
        Disks.visitFile(dirHome, new FileVisitor() {
            public void visit(File f) {
                String rph = Disks.getRelativePath(dirHome, f);
                log.infof("  + %s", rph);

                // 解析
                String input = Files.read(f);
                LuDocument doc = docParser.parse(input);
                doc.setDefaultTitle(Files.getMajorName(f));
                doc.setPath(rph);

                // 计入
                if (doc.hasFunctions()) {
                    ds.addDoc(doc);
                }
            }
        }, new FileFilter() {
            public boolean accept(File f) {
                // 无视隐藏文件
                if (f.isHidden()) {
                    return false;
                }
                // 目录是否递归
                if (f.isDirectory()) {
                    return en.isDeep();
                }
                // 获取相对路径
                String rph = Disks.getRelativePath(dirHome, f);
                if (!en.isMatch(rph)) {
                    log.debugf("  ~ ignore: %s", rph);
                    return false;
                }

                return true;
            }
        });

        return ds;
    }

    private static void genForFiles(List<String> inputs, String outdir, String outas)
            throws IOException {
        // .....................................................
        // 确认输出类型
        String[] ass = Strings.splitIgnoreBlank(Strings.sBlank(outas, "md,json"));
        // .....................................................
        // 准备输出目录
        File dirOut;
        // 默认当前目录
        if (Strings.isBlank(outdir)) {
            dirOut = Files.findFile(".").getCanonicalFile();
        }
        // 否则
        else {
            dirOut = Files.createDirIfNoExists(outdir);
            if (dirOut.isFile()) {
                dirOut = dirOut.getParentFile();
            }
        }
        log.infof("# Gen %d files -> %s:", inputs.size(), dirOut);
        log.info(HR);
        log.info("");
        // .....................................................
        // 准备渲染器
        ComboLuDocRender dr = new ComboLuDocRender(ass);
        // .....................................................
        // 循环解析输出
        int i = 0;
        for (String fph : inputs) {
            File f = Files.findFile(fph);
            log.infof(" %2d) %s\n", ++i, f);

            // 解析
            String text = Files.read(f);
            LuDocument doc = docParser.parse(text);

            // 渲染输出
            dr.output(doc, dirOut, f.getName(), null);
        }
    }

}
