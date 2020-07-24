package com.luatos.toolkit.impl;

import java.io.BufferedWriter;
import java.io.File;
import java.io.IOException;
import java.io.Writer;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

import org.nutz.lang.Files;
import org.nutz.lang.Lang;
import org.nutz.lang.Streams;
import org.nutz.lang.Strings;
import org.nutz.lang.tmpl.Tmpl;
import org.nutz.lang.util.Disks;
import org.nutz.lang.util.NutBean;
import org.nutz.lang.util.NutMap;
import org.nutz.log.Log;
import org.nutz.log.Logs;

import com.luatos.toolkit.LuatDocEntry;
import com.luatos.toolkit.LuatDocSetup;
import com.luatos.toolkit.api.LuDocSetRender;
import com.luatos.toolkit.bean.LuDocument;
import com.luatos.toolkit.bean.LuatDocSet;
import com.luatos.toolkit.util.ComboLuDocRender;

public class ComboDocSetRender implements LuDocSetRender {

    private static final Log log = Logs.get();

    private LuatDocSetup setup;

    private ComboLuDocRender render;

    public ComboDocSetRender(LuatDocSetup setup) {
        this.setup = setup;
        this.render = new ComboLuDocRender(setup.getAs());
    }

    @Override
    public void render(LuatDocSet ds) throws IOException {
        // 防守一下
        if (!ds.hasDocuments()) {
            log.info("~ Empty Document Set ~");
            return;
        }

        LuatDocEntry en = ds.getEntry();
        // 准备输出目录
        NutBean context = Lang.map("name", Files.getName(en.getPaths()[0]));
        context.put("workdir", setup.getWorkdir());
        String tmplOutDir = Disks.appendPath(setup.getOutput(), en.getOut());
        String phOut = Tmpl.exec(tmplOutDir, context);
        File dirOut = Files.createDirIfNoExists(phOut);
        log.infof(">> %s", phOut);

        // 循环渲染文档
        List<LuDocument> docList = new ArrayList<>(ds.getDocumentsCount());
        for (LuDocument doc : ds.getDocuments()) {
            String rph = doc.getPath();
            log.infof("  => %s", rph);
            if (render.output(doc, dirOut, rph, en)) {
                docList.add(doc);
            }
        }

        // 生成摘要
        log.infof("build README.md");
        buildReadMe(ds, dirOut, docList);
    }

    private void buildReadMe(LuatDocSet ds, File dirOut, List<LuDocument> docList)
            throws IOException {
        for (LuDocument doc : docList) {
            System.out.println("!!!" + doc.getDisplayTitle());
        }
        // 首先按照名称排序索引
        docList.sort(new Comparator<LuDocument>() {
            public int compare(LuDocument o1, LuDocument o2) {
                String title1 = o1.getDisplayTitle();
                String title2 = o2.getDisplayTitle();
                return title1.compareTo(title2);
            }
        });
        // 索引
        StringBuilder sb = new StringBuilder();
        wlnf(sb, "模块 | 描述");
        wlnf(sb, "---|----");
        for (LuDocument doc : docList) {
            String rph = doc.getPath();
            rph = Files.renameSuffix(rph, ".md");
            wlnf(sb, "[%s](%s) | %s", doc.getDisplayTitle(), rph, doc.getDisplaySummary());
        }

        // 构建上下文
        NutMap context = new NutMap();
        context.put("title", ds.getTitle());
        context.put("index", sb);

        // 渲染
        String str = ds.getReadme().render(context);

        File fReadme = Files.getFile(dirOut, "README.md");
        fReadme = Files.createFileIfNoExists(fReadme);
        Writer w = Streams.fileOutw(fReadme);
        BufferedWriter bw = Streams.buffw(w);
        try {
            bw.write(str);

        }
        finally {
            Streams.safeFlush(bw);
            Streams.safeClose(w);
        }
    }

    private void wlnf(StringBuilder sb, String fmt, Object... args) throws IOException {
        if (!Strings.isBlank(fmt)) {
            sb.append(String.format(fmt, args));
        }
        sb.append('\n');
    }

}
