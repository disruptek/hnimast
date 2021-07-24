import
  compiler/[ast, lineinfos, idents]

import
  hnimast/hast_common

import
  ./cst_lexer

import
  std/[macros, with, strformat, sequtils]

import
  hmisc/[helpers, hexceptions, base_errors, hdebug_misc],
  hmisc/types/colorstring,
  hmisc/algo/[halgorithm, clformat],
  hmisc/other/blockfmt



type
  CstPoint* = object
    tokenIdx*: int
    lineInfo*: TLineInfo

  CstRange* = object
    startPoint*, endPoint*: CstPoint

  CommentKind = enum
    ckNone
    ckLine ## Line comment for a single line
    ckInline ## Inline coment
    ckMultilineLine ## Line coment that spans multiple lines
    ckMultilineInline ## Inline comment that spans multiple lines

  CstComment* = object
    kind*: CommentKind
    isRawComment*: bool
    rangeInfo*: CstRange
    text*: string

  CstNode* = ref CstNodeObj
  CstNodeObj* = object
    rangeInfo*: CstRange
    docComment*: CstComment
    nextComment*: CstComment
    flags*: set[TNodeFlag]
    baseTokens*: ref seq[Token]

    case kind*: TNodeKind
      of nkCharLit..nkUInt64Lit:
        intVal*: BiggestInt

      of nkFloatLit..nkFloat128Lit:
        floatVal*: BiggestFloat

      of nkStrLit..nkTripleStrLit:
        strVal*: string

      of nkIdent, nkSym:
        ident*: PIdent

      else:
        subnodes*: seq[CstNode]

macro wrapSeqContainer*(
    main: typed,
    fieldType: typed,
    isRef: static[bool] = false,
    withIterators: static[bool] = true
  ) =

  ## - TODO :: Generate kind using `assertKind`

  let
    mainType = main[0]
    field = main[1]
    mutType = if isRef: mainType else: nnkVarTy.newTree(mainType)

  let
    indexOp = ident("[]")
    indexAsgn = ident("[]=")

  result = quote do:
    proc len*(main: `mainType`): int = len(main.`field`)
    proc high*(main: `mainType`): int = high(main.`field`)
    proc add*(main: `mutType`, other: `mainType` | seq[`mainType`]) =
      add(main.`field`, other)

    proc `indexOp`*(main: `mainType`, index: IndexTypes): `fieldType` =
      main.`field`[index]

    proc `indexOp`*(main: `mainType`, slice: SliceTypes): seq[`fieldType`] =
      main.`field`[slice]

    proc `indexAsgn`*(
        main: `mainType`, index: IndexTypes, value: `fieldType`) =

      main.`field`[index] = value

  if withIterators:
    result.add quote do:
      iterator pairs*(main: `mainType`): (int, `fieldType`) =
        for item in pairs(main.`field`):
          yield item

      iterator items*(main: `mainType`): `fieldType` =
        for item in items(main.`field`):
          yield item

      iterator pairs*(main: `mainType`, slice: SliceTypes):
        (int, `fieldType`) =
        let slice = clamp(slice, main.`field`.high)
        var resIdx = 0
        for idx in slice:
          yield (resIdx, main.`field`[idx])
          inc resIdx

      iterator items*(main: `mainType`, slice: SliceTypes): `fieldType` =
        for idx, item in pairs(main, slice):
          yield item

macro wrapStructContainer*(
    main: untyped,
    fieldList: untyped,
    isRef: static[bool] = false
  ): untyped =

  assertKind(main, {nnkDotExpr})

  let
    mainType = main[0]
    structField = main[1]
    mutType = if isRef: mainType else: nnkVarTy.newTree(mainType)

  result = newStmtList()

  var prev: seq[NimNode]
  for field in fieldList:
    if field.kind != nnkExprColonExpr:
      prev.add field

    else:
      for name in prev & field[0]:
        assertNodeKind(name, {nnkIdent})
        let fieldType = field[1]
        assertNodeKind(fieldType, {nnkIdent, nnkBracketExpr})

        let asgn = ident(name.strVal() & "=")

        result.add quote do:
          func `name`*(n: `mainType`): `fieldType` =
            n.`structField`.`name`

          func `asgn`*(n: `mutType`, value: `fieldType`) =
            n.`structField`.`name` = value

      prev = @[]

