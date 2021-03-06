#
#
#            Nimrod's Runtime Library
#        (c) Copyright 2011 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#


## Nimrod's standard IO library. It contains high-performance
## routines for reading and writing data to (buffered) files or
## TTYs.

{.push debugger:off .} # the user does not want to trace a part
                       # of the standard library!


proc fputs(c: cstring, f: TFile) {.importc: "fputs", noDecl.}
proc fgets(c: cstring, n: int, f: TFile): cstring {.importc: "fgets", noDecl.}
proc fgetc(stream: TFile): cint {.importc: "fgetc", nodecl.}
proc ungetc(c: cint, f: TFile) {.importc: "ungetc", nodecl.}
proc putc(c: Char, stream: TFile) {.importc: "putc", nodecl.}
proc fprintf(f: TFile, frmt: CString) {.importc: "fprintf", nodecl, varargs.}
proc strlen(c: cstring): int {.importc: "strlen", nodecl.}

proc setvbuf(stream: TFile, buf: pointer, typ, size: cint): cint {.
  importc, nodecl.}

proc freopen(path, mode: cstring, stream: TFile): TFile {.importc: "freopen",
  nodecl.}

proc write(f: TFile, c: cstring) = fputs(c, f)

var
  IOFBF {.importc: "_IOFBF", nodecl.}: cint
  IONBF {.importc: "_IONBF", nodecl.}: cint

proc raiseEIO(msg: string) {.noinline, noreturn.} =
  raise newException(EIO, msg)

proc rawReadLine(f: TFile, result: var string) =
  # of course this could be optimized a bit; but IO is slow anyway...
  # and it was difficult to get this CORRECT with Ansi C's methods
  setLen(result, 0) # reuse the buffer!
  while True:
    var c = fgetc(f)
    if c < 0'i32:
      if result.len > 0: break
      else: raiseEIO("EOF reached")
    if c == 10'i32: break # LF
    if c == 13'i32:  # CR
      c = fgetc(f) # is the next char LF?
      if c != 10'i32: ungetc(c, f) # no, put the character back
      break
    add result, chr(int(c))

proc readLine(f: TFile): TaintedString =
  when taintMode:
    result = TaintedString""
    rawReadLine(f, result.string)
  else:
    result = ""
    rawReadLine(f, result)

proc write(f: TFile, i: int) = 
  when sizeof(int) == 8:
    fprintf(f, "%lld", i)
  else:
    fprintf(f, "%ld", i)

proc write(f: TFile, i: biggestInt) = 
  when sizeof(biggestint) == 8:
    fprintf(f, "%lld", i)
  else:
    fprintf(f, "%ld", i)
    
proc write(f: TFile, b: bool) =
  if b: write(f, "true")
  else: write(f, "false")
proc write(f: TFile, r: float) = fprintf(f, "%g", r)
proc write(f: TFile, r: biggestFloat) = fprintf(f, "%g", r)

proc write(f: TFile, c: Char) = putc(c, f)
proc write(f: TFile, a: openArray[string]) =
  for x in items(a): write(f, x)

proc readFile(filename: string): TaintedString =
  var f = open(filename)
  try:
    var len = getFileSize(f)
    if len < high(int):
      when taintMode:
        result = newString(int(len)).TaintedString
        if readBuffer(f, addr(string(result)[0]), int(len)) != len:
          raiseEIO("error while reading from file")
      else:
        result = newString(int(len))
        if readBuffer(f, addr(result[0]), int(len)) != len:
          raiseEIO("error while reading from file")
    else:
      raiseEIO("file too big to fit in memory")
  finally:
    close(f)

proc writeFile(filename, content: string) =
  var f = open(filename, fmWrite)
  try:
    f.write(content)
  finally:
    close(f)

proc EndOfFile(f: TFile): bool =
  # do not blame me; blame the ANSI C standard this is so brain-damaged
  var c = fgetc(f)
  ungetc(c, f)
  return c < 0'i32

