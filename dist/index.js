'use strict';

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.Deparser = exports.verify = exports.clean = exports.byType = exports.tables = exports.all = exports.first = exports.walk = exports.deparse = exports.parse = undefined;

var _deparser = require('./deparser');

var _deparser2 = _interopRequireDefault(_deparser);

var _utils = require('./utils');

function _interopRequireDefault(obj) { return obj && obj.__esModule ? obj : { default: obj }; }

function canRequire(name) {
  try {
    return !!require.resolve(name);
  } catch (e) {/* do nothing */}
  return false;
}

const whichParser = canRequire('pg-query-native') ? 'pg-query-native' : 'pg-query-emscripten';
const parser = require(whichParser).parse;
let parse = parser;
if (whichParser === 'pg-query-emscripten') {
  const emscriptenParser = parse;
  // make the return of the emscripen parser be equivalent to the native parser
  exports.parse = parse = sql => {
    var _emscriptenParser = emscriptenParser(sql);

    const err = _emscriptenParser.error,
          stderr = _emscriptenParser.stderr_buffer,
          query = _emscriptenParser.parse_tree;

    if (err) {
      const message = err.message,
            funcname = err.funcname,
            filename = err.filename,
            lineno = err.lineno,
            cursorpos = err.cursorpos;

      const error = new Error(message);
      error.fileName = filename;
      error.lineNumber = lineno;
      error.cursorPosition = cursorpos;
      error.functionName = funcname;
      error.context = null;
      return { error: error, query: query };
    }
    return { query: query, stderr: stderr };
  };
}

const deparse = _deparser2.default.deparse;

const verify = query => {
  const result = deparse(parse(query).query);

  const json1 = (0, _utils.clean)(parse(query).query);
  const json2 = (0, _utils.clean)(parse(result).query);

  return JSON.stringify(json1) === JSON.stringify(json2);
};

exports.parse = parse;
exports.deparse = deparse;
exports.walk = _utils.walk;
exports.first = _utils.first;
exports.all = _utils.all;
exports.tables = _utils.tables;
exports.byType = _utils.byType;
exports.clean = _utils.clean;
exports.verify = verify;
exports.Deparser = _deparser2.default;
//# sourceMappingURL=index.js.map