unit PasUnitInterfaceCleaner;

interface

uses
  System.SysUtils,
  System.Character,
  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.StrUtils,
  autoFree;

type
  TTokenType = (
    ttUnknown,
    ttWhitespace,
    ttCode,
    ttStringLiteral,
    ttLineComment,
    ttBlockComment,
    ttCompilerDirective,
    ttKeywordUnit,
    ttKeywordInterface,
    ttKeywordImplementation,
    ttKeywordClass,
    ttKeywordRecord,
    ttKeywordEnd,
    ttKeywordPrivate,
    ttKeywordStrictPrivate,
    ttKeywordProtected,
    ttKeywordPublic,
    ttKeywordPublished
  );

  TToken = record
    StartIndex: Integer;
    Length: Integer;
    TokenType: TTokenType;
    constructor Create(aStart, aLen: Integer; aType: TTokenType);
    function GetText(const aSource: string): string;
  end;

  TInterfaceSectionCleaner = class
  private
    fBoilerplateKeywords: TArray<string>;
    function IsBoilerplate(const aHeaderText: string): Boolean;
    function Tokenize(const aSource: string): TArray<TToken>;
    function AnalyzeAndBuild(const aSource: string; const aTokens: TArray<TToken>): string;
    function RemoveRedundantPropertyReexposures(
  const aSource: string): String;
    function RemoveCompatibilityShims(const aSource: string): string;
    function RemoveAliasConstants(const aSource: string): string;
    function CompressEnumDeclarations(const aSource: string): string;
    function RemoveDispInterfaces(const aSource: string): string;
    function RemovePropertyStorageHints(const aSource: string): string;
    function NormalizeWhitespace(const aSource: string): string;
  public
    constructor Create;
    function Process(const aSource: string): string;
  end;

implementation

type
  TClassState = (csKeeping, csDiscarding);
  TParserState = (psRoot, psInClass);

{ TToken }

constructor TToken.Create(aStart, aLen: Integer; aType: TTokenType);
begin
  StartIndex := aStart;
  Length     := aLen;
  TokenType  := aType;
end;

function TToken.GetText(const aSource: string): string;
begin
  Result := Copy(aSource, StartIndex, Length);
end;

{ TInterfaceSectionCleaner }

constructor TInterfaceSectionCleaner.Create;
begin
  inherited;
  fBoilerplateKeywords := [
    'license', 'copyright', 'author', 'created', 'modified',
    'all rights reserved', 'codegear', 'borland', 'embarcadero'
  ];
end;

function TInterfaceSectionCleaner.IsBoilerplate(const aHeaderText: string): Boolean;
var
  lKeyword: string;
  lUpper: string;
begin
  Result := False;
  lUpper := aHeaderText.ToUpper;
  for lKeyword in fBoilerplateKeywords do
    if lUpper.Contains(lKeyword.ToUpper) then
      Exit(True);
end;

