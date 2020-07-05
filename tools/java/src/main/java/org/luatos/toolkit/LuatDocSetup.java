package org.luatos.toolkit;

public class LuatDocSetup {

    private String workdir;

    private String[] as;

    private LuatDocEntry[] entries;

    private String output;

    public String getWorkdir() {
        return workdir;
    }

    public void setWorkdir(String workdir) {
        this.workdir = workdir;
    }

    public String[] getAs() {
        return as;
    }

    public void setAs(String[] as) {
        this.as = as;
    }

    public LuatDocEntry[] getEntries() {
        return entries;
    }

    public int getEntryCount() {
        return null != entries ? entries.length : 0;
    }

    public void setEntries(LuatDocEntry[] entries) {
        this.entries = entries;
    }

    public String getOutput() {
        return output;
    }

    public void setOutput(String output) {
        this.output = output;
    }

}