wrapStructContainer(
  CstNode.rangeInfo, { startPoint, endPoint: CstPoint }, isRef = true)

wrapSeqContainer(CstNode.subnodes, CstNode, isRef = true)


func getStrVal*(p: CstNode, doRaise: bool = true): string =
  ## Get string value from `PNode`
  case p.kind:
    of nkIdent, nkSym: p.ident.s
    of nkStringKinds: p.strVal
    else:
      if doRaise:
        raiseArgumentError(
          "Cannot get string value from node of kind " & $p.kind)

      else:
        ""

func newEmptyCNode*(): CstNode = CstNode(kind: nkEmpty)
func add*(comm: var CstComment, str: string) = comm.text.add str
func newNodeI*(
    kind: TNodeKind, point: CstPoint, base: ref seq[Token]): CstNode =
  CstNode(
    baseTokens: base,
    kind: kind,
    rangeInfo: CstRange(startPoint: point))

proc newTreeI*(
    kind: TNodeKind; info: CstPoint;
    base: ref seq[Token],
    children: varargs[CstNode]
  ): CstNode =

  result = newNodeI(kind, info, base)
  if children.len > 0:
    result.startPoint = children[0].startPoint

  result.subnodes = @children


template transitionNodeKindCommon(k: TNodeKind) =
  let obj {.inject.} = n[]
  n[] = CstNodeObj(
    kind: k,
    rangeInfo: obj.rangeInfo,
    docComment: obj.docComment,
    nextComment: obj.nextComment,
    flags: obj.flags
  )

  when defined(useNodeIds):
    n.id = obj.id

proc transitionSubnodesKind*(n: CstNode, kind: range[nkComesFrom..nkTupleConstr]) =
  transitionNodeKindCommon(kind)
  n.subnodes = obj.subnodes

proc transitionIntKind*(n: CstNode, kind: range[nkCharLit..nkUInt64Lit]) =
  transitionNodeKindCommon(kind)
  n.intVal = obj.intVal

proc transitionNoneToSym*(n: CstNode) =
  transitionNodeKindCommon(nkSym)

proc startToken*(node: CstNode): Token =
  node.baseTokens[][node.startPoint.tokenIdx]

proc relIndent*(node: CstNode, idx: IndexTypes): int =
  let mainIndent = node.startToken.indent
  let subIndent = node.subnodes[idx].startToken.indent

proc newProcNode*(
    kind: TNodeKind, info: CstPoint, body: CstNode,
    params, name, pattern, genericParams, pragmas, exceptions: CstNode
  ): CstNode =

  result = newNodeI(kind, info, body.baseTokens)
  result.subnodes = @[
    name, pattern, genericParams, params, pragmas, exceptions, body]

func `$`*(point: CstPoint): string =
  with result:
    add hshow(point.lineInfo.line)
    add ":"
    add hshow(point.lineInfo.col)
    add "@", tcGrey27.fg + tcDefault.bg
    add hshow(point.tokenIdx)

