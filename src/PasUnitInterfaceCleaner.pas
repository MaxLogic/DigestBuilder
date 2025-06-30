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
end;

end.

