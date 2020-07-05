package org.luatos.toolkit.impl;

import java.io.BufferedWriter;
import java.io.File;
import java.io.IOException;
import java.io.Writer;

import org.luatos.toolkit.LuatDocEntry;
import org.luatos.toolkit.LuatDocSetup;
import org.luatos.toolkit.api.LuDocSetRender;
import org.luatos.toolkit.bean.LuDocument;
import org.luatos.toolkit.bean.LuatDocSet;
import org.luatos.toolkit.util.ComboLuDocRender;
import org.nutz.lang.Files;
import org.nutz.lang.Lang;
import org.nutz.lang.Streams;
import org.nutz.lang.Strings;
import org.nutz.lang.tmpl.Tmpl;
import org.nutz.lang.util.Disks;
import org.nutz.lang.util.NutBean;
import org.nutz.log.Log;
import org.nutz.log.Logs;

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
        NutBean context = Lang.map("name", Files.getName(en.getPath()));
        context.put("workdir", setup.getWorkdir());
        String tmplOutDir = Disks.appendPath(setup.getOutput(), en.getOut());
        String phOut = Tmpl.exec(tmplOutDir, context);
        File dirOut = Files.createDirIfNoExists(phOut);
        log.infof(">> %s", phOut);

        // 生成摘要
        log.infof("build README.md");
        buildReadMe(ds, dirOut);

        // 循环渲染文档
        for (LuDocument doc : ds.getDocuments()) {
            String rph = doc.getPath();
            log.infof("  => %s", rph);
            render.output(doc, dirOut, rph);
        }
    }

    private void buildReadMe(LuatDocSet ds, File dirOut) throws IOException {
        File fReadme = Files.getFile(dirOut, "README.md");
        fReadme = Files.createFileIfNoExists(fReadme);
        Writer w = Streams.fileOutw(fReadme);
        try {
            BufferedWriter bw = Streams.buffw(w);
            // 头部
            wlnf(bw, "---");
            wlnf(bw, "title: %s", ds.getTitle());
            wlnf(bw, "---");
            wlnf(bw, null);

            // 大标题
            wlnf(bw, "# %s\n", ds.getTitle());

            // 索引
            for (LuDocument doc : ds.getDocuments()) {
                String rph = doc.getPath();
                rph = Files.renameSuffix(rph, ".md");
                wlnf(bw, "- [%s](%s)", doc.getTitle(), rph);
            }
            Streams.safeFlush(bw);
        }
        finally {
            Streams.safeClose(w);
        }
    }

    private void wlnf(BufferedWriter bw, String fmt, Object... args) throws IOException {
        if (!Strings.isBlank(fmt)) {
            bw.write(String.format(fmt, args));
        }
        bw.write("\n");
    }

}
