## Contains helper macros for NimQml

import macros
import strutils
import sequtils
import typetraits
import tables


type
  FindQObjectTypeResult = tuple
   typeIdent: NimNode
   superTypeIdent: NimNode

  ProcInfo = object
    name: string
    returnType: string
    parametersTypes: seq[string]
    parametersNames: seq[string]

  PropertyInfo = object
    name: string
    typ: string
    read: string
    write: string
    notify: string

  QObjectInfo = object
    name: string
    superType: string
    slots: seq[ProcInfo]
    signals: seq[ProcInfo]
    properties: seq[PropertyInfo]


proc toString(info: ProcInfo): string {.compiletime.} =
  ## Convert a ProcInfo to string
  "SlotInfo {\"$1\", $2, [$3]}" % [info.name, info.returnType, info.parametersTypes.join(",")]


proc display(info: ProcInfo) {.compiletime.} =
  ## Display a ProcInfo
  echo info.toString


proc toString(info: PropertyInfo): string {.compiletime.} =
  ## Convert a PropertyInfo to string
  "PropertyInfo {\"$1\", \"$2\", \"$3\", \"$4\", \"$5\"}" % [info.name, info.typ, info.read, info.write, info.notify]


proc display(info: PropertyInfo) {.compiletime.} =
  ## Display a PropertyInfo
  echo info.toString


proc toString(info: QObjectInfo): string {.compiletime.} =
  ## Convert a QObjectInfo to string
  var slots: seq[string] = @[]
  for s in info.slots: slots.add(s.toString)
  var signals: seq[string] = @[]
  for s in info.signals: signals.add(s.toString)
  var properties: seq[string] = @[]
  for p in info.properties: properties.add(p.toString)
  "QObjectInfo {\"$1\", \"$2\", [\"$3\"], [\"$4\"], [\"$5\"]}" % [info.name, info.superType, slots.join(", "), signals.join(", "), properties.join(", ")]


proc display(info: QObjectInfo) {.compiletime.} =
  ## Display a QObjectInfo
  echo info.toString


proc toMetaType(x: string): string {.compiletime.} =
  ## Convert a nim type to QMetaType
  case x
  of nil: result = "Void"
  of "": result = "Void"
  of "void": result = "Void"
  of "int": result = "Int"
  of "bool": result = "Bool"
  of "string": result = "QString"
  of "double": result = "Double"
  of "float": result = "Float"
  of "pointer": result = "VoidStar"
  of "QVariant": result = "QVariant"
  of "QObject": result = "QObjectStar"
  else: error("Unsupported conversion of $1 to metatype" % x)
  result = "QMetaType.$1" % result


proc toMetaType(types: seq[string]): seq[string] {.compiletime.} =
  ## Convert a sequence of nim types to a sequence of QMetaTypes
  result = @[]
  for t in types:
    result.add(t.toMetaType)


proc childrenOfKind(n: NimNode, kind: NimNodeKind): seq[NimNode] {.compiletime.} =
  ## Return the sequence of child nodes of the given kind
  result = @[]
  for c in n:
    if c.kind == kind:
      result.add(c)

proc numChildrenOfKind(n: NimNode, kind: NimNodeKind): int {.compiletime.} =
  ## Return the number of child nodes of the given kind
  childrenOfKind(n, kind).len


proc getPragmas(n: NimNode): seq[string] {.compiletime.} =
  ## Return the pragmas of a node
  result = @[]
  let pragmas = n.childrenOfKind(nnkPragma)
  if pragmas.len != 1:
    return
  let pragma = pragmas[0]
  for c in pragma:
    doAssert(c.kind == nnkIdent)
    result.add($c)


proc extractQObjectTypeDef(head: NimNode): FindQObjectTypeResult {.compiletime.} =
  ## Extract the first type section and extract the first type Name and SuperType
  ## i.e. Given "type Bar = ref object of Foo" you get "Bar" and "Foo"
  let sections = head.childrenOfKind(nnkTypeSection)

  if sections.len == 0:
    error("No type section found")

  if sections.len != 1:
    error("Only one type section is supported")

  let definitions = sections[0].childrenOfKind(nnkTypeDef)

  if definitions.len == 0:
    error("No type definition found")

  if definitions.len != 1:
    error("Only ne type definition is supported")

  let def = definitions[0]

  let name = def[0] # type Object = ... <---
  let pragma = def[1] # type Object {.something.} = ... <---
  let typeKind = def[2]  # .. = ref/distinct/object ..

  if def[2].kind != nnkRefTy: # .. = ref ..
    error("ref type expected")

  if typekind[0].kind != nnkObjectTy: # .. = ref object of ...
    error("ref object expected")

  let objectType = typekind[0]
  if objectType[1].kind != nnkOfInherit:
    error("ref object with super type expected")

  let superType = objectType[1][0]

  result.typeIdent = name
  result.superTypeIdent = superType


proc extractProcInfo(n: NimNode): ProcInfo {.compiletime.} =
  ## Extract the ProcInfo for the given node
  result.name = $n[0]
  let paramsSeq = n.childrenOfKind(nnkFormalParams)
  if paramsSeq.len != 1: error("Failed to find parameters")
  let params = paramsSeq[0]
  result.returnType = repr params[0]
  result.parametersNames = @[]
  result.parametersTypes = @[]
  for def in params.childrenOfKind(nnkIdentDefs):
    result.parametersNames.add(repr def[0])
    result.parametersTypes.add(repr def[1])


proc extractPropertyInfo(node: NimNode): tuple[ok: bool, info: PropertyInfo] {.compiletime.} =
  ## Extract the PropertyInfo for a given node
  #[
  Command
      BracketExpr
        Ident !"QtProperty"
        Ident !"string"
      Ident !"name"
      StmtList
        Asgn
          Ident !"read"
          Ident !"getName"
        Asgn
          Ident !"write"
          Ident !"setName"
        Asgn
          Ident !"notify"
          Ident !"nameChanged"
  ]#
  if node.kind != nnkCommand or
     node.len != 3 or
     node[0].kind != nnkBracketExpr or
     node[1].kind != nnkIdent or
     node[2].kind != nnkStmtList:
    return
  let bracketExpr = node[0]
  if bracketExpr.len != 2 or
     bracketExpr[0].kind != nnkIdent or
     bracketExpr[1].kind != nnkIdent or
     $(bracketExpr[0]) != "QtProperty":
     return
  let stmtList = node[2]
  if stmtList.len != 3 or
     stmtList[0].kind != nnkAsgn or stmtList[0].len != 2 or
     stmtList[1].kind != nnkAsgn or stmtList[1].len != 2 or
     stmtList[2].kind != nnkAsgn or stmtList[2].len != 2 or
     stmtList[0][0].kind != nnkIdent or
     stmtList[0][1].kind != nnkIdent or
     stmtList[1][0].kind != nnkIdent or
     stmtList[1][1].kind != nnkIdent or
     stmtList[2][0].kind != nnkIdent or
     stmtList[2][1].kind != nnkIdent:
     return

  result.info.name = $(node[1])
  result.info.typ = $(bracketExpr[1])

  var
    readFound = false
    writeFound = false
    notifyFound = false

  for c in stmtList:
    let accessorType = $(c[0])
    let accessorName = $(c[1])
    if accessorType != "read" and accessorType != "write" and accessorType != "notify":
      error("Invalid property accessor. Use read, write or notify")
    if accessorType == "read" and readFound:
      error("Read slot already defined")
    if accessorType == "write" and writeFound:
      error("Write slot already defined")
    if accessorType == "notify" and notifyFound:
      error("Notify signal already defined")
    if accessorType == "read":
      readFound = true
      result.info.read = accessorName
    if accessorType == "write":
      writeFound = true
      result.info.write = accessorName
    if accessorType == "notify":
      notifyFound = true
      result.info.notify = accessorName

  result.ok = true


proc extractQObjectInfo(node: NimNode): QObjectInfo {.compiletime.} =
  ## Extract the QObjectInfo for the given node
  let (typeNode, superTypeNode) = extractQObjectTypeDef(node)
  result.name = $typeNode
  result.superType = $superTypeNode
  result.slots = @[]
  result.signals = @[]
  result.properties = @[]

  # Extract slots and signals infos
  for c in node.children:
    if c.kind != nnkProcDef and c.kind != nnkMethodDef:
      continue
    let pragmas = c.getPragmas
    # Extract slot
    if "slot" in pragmas:
      var info = extractProcInfo(c)
      if info.parametersTypes.len == 0:
        error("Slot $1 must have at least an argument" % info.name)
      if info.parametersTypes[0] != $typeNode:
        error("Slot $1 first arguments must be $2" % [info.name, $typeNode])
      info.parametersTypes.delete(0,0)
      result.slots.add(info)
    # Extract signal
    if "signal" in pragmas:
      var info = extractProcInfo(c)
      if info.parametersTypes.len == 0:
        error("Signal $1 must have at least an argument" % info.name)
      if info.parametersTypes[0] != $typeNode:
        error("Signal $1 first arguments must be $2" % [info.name, $typeNode])
      info.parametersTypes.delete(0,0)
      result.signals.add(info)

  # Extract properties infos
  for c in node.children:
    let (ok, info) = extractPropertyInfo(c)
    if not ok: continue
    result.properties.add(info)


proc generateMetaObjectSignalDefinitions(signals: seq[ProcInfo]): seq[string] {.compiletime.} =
  result = @[]
  for signal in signals:
    let args = [signal.name, signal.parametersTypes.toMetaType.join(",")]
    let def = "SignalDefinition(name: \"$1\", parametersTypes: @[$2])" % args
    let str = "  signals.add($1)" % def
    result.add(str)


proc generateMetaObjectSlotsDefinitions(slots: seq[ProcInfo]): seq[string] {.compiletime.} =
  result = @[]
  for slot in slots:
    let args = [slot.name, slot.returnType.toMetaType, slot.parametersTypes.toMetaType.join(",")]
    let def = "SlotDefinition(name: \"$1\", returnMetaType: $2, parametersTypes: @[$3])" % args
    let str = "  slots.add($1)" % def
    result.add(str)


proc generateMetaObjectPropertiesDefinitions(properties: seq[PropertyInfo]): seq[string] {.compiletime.} =
  result = @[]
  for property in properties:
    let args = [property.name, property.typ.toMetaType, property.read, property.write, property.notify]
    let def = "PropertyDefinition(name: \"$1\", propertyMetaType: $2, readSlot: \"$3\", writeSlot: \"$4\", notifySignal: \"$5\")" % args
    let str = "  properties.add($1)" % def
    result.add(str)


proc generateMetaObjectInitializer(info: QObjectInfo): NimNode {.compiletime.} =
  ## Generate the metaObject initialization procedure

  let signals = generateMetaObjectSignalDefinitions(info.signals)
  let slots = generateMetaObjectSlotsDefinitions(info.slots)
  let properties = generateMetaObjectPropertiesDefinitions(info.properties)

  var lines = @[ "proc initializeMetaObjectInstance(): QMetaObject ="
             , "  var signals: seq[SignalDefinition] = @[]"
             , "  var slots: seq[SlotDefinition] = @[]"
             , "  var properties: seq[PropertyDefinition] = @[]"]
  lines = lines.concat(signals.concat(slots.concat(properties)))
  let newStmt = "  newQMetaObject($2.staticMetaObject, \"$1\", signals, slots, properties)".format([info.name, info.superType])
  lines = lines.concat(@[newStmt])
  let str = lines.join("\n")
  result = parseStmt(str)


proc generateMetaObjectAccessors(info: QObjectInfo): NimNode {.compiletime.} =
  ## Generate the metaObject instance and accessors
  let str = [ "let staticMetaObjectInstance: QMetaObject = initializeMetaObjectInstance()"
            , "proc staticMetaObject*(c: type $1): QMetaObject = staticMetaObjectInstance"
            , "proc staticMetaObject*(self: $1): QMetaObject = staticMetaObjectInstance"
            , "method metaObject*(self: $1): QMetaObject = staticMetaObjectInstance"].join("\n")
  result = parseStmt(str % info.name)


proc generateMetaObject(info: QObjectInfo): NimNode {.compiletime.} =
  ## Generate the metaObject related procs and vars
  result = newStmtList();
  result.add(generateMetaObjectInitializer(info))
  result.add(generateMetaObjectAccessors(info))


macro slot*(s: stmt): stmt =
  ## Do nothing. Used only for tagging
  result = s


macro signal*(s: stmt): stmt {.immediate.} =
  ## Generate the signal implementation
  let info = extractProcInfo(s)
  let str = "$1.emit(\"$2\", [$3])"
  s[s.len - 1 ] = parseStmt(str % [info.parametersNames[0], info.name, ""])
  return s


macro QtObject*(body: stmt): stmt {.immediate.} =
  ## Generate the QObject stuff
  let info = extractQObjectInfo(body)
  result = newStmtList()
  result.add(body)
  result.add(generateMetaObject(info))
