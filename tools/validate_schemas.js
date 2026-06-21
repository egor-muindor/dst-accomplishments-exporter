#!/usr/bin/env node
// Validates JSON data files against JSON Schema draft 2020-12 using ajv v8.
// Usage: node tools/validate_schemas.js <schema.json> <data.json|glob> [more...]
// Exit codes: 0 all valid; 1 any invalid/unreadable; 2 usage error, bad schema,
// or a glob that matched no files (a zero-match must not pass the gate silently).

const Ajv2020 = require("ajv/dist/2020");
const fs = require("fs");
const path = require("path");

const [, , schemaFile, ...dataGlobs] = process.argv;
if (!schemaFile || dataGlobs.length === 0) {
  console.error("Usage: validate_schemas.js <schema.json> <data-glob...>");
  process.exit(2);
}

const ajv = new Ajv2020({ strict: true });

let validate;
try {
  validate = ajv.compile(JSON.parse(fs.readFileSync(schemaFile, "utf8")));
} catch (e) {
  console.error(`cannot load schema ${schemaFile}: ${e.message}`);
  process.exit(2);
}

// Expand simple "*" globs manually (no extra dependency, node-version agnostic).
// Only "*" is a wildcard; every other regex metacharacter is escaped.
function expand(pattern) {
  if (!pattern.includes("*")) return [pattern];
  const dir = path.dirname(pattern);
  const base = path.basename(pattern);
  const re = new RegExp(
    "^" + base.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replace(/\\\*/g, ".*") + "$"
  );
  let entries;
  try {
    entries = fs.readdirSync(dir);
  } catch (e) {
    return [];
  }
  return entries
    .filter((f) => re.test(f))
    .map((f) => path.join(dir, f))
    .filter((f) => fs.statSync(f).isFile());
}

let allValid = true;
for (const pattern of dataGlobs) {
  const files = expand(pattern);
  if (files.length === 0) {
    console.error(`no files matched: ${pattern}`);
    process.exit(2);
  }
  for (const dataFile of files) {
    let data;
    try {
      data = JSON.parse(fs.readFileSync(dataFile, "utf8"));
    } catch (e) {
      console.error(`${dataFile} unreadable: ${e.message}`);
      allValid = false;
      continue;
    }
    if (validate(data)) {
      console.log(`${dataFile} valid`);
    } else {
      console.error(`${dataFile} invalid`);
      console.error(JSON.stringify(validate.errors, null, 2));
      allValid = false;
    }
  }
}

process.exit(allValid ? 0 : 1);
