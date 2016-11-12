function canRequire(name) {
  try {
    return !!require.resolve(name);
  } catch (e) { /* do nothing */ }
  return false;
}

const whichParser = canRequire('pg-query-native') ? 'pg-query-native' : 'pg-query-emscripten';
const parser = require(whichParser).parse;
let parse = parser;
if (whichParser === 'pg-query-emscripten') {
  const emscriptenParser = parse;
  // make the return of the emscripen parser be equivalent to the native parser
  parse = (sql) => {
    const { error: err, stderr_buffer: stderr, parse_tree: query } = emscriptenParser(sql);
    if (err) {
      const { message, funcname, filename, lineno, cursorpos } = err;
      const error = new Error(message);
      error.fileName = filename;
      error.lineNumber = lineno;
      error.cursorPosition = cursorpos;
      error.functionName = funcname;
      error.context = null;
      return { error, query };
    }
    return { query, stderr };
  };
}

import Deparser from './deparser';
import { walk, all, first, tables, byType, clean } from './utils';

const deparse = Deparser.deparse;

const verify = (query) => {
  const result = deparse(parse(query).query);

  const json1 = clean(parse(query).query);
  const json2 = clean(parse(result).query);

  return JSON.stringify(json1) === JSON.stringify(json2);
};

export { parse, deparse, walk, first, all, tables, byType, clean, verify, Deparser };
