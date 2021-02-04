import sugar, strutils, sequtils, strformat, options
import compiler/ast
import ../src/hnimast/[obj_field_macros, object_decl]
import ../src/hnimast
import hmisc/types/colorstring

#===========================  implementation  ============================#

#================================  tests  ================================#



import unittest

suite "Case object field iteration":
  test "{parseObject} parse at runtime":
    let instr = """
type
  U = object
    f1*: int
"""

    let obj = parseObject(parsePNodeStr(instr), parsePPragma)
    echo obj.toNNode()

  test "{toNNode}":
    let pr = newProcNType[PNode](
      @[
        newPType("int")
      ],
      newPType("void"),
      newPPragma("cdecl")
    )

    echo pr.toNNode()


  test "{makeFieldsLiteral} No case fields :macro:":
    type
      U = object
        f1: int


    let expected = @[
      ValField(
        name: "f1", fldType: newOType("int"), isKind: false,
        isTuple: false#
      )
    ]

    # echo $(ValField())
    # echo typeof U.makeFieldsLiteral()
    let generated = U.makeFieldsLiteral()
    assert generated == expected

  test "{makeFieldsLiteral} Multiple fields on the same level :macro:":
    type
      U = object
        f1: int
        f2: float
        f3: char
        f4: string

    let generated = U.makeFieldsLiteral()
    let expected = @[
      ValField(name: "f1", fldType: newOType("int"), isKind: false,
               isTuple: false),
      ValField(name: "f2", fldType: newOType("float"), isKind: false,
               isTuple: false),
      ValField(name: "f3", fldType: newOType("char"), isKind: false,
               isTuple: false),
      ValField(name: "f4", fldType: newOType("string"), isKind: false,
               isTuple: false)
    ]

    if generated != expected:
      # "/tmp/generated.nim".writeFile(pstring generated)
      # "/tmp/expected.nim".writeFile(pstring expected)
      # shell:
      #   cwdiff /tmp/expected.nim /tmp/generated.nim

      quit 1

  test "{makeFieldsLiteral} Single case field :macro:":
    type
      U = object
        case kind: bool
          of true:
            f1: int
          of false:
            f2: float

    let lhs = U.makeFieldsLiteral()
    let rhs = @[
      ValField(fldType: newOType("bool"), name: "kind", isKind: true,
               isTuple: false,
               branches: @[
        ValFieldBranch(
          ofValue: ObjTree(
            kind: okConstant, constType: "bool", strLit: "true",
            styling: initPrintStyling()
          ),
          flds: @[ ValField(
            fldType: newOType("int"),
            isKind: false,
            name: "f1",
            isTuple: false
          ) ],
          isElse: false
        ),
        ValFieldBranch(
          ofValue: ObjTree(
            kind: okConstant,
            constType: "bool",
            strLit: "false",
            styling: initPrintStyling()
          ),
          flds: @[ ValField(
            fldType: newOType("float"),
            isKind: false,
            name: "f2",
            isTuple: false,

          ) ],
          isElse: false
        ),
      ]
    )]

    if lhs != rhs:
      # echo lhs
      # echo rhs
      # "/tmp/generated.nim".writeFile(pstring lhs)
      # "/tmp/expected.nim".writeFile(pstring rhs)
      # shell:
      #   cwdiff /tmp/expected.nim /tmp/generated.nim
      raiseAssert "Fail"

  test "{makeFieldsLiteral} Multiple case fields :macro:":
    type
      U = object
        case kind1: bool
          of true: f11: int
          of false: f21: float

        case kind2: char
          of 'a':
            f12: int
          else:
            f22: float

    let generated = U.makeFieldsLiteral()
    let expected  = @[
      ValField(fldType: newOType("bool"), name: "kind1", isKind: true,
               isTuple: false,
               branches: @[
        ValFieldBranch(
          ofValue: ObjTree(
            kind: okConstant,
            constType: "bool",
            strLit: "true",
            styling: initPrintStyling()
          ),
          flds: @[ ValField(
            fldType: newOType("int"),
            isKind: false,
            name: "f11",
            isTuple: false,

          ) ],
          isElse: false
         ),
        ValFieldBranch(
          ofValue: ObjTree(
            kind: okConstant, constType: "bool",
            strLit: "false", styling: initPrintStyling()),
          flds: @[ ValField(
            fldType: newOType("float"), isKind: false, name: "f21",
            isTuple: false) ],
          isElse: false
         ),
      ]),
      ValField(fldType: newOType("char"), name: "kind2", isKind: true,
               isTuple: false, branches: @[
        ValFieldBranch(
          ofValue: ObjTree(styling: initPrintStyling(),
            kind: okConstant, constType: "char", strLit: "'a'"),
          flds: @[ ValField(fldType: newOType("int"), isKind: false,
                            name: "f12", isTuple: false) ],
          isElse: false
        ),
        ValFieldBranch(
          notOfValue: ObjTree(styling: initPrintStyling(),),
          flds: @[ ValField(fldType: newOType("float"), isKind: false,
                            name: "f22", isTuple: false) ],
          isElse: true
        ),
      ])
    ]


    if generated != expected:
      # raiseAssert "Fail"
      # "/tmp/generated.nim".writeFile(pstring generated)
      # "/tmp/expected.nim".writeFile(pstring expected)
      # shell:
      #   cwdiff /tmp/expected.nim /tmp/generated.nim
      quit 1

  test "{makeFieldsLiteral} Nested case fields :macro:":
    type
      U = object
        case kind1: bool
          of true: f11: int
          of false:
            case kind2: char
              of 'a':
                f12: int
              else:
                f22: float

    let generated = U.makeFieldsLiteral()
    let expected = @[
      ValField(fldType: newOType("bool"), name: "kind1", isKind: true,
               isTuple: false, branches: @[
        ValFieldBranch(
          ofValue: ObjTree(styling: initPrintStyling(),
            kind: okConstant, constType: "bool", strLit: "true"),
          flds: @[ ValField(fldType: newOType("int"), isKind: false,
                            name: "f11", isTuple: false) ],
          isElse: false
         ),
        ValFieldBranch(
          ofValue: ObjTree(styling: initPrintStyling(),
            kind: okConstant, constType: "bool", strLit: "false"),
          flds: @[
            ValField(
              fldType: newOType("char"), name: "kind2", isKind: true,
              isTuple: false, branches: @[
              ValFieldBranch(
                ofValue: ObjTree(styling: initPrintStyling(),
                  kind: okConstant, constType: "char", strLit: "'a'"),
                flds: @[ ValField(
                  fldType: newOType("int"), isKind: false, name: "f12",
                  isTuple: false) ],
                isElse: false
              ),
              ValFieldBranch(
                notOfValue: ObjTree(styling: initPrintStyling(),),
                flds: @[ ValField(
                  fldType: newOType("float"), isKind: false,
                  name: "f22", isTuple: false) ],
                isElse: true
              ),
            ])
          ],
         isElse: false
         ),
      ]),
    ]

    if generated != expected:
      raiseAssert "Fail"

  test "{makeFieldsLiteral} Get fields inside of generic proc :macro:":
    proc generic[T](a: T): void =
      let generated = T.makeFieldsLiteral()
      let expected = @[
        ValField(name: "f1", fldType: newOType("int"),
                 isKind: false, isTuple: false),
        ValField(name: "f2", fldType: newOType("char"),
                 isKind: false, isTuple: false)
      ]

      if generated != expected:
        # "/tmp/generated.nim".writeFile(pstring generated)
        # "/tmp/expected.nim".writeFile(pstring expected)
        raiseAssert "Fail"


    type
      U = object
        f1: int
        f2: char

    generic(U())


  test "{makeFieldsLiteral} Get all kind fields :macro:":
    type
      U = object
        case kind1: bool
          of true: f11: int
          of false:
            case kind2: char
              of 'a':
                f12: int
              else:
                f22: float

        case kind3: bool
          of true:
            f31: float
          of false:
            f32: seq[seq[seq[seq[seq[set[char]]]]]]


    let generated = makeFieldsLiteral(U).getKindFields()
    let expected = @[
      ValField(
        name: "kind1", fldType: newOType("bool"), isKind: true,
        isTuple: false, branches: @[
          ValFieldBranch(
            isElse: false,
            ofValue: ObjTree(styling: initPrintStyling(),
              kind: okConstant, constType: "bool", strLit: "false"),
            flds: @[
              ValField( name: "kind2", fldType: newOType("char"),
                       isKind: true, isTuple: false)
            ]
          )
        ]
      ),
      ValField( name: "kind3", fldType: newOType("bool"), isKind: true, isTuple: false)
    ]

    if generated != expected:
      # "/tmp/generated.nim".writeFile(pstring generated)
      # "/tmp/expected.nim".writeFile(pstring expected)
      # shell:
      #   cwdiff /tmp/expected.nim /tmp/generated.nim

      quit 1


  type
    UTop = object
      case kind: bool
        of true:
          f1: char
        of false:
          f2: string

      f3: int

  template checkDeclaredFields(fldName): untyped =
    if fldName == "kind":
      assert (lhs is bool) and (rhs is bool)
      assert isKind
    elif fldName == "f1":
      assert (lhs is char) and (rhs is char)
      assert not isKind
    elif (fldName == "f2") or (fldName == "f3"):
      discard
    else:
      fail()

  test "{parallelFieldPairs} from object constructor :macro:":
    parallelFieldPairs(
      UTop(kind: true, f1: '1'),
      UTop(kind: true, f1: '1')
    ):
      checkDeclaredFields(name)

  test "{parallelFieldPairs} from variable :macro:":
    let v1 = UTop()
    let v2 = UTop()
    parallelFieldPairs(v1, v2):
      checkDeclaredFields(name)

  test "{parallelFieldPairs} inside generic function :macro:generic:":
    var found = (kind: false, f2: false, f3: false)
    when false: # FIXME for some reason shit stopped working - `name` is
                # correctly injected into the scope, but is not recognized
                # for overload resolution (instead it tries to use
                # `std/macros/name()` for `NimNode`)
      proc generic[T](lhsIn, rhsIn: T): void =
        parallelFieldPairs(lhsIn, rhsIn):
          checkDeclaredFields(name)

          if name == "kind":
            found.kind = true
          elif name == "f2":
            found.f2 = true
          elif name == "f3":
            found.f3 = true

      generic(UTop(), UTop())
      assert found.kind
      assert found.f2
      assert found.f3

  test "{parallelFieldPairs} iterate field/call :macro:":
    block:
      proc makeObj(): UTop =
        discard

      parallelFieldPairs(makeObj(), makeObj()):
        assert lhsObj is UTop
        checkDeclaredFields(name)

    block:
      let val = (f: UTop())

      parallelFieldPairs(val.f, val.f):
        assert lhsObj is UTop
        checkDeclaredFields(name)