func treeRepr*(
    pnode: CstNode,
    colored: bool = true,
    pathIndexed: bool = false,
    positionIndexed: bool = true,
    maxdepth: int = 120,
    maxlen: int = 30
  ): string =

  var p = addr result
  template res(): untyped = p[]

  proc aux(n: CstNode, level: int, idx: seq[int]) =
    if pathIndexed:
      res &= idx.join("", ("[", "]")) & "    "

    elif positionIndexed:
      if level > 0:
        res &= "  ".repeat(level - 1) & "\e[38;5;240m#" & $idx[^1] & "\e[0m" &
          "\e[38;5;237m/" & alignLeft($level, 2) & "\e[0m" & " "

      else:
        res &= "    "

    else:
      res.addIndent(level)

    if level > maxdepth:
      res &= " ..."
      return
    elif isNil(n):
      res &= toRed("<nil>", colored)
      return

    with res:
      add ($n.kind)[2..^1]
      add " "
      add $n.startPoint()
      add ".."
      add $n.endPoint()

    var hadComment = false
    if n.docComment.text.len > 0:
      res.add "\n"
      for line in split(n.docComment.text, '\n'):
        res.addIndent(level + 2)
        res.add "  ## " & toYellow(line) & "\n"

      hadComment = true

    if n.nextComment.text.len > 0:
      res.add "\n"
      for line in split(n.nextComment.text, '\n'):
        res.addIndent(level + 2)
        res.add "  # " & toCyan(line) & "\n"

      hadComment = true

    if not hadComment:
      res.add " "


    case n.kind:
      of nkStringKinds: res &= "\"" & toYellow(n.getStrVal(), colored) & "\""
      of nkIntKinds: res &= toBlue($n.intVal, colored)
      of nkFloatKinds: res &= toMagenta($n.floatVal, colored)
      of nkIdent, nkSym: res &= toGreen(n.getStrVal(), colored)
      of nkCommentStmt: discard
      else:
        if n.len > 0: res &= "\n"
        for newIdx, subn in n:
          aux(subn, level + 1, idx & newIdx)
          if level + 1 > maxDepth: break
          if newIdx > maxLen: break
          if newIdx < n.len - 1: res &= "\n"

  aux(pnode, 0, @[])

initBlockFmtDsl()


proc toFmtBlock*(node: CstNode): LytBlock

proc lytDocComment(n: CstNode, prefix: string = ""): LytBlock =
  if n.docComment.text.len > 0:
    result = V[]
    for line in n.docComment.text.split('\n'):
      result.add T[prefix & "## " & line]

  else:
    result = E[]


proc lytNextComment(n: CstNode, prefix: string = ""): LytBlock =
  if n.nextComment.text.len == 0:
    return E[]

  case n.nextComment.kind:
    of ckNone:
      result = T[prefix & n.nextComment.text]

    of ckLine:
      result = T["# " & n.nextComment.text]

    of ckInline:
      result = T["#[ " & n.nextComment.text & "]#"]

    else:
      raise newImplementKindError(n.nextComment)


proc lytIdentDefs(n: CstNode): tuple[idents, itype, default: LytBlock] =

  result.idents = H[joinItBlock(bkLine, n[0 ..^ 3], toFmtBlock(it), T[", "])]

  if n[^2].kind != nkEmpty:
    result.idents.add T[": "]
    result.itype = toFmtBlock(n[^2])

  else:
    result.itype = E[]

  if n[^1].kind != nkEmpty:
    result.default = H[T[" = "], toFmtBlock(n[^1])]

  else:
    result.default = E[]



proc lytIdentList(idents: seq[CstNode]): LytBlock =
  var argBlocks = mapIt(idents, lytIdentDefs(it))
  let nameW = mapIt(argBlocks, it.idents.minWidth).sorted().getClamped(^2)
  let typeW = maxIt(argBlocks, it.itype.minWidth)

  for (idents, itype, default) in mitems(argBlocks):
    idents.add T[repeat(" ", clampIdx(nameW - idents.minWidth))]
    if not isEmpty(default):
      itype.add T[repeat(" ", clampIdx(typeW - itype.minWidth))]

  result = V[]
  for idx, (idents, itype, default) in pairs(argBlocks):
    if idx < argBlocks.high:
      result.add H[idents, itype, default, T[", "]]

    else:
      result.add H[idents, itype, default]

