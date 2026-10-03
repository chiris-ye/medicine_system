import com.healthmarketscience.jackcess.*;
import java.io.File;
import java.util.*;

public class AccessInspector {
  public static void main(String[] args) throws Exception {
    for (String path : args) {
      System.out.println("=== " + path + " ===");
      Database db = DatabaseBuilder.open(new File(path));
      for (String name : db.getTableNames()) {
        Table t = db.getTable(name);
        System.out.println("TABLE\t" + name + "\tROWS=" + t.getRowCount());
        List<? extends Column> cols = t.getColumns();
        for (Column c : cols) System.out.println("FIELD\t" + name + "\t" + c.getName() + "\t" + c.getType());
        int n = 0;
        for (Map<String,Object> row : t) {
          System.out.println("ROW\t" + name + "\t" + row);
          if (++n >= 2) break;
        }
      }
      db.close();
    }
  }
}
