package org.luatos.toolkit.util;

import java.io.File;
import java.io.OutputStream;
import java.util.HashMap;
import java.util.Map;

import org.luatos.toolkit.api.LuDocRender;
import org.luatos.toolkit.bean.LuDocument;
import org.luatos.toolkit.impl.JsonLuDocRender;
import org.luatos.toolkit.impl.MarkdownLuDocRender;
import org.nutz.lang.Files;
import org.nutz.lang.Lang;
import org.nutz.lang.Streams;
import org.nutz.log.Log;
import org.nutz.log.Logs;

public class ComboLuDocRender {

    private static final Log log = Logs.get();

    private static final Map<String, LuDocRender> renders = new HashMap<>();
    static {
        renders.put("md", new MarkdownLuDocRender());
        renders.put("json", new JsonLuDocRender());
    }

    private String[] ass;

    private LuDocRender[] reds;

    public ComboLuDocRender(String[] ass) {
        this.ass = ass;
        this.reds = new LuDocRender[ass.length];
        for (int i = 0; i < ass.length; i++) {
            LuDocRender red = renders.get(ass[i]);
            if (null == red) {
                throw Lang.makeThrow("Fail to found the render for type '%s'", ass[i]);
            }
            reds[i] = red;
        }
    }

    /**
     * @param doc
     *            要输出的文档
     * @param taDir
     *            目标目录
     * @param rph
     *            相对目标目录的路径（后缀会自动被对应类型替换的）
     */
    public void output(LuDocument doc, File taDir, String rph) {
        for (int i = 0; i < ass.length; i++) {
            String as = ass[i];
            LuDocRender red = reds[i];

            // 准备一下输出文件
            String ph = Files.renameSuffix(rph, "." + as);
            File f = Files.getFile(taDir, ph);

            // 确保创建
            f = Files.createFileIfNoExists(f);

            // 打开
            OutputStream ops = Streams.fileOut(f);
            try {
                red.render(doc, ops);
            }
            finally {
                Streams.safeClose(ops);
            }

            // 写日志
            log.infof("    - OK: %6s : %s", as, ph);
        }
    }

}