func isSimpleExprList(list: seq[CstNode]): bool =
  result = true
  for expr in list:
    if expr.kind notin nkTokenKinds:
      return false



proc toFmtBlock*(node: CstNode): LytBlock =
  proc aux(n: CstNode): LytBLock =
    case n.kind:
      of nkStmtList:
        result = V[]
        var lastLet: CstNode
        for sub in n:
          if sub.kind == nkLetSection:
            if isNil(lastLet):
              lastLet = sub

            else:
              lastLet.add sub[0..^1]

          else:
            if not isNil(lastLet):
              result.add aux(lastLet)
              lastLet = nil

            result.add aux(sub)

      of nkIdent:
        result = H[T[n.getStrVal()], lytNextComment(n, " ")]

      of nkIntLit:
        result = T[$n.intVal]

      of nkStrLit:
        result = T[&"\"{n.strVal}\""]

      of nkCharLit:
        var buf = "'"
        buf.addEscapedChar(n.intVal.int.char)
        buf.add '\''
        result = T[buf]

      of nkElse:
        result = V[T["else:"], I[2, aux(n[0])], S[]]

      of nkOfBranch:
        var alts = C[]
        block:
          var alt = H[]
          for idx, expr in pairs(n, 0 ..^ 2):
            if idx > 0:
              alt.add T[", "]

            alt.add aux(expr)

          alts.add alt

        if isSimpleExprList(n[0 ..^ 2]):
          alts.add joinItBlock(bkWrap, n[0..^2], aux(it), T[", "])

        result = V[H[T["of "], alts, T[":"]], I[2, aux(n[^1])], S[]]

      of nkCommand, nkCall:
        let isCall = n.kind == nkCall
        if n.kind == nkCall and
           n.len == 2 and
           n[0].kind == nkIdent and
           n[0].getStrVal() in ["inc", "dec", "echo"]:
          result = H[aux(n[0]), T[" "], aux(n[1])]


        var head = H[aux(n[0]), (T["("], T[" "]) ?? isCall]
        var body = V[]
        var commandBody = false
        for sub in items(n, 1 ..^ 1):
          if sub.kind in { nkOfBranch, nkStmtList, nkElse }:
            if not commandBody:
              head.add (T["):"], T[":"]) ?? isCall

            commandBody = true

          if commandBody:
            body.add aux(sub)

          else:
            head.add aux(sub)

        if not commandBody:
          if isCall: head.add T[")"]
          result = head

        else:
          result = V[head, I[2, body]]

      of nkInfix:
        result = H[aux(n[1]), T[" "], aux(n[0]), T[" "], aux(n[2])]

      of nkPrefix:
        result = H[aux(n[0]), aux(n[1])]

      of nkBracket:
        result = H[T["["]]
        result.addItBlock n, aux(it), T[", "]
        result.add T["]"]

      of nkPostfix:
        result = H[aux(n[1]), aux(n[0])]

      of nkPar:
        result = H[T["("]]
        result.addItBlock n, aux(it), T[", "]
        result.add T[")"]

      of nkBracketExpr:
        result = H[aux(n[0]), T["["]]
        result.addItBLock n[1..^1], aux(it), T[", "]
        result.add T["]"]


      of nkDotExpr:
        result = H[aux(n[0]), T["."], aux(n[1])]

      of nkAccQuoted:
        var txt = "`"
        for item in n:
          txt.add item.getStrVal()

        txt.add "`"

        result = T[txt]

      of nkEmpty:
        result = lytNextComment(n)

      of nkIdentDefs:
        let (idents, itype, default) = lytIdentDefs(n)
        result = H[
          idents, itype, default,
          lytDocComment(n, " "),
          lytNextComment(n, " ")
        ]

      of nkForStmt:
        var head = H[T["for "]]
        head.addItBlock(n[0 ..^ 3], aux(it), T[", "])
        head.add T[" in "]
        head.add aux(n[^2])
        result = V[H[head], I[2, aux(n[^1])]]

      of nkWhileStmt:
        result = V[
          H[T["while "], aux(n[0]), T[":"]],
          I[2, aux(n[1])]
        ]

      of nkCaseStmt:
        result = V[
          H[T["case "], aux(n[0]), T[":"]],
          I[2, joinItBlock(bkStack, n[1 ..^ 1], aux(it), S[])]
        ]


      of nkYieldStmt:
        result = H[T["yield "], aux(n[0])]

      of nkDiscardStmt:
        result = H[T["discard "], aux(n[0])]

      of nkReturnStmt:
        result = H[T["return "], aux(n[0])]

      of nkBreakStmt:
        result = H[T["break "], aux(n[0])]

      of nkCurly:
        let isSet = allIt(n, it.kind != nkExprColonExpr)

        if isSet:
          var alts: seq[LytBlock]
          block:
            var alt = H[T["{ "]]
            alt.addItBlock(n, aux(it), T[", "])
            alt.add T[" }"]
            alts.add alt

          result = C[alts]

        else:
          raise newImplementError()

      of nkVarTy:
        result = H[T["var "], aux(n[0])]

      of nkTypeSection:
        var types = V[]
        for t in n:
          types.add aux(t)
          types.add S[]

        result = V[T["type"], I[2, types]]

      of nkRecList:
        result = V[]
        for item in n:
          if item.kind != nkEmpty:
            result.add aux(item)

      of nkTypeDef:
        var body = V[]
        for field in n[2]:
          if field.kind != nkEmpty:
            body.add aux(field)

        case n[2].kind:
          of nkObjectTy:
            result = V[H[aux(n[0]), T[" = object"]], I[2, body]]

          else:
            raise newImplementKindError(n[2])

      of nkCommentStmt:
        result = lytDocComment(n)

      of nkIfStmt:
        result = V[]
        for idx, branch in n:
          if idx == 0:
            result.add V[
              H[T["if "], aux(branch[0]), T[":"]],
              I[2, aux(branch[1])],
              S[]]

          else:
            if branch.kind == nnkElifBranch:
              result.add V[
                H[T["elif "], aux(branch[0]), T[":"]],
                I[2, aux(branch[1])],
                S[]]

            else:
              result.add V[
                H[T["else:"]],
                I[2, aux(branch[0])],
                S[]]

        # result.add S[]

      of nkNilLit:
        result = T["nil"]

      of nkAsgn:
        result = H[aux(n[0]), T[" = "], aux(n[1])]

      of nkLetSection, nkVarSection:
        let word = if n.kind == nkLetSection: "let" else: "var"
        if n.len == 1:
          result = H[T[word & " "], aux(n[0])]

        else:
          result = V[T[word], I[2, V[mapIt(n, aux(it))]]]

      of nkProcDeclKinds:
        let name =
          case n.kind:
            of nkIteratorDef: "iterator "
            of nkProcDef: "proc "
            else: raise newImplementKindError(n)

        var alts: seq[LytBlock]

        block:
          var alt = H[T[name], aux(n[0]), aux(n[1]), aux(n[2]), T["("]]
          alt.addItBlock n[3][1..^1], aux(it), T[", "]
          alt.add T["): "]
          alt.add aux(n[3][0])
          alt.add T[" = "]
          alts.add alt

        block:
          var alt = V[H[T[name], aux(n[0]), aux(n[1]), aux(n[2]), T["("]]]
          alt.add I[4, lytIdentList(n[3][1..^1])]
          alt.add H[T["  ): "], aux(n[3][0]), T[" = "]]
          alts.add alt


        result = V[C[alts], I[2, aux(n[6])], S[]]


      else:
        raise newImplementKindError(n, n.treeRepr(maxdepth = 4))

    assertRef result, $n.kind

  return aux(node)

proc `$`*(node: CstNode): string =
  let blc = toFmtBlock(node)
  return blc.toString()
