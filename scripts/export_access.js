const fs = require('fs');
const path = require('path');
const MDBReader = require('mdb-reader').default;

const [,, input, output] = process.argv;
if (!input || !output) throw new Error('usage: node export_access.js input.dat output.json');
const reader = new MDBReader(fs.readFileSync(input));
const result = { source: path.basename(input), exportedAt: new Date().toISOString(), tables: {} };
for (const tableName of reader.getTableNames()) {
  const table = reader.getTable(tableName);
  result.tables[tableName] = {
    columns: table.getColumnNames(),
    rows: table.getData()
  };
}
fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, JSON.stringify(result, null, 2));
console.log(`${input}: ${reader.getTableNames().length} tables -> ${output}`);
