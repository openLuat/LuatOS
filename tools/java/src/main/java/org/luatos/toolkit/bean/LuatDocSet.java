package org.luatos.toolkit.bean;

import java.util.LinkedList;
import java.util.List;

public class LuatDocSet {

    private String name;

    private List<LuDocument> docs;

    public LuatDocSet(String name) {
        this.name = name;
        this.docs = new LinkedList<>();
    }

    public void addDoc(LuDocument doc) {
        this.docs.add(doc);
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public List<LuDocument> getDocs() {
        return docs;
    }

}
