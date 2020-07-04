package org.luatos.toolkit.bean;

import java.util.LinkedList;
import java.util.List;

import org.luatos.toolkit.Luats;

public class LuDocument {

    private LuHead head;

    private List<FnSign> functions;

    public boolean hasHead() {
        return null != head;
    }

    public LuHead getHead() {
        return head;
    }

    public void setHead(LuHead title) {
        this.head = title;
    }

    public void mergeHead(LuHead head) {
        if (null == this.head) {
            this.head = head;
        } else {
            this.head.mergeWith(head);
        }
    }

    public String getTitle() {
        if (null != head)
            return head.getTitle();
        return null;
    }

    public void setDefaultTitle(String title) {
        if (null == head) {
            head = new LuHead();
            head.setTitle(title);
        }
    }

    public String getPath() {
        if (null != head)
            return head.getPath();
        return null;
    }

    public void setPath(String path) {
        if (null == head) {
            head = new LuHead();
            head.setPath(path);
        }
    }

    public boolean hasFunctions() {
        return null != this.functions && !this.functions.isEmpty();
    }

    public List<FnSign> getFunctions() {
        return functions;
    }

    public void setFunctions(List<FnSign> functions) {
        this.functions = functions;
    }

    public void addFunctions(FnSign func) {
        if (null == this.functions) {
            this.functions = new LinkedList<>();
        }
        this.functions.add(func);
    }

    public boolean equals(Object o) {
        if (o instanceof LuDocument) {
            LuDocument doc = (LuDocument) o;
            if (!Luats.isSame(head, doc.head))
                return false;
            if (!Luats.isSameList(functions, doc.functions))
                return false;

            return true;
        }
        return false;
    }

}