proc writeln[Ty](f: TFile, x: Ty) =
  write(f, x)
  write(f, "\n")

proc writeln[Ty](f: TFile, x: openArray[Ty]) =
  for i in items(x): write(f, i)
  write(f, "\n")

proc rawEcho(x: string) {.inline, compilerproc.} = write(stdout, x)
proc rawEchoNL() {.inline, compilerproc.} = write(stdout, "\n")

# interface to the C procs:
proc fopen(filename, mode: CString): pointer {.importc: "fopen", noDecl.}

const
  FormatOpen: array [TFileMode, string] = ["rb", "wb", "w+b", "r+b", "ab"]
    #"rt", "wt", "w+t", "r+t", "at"
    # we always use binary here as for Nimrod the OS line ending
    # should not be translated.


proc Open(f: var TFile, filename: string,
          mode: TFileMode = fmRead,
          bufSize: int = -1): Bool =
  var p: pointer = fopen(filename, FormatOpen[mode])
  result = (p != nil)
  f = cast[TFile](p)
  if bufSize > 0:
    if setvbuf(f, nil, IOFBF, bufSize) != 0'i32:
      raise newException(EOutOfMemory, "out of memory")
  elif bufSize == 0:
    discard setvbuf(f, nil, IONBF, 0)

proc reopen(f: TFile, filename: string, mode: TFileMode = fmRead): bool = 
  var p: pointer = freopen(filename, FormatOpen[mode], f)
  result = p != nil

proc fdopen(filehandle: TFileHandle, mode: cstring): TFile {.
  importc: pccHack & "fdopen", header: "<stdio.h>".}

proc open(f: var TFile, filehandle: TFileHandle, mode: TFileMode): bool =
  f = fdopen(filehandle, FormatOpen[mode])
  result = f != nil

# C routine that is used here:
proc fread(buf: Pointer, size, n: int, f: TFile): int {.
  importc: "fread", noDecl.}
proc fseek(f: TFile, offset: clong, whence: int): int {.
  importc: "fseek", noDecl.}
proc ftell(f: TFile): int {.importc: "ftell", noDecl.}

proc fwrite(buf: Pointer, size, n: int, f: TFile): int {.
  importc: "fwrite", noDecl.}

proc readBuffer(f: TFile, buffer: pointer, len: int): int =
  result = fread(buffer, 1, len, f)

proc ReadBytes(f: TFile, a: var openarray[byte], start, len: int): int =
  result = readBuffer(f, addr(a[start]), len)

proc ReadChars(f: TFile, a: var openarray[char], start, len: int): int =
  result = readBuffer(f, addr(a[start]), len)

proc writeBytes(f: TFile, a: openarray[byte], start, len: int): int =
  var x = cast[ptr array[0..1000_000_000, byte]](a)
  result = writeBuffer(f, addr(x[start]), len)
proc writeChars(f: TFile, a: openarray[char], start, len: int): int =
  var x = cast[ptr array[0..1000_000_000, byte]](a)
  result = writeBuffer(f, addr(x[start]), len)
proc writeBuffer(f: TFile, buffer: pointer, len: int): int =
  result = fwrite(buffer, 1, len, f)

proc write(f: TFile, s: string) =
  if writeBuffer(f, cstring(s), s.len) != s.len:
    raiseEIO("cannot write string to file")

proc setFilePos(f: TFile, pos: int64) =
  if fseek(f, clong(pos), 0) != 0:
    raiseEIO("cannot set file position")

proc getFilePos(f: TFile): int64 =
  result = ftell(f)
  if result < 0: raiseEIO("cannot retrieve file position")

proc getFileSize(f: TFile): int64 =
  var oldPos = getFilePos(f)
  discard fseek(f, 0, 2) # seek the end of the file
  result = getFilePos(f)
  setFilePos(f, oldPos)

{.pop.}
