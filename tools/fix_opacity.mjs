import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, "..", "lib");

function walk(d) {
  for (const f of fs.readdirSync(d)) {
    const p = path.join(d, f);
    if (fs.statSync(p).isDirectory()) walk(p);
    else if (p.endsWith(".dart")) {
      let t = fs.readFileSync(p, "utf8");
      const n = t.replace(
        /\.withOpacity\(\s*([\d.]+)\s*\)/g,
        (_, a) => `.withValues(alpha: ${a})`,
      );
      if (n !== t) {
        fs.writeFileSync(p, n);
        console.log(p);
      }
    }
  }
}
walk(root);
