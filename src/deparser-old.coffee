_ = require 'lodash'
{format} = require 'util'
contains = _.contains
keys = _.keys
first = _.first

compact = (o) ->
  _.select _.compact(o), (p) ->
    return false unless p?
    p.toString().length

fk = (value) -> _.first(_.keys(value))
fv = (value) -> _.first(_.values(value))

fail = (msg) -> throw new Error(msg)

indent = (text, count=1) -> text

module.exports =
class Deparser
  @deparse: (query) ->
    new Deparser(query).deparseQuery()

  constructor: (@tree) ->

  deparseQuery: ->
    (@tree.map (node) => @deparse(node)).join("\n\n")

  deparseNodes: (nodes) ->
    nodes.map (node) => @deparse(node)

  quote: (value) ->
    return unless value?
    if _.isArray(value)
      value.map (o) => @quote(o)
    else
      '"' + value + '"'

  # SELECT encode(E'''123\\000\\001', 'base64')
  escape: (literal) ->
    "'" + literal.replace(/'/g, "''") + "'"

  type: (names, args) ->
    [catalog, type] = names.map((name) => @deparse(name))

    mods = (name, args) ->
      if args?
        name + '(' + args + ')'
      else
        name

    # handle the special "char" (in quotes) type
    names[0].String.str = '"char"' if names[0].String.str is 'char'

    return mods(@deparseNodes(names).join('.'), args) if catalog isnt 'pg_catalog'

    res =
      switch type
        when 'bpchar'
          if args?
            'char'
          else
            # return `pg_catalog.bpchar` below so that the following is symmetric
            # SELECT char 'c' = char 'c' AS true
            'pg_catalog.bpchar'
        when 'varchar'
          'varchar'
        when 'numeric'
          'numeric'
        when 'bool'
          'boolean'
        when 'int2'
          'smallint'
        when 'int4'
          'int'
        when 'int8'
          'bigint'
        when 'real', 'float4'
          'real'
        when 'float8'
          'pg_catalog.float8'
        when 'text'
          # SELECT EXTRACT(CENTURY FROM CURRENT_DATE)>=21 AS True
          'pg_catalog.text'
        when 'date'
          'pg_catalog.date'
        when 'time'
          'time'
        when 'timetz'
          'pg_catalog.timetz'
        when 'timestamp'
          'timestamp'
        when 'timestamptz'
          'pg_catalog.timestamptz'
        when 'interval'
          'interval'
        else
          fail format("Can't deparse type: %s", type)

    return mods(res, args)

  deparse: (item, context) ->
    return unless item?
    return item if _.isNumber(item)

    type = keys(item)[0]
    node = _.values(item)[0]

    throw new Error(type + " is not implemented") unless @[type]?

    func = @[type]

    func.call(this, node, context)

  'A_Expr': (node, context) ->
    output = []

    switch node.kind
      when 0 # AEXPR_OP
        if node.lexpr
          output.push '(' + @deparse(node.lexpr) + ')'

        if node.name.length > 1
          arg1 = @deparse(node.name[0])
          arg2 = @deparse(node.name[1])
          output.push 'OPERATOR(' + arg1 + '.' + arg2 + ')'
        else
          output.push(@deparse(node.name[0]))

        if node.rexpr
          output.push '(' + @deparse(node.rexpr) + ')'

        if output.length is 2
          return '(' + output.join('') + ')'
        else
          return '(' + output.join(' ') + ')'

      when 1 # AEXPR_OP_ANY
        output.push @deparse(node.lexpr)
        output.push format('ANY (%s)', @deparse(node.rexpr))
        return output.join(' ' + @deparse(node.name[0]) + ' ')

      when 2 # AEXPR_OP_ALL
        output.push @deparse(node.lexpr)
        output.push format('ALL (%s)', @deparse(node.rexpr))
        return output.join(' ' + @deparse(node.name[0]) + ' ')

      when 3 # AEXPR_DISTINCT
        return format('%s IS DISTINCT FROM %s', @deparse(node.lexpr), @deparse(node.rexpr))

      when 4 # AEXPR_NULLIF
        return format('NULLIF(%s, %s)', @deparse(node.lexpr), @deparse(node.rexpr))

      when 5 # AEXPR_OF
        op = if node.name[0].String.str is '=' then 'IS OF' else 'IS NOT OF'
        list = node.rexpr.map (node) => @deparse(node)
        return format('%s %s (%s)', @deparse(node.lexpr), op, list.join(', '))

      when 6 # AEXPR_IN
        rexpr = node.rexpr.map (node) => @deparse(node)

        operator =
          if node.name[0].String.str == '='
            'IN'
          else
            'NOT IN'

        return format('%s %s (%s)', @deparse(node.lexpr), operator, rexpr.join(', '))

      when 7 # AEXPR_LIKE
        output.push @deparse(node.lexpr)

        if node.name[0].String.str is '!~~'
          output.push format('NOT LIKE (%s)', @deparse(node.rexpr))
        else
          output.push format('LIKE (%s)', @deparse(node.rexpr))

        return output.join(' ')

      when 8 # AEXPR_ILIKE
        output.push @deparse(node.lexpr)

        if node.name[0].String.str is '!~~*'
          output.push format('NOT ILIKE (%s)', @deparse(node.rexpr))
        else
          output.push format('ILIKE (%s)', @deparse(node.rexpr))

        return output.join(' ')

      when 9 # AEXPR_SIMILAR TODO(zhm) untested
        output.push @deparse(node.lexpr)
        output.push format('SIMILAR TO %s', @deparse(node.rexpr))
        return output.join(' ')

      when 10 # AEXPR_BETWEEN TODO(zhm) untested
        output.push @deparse(node.lexpr)
        output.push format('BETWEEN %s AND %s', @deparse(node.rexpr[0]),  @deparse(node.rexpr[1]))
        return output.join(' ')

      when 11 # AEXPR_NOT_BETWEEN TODO(zhm) untested
        output.push @deparse(node.lexpr)
        output.push format('NOT BETWEEN %s AND %s', @deparse(node.rexpr[0]),  @deparse(node.rexpr[1]))
        return output.join(' ')


    if node.lexpr
      if node.lexpr.A_Const?
        output.push @deparse(node.lexpr, context || true)
      else
        output.push '(' + @deparse(node.lexpr, context || true) + ')'

    '(' + output + ')'

  'Alias': (node, context) ->
    name = node.aliasname

    output = [ 'AS' ]

    if node.colnames
      output.push name + '(' + @deparseNodes(node.colnames).join(', ') + ')'
    else
      output.push @quote(name)

    output.join(' ')

  'A_ArrayExpr': (node) ->
    output = [ 'ARRAY[' ]

    list = []

    if node.elements
      list = node.elements.map (e) => @deparse(e)
      # list = (@deparse(element) for element in node.elements)

    output.push list.join(', ')
    output.push(']')

    output.join('')

  'A_Const': (node, context) ->
    if node.val.String
      @escape(@deparse(node.val))
    else
      @deparse(node.val)

  'A_Indices': (node) ->
    if node.lidx
      format('[%s:%s]', @deparse(node.lidx), @deparse(node.uidx))
    else
      format('[%s]', @deparse(node.uidx))

  'A_Indirection': (node) ->
    output = [ '(' + @deparse(node.arg) + ')' ]

    # TODO(zhm) figure out the actual rules for when a '.' is needed
    #
    # select a.b[0] from a;
    # select (select row(1)).*
    # select c2[2].f2 from comptable
    # select c2.a[2].f2[1].f3[0].a1 from comptable

    parts = []

    for subnode in node.indirection
      if subnode.String or subnode.A_Star
        value =
          if subnode.A_Star
            '*'
          else
            @quote(subnode.String.str)

        output.push '.' + value
      else
        output.push @deparse(subnode)

    output.join('')

  'A_Star': (node, context) ->
    '*'

  'BitString': (node) ->
    prefix = node.str[0]
    "#{prefix}'#{node.str.substring(1)}'"

  'BoolExpr': (node) ->
    switch node.boolop
      when 0
        '(' + @deparseNodes(node.args).join(' AND ') + ')'
      when 1
        '(' + @deparseNodes(node.args).join(' OR ') + ')'
      when 2
        format('NOT (%s)', @deparseNodes(node.args))
      else
        fail(format('Unhandled BoolExpr: %s', JSON.stringify(node)))

  'BooleanTest': (node) ->
    output = []
    output.push @deparse(node.arg)

    tests = [
      'IS TRUE'
      'IS NOT TRUE'
      'IS FALSE'
      'IS NOT FALSE'
      'IS UNKNOWN'
      'IS NOT UNKNOWN'
    ]

    output.push tests[node.booltesttype]
    output.join ' '

  'CaseExpr': (node) ->
    output = ['CASE']

    output.push(@deparse(node.arg)) if node.arg

    output.push(@deparse(arg)) for arg in node.args

    if node['defresult']
      output.push 'ELSE'
      output.push @deparse(node.defresult)

    output.push 'END'
    output.join(' ')

  'CoalesceExpr': (node) ->
    output = []

    args = []
    args.push(@deparse(arg)) for arg in node.args

    format 'COALESCE(%s)', args.join(', ')

  'CollateClause': (node) ->
    output = []
    output.push @deparse(node.arg) if node.arg?
    output.push 'COLLATE'
    output.push @quote(@deparseNodes(node.collname)) if node.collname?
    output.join ' '

  'ColumnDef': (node) ->
    output = [ @quote(node.colname) ]

    output.push @deparse(node.typeName)

    if node.raw_default
      output.push 'USING'
      output.push @deparse(node.raw_default)

    if node.constraints
      output.push(@deparse(item)) for item in node.constraints

    _.compact(output).join(' ')

  'ColumnRef': (node) ->
    fields = node.fields.map (field) =>
      if field.String
        @quote(@deparse(field))
      else
        @deparse(field)

    fields.join('.')

  'CommonTableExpr': (node) ->
    output = []
    output.push node.ctename
    output.push format('(%s)', @quote(@deparseNodes(node.aliascolnames))) if node.aliascolnames
    output.push format('AS (%s)', @deparse(node.ctequery))
    output.join(' ')

  'Float': (node) ->
    # wrap negative numbers in parens, SELECT (-2147483648)::int4 * (-1)::int4
    if node.str[0] is '-'
      '(' + node.str + ')'
    else
      node.str

  'FuncCall': (node, context) ->
    output = []

    params = []

    if node.args
      params = node.args.map (item) =>
        @deparse(item)

    # COUNT(*)
    params.push '*' if node.agg_star

    name = @deparseNodes(node.funcname).join('.')

    order = []

    withinGroup = node.agg_within_group

    if node.agg_order
      order.push 'ORDER BY'
      order.push (node.agg_order.map (node) => @deparse(node, context)).join(", ")

    call = []
    call.push "#{name}("
    call.push 'DISTINCT ' if node.agg_distinct

    # prepend variadic before the last parameter
    # SELECT CONCAT('|', VARIADIC ARRAY['1','2','3'])
    if node.func_variadic
      params[params.length - 1] = "VARIADIC #{params[params.length - 1]}"

    call.push params.join(', ')

    if order.length and not withinGroup
      call.push ' '
      call.push order.join(' ')

    call.push "#{''})"

    output.push(compact(call).join(''))

    if order.length and withinGroup
      output.push 'WITHIN GROUP'
      output.push '(' + order.join(' ') + ')'

    if node.agg_filter?
      output.push format('FILTER (WHERE %s)', @deparse(node.agg_filter))

    if node.over?
      output.push format('OVER %s', @deparse(node.over, 'function'))

    output.join(' ')

  'Integer': (node) ->
    if node.ival < 0
      '(' + node.ival + ')'
    else
      node.ival.toString()

  'IntoClause': (node) ->
    output = []
    output.push @deparse(node.rel)
    output.join ''

  'JoinExpr': (node, context) ->
    output = []

    output.push @deparse(node.larg)

    if node.isNatural
      output.push('NATURAL')

    join =
      switch true
        when node.jointype is 0 and node.quals? then 'INNER JOIN'
        when node.jointype is 0 and not node.isNatural and not node.quals? and not node.usingClause? then 'CROSS JOIN'
        when node.jointype is 0 then 'JOIN'
        when node.jointype is 1 then 'LEFT OUTER JOIN'
        when node.jointype is 2 then 'FULL OUTER JOIN'
        when node.jointype is 3 then 'RIGHT OUTER JOIN'
        else fail format('unhandled join type %s', node.jointype)

    output.push(join)

    if node.rarg
      # wrap nested join expressions in parens to make the following symmetric:
      # select * from int8_tbl x cross join (int4_tbl x cross join lateral (select x.f1) ss)
      if node.rarg.JoinExpr? and not node.rarg.JoinExpr.alias?
        output.push '(' + @deparse(node.rarg) + ')'
      else
        output.push @deparse(node.rarg)

    if node.quals
      output.push "ON " + @deparse(node.quals)

    if node.usingClause
      output.push "USING (" + @quote(@deparseNodes(node.usingClause)).join(", ") + ")"

    wrapped =
      if node.rarg.JOINEXPR? or node.alias
        '(' + output.join(' ') + ')'
      else
        output.join(' ')

    if node.alias
      wrapped + ' ' + @deparse(node.alias)
    else
      wrapped

  'LockingClause': (node) ->
    strengths = [
      'NONE' # LCS_NONE
      'FOR KEY SHARE'
      'FOR SHARE'
      'FOR NO KEY UPDATE'
      'FOR UPDATE'
    ]

    output = []

    output.push strengths[node.strength]

    if node.lockedRels
      output.push 'OF'
      output.push (node.lockedRels.map((item) => @deparse(item))).join(', ')

    output.join(' ')

  'MinMaxExpr': (node) ->
    output = []

    if node.op is 0
      output.push 'GREATEST'
    else
      output.push 'LEAST'


    args = []
    args.push(@deparse(arg)) for arg in node.args

    output.push('(' + args.join(', ') + ')')
    output.join('')

  'NamedArgExpr': (node) ->
    output = []
    output.push node.name
    output.push ':='
    output.push @deparse(node.arg)
    output.join ' '

  'Null': (node) ->
    'NULL'

  'NullTest': (node) ->
    output = [ @deparse(node.arg) ]
    if node.nulltesttype is 0
      output.push 'IS NULL'
    else if node.nulltesttype is 1
      output.push 'IS NOT NULL'
    output.join(' ')

  'RangeFunction': (node) ->
    output = []
    output.push 'LATERAL' if node.lateral

    funcs = []

    for funcCall in node.functions
      call = [ @deparse(funcCall[0]) ]

      if funcCall[1] && funcCall[1].length
        call.push 'AS (' + (funcCall[1].map((def) => @deparse(def))).join(', ') + ')'

      funcs.push call.join(' ')

    calls = funcs.join(', ')

    if node.is_rowsfrom
      output.push 'ROWS FROM (' + calls + ')'
    else
      output.push calls

    if node.ordinality
      output.push 'WITH ORDINALITY'

    output.push @deparse(node.alias) if node.alias

    if node.coldeflist
      if not node.alias
        output.push ' AS (' + (node.coldeflist.map (col) => @deparse(col)).join(", ") + ')'
      else
        output.push '(' + (node.coldeflist.map (col) => @deparse(col)).join(", ") + ')'

    output.join(' ')

  'RangeSubselect': (node, context) ->
    output = ''

    if node.lateral
      output += 'LATERAL '

    output += '(' + @deparse(node.subquery) + ')'

    if node.alias
      output + ' ' + @deparse(node.alias)
    else
      output

  'RangeVar': (node, context) ->
    output = []
    output.push 'ONLY' if node.inhOpt is 0

    if node.relpersistence is 'u'
      output.push 'UNLOGGED'

    if node.relpersistence is 't'
      output.push 'TEMPORARY'

    if node.schemaname?
      output.push @quote(node.schemaname)
      output.push '.'

    output.push @quote(node.relname)
    output.push @deparse(node.alias) if node.alias

    output.join(' ')

  'ResTarget': (node, context) ->
    if context is 'select'
      compact([ @deparse(node.val), @quote(node.name) ]).join(' AS ')
    else if context is 'update'
      compact([ node.name, @deparse(node.val) ]).join(' = ')
    else if not node.val?
      @quote(node.name)
    else
      fail format("Can't deparse %s in context %s", JSON.stringify(node), context)

  'RowExpr': (node) ->
    args = node.args or []
    if node.row_format is 2
      '(' + args.map((arg) => @deparse(arg)).join(', ') + ')'
    else
      'ROW(' + args.map((arg) => @deparse(arg)).join(', ') + ')'

  'SelectStmt': (node, context) ->
    output = []

    output.push @deparse(node.withClause) if node.withClause

    if node.op is 0
      # VALUES select's don't get SELECT
      unless node.valuesLists?
        output.push 'SELECT'
    else
      output.push '(' + @deparse(node.larg) + ')'

      sets = [
        'NONE'
        'UNION'
        'INTERSECT'
        'EXCEPT'
      ]

      output.push sets[node.op]

      if node.all
        output.push 'ALL'

      output.push '(' + @deparse(node.rarg) + ')'

    if node.distinctClause
      if node.distinctClause[0]?
        output.push 'DISTINCT ON'
        output.push '(' + indent((node.distinctClause.map (node) => @deparse(node, 'select')).join(",\n")) + ')'
      else
        output.push 'DISTINCT'

    if node.targetList
      output.push indent((node.targetList.map (node) => @deparse(node, 'select')).join(",\n"))

    if node.intoClause
      output.push "INTO"
      output.push indent(@deparse(node.intoClause))

    if node.fromClause
      output.push "FROM"
      output.push indent((node.fromClause.map (node) => @deparse(node, 'from')).join(",\n"))

    if node.whereClause
      output.push "WHERE"
      output.push indent(@deparse(node.whereClause))

    if node.valuesLists
      output.push 'VALUES'

      lists = node.valuesLists.map (list) =>
        '(' + (list.map (v) => @deparse(v)).join(', ') + ')'

      output.push lists.join(', ')

    if node.groupClause
      output.push 'GROUP BY'
      output.push indent((node.groupClause.map (node) => @deparse(node, 'group')).join(",\n"))

    if node.havingClause
      output.push 'HAVING'
      output.push indent(@deparse(node.havingClause))

    if node.windowClause
      output.push 'WINDOW'

      windows = []

      for w in node.windowClause
        window = []
        window.push @quote(w.WindowDef.name) + ' AS' if w.WindowDef.name
        window.push '(' + @deparse(w, 'window') + ')'
        windows.push window.join(' ')

      output.push windows.join(', ')

    if node.sortClause
      output.push 'ORDER BY'
      output.push indent((node.sortClause.map (node) => @deparse(node, 'sort')).join(",\n"))

    if node.limitCount
      output.push 'LIMIT'
      output.push indent(@deparse(node.limitCount))

    if node.limitOffset
      output.push 'OFFSET'
      output.push indent(@deparse(node.limitOffset))

    if node.lockingClause
      node.lockingClause.forEach (item) =>
        output.push @deparse(item)

    output.join(" ")

  'SortBy': (node) ->
    output = []
    output.push @deparse(node.node)

    output.push 'ASC'  if node.sortby_dir is 1
    output.push 'DESC' if node.sortby_dir is 2

    if node.sortby_dir is 3
      output.push 'USING ' + @deparseNodes(node.useOp)

    output.push 'NULLS FIRST' if node.sortby_nulls is 1
    output.push 'NULLS LAST'  if node.sortby_nulls is 2

    output.join(' ')

  'String': (node) ->
    node.str

  'SubLink': (node) ->
    # if node.subLinkType is 2 and not node.operName?
    #   node.operName = ['=']

    switch true
      when node.subLinkType is 0
        format('EXISTS (%s)', @deparse(node.subselect))
      when node.subLinkType is 1
        format('%s %s ALL (%s)', @deparse(node.testexpr), @deparse(node.operName[0]), @deparse(node.subselect))
      when node.subLinkType is 2 and not node.operName?
        format('%s IN (%s)', @deparse(node.testexpr), @deparse(node.subselect))
      when node.subLinkType is 2
        format('%s %s ANY (%s)', @deparse(node.testexpr), @deparse(node.operName[0]), @deparse(node.subselect))
      when node.subLinkType is 3
        format('%s %s (%s)', @deparse(node.testexpr), @deparse(node.operName[0]), @deparse(node.subselect))
      when node.subLinkType is 4
        format('(%s)', @deparse(node.subselect))
      when node.subLinkType is 5
        # TODO(zhm) what is this?
        fail('Encountered MULTIEXPR_SUBLINK', JSON.stringify(node))
        # MULTIEXPR_SUBLINK
        # format('(%s)', @deparse(node.subselect))
      when node.subLinkType is 6
        format('ARRAY (%s)', @deparse(node.subselect))

  'TypeCast': (node) ->
    @deparse(node.arg) + '::' + @deparse(node['typeName'])

  'TypeName': (node) ->
    return @deparseInterval(node) if _.last(node.names).String.str is 'interval'

    output = []
    output.push('SETOF') if node['setof']

    args = null

    if node.typmods?
      args = node.typmods.map (item) =>
        @deparse(item)

    type = []
    type.push @type(node['names'], args && args.join(', '))
    type.push '[]' if node.arrayBounds?

    output.push type.join('')

    output.join(' ')

  'CaseWhen': (node) ->
    output = [ 'WHEN' ]
    output.push @deparse(node.expr)
    output.push 'THEN'
    output.push @deparse(node.result)
    output.join(' ')

  'WindowDef': (node, context) ->
    output = []

    unless context is 'window'
      output.push(node.name) if node.name

    empty = (not node.partitionClause? and not node.orderClause?)

    frameOptions = @deparseFrameOptions(node.frameOptions, node.refname, node.startOffset, node.endOffset)

    if empty and context isnt 'window' and not node.name? and frameOptions.length is 0
      return '()'

    windowParts = []

    parens = false

    if node.partitionClause
      partition = [ 'PARTITION BY' ]

      clause = node.partitionClause.map (item) => @deparse(item)

      partition.push clause.join(', ')

      windowParts.push partition.join(' ')
      parens = true

    if node.orderClause
      windowParts.push 'ORDER BY'

      orders = node.orderClause.map (item) =>
        @deparse(item)

      windowParts.push orders.join(', ')

      parens = true

    if frameOptions.length
      parens = true
      windowParts.push frameOptions

    if parens and context isnt 'window'
      output.join(' ') + ' (' + windowParts.join(' ') + ')'
    else
      output.join(' ') + windowParts.join(' ')

  'WithClause': (node) ->
    output = [ 'WITH' ]

    output.push 'RECURSIVE' if node.recursive

    ctes = []
    ctes.push(@deparse(cte)) for cte in node.ctes

    output.push ctes.join(', ')
    output.join(' ')

  deparseFrameOptions: (options, refName, startOffset, endOffset) ->
    FRAMEOPTION_NONDEFAULT = 0x00001 #/* any specified? */
    FRAMEOPTION_RANGE = 0x00002 #/* RANGE behavior */
    FRAMEOPTION_ROWS = 0x00004 #/* ROWS behavior */
    FRAMEOPTION_BETWEEN = 0x00008 #/* BETWEEN given? */
    FRAMEOPTION_START_UNBOUNDED_PRECEDING = 0x00010 #/* start is U. P. */
    FRAMEOPTION_END_UNBOUNDED_PRECEDING = 0x00020 #/* (disallowed) */
    FRAMEOPTION_START_UNBOUNDED_FOLLOWING = 0x00040 #/* (disallowed) */
    FRAMEOPTION_END_UNBOUNDED_FOLLOWING = 0x00080 #/* end is U. F. */
    FRAMEOPTION_START_CURRENT_ROW = 0x00100 #/* start is C. R. */
    FRAMEOPTION_END_CURRENT_ROW = 0x00200 #/* end is C. R. */
    FRAMEOPTION_START_VALUE_PRECEDING = 0x00400 #/* start is V. P. */
    FRAMEOPTION_END_VALUE_PRECEDING = 0x00800 #/* end is V. P. */
    FRAMEOPTION_START_VALUE_FOLLOWING = 0x01000 #/* start is V. F. */
    FRAMEOPTION_END_VALUE_FOLLOWING = 0x02000 #/* end is V. F. */

    return '' unless options & FRAMEOPTION_NONDEFAULT

    output = []

    output.push refName if refName?

    if options & FRAMEOPTION_RANGE
      output.push 'RANGE'

    if options & FRAMEOPTION_ROWS
      output.push 'ROWS'

    between = options & FRAMEOPTION_BETWEEN

    if between
      output.push 'BETWEEN'

    if options & FRAMEOPTION_START_UNBOUNDED_PRECEDING
      output.push 'UNBOUNDED PRECEDING'

    if options & FRAMEOPTION_START_UNBOUNDED_FOLLOWING
      output.push 'UNBOUNDED FOLLOWING'

    if options & FRAMEOPTION_START_CURRENT_ROW
      output.push 'CURRENT ROW'

    if options & FRAMEOPTION_START_VALUE_PRECEDING
      output.push @deparse(startOffset) + ' PRECEDING'

    if options & FRAMEOPTION_START_VALUE_FOLLOWING
      output.push @deparse(startOffset) + ' FOLLOWING'

    if between
      output.push 'AND'

      if options & FRAMEOPTION_END_UNBOUNDED_PRECEDING
        output.push 'UNBOUNDED PRECEDING'

      if options & FRAMEOPTION_END_UNBOUNDED_FOLLOWING
        output.push 'UNBOUNDED FOLLOWING'

      if options & FRAMEOPTION_END_CURRENT_ROW
        output.push 'CURRENT ROW'

      if options & FRAMEOPTION_END_VALUE_PRECEDING
        output.push @deparse(endOffset) + ' PRECEDING'

      if options & FRAMEOPTION_END_VALUE_FOLLOWING
        output.push @deparse(endOffset) + ' FOLLOWING'

    output.join ' '

  deparseInterval: (node) ->
    type = [ 'interval' ]
    type.push '[]' if node.arrayBounds?

    if node.typmods
      typmods = node.typmods.map((item) => @deparse(item))

      intervals = @interval(typmods[0])

      # SELECT interval(0) '1 day 01:23:45.6789'
      if node.typmods[0] and node.typmods[0].A_Const and node.typmods[0].A_Const.val.Integer.ival is 32767 and node.typmods[1] and node.typmods[1].A_Const?
        intervals = ['(' + node.typmods[1].A_Const.val.Integer.ival + ')']

      else
        intervals = intervals.map (part) =>
          if part is 'second' and typmods.length is 2
            "second(#{_.last(typmods)})"
          else
            part

      type.push intervals.join(' to ')

    type.join(' ')

  interval: (mask) ->
    # ported from https://github.com/lfittl/pg_query/blob/master/lib/pg_query/deparse/interval.rb
    @MASKS ?=
      0: 'RESERV'
      1: 'MONTH'
      2: 'YEAR'
      3: 'DAY'
      4: 'JULIAN'
      5: 'TZ'
      6: 'DTZ'
      7: 'DYNTZ'
      8: 'IGNORE_DTF'
      9: 'AMPM'
      10: 'HOUR'
      11: 'MINUTE'
      12: 'SECOND'
      13: 'MILLISECOND'
      14: 'MICROSECOND'
      15: 'DOY'
      16: 'DOW'
      17: 'UNITS'
      18: 'ADBC'
      19: 'AGO'
      20: 'ABS_BEFORE'
      21: 'ABS_AFTER'
      22: 'ISODATE'
      23: 'ISOTIME'
      24: 'WEEK'
      25: 'DECADE'
      26: 'CENTURY'
      27: 'MILLENNIUM'
      28: 'DTZMOD'

    @BITS ?= _.invert(@MASKS)

    results = []

    unless @INTERVALS?
      @INTERVALS = {}
      @INTERVALS[(1 << @BITS['YEAR'])] = ['year']
      @INTERVALS[(1 << @BITS['MONTH'])] = ['month']
      @INTERVALS[(1 << @BITS['DAY'])] = ['day']
      @INTERVALS[(1 << @BITS['HOUR'])] = ['hour']
      @INTERVALS[(1 << @BITS['MINUTE'])] = ['minute']
      @INTERVALS[(1 << @BITS['SECOND'])] = ['second']
      @INTERVALS[(1 << @BITS['YEAR'] | 1 << @BITS['MONTH'])] = ['year', 'month']
      @INTERVALS[(1 << @BITS['DAY'] | 1 << @BITS['HOUR'])] = ['day', 'hour']
      @INTERVALS[(1 << @BITS['DAY'] | 1 << @BITS['HOUR'] | 1 << @BITS['MINUTE'])] = ['day', 'minute']
      @INTERVALS[(1 << @BITS['DAY'] | 1 << @BITS['HOUR'] | 1 << @BITS['MINUTE'] | 1 << @BITS['SECOND'])] = ['day', 'second']
      @INTERVALS[(1 << @BITS['HOUR'] | 1 << @BITS['MINUTE'])] = ['hour', 'minute']
      @INTERVALS[(1 << @BITS['HOUR'] | 1 << @BITS['MINUTE'] | 1 << @BITS['SECOND'])] = ['hour', 'second']
      @INTERVALS[(1 << @BITS['MINUTE'] | 1 << @BITS['SECOND'])] = ['minute', 'second']

      # utils/timestamp.h
      # #define INTERVAL_FULL_RANGE (0x7FFF)
      @INTERVALS[@INTERVAL_FULL_RANGE = '32767'] = []

    return @INTERVALS[mask.toString()]