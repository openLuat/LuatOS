package org.luatos.toolkit.bean;

import java.util.LinkedList;
import java.util.List;

import org.luatos.toolkit.LuatDocEntry;
import org.nutz.lang.Files;
import org.nutz.lang.Strings;

public class LuatDocSet {

    private String name;

    /**
     * 即 workdir + path 的全路径， 下面的文档路径会根据这个路径计算相对路径
     */
    private String homePath;

    private LuatDocEntry entry;

    private List<LuDocument> documents;

    public LuatDocSet(String name) {
        this.name = name;
        this.documents = new LinkedList<>();
    }

    public LuatDocEntry getEntry() {
        return entry;
    }

    public void setEntry(LuatDocEntry entry) {
        this.entry = entry;
    }

    public String getTitle() {
        if (entry != null) {
            return entry.getTitle();
        }
        if (!Strings.isBlank(name)) {
            return name;
        }
        return Strings.sBlank(Files.getName(homePath), "NoTitle");
    }

    public String getHomePath() {
        return homePath;
    }

    public void setHomePath(String homePath) {
        this.homePath = homePath;
    }

    public void addDoc(LuDocument doc) {
        this.documents.add(doc);
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public boolean hasDocuments() {
        return null != this.documents && !this.documents.isEmpty();
    }

    public List<LuDocument> getDocuments() {
        return documents;
    }

    public int getDocumentsCount() {
        return null == documents ? 0 : documents.size();
    }

}
