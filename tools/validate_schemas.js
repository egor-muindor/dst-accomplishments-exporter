#!/usr/bin/env node
// Validates JSON data files against JSON Schema draft 2020-12 using ajv v8.
// Usage: node tools/validate_schemas.js <schema.json> <data.json> [data2.json ...]
// Exits 0 if all valid, 1 if any invalid.

const Ajv2020 = require("ajv/dist/2020");
const fs = require("fs");
const path = require("path");

const [,, schemaFile, ...dataGlobs] = process.argv;
if (!schemaFile || dataGlobs.length === 0) {
  console.error("Usage: validate_schemas.js <schema.json> <data-glob...>");
  process.exit(2);
}

const ajv = new Ajv2020({ strict: false });

const schema = JSON.parse(fs.readFileSync(schemaFile, "utf8"));
const validate = ajv.compile(schema);

// Expand globs manually if needed (node 21+ has globSync, older does not)
const dataFiles = [];
for (const pattern of dataGlobs) {
  if (pattern.includes("*")) {
    // Simple glob: expand directory + pattern match
    const dir = path.dirname(pattern);
    const base = path.basename(pattern);
    const re = new RegExp("^" + base.replace(/\./g, "\\.").replace(/\*/g, ".*") + "$");
    const entries = fs.readdirSync(dir).filter(f => re.test(f)).map(f => path.join(dir, f));
    dataFiles.push(...entries);
  } else {
    dataFiles.push(pattern);
  }
}

let allValid = true;
for (const dataFile of dataFiles) {
  const data = JSON.parse(fs.readFileSync(dataFile, "utf8"));
  const valid = validate(data);
  if (valid) {
    console.log(`${dataFile} valid`);
  } else {
    console.error(`${dataFile} invalid`);
    console.error(JSON.stringify(validate.errors, null, 2));
    allValid = false;
  }
}

process.exit(allValid ? 0 : 1);