import private

suite "Parallel field pairs":
  test "{parallelFieldPairs} field indexing :macro:":
    type
      Case = object
        f1: int                # fldIdx - `0`, valIdx - `0`
        case kind: bool        # fldIdx - `1`, valIdx - `1`
          of true: f2: float   # fldIdx - `2`, valIdx - `2`
          of false: f3: string # fldIdx - `3`, valIdx - `2`

          # Fields `f2` and `f3` have the same `valIdx` because they
          # are located in different branches and cannot be accessed
          # simotaneously.

    let v = Case(kind: false, f3: "Hello")
    parallelFieldPairs(v, v):
      if name == "f3":
        assert fldIdx == 3
        assert valIdx == 2
    # echo 1

  test "{parallelFieldPairs} generic ref object":
    type
      RefT[G] = ref object
        fld: G

    let t = RefT[int](fld: 12)
    let y = RefT[int](fld: 12)
    parallelFieldPairs(t, y):
      discard

  test "{parallelFieldPairs} crazy generic shit":

    type
      Token[Category, Lexeme, Info] = object
        cat*: Category
        lex*: Lexeme
        info*: Info

      ParseTreeKind = enum
        ptkToken
        ptkNterm
        ptkList

      ParseTree[C, L, I] = ref object
        start*: int
        finish*: int

        case kind*: ParseTreeKind
          of ptkToken:
            tok*: Token[C, L, I]
          of ptkNTerm:
            subnodes*: seq[ParseTree[C, L, I]]
          of ptkList:
            elements*: seq[ParseTree[C, L, I]]

    let t = ParseTree[int, string, void]()
    let y = ParseTree[int, string, void]()
    parallelFieldPairs(t, y):
      if name == "finish":
        assert not isKind

  test "{hackParallelFieldPairs} access private fields":

    block:
      let a = Private(kind: true)
      let b = Private(kind: false)

      hackPrivateParallelFieldPairs(a, b):
        discard

    block:
      let a = Private()
      let b = Private()

      hackPrivateParallelFieldPairs(a, b):
        discard
