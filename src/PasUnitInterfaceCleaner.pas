unit PasUnitInterfaceCleaner;

interface

uses
  System.SysUtils, System.Generics.Collections, System.Character, System.Classes,
  autoFree;

type
  TTokenType = (
    ttUnknown,
    ttWhitespace,
    ttCode,
    ttStringLiteral,
    ttLineComment,
    ttBlockComment,
    ttKeywordInterface,
    ttKeywordImplementation
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

{ TToken }

constructor TToken.Create(aStart, aLen: Integer; aType: TTokenType);
begin
  Self.StartIndex := aStart;
  Self.Length := aLen;
  Self.TokenType := aType;
end;

function TToken.GetText(const aSource: string): string;
begin
  Result := Copy(aSource, Self.StartIndex, Self.Length);
end;

{ TInterfaceSectionCleaner }

constructor TInterfaceSectionCleaner.Create;
begin
  inherited Create;
  // Keywords that identify a comment as boilerplate to be removed.
  fBoilerplateKeywords := [
    'license', 'copyright', 'author', 'created', 'modified',
    'all rights reserved', 'codegear', 'borland', 'embarcadero'
  ];
end;

function TInterfaceSectionCleaner.IsBoilerplate(const aHeaderText: string): Boolean;
var
  lKeyword: string;
  lUpperHeader: string;
begin
  Result := False;
  lUpperHeader := aHeaderText.ToUpper;
  for lKeyword in fBoilerplateKeywords do
  begin
    if lUpperHeader.Contains(lKeyword.ToUpper) then
      Exit(True);
  end;
end;

function TInterfaceSectionCleaner.Tokenize(const aSource: string): TArray<TToken>;
var
  lTokens: TList<TToken>;
  lCurrentIndex: Integer;
  lTokenStart: Integer;
  lNestedLevel: Integer;
  c: Char;
  c2: Char;
begin
  gc(lTokens, TList<TToken>.Create);
  lCurrentIndex := 1;

  while (lCurrentIndex <= Length(aSource)) do
  begin
    lTokenStart := lCurrentIndex;
    c := aSource[lCurrentIndex];

    // 1. Whitespace
    if TCharacter.IsWhiteSpace(c) then
    begin
      while (lCurrentIndex <= Length(aSource)) and TCharacter.IsWhiteSpace(aSource[lCurrentIndex]) do
        Inc(lCurrentIndex);
      lTokens.Add(TToken.Create(lTokenStart, lCurrentIndex - lTokenStart, ttWhitespace));
    end
    // 2. Line Comment
    else if (c = '/') and (lCurrentIndex < Length(aSource)) and (aSource[lCurrentIndex + 1] = '/') then
    begin
      Inc(lCurrentIndex, 2);
      while (lCurrentIndex <= Length(aSource)) and (not (aSource[lCurrentIndex] in [#10, #13])) do
        Inc(lCurrentIndex);
      lTokens.Add(TToken.Create(lTokenStart, lCurrentIndex - lTokenStart, ttLineComment));
    end
    // 3. Block Comment { ... } with nesting support
    else if (c = '{') then
    begin
      Inc(lCurrentIndex); // Move past the opening '{'
      lNestedLevel := 1;
      while (lCurrentIndex <= Length(aSource)) and (lNestedLevel > 0) do
      begin
        case aSource[lCurrentIndex] of
          '{': Inc(lNestedLevel);
          '}': Dec(lNestedLevel);
        end;
        Inc(lCurrentIndex);
      end;
      lTokens.Add(TToken.Create(lTokenStart, lCurrentIndex - lTokenStart, ttBlockComment));
    end
    // 4. Block Comment (* ... *) with nesting support
    else if (c = '(') and (lCurrentIndex < Length(aSource)) and (aSource[lCurrentIndex + 1] = '*') then
    begin
      Inc(lCurrentIndex, 2);
      lNestedLevel := 1;
      while (lCurrentIndex <= Length(aSource)) and (lNestedLevel > 0) do
      begin
        if (aSource[lCurrentIndex] = '(') and (lCurrentIndex < Length(aSource)) and (aSource[lCurrentIndex+1] = '*') then
        begin
          Inc(lNestedLevel);
          Inc(lCurrentIndex, 2);
        end
        else if (aSource[lCurrentIndex] = '*') and (lCurrentIndex < Length(aSource)) and (aSource[lCurrentIndex+1] = ')') then
        begin
          Dec(lNestedLevel);
          Inc(lCurrentIndex, 2);
        end
        else
        begin
          Inc(lCurrentIndex);
        end;
      end;
      lTokens.Add(TToken.Create(lTokenStart, lCurrentIndex - lTokenStart, ttBlockComment));
    end
    // 5. String Literal
    else if (c = '''') then
    begin
      Inc(lCurrentIndex);
      while lCurrentIndex <= Length(aSource) do
      begin
        if aSource[lCurrentIndex] = '''' then
        begin
          if (lCurrentIndex < Length(aSource)) and (aSource[lCurrentIndex + 1] = '''') then
            Inc(lCurrentIndex, 2) // Escaped quote
          else
          begin
            Inc(lCurrentIndex); // End of string
            Break;
          end;
        end
        else
        begin
          Inc(lCurrentIndex);
        end;
      end;
      lTokens.Add(TToken.Create(lTokenStart, lCurrentIndex - lTokenStart, ttStringLiteral));
    end
    // 6. Code
    else
    begin
      while (lCurrentIndex <= Length(aSource)) do
      begin
        c2 := aSource[lCurrentIndex];
        if TCharacter.IsWhiteSpace(c2) or (c2 = '{') or (c2 = '''') then
          Break;
        if (c2 = '/') and (lCurrentIndex < Length(aSource)) and (aSource[lCurrentIndex + 1] = '/') then
          Break;
        if (c2 = '(') and (lCurrentIndex < Length(aSource)) and (aSource[lCurrentIndex + 1] = '*') then
          Break;
        Inc(lCurrentIndex);
      end;
      var lToken := TToken.Create(lTokenStart, lCurrentIndex - lTokenStart, ttCode);
      var lLowerTokenText := lToken.GetText(aSource).ToLowerInvariant;
      if lLowerTokenText = 'interface' then
        lToken.TokenType := ttKeywordInterface
      else if lLowerTokenText = 'implementation' then
        lToken.TokenType := ttKeywordImplementation;
      lTokens.Add(lToken);
    end;
  end;

  Result := lTokens.ToArray;
end;

function TInterfaceSectionCleaner.AnalyzeAndBuild(const aSource: string; const aTokens: TArray<TToken>): string;
var
  i, j: Integer;
  lInterfaceTokenIndex: Integer;
  lImplementationTokenIndex: Integer;
  lFinalStartIndex: Integer;
  lFinalEndIndex: Integer;
  lHeaderStartIndex: Integer;
  lHeaderCommentBlock: string;
begin
  // Stage 1: Find the boundaries
  lInterfaceTokenIndex := -1;
  lImplementationTokenIndex := -1;

  for i := 0 to High(aTokens) do
  begin
    if aTokens[i].TokenType = ttKeywordInterface then
    begin
      if lInterfaceTokenIndex = -1 then // Find first occurrence
        lInterfaceTokenIndex := i;
    end
    else if aTokens[i].TokenType = ttKeywordImplementation then
    begin
      lImplementationTokenIndex := i; // Find last occurrence
    end;
  end;

  // If no interface keyword, return original string as per spec
  if lInterfaceTokenIndex = -1 then
    Exit(aSource);

  // Default start is the beginning of the 'interface' keyword
  lFinalStartIndex := aTokens[lInterfaceTokenIndex].StartIndex;

  // Stage 2: Analyze potential header comment
  // Note on unclosed comments: The tokenizer is tolerant and will treat an unclosed
  // comment as running to the end of the file. This is acceptable for this tool's purpose.
  lHeaderStartIndex := -1;
  lHeaderCommentBlock := '';

  // Walk backwards from the interface token to find a comment block
  for i := lInterfaceTokenIndex - 1 downto 0 do
  begin
    var lCurrentToken := aTokens[i];
    if lCurrentToken.TokenType = ttWhitespace then
      Continue; // Skip whitespace

    if (lCurrentToken.TokenType = ttBlockComment) or (lCurrentToken.TokenType = ttLineComment) then
    begin
      // Found the end of a comment block, now find its beginning
      lHeaderStartIndex := lCurrentToken.StartIndex;
      var lHeaderText: TStringBuilder;
      gc(lHeaderText, TStringBuilder.Create);

      // Walk backwards to gather all contiguous comment/whitespace tokens
      for j := i downto 0 do
      begin
        var lPrevToken := aTokens[j];
        if (lPrevToken.TokenType = ttLineComment) or (lPrevToken.TokenType = ttBlockComment) or (lPrevToken.TokenType = ttWhitespace) then
        begin
          lHeaderStartIndex := lPrevToken.StartIndex;
          lHeaderText.Insert(0, lPrevToken.GetText(aSource));
        end
        else
        begin
          Break; // Not a contiguous comment block
        end;
      end;
      lHeaderCommentBlock := lHeaderText.ToString;
      Break;
    end
    else
    begin
      // Found non-comment, non-whitespace token, so no header
      Break;
    end;
  end;

  // Stage 3: Decide whether to keep the header
  if lHeaderStartIndex <> -1 then
  begin
    if not IsBoilerplate(lHeaderCommentBlock) then
    begin
      lFinalStartIndex := lHeaderStartIndex;
    end;
  end;

  // Stage 4: Determine the end index
  if lImplementationTokenIndex <> -1 then
    lFinalEndIndex := aTokens[lImplementationTokenIndex].StartIndex - 1
  else
    lFinalEndIndex := Length(aSource); // To the end of the file

  // Stage 5: Assemble the final string
  Result := Copy(aSource, lFinalStartIndex, (lFinalEndIndex - lFinalStartIndex) + 1);
end;

function TInterfaceSectionCleaner.Process(const aSource: string): string;
var
  lTokens: TArray<TToken>;
begin
  if aSource.IsEmpty then
    Exit('');

  // Stage 1: Lexical Tokenization
  lTokens := Self.Tokenize(aSource);

  // Stage 2: Structural Analysis & String Assembly
  Result := Self.AnalyzeAndBuild(aSource, lTokens);
end;

end.
