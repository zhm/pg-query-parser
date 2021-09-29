const { parse } = require('pg-query-native');
const Deparser = require('./deparser');
const { walk, all, first, tables, byType, clean } = require('./utils');

const deparse = Deparser.deparse;

const verify = (query) => {
  const result = deparse(parse(query).query);

  const json1 = clean(parse(query).query);
  const json2 = clean(parse(result).query);

  return JSON.stringify(json1) === JSON.stringify(json2);
};

module.exports = { parse, deparse, walk, first, all, tables, byType, clean, verify, Deparser };