function TInterfaceSectionCleaner.Tokenize(const aSource: string): TArray<TToken>;
var
  lTokens: TList<TToken>;
  lIdx: Integer;
  lStart: Integer;
  lNest: Integer;
  c: Char;
  c2: Char;

  function IsBreak(const aCh: Char): Boolean; inline;
  begin
    Result := TCharacter.IsWhiteSpace(aCh) or (aCh in
      ['{', '''', '(', ')', ';', ':', ',', '[', ']']);
  end;

begin
  gc(lTokens, TList<TToken>.Create);
  lIdx := 1;

  while lIdx <= Length(aSource) do
  begin
    lStart := lIdx;
    c      := aSource[lIdx];

    // 1. Whitespace ----------------------------------------------------------
    if TCharacter.IsWhiteSpace(c) then
    begin
      repeat
        Inc(lIdx);
      until (lIdx > Length(aSource)) or
            not TCharacter.IsWhiteSpace(aSource[lIdx]);
      lTokens.Add(TToken.Create(lStart, lIdx - lStart, ttWhitespace));
    end
    // 2. Line Comment // -----------------------------------------------------
    else if (c = '/') and (lIdx < Length(aSource)) and
            (aSource[lIdx + 1] = '/') then
    begin
      Inc(lIdx, 2);
      while (lIdx <= Length(aSource)) and
            not (aSource[lIdx] in [#10, #13]) do
        Inc(lIdx);
      lTokens.Add(TToken.Create(lStart, lIdx - lStart, ttLineComment));
    end
    // 3. Block Comment { … } / {$ … } ---------------------------------------
    else if c = '{' then
    begin
      if (lIdx < Length(aSource)) and (aSource[lIdx + 1] = '$') then
      begin
        lIdx := aSource.IndexOf('}', lIdx) + 1;
        if lIdx = 0 then
          lIdx := Length(aSource) + 1;
        lTokens.Add(TToken.Create(lStart, lIdx - lStart, ttCompilerDirective));
      end else
      begin
        Inc(lIdx);
        lNest := 1;
        while (lIdx <= Length(aSource)) and (lNest > 0) do
        begin
          case aSource[lIdx] of
            '{': Inc(lNest);
            '}': Dec(lNest);
          end;
          Inc(lIdx);
        end;
        lTokens.Add(TToken.Create(lStart, lIdx - lStart, ttBlockComment));
      end;
    end
    // 4. Block Comment (* … *) / (*$ … *) -----------------------------------
    else if (c = '(') and (lIdx < Length(aSource)) and
            (aSource[lIdx + 1] = '*') then
    begin
      if (lIdx + 2 < Length(aSource)) and (aSource[lIdx + 2] = '$') then
      begin
        lIdx := aSource.IndexOf('*)', lIdx) + 2;
        if lIdx = 1 then
          lIdx := Length(aSource) + 1;
        lTokens.Add(TToken.Create(lStart, lIdx - lStart, ttCompilerDirective));
      end else
      begin
        Inc(lIdx, 2);
        lNest := 1;
        while (lIdx <= Length(aSource)) and (lNest > 0) do
        begin
          if (aSource[lIdx] = '(') and (aSource[lIdx + 1] = '*') then
          begin
            Inc(lNest);
            Inc(lIdx, 2);
          end
          else if (aSource[lIdx] = '*') and (aSource[lIdx + 1] = ')') then
          begin
            Dec(lNest);
            Inc(lIdx, 2);
          end
          else
            Inc(lIdx);
        end;
        lTokens.Add(TToken.Create(lStart, lIdx - lStart, ttBlockComment));
      end;
    end
    // 5. String Literal ------------------------------------------------------
    else if c = '''' then
    begin
      repeat
        Inc(lIdx);
        if (lIdx <= Length(aSource)) and (aSource[lIdx] = '''') and
           (lIdx < Length(aSource))  and (aSource[lIdx + 1] = '''') then
          Inc(lIdx); // handle doubled quotes
      until (lIdx > Length(aSource)) or (aSource[lIdx] = '''');
      Inc(lIdx);
      lTokens.Add(TToken.Create(lStart, lIdx - lStart, ttStringLiteral));
    end
    // 6. Code / Identifier / Punctuation ------------------------------------
    else
    begin
      // --- fast-path punctuation (prevents zero-length tokens / endless loop)
      if aSource[lIdx] in ['(', ')', ';', ':', ',', '[', ']', '.'] then
      begin
        Inc(lIdx); // ensure progress
        lTokens.Add(TToken.Create(lStart, 1, ttCode));
        Continue;  // process next char
      end;

      while (lIdx <= Length(aSource)) do
      begin
        c2 := aSource[lIdx];
        if IsBreak(c2) then Break;
        if (c2 = '/') and (lIdx < Length(aSource)) and
           (aSource[lIdx + 1] = '/') then Break;
        if (c2 = '(') and (lIdx < Length(aSource)) and
           (aSource[lIdx + 1] = '*') then Break;
        Inc(lIdx);
      end;

      var lTextLower := aSource.Substring(lStart - 1, lIdx - lStart).ToLowerInvariant;
      var lTok := TToken.Create(lStart, lIdx - lStart, ttCode);

      if      lTextLower.StartsWith('unit')           then lTok.TokenType := ttKeywordUnit
      else if lTextLower.StartsWith('interface')      then lTok.TokenType := ttKeywordInterface
      else if lTextLower.StartsWith('implementation') then lTok.TokenType := ttKeywordImplementation
      else if lTextLower.StartsWith('class')          then lTok.TokenType := ttKeywordClass
      else if lTextLower.StartsWith('record')         then lTok.TokenType := ttKeywordRecord
      else if lTextLower.StartsWith('end')            then lTok.TokenType := ttKeywordEnd
      else if lTextLower.StartsWith('private')        then lTok.TokenType := ttKeywordPrivate
      else if lTextLower.StartsWith('protected')      then lTok.TokenType := ttKeywordProtected
      else if lTextLower.StartsWith('public')         then lTok.TokenType := ttKeywordPublic
      else if lTextLower.StartsWith('published')      then lTok.TokenType := ttKeywordPublished
      else if lTextLower.StartsWith('strict') then
      begin
        var lWs := lIdx;
        while (lWs <= Length(aSource)) and
              TCharacter.IsWhiteSpace(aSource[lWs]) do
          Inc(lWs);
        if (lWs + 6 <= Length(aSource)) and
           (CompareText(aSource.Substring(lWs, 7), 'private') = 0) then
        begin
          lIdx := lWs + 7;
          lTok := TToken.Create(lStart, lIdx - lStart, ttKeywordStrictPrivate);
        end;
      end;

      lTokens.Add(lTok);
    end;
  end;

  Result := lTokens.ToArray;
end;

function TInterfaceSectionCleaner.AnalyzeAndBuild(
  const aSource: string; const aTokens: TArray<TToken>): string;
var
  lI, lJ: Integer;
  lUnitIdx, lIntfIdx, lImplIdx: Integer;
  lUnitEnd: Integer;
  lSB: TStringBuilder;
  lState: TParserState;
  lTok: TToken;
  lStack: TStack<TClassState>;
begin
  lUnitIdx := -1;
  lIntfIdx := -1;
  lImplIdx := -1;

  for lI := 0 to High(aTokens) do
    case aTokens[lI].TokenType of
      ttKeywordUnit:            if lUnitIdx = -1 then lUnitIdx := lI;
      ttKeywordInterface:       if lIntfIdx = -1 then lIntfIdx := lI;
      ttKeywordImplementation:  if lImplIdx = -1 then lImplIdx := lI;
    end;

  if lIntfIdx = -1 then Exit(aSource);

  if lImplIdx = -1 then lImplIdx := High(aTokens) + 1;
  if lUnitIdx = -1 then lUnitIdx := 0;

  gc(lSB, TStringBuilder.Create);

  // copy unit header ---------------------------------------------------------
  lUnitEnd := lUnitIdx;
  for lI := lUnitIdx to lIntfIdx - 1 do
    if (aTokens[lI].TokenType = ttCode) and
       (aTokens[lI].GetText(aSource) = ';') then
    begin
      lUnitEnd := lI;
      Break;
    end;

  lSB.Append(aSource.Substring(
    aTokens[lUnitIdx].StartIndex - 1,
    (aTokens[lUnitEnd].StartIndex + aTokens[lUnitEnd].Length) -
    aTokens[lUnitIdx].StartIndex));

  // optional comment block ---------------------------------------------------
  var lHdrStart := lUnitEnd + 1;
  var lFirstCmt := -1;
  var lHdrTxt: TStringBuilder;
  gc(lHdrTxt, TStringBuilder.Create);

  for lI := lIntfIdx - 1 downto lHdrStart do
  begin
    lTok := aTokens[lI];
    if lTok.TokenType = ttWhitespace then Continue;

    if lTok.TokenType in [ttLineComment, ttBlockComment] then
    begin
      lFirstCmt := lI;
      for lJ := lI downto lHdrStart do
      begin
        var lPrev := aTokens[lJ];
        if lPrev.TokenType in [ttWhitespace, ttLineComment, ttBlockComment] then
        begin
          lFirstCmt := lJ;
          lHdrTxt.Insert(0, lPrev.GetText(aSource));
        end
        else Break;
      end;
      Break;
    end
    else Break;
  end;

  if lFirstCmt <> -1 then
  begin
    if IsBoilerplate(lHdrTxt.ToString) then
      for lI := lHdrStart to lFirstCmt - 1 do
        lSB.Append(aTokens[lI].GetText(aSource))
    else
      for lI := lHdrStart to lIntfIdx - 1 do
        lSB.Append(aTokens[lI].GetText(aSource));
  end
  else
    for lI := lHdrStart to lIntfIdx - 1 do
      lSB.Append(aTokens[lI].GetText(aSource));

  // interface parsing --------------------------------------------------------
  gc(lStack, TStack<TClassState>.Create);
  lState := psRoot;

  for lI := lIntfIdx to lImplIdx - 1 do
  begin
    lTok := aTokens[lI];
    var lEmit := True;

    case lState of
      psRoot:
      begin
        if lTok.TokenType in [ttKeywordClass, ttKeywordRecord] then
        begin
          lStack.Push(csKeeping);
          lState := psInClass;
        end;
      end;

      psInClass:
      begin
        var lMode := csKeeping;
        if lStack.Count > 0 then
          lMode := lStack.Peek;

        case lTok.TokenType of
          ttKeywordPrivate, ttKeywordStrictPrivate:
          begin
            lStack.Pop;
            lStack.Push(csDiscarding);
            lEmit := False;
          end;

          ttKeywordProtected, ttKeywordPublic, ttKeywordPublished:
          begin
            lStack.Pop;
            lStack.Push(csKeeping);
          end;

          ttKeywordClass, ttKeywordRecord:
            lStack.Push(lMode);

          ttKeywordEnd:
          begin
            lStack.Pop;
            if lStack.Count = 0 then
              lState := psRoot;
          end;
        end;

        if not (lTok.TokenType in
          [ttKeywordPrivate, ttKeywordStrictPrivate,
           ttKeywordProtected, ttKeywordPublic, ttKeywordPublished]) then
          lEmit := lEmit and ( (lStack.Count = 0) or (lStack.Peek = csKeeping) );
      end;
    end;

    if lEmit then
      lSB.Append(lTok.GetText(aSource));
  end;

  // trailing whitespace + implementation ------------------------------------
  var lTrim := lSB.Length;
  while (lTrim > 0) and TCharacter.IsWhiteSpace(lSB[lTrim - 1]) do
    Dec(lTrim);
  lSB.Length := lTrim;

  if lImplIdx <= High(aTokens) then
  begin
    lSB.AppendLine;
    lSB.AppendLine;
    lSB.Append('implementation');
  end;

  Result := lSB.ToString;
end;

function TInterfaceSectionCleaner.Process(const aSource: string): string;
var
  lToks: TArray<TToken>;
begin
  if aSource.IsEmpty then
    Exit('');

  lToks  := Tokenize(aSource);
  Result := AnalyzeAndBuild(aSource, lToks);
  Result := RemoveRedundantPropertyReexposures(Result); // <-- new line
  Result := RemoveCompatibilityShims(Result);           // <-- step 2
  Result := RemoveAliasConstants(Result);               // pass #3  <-- new line
  Result := CompressEnumDeclarations(Result);           // pass #4  <-- new
  Result := RemoveDispInterfaces(Result);               // pass 5  <-- new line
  Result := RemovePropertyStorageHints(Result);         // pass 6  <-- NEW
  Result := NormalizeWhitespace(Result);                // pass 7  <-- NEW
end;


/// <summary>
/// *  trims trailing spaces/tabs,
/// *  collapses runs of 2+ blank lines into one,
/// *  reduces any leading indentation to a single space
///    (if the line originally had *any* leading whitespace).
/// </summary>
function TInterfaceSectionCleaner.NormalizeWhitespace(
  const aSource: string): string;
var
  lLines : TStringList;
  lOut   : TStringBuilder;
  i      : Integer;
  lLine  : string;
  lTrimR : string;
  lPrevBlank: Boolean;
begin
  gc(lLines, TStringList.Create);
  lLines.LineBreak := sLineBreak;
  lLines.Text := aSource;

  gc(lOut, TStringBuilder.Create(aSource.Length));

  lPrevBlank := False;

  for i := 0 to lLines.Count - 1 do
  begin
    lLine  := lLines[i];
    lTrimR := TrimRight(lLine);                      // strip trailing ws

    if Trim(lTrimR) = '' then                   // blank after trim
    begin
      if not lPrevBlank then
      begin
        lOut.AppendLine;                        // keep a single blank
        lPrevBlank := True;
      end;
      Continue;
    end;

    // non-blank line ---------------------------------------------------------
    lPrevBlank := False;

    // compress indentation to a single space (if any existed)
    var lCore := lTrimR.TrimLeft;
    if lCore.Length < lTrimR.Length then
      lOut.Append(' ').AppendLine(lCore)
    else
      lOut.AppendLine(lCore);
  end;

  Result := lOut.ToString;
end;


/// <summary>
/// Deletes “default …”, “stored …”, and “nodefault” tokens from property
/// declarations – e.g.
///
///   property Enabled: Boolean read GetEnabled write SetEnabled default True;
///   property Controls: TMyCtl read FCtl stored False;
///   property Size: Integer read FSize nodefault;
///
/// all collapse to
///
///   property Enabled: Boolean read GetEnabled write SetEnabled;
///   property Controls: TMyCtl read FCtl;
///   property Size: Integer read FSize;
/// </summary>
function TInterfaceSectionCleaner.RemovePropertyStorageHints(
  const aSource: string): string;

  function PosTextInsensitive(const aSub, aText: string; aOffset: Integer = 1): Integer;
  begin
    Result := PosEx(LowerCase(aSub), LowerCase(aText), aOffset);
  end;

  // strips one hint type (“default ”, “stored ”, “nodefault”) from a single line
  procedure StripHint(var aLine: string; const aHint: string);
  var
    p, semi: Integer;
  begin
    repeat
      p := PosTextInsensitive(aHint, aLine);
      if p = 0 then
        Exit;

      semi := PosEx(';', aLine, p + Length(aHint));
      if semi = 0 then
        semi := Length(aLine) + 1;

      Delete(aLine, p, semi - p);
    until False;
  end;

var
  lLines: TStringList;
  lOut  : TStringBuilder;
  i     : Integer;
  lLine : string;
begin
  gc(lLines, TStringList.Create);
  lLines.LineBreak := sLineBreak;
  lLines.Text := aSource;

  gc(lOut, TStringBuilder.Create(aSource.Length));

  for i := 0 to lLines.Count - 1 do
  begin
    lLine := lLines[i];

    if lLine.TrimLeft.StartsWith('property', True) then
    begin
      StripHint(lLine, 'default ');
      StripHint(lLine, 'stored ');
      StripHint(lLine, 'nodefault');
    end;

    lOut.AppendLine(lLine);
  end;

  Result := lOut.ToString;
end;


/// <summary>
/// Removes auto-generated COM dispinterface stubs:
///   IMyFooDisp = dispinterface
///   ['{GUID}']
///   procedure Bar; safecall;
///   end;
///
/// Everything from the line that contains “dispinterface” through the matching
/// “end;” (or bare “end”) is discarded.
/// </summary>
function TInterfaceSectionCleaner.RemoveDispInterfaces(
  const aSource: string): string;
var
  lLines : TStringList;
  lOut   : TStringBuilder;
  i      : Integer;
  lTrim  : string;
  lSkip  : Boolean;
begin
  gc(lLines, TStringList.Create);
  lLines.LineBreak := sLineBreak;
  lLines.Text := aSource;

  gc(lOut, TStringBuilder.Create(aSource.Length));

  lSkip := False;

  for i := 0 to lLines.Count - 1 do
  begin
    lTrim := lLines[i].TrimLeft.ToLower;

    if not lSkip then
    begin
      // Start skipping when we meet “= dispinterface”
      if (lTrim.Contains('dispinterface')) and (lTrim.Contains('=')) then
      begin
        lSkip := True;
        Continue;                        // drop this trigger line
      end;
    end
    else
    begin
      // Inside a dispinterface block ­– look for terminator
      if lTrim.StartsWith('end') then
      begin
        lSkip := False;                 // do NOT output the “end;” line
        Continue;
      end
      else
        Continue;                       // swallow interior lines
    end;

    // Normal line
    lOut.AppendLine(lLines[i]);
  end;

  Result := lOut.ToString;
end;


/// <summary>
/// Flattens multi-line enum declarations to a single line:
///
///   TMyEnum = (
///     eOne,
///     eTwo,
///     eThree
///   );
///
/// becomes
///
///   TMyEnum = (eOne, eTwo, eThree);
/// </summary>
function TInterfaceSectionCleaner.CompressEnumDeclarations(
  const aSource: string): string;
var
  lLines     : TStringList;
  lEnumItems : TStringList;
  lOut       : TStringBuilder;
  i          : Integer;
  lLine      : string;
  lTrim      : string;
  lInEnum    : Boolean;
  lPrefix    : string;
begin
  gc(lLines, TStringList.Create);
  lLines.LineBreak := sLineBreak;
  lLines.Text := aSource;

  gc(lEnumItems, TStringList.Create);
  lEnumItems.StrictDelimiter := True;  // no smart quote handling
  lEnumItems.Delimiter := ',';

  gc(lOut, TStringBuilder.Create(aSource.Length));

  lInEnum := False;
  lPrefix := '';

  for i := 0 to lLines.Count - 1 do
  begin
    lLine := lLines[i];
    lTrim := lLine.Trim;

    // -----------------------------------------------------------------------
    // Detect start of multi-line enum: "identifier = (" with NO ')'
    // -----------------------------------------------------------------------
    if (not lInEnum) then
    begin
      var openPos := lTrim.IndexOf('=(');
      if (openPos > 0) and (lTrim.IndexOf(')') = -1) then
      begin
        lInEnum := True;
        lPrefix := lLine.Substring(0, lLine.IndexOf('(') + 1); // keeps indent

        // collect any items on the same line after '('
        var rest := lTrim.Substring(openPos + 2).Trim;
        rest := rest.TrimRight([',']);
        if rest <> '' then
          lEnumItems.Add(rest);
        Continue; // do not emit this line now
      end;
    end
    else
    begin
      // --------------------------------------------------------------------
      // Inside enum block
      // --------------------------------------------------------------------
      var closePos := lTrim.IndexOf(')');
      if closePos <> -1 then
      begin
        // last line of the enum
        var part := lTrim.Substring(0, closePos).Trim;
        part := part.TrimRight([',']);
        if part <> '' then
          lEnumItems.Add(part);

        // emit compressed enum
        lOut.Append(lPrefix);
        for var j := 0 to lEnumItems.Count - 1 do
        begin
          if j > 0 then
            lOut.Append(', ');
          lOut.Append(lEnumItems[j]);
        end;
        lOut.Append(');').AppendLine;

        // reset state
        lInEnum := False;
        lEnumItems.Clear;
        Continue; // nothing else to add from this line
      end
      else
      begin
        // middle line of the enum
        var item := lTrim.TrimRight([',']);
        if item <> '' then
          lEnumItems.Add(item);
        Continue; // skip emitting this line
      end;
    end;

    // normal line (outside enum)
    lOut.AppendLine(lLine);
  end;

  Result := lOut.ToString;
end;


/// <summary>
/// Removes single-line constant declarations whose right-hand side is just a
/// qualified identifier (e.g.  Foo = UnitName.Foo;).
/// </summary>
function TInterfaceSectionCleaner.RemoveAliasConstants(
  const aSource: string): string;
var
  lLines: TStringList;
  lOut  : TStringBuilder;
  i     : Integer;
  lLine : string;

  function IsAliasConst(const aText: string): Boolean;
  var
    lEqPos, lSemiPos, lDotPos: Integer;
    lRhs: string;
    ch  : Char;
  begin
    Result := False;

    lEqPos   := aText.IndexOf('=');
    lSemiPos := aText.IndexOf(';');
    if (lEqPos = -1) or (lSemiPos = -1) or (lSemiPos < lEqPos) then
      Exit;

    // Extract right-hand side
    lRhs   := aText.Substring(lEqPos + 1, lSemiPos - lEqPos - 1).Trim;
    lDotPos := lRhs.IndexOf('.');
    if lDotPos = -1 then
      Exit;                       // not qualified → keep

    // Ensure RHS is only identifiers + dots
    for ch in lRhs do
      if not (TCharacter.IsLetterOrDigit(ch) or (ch = '.') or (ch = '_')) then
        Exit;                     // contains operators / literals → keep

    Result := True;               // qualifies as a mirror constant
  end;

begin
  gc(lLines, TStringList.Create);
  lLines.LineBreak := sLineBreak;
  lLines.Text := aSource;

  gc(lOut, TStringBuilder.Create(aSource.Length));

  for i := 0 to lLines.Count - 1 do
  begin
    lLine := lLines[i];

    if IsAliasConst(lLine.TrimLeft) then
      Continue;                   // drop mirror constant

    lOut.AppendLine(lLine);
  end;

  Result := lOut.ToString;
end;



/// <summary>
/// Drops "1.x / compatibility / legacy / deprecated" shim blocks.
/// Heuristic:  when we hit a line whose trimmed lowercase text contains any
/// of the trigger words, we skip that line and every subsequent line until
///   * we see a completely blank line,  OR
///   * the line starts with a section keyword (type/const/var/
function TInterfaceSectionCleaner.RemoveCompatibilityShims(
  const aSource: string): string;
const
  CTriggers: array[0..3] of string = ('compatibility', 'deprecated', 'legacy', '1.x');
  // section keywords that mark the end of a shim block
  CSectionStarters: array[0..10] of string = (
    'type', 'const', 'var', 'resourcestring', 'procedure', 'function',
    'interface', 'implementation', 'begin', 'class', 'record');
var
  lLines: TStringList;
  lOut: TStringBuilder;
  i: Integer;
  lLine: string;
  lSkip: Boolean;
  lLower: string;
  k: string;
begin
  gc(lLines, TStringList.Create);
  lLines.LineBreak := sLineBreak;
  lLines.Text := aSource;

  gc(lOut, TStringBuilder.Create(aSource.Length));

  lSkip := False;

  for i := 0 to lLines.Count - 1 do
  begin
    lLine  := lLines[i];
    lLower := lLine.TrimLeft.ToLower;

    // --- begin skip?
    if not lSkip then
      for k in CTriggers do
        if lLower.Contains(k) then
        begin
          lSkip := True;
          Break;                 // do NOT add this trigger line
        end;

    // --- inside skip block?
    if lSkip then
    begin
      // terminate skip on blank line
      if lLower = '' then
      begin
        lSkip := False;
        Continue;                // drop the blank line too
      end;

      // or on a new section
      for k in CSectionStarters do
        if lLower.StartsWith(k) then
        begin
          lSkip := False;
          Break;                 // we’ll add this line below
        end;
    end;

    if not lSkip then
      lOut.AppendLine(lLine);
  end;

  Result := lOut.ToString;
end;


function TInterfaceSectionCleaner.RemoveRedundantPropertyReexposures(
  const aSource: string): string;
var
  lLines: TStringList;
  lOut: TStringBuilder;
  i: Integer;
  lLine: string;
  lTrim: string;
begin
  gc(lLines, TStringList.Create);
  lLines.LineBreak := sLineBreak;
  lLines.Text := aSource;

  gc(lOut, TStringBuilder.Create(aSource.Length));

  for i := 0 to lLines.Count - 1 do
  begin
    lLine := lLines[i];
    lTrim := lLine.TrimLeft;

    if lTrim.StartsWith('property', True) then
    begin
      // text after the keyword
      var lRest := lTrim.Substring(8).Trim; // 8 = Length('property')
      // heuristic: re-published property has *no* type part or accessor list
      if (not lRest.Contains(':')) and
         (not lRest.Contains('read')) and
         (not lRest.Contains('write')) and
         (not lRest.Contains('index')) and
         (not lRest.Contains('implements')) and
         (not lRest.Contains('default')) and
         (not lRest.Contains('stored')) and
         (not lRest.Contains('nodefault')) then
        Continue; //  drop the whole line
    end;

    lOut.AppendLine(lLine);
  end;

  Result := lOut.ToString;
end;


end.

