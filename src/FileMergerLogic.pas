unit FileMergerLogic;

interface

uses
  System.SysUtils, System.Classes, System.IniFiles, System.NetEncoding;


type
  /// <summary>
  /// Handles all settings-related operations through INI file
  /// </summary>
  TFileMergerSettings = class
  private
    fIni: TMemIniFile;
  public
    // Constants for section names
    const
      cSecExtension = '$Extensions';
      cSecSettings = '$Settings';

    constructor Create;
    destructor Destroy; override;

    // Settings file operations
    function GetSettingsFilePath: string;
    procedure InitializeDefaultExtensions;
    function GetLanguageSpecifier(const aFileName: string): string;

    // File mask operations
    procedure SaveFileMaskList(const aFileMasks: TStrings);
    function LoadFileMaskList: string;

    // Project selection persistence
    procedure SaveLastSelectedProject(const aProjectName: string);
    function GetLastSelectedProject: string;

    // Application settings
    procedure SetCopyToClipboardFlag(aValue: Boolean);
    function GetCopyToClipboardFlag: Boolean;

    property IniFile: TMemIniFile read fIni;
  end;

  /// <summary>
  /// Represents a project with all its properties
  /// </summary>
  TProject = record
    Name: string;
    FileList: String; // filename of a text file containing the file list to be included. one file per line
    SourceDir: string;
    FileMask: string;
    Recursive: Boolean;
    Description: string;
    IncludeFileStructure: Boolean;
    PasInterfaceSectionOnly: Boolean;
  end;

  /// <summary>
  /// Manages project operations (loading, saving, listing)
  /// </summary>
  TProjectManager = class
  private
    fSettings: TFileMergerSettings;
  public
    constructor Create(aSettings: TFileMergerSettings);

    // Project list management
    function LoadProjectList: TStringList;

    // Individual project operations
    procedure LoadProject(const aProjectName: string; out aProject: TProject);
    procedure SaveProject(const aProject: TProject);
    procedure DeleteProject(const aProjectName: string);
  end;

  /// <summary>
  /// Handles all file operations including scanning and merging
  /// </summary>
  TFileProcessor = class
  private
    fSettings: TFileMergerSettings;
    fPythonCommand: string;
    fTokenizerProcess: THandle;
    fTokenizerStdInWrite: THandle;
    fTokenizerStdOutRead: THandle;
    fTokenizerStdOutBuffer: RawByteString;
    fTokenizerScriptFile: string;
    fTokenizerReady: Boolean;

    // Directory tree generation helpers
    function IsCommonDelphiTemp(const aName: string; aIsDir: Boolean): Boolean;
    function ShouldIgnore(const aName: string; const aIgnoreRules: TArray<string>): Boolean;
    procedure AddDirToTree(const aDir, aRootDir: string; const aLevel: Integer;
                          aOutput: TStringList);
    function QuoteCommandArg(const aValue: string): string;
    function ExecuteShellCommand(const aCommand, aStdOutFile, aStdErrFile: string; out aExitCode: Cardinal): Boolean;
    function EnsurePythonCommand: string;
    function EnsureTokenizerProcess: Boolean;
    function ReadTokenizerLine(out aLine: string): Boolean;
    procedure CloseTokenizerProcess;
    function CountTokensWithPython(const aText: string; out aTokenCount: Int64): Boolean;
    function RenderFileSection(const aFileName: string; aPasInterfaceSectionOnly: Boolean): string;
    function BuildFileMapText(const aRootDir: string; const aFilesInPart: TStringList): string;
    function BuildPartFilePath(const aBaseOutputFile: string; aPartIndex: Integer): string;
    procedure CleanupOutputArtifacts(const aBaseOutputFile: string; aSplitMode: Boolean);
    function BuildPartHeader(const aProject: TProject; const aOutputFileName: string; const aPartIndex: Integer;
      const aHasPrevPart, aHasNextPart: Boolean): string;
    function TokenizeText(const aText: string; out aTokenCount: Int64): Boolean;
  public
    constructor Create(aSettings: TFileMergerSettings);
    destructor Destroy; override;

    // File gathering and processing
    procedure GatherFiles(const aSourceDir, aFileMask: string; aRecursive: Boolean; aFileList: TStringList);

    procedure MergeFiles(aFileList, aOutput: TStringList; aPasInterfaceSectionOnly: boolean);
    function ExtractInterfaceSetionFrompasFile(const aPasFileContent: String): String;
    function GenerateFileStructureTree(const aRootDir: string): string;
    function GenerateFileStructureTreeForFiles(const aRootDir: string; const aPartFiles: TStringList): string;

    // Main processing function
    procedure ProcessProject(const aProject: TProject; const aOutputFileName: string; const aMaxTokenPerFile: Int64 = 0);
  end;

implementation

uses
  PasUnitInterfaceCleaner, System.IOUtils, System.StrUtils, System.Masks, MaxLogic.IOUtils, autoFree,
  Winapi.Windows, Winapi.ShellApi;

{ TFileMergerSettings }

constructor TFileMergerSettings.Create;
begin
  inherited Create;
  fIni := TMemIniFile.Create(GetSettingsFilePath, TEncoding.utf8, false);

  // Initialize default extensions if needed
  if not fIni.SectionExists(cSecExtension) then
    InitializeDefaultExtensions;
end;

destructor TFileMergerSettings.Destroy;
begin
  fIni.Free;
  inherited;
end;

function TFileMergerSettings.GetSettingsFilePath: string;
begin
  Result := GetInstallDir + 'Projects.ini';
end;

procedure TFileMergerSettings.InitializeDefaultExtensions;
begin
  // Set up language specifiers for common file extensions
  fIni.WriteString(cSecExtension, 'pas', 'pascal');
  fIni.WriteString(cSecExtension, 'dfm', 'dfm');
  fIni.WriteString(cSecExtension, 'dpr', 'pascal');
  fIni.WriteString(cSecExtension, 'inc', 'pascal');
  fIni.WriteString(cSecExtension, 'sql', 'sql');
  fIni.WriteString(cSecExtension, 'html', 'html');
  fIni.WriteString(cSecExtension, 'css', 'css');
  fIni.WriteString(cSecExtension, 'js', 'javascript');
  fIni.WriteString(cSecExtension, 'json', 'json');
  fIni.WriteString(cSecExtension, 'xml', 'xml');
  fIni.WriteString(cSecExtension, 'cs', 'csharp');
  fIni.WriteString(cSecExtension, 'cpp', 'cpp');
  fIni.WriteString(cSecExtension, 'h', 'cpp');
  fIni.WriteString(cSecExtension, 'py', 'python');
  fIni.UpdateFile;
end;

function TFileMergerSettings.GetLanguageSpecifier(const aFileName: string): string;
var
  lExt: string;
begin
  // Map file extension to markdown language specifier
  lExt := LowerCase(Copy(ExtractFileExt(aFileName), 2, MaxInt));
  Result := fIni.ReadString(cSecExtension, lExt, 'text');
end;

procedure TFileMergerSettings.SaveFileMaskList(const aFileMasks: TStrings);
begin
  fIni.WriteString('$FileMasks', 'List', aFileMasks.CommaText);
  fIni.UpdateFile;
end;

function TFileMergerSettings.LoadFileMaskList: string;
begin
  Result := fIni.ReadString('$FileMasks', 'List', '');
end;

procedure TFileMergerSettings.SaveLastSelectedProject(const aProjectName: string);
begin
  fIni.WriteString(cSecSettings, 'LastProject', aProjectName);
  fIni.UpdateFile;
end;

function TFileMergerSettings.GetLastSelectedProject: string;
begin
  Result := fIni.ReadString(cSecSettings, 'LastProject', '');
end;

procedure TFileMergerSettings.SetCopyToClipboardFlag(aValue: Boolean);
begin
  fIni.WriteBool(cSecSettings, 'CopyOutputToClipboard', aValue);
  fIni.UpdateFile;
end;

function TFileMergerSettings.GetCopyToClipboardFlag: Boolean;
begin
  Result := fIni.ReadBool(cSecSettings, 'CopyOutputToClipboard', False);
end;

{ TProjectManager }

constructor TProjectManager.Create(aSettings: TFileMergerSettings);
begin
  inherited Create;
  fSettings := aSettings;
end;

function TProjectManager.LoadProjectList: TStringList;
var
  lAllSections: TStringList;
begin
  Result := TStringList.Create;
  gc(lAllSections, TStringList.Create);

  fSettings.IniFile.ReadSections(lAllSections);

  // Filter out special sections (those starting with $)
  for var i := 0 to lAllSections.Count-1 do
    if not StartsText('$', lAllSections[i]) then
      Result.Add(lAllSections[i]);

  Result.Sort;
end;

procedure TProjectManager.LoadProject(const aProjectName: string; out aProject: TProject);
var
  l: TStringList;
begin
  gc(l, TStringList.Create);
  l.StrictDelimiter:= True;

  aProject.Name := aProjectName;
  aProject.SourceDir := fSettings.IniFile.ReadString(aProjectName, 'SourceDir', '');
  aProject.FileMask := fSettings.IniFile.ReadString(aProjectName, 'FileMask', '');

  l.Delimiter:= '|';
  l.DelimitedText:= fSettings.IniFile.ReadString(aProjectName, 'Description', '');
  aProject.Description := trim(l.Text);
  aProject.IncludeFileStructure := fSettings.IniFile.ReadBool(aProjectName, 'IncludeFileStructure', False);
  aProject.PasInterfaceSectionOnly:= fSettings.IniFile.ReadBool(aProjectName, 'PasInterfaceSectionOnly', False);
end;

procedure TProjectManager.SaveProject(const aProject: TProject);
var
  lProjectName: string;
  l: TStringList;
begin
  gc(l, TStringList.Create);
  l.StrictDelimiter:= True;
  lProjectName := Trim(aProject.Name);

  // Remove $ prefix if present (reserved for special sections)
  while StartsText('$', lProjectName) do
    Delete(lProjectName, 1, 1);

  lProjectName := Trim(lProjectName);
  if lProjectName = '' then
    Exit;

  // Save project settings
  fSettings.IniFile.WriteString(lProjectName, 'SourceDir', aProject.SourceDir);
  fSettings.IniFile.WriteString(lProjectName, 'FileMask', aProject.FileMask);

  l.Delimiter:= '|';
  l.Text:= aProject.Description;
  fSettings.IniFile.WriteString(lProjectName, 'Description', trim(l.DelimitedText));
  fSettings.IniFile.WriteBool(lProjectName, 'IncludeFileStructure', aProject.IncludeFileStructure);
  fSettings.IniFile.WriteBool(lProjectName, 'PasInterfaceSectionOnly', aProject.PasInterfaceSectionOnly);


  fSettings.IniFile.UpdateFile;
end;

procedure TProjectManager.DeleteProject(const aProjectName: string);
begin
  if aProjectName <> '' then
  begin
    fSettings.IniFile.EraseSection(aProjectName);
    fSettings.IniFile.UpdateFile;
  end;
end;

{ TFileProcessor }

constructor TFileProcessor.Create(aSettings: TFileMergerSettings);
begin
  inherited Create;
  fSettings := aSettings;
  fTokenizerProcess := 0;
  fTokenizerStdInWrite := 0;
  fTokenizerStdOutRead := 0;
  fTokenizerReady := False;
  fTokenizerStdOutBuffer := '';
  fTokenizerScriptFile := '';
end;

destructor TFileProcessor.Destroy;
begin
  CloseTokenizerProcess;
  inherited;
end;

function TFileProcessor.ExtractInterfaceSetionFrompasFile(
  const aPasFileContent: String): String;
var
  lCleaner: TInterfaceSectionCleaner;
begin
  gc(lCleaner, TInterfaceSectionCleaner.Create);
  Result:= lCleaner.Process(aPasFileContent);
end;

procedure TFileProcessor.GatherFiles(const aSourceDir, aFileMask: string;
  aRecursive: Boolean;
  aFileList: TStringList);
var
  lFileMask: TStringList;
  lDir: string;
  lOption: TSearchOption;
begin
  gc(lFileMask, TStringList.Create);
  lFileMask.StrictDelimiter := True;
  lFileMask.Delimiter := '|';
  lDir := aSourceDir;
  lFileMask.DelimitedText := Trim(aFileMask);

  if lFileMask.Count = 0 then
    lFileMask.Add('*.*');

  for var lPattern in lFileMask do
  begin
    if aRecursive then
      lOption := TSearchOption.soAllDirectories
    else
      lOption := TSearchOption.soTopDirectoryOnly;

    for var lFileName in TDirectory.GetFiles(lDir, lPattern, lOption) do
      aFileList.Add(lFileName);
  end;
end;

function TFileProcessor.IsCommonDelphiTemp(const aName: string; aIsDir: Boolean): Boolean;
begin
  // Filter out common Delphi temporary files and directories
  if aIsDir then
    Result := system.strUtils.MatchText(aName, ['__history', '__recovery'])
  else
    Result := MatchesMask(aName, '*.dcu') or MatchesMask(aName, '*.~*');
end;

function TFileProcessor.ShouldIgnore(const aName: string;
                                    const aIgnoreRules: TArray<string>): Boolean;
var
  lRule: string;
begin
  // Check if file matches any ignore rule
  for lRule in aIgnoreRules do
  begin
    if MatchesMask(aName, lRule) then
      Exit(True);
  end;
  Result := False;
end;

procedure TFileProcessor.AddDirToTree(const aDir, aRootDir: string;
                                     const aLevel: Integer;
                                     aOutput: TStringList);
var
  lDirInfo: TSearchRec;
  lDirs, lFiles: TStringList;
  lIndent, lRelPath: string;
  lIgnoreRules: TArray<string>;
  lGitIgnorePath: string;
begin
  // Load .gitignore rules if present in the current directory
  lGitIgnorePath := IncludeTrailingPathDelimiter(aDir) + '.gitignore';
  if FileExists(lGitIgnorePath) then
    lIgnoreRules := TFile.ReadAllLines(lGitIgnorePath)
  else
    lIgnoreRules := nil;

  // Calculate relative path for display
  lRelPath := aDir;
  if StartsText(aRootDir, lRelPath) then
    lRelPath := Copy(lRelPath, Length(aRootDir) + 1, Length(lRelPath));
  if (lRelPath <> '') and (lRelPath[1] = PathDelim) then
    Delete(lRelPath, 1, 1);

  // Add directory to the output with appropriate indentation
  lIndent := StringOfChar(' ', aLevel * 2);
  if lRelPath = '' then
    aOutput.Add(aRootDir + PathDelim)
  else
    aOutput.Add(lIndent + PathDelim + lRelPath);

  // Collect directories and files, excluding ignored ones
  gc(lDirs, TStringList.Create);
  gc(lFiles, TStringList.Create);

  if FindFirst(IncludeTrailingPathDelimiter(aDir) + '*.*', faAnyFile, lDirInfo) = 0 then
  begin
    try
      repeat
        if (lDirInfo.Name <> '.') and (lDirInfo.Name <> '..') and
           not ShouldIgnore(lDirInfo.Name, lIgnoreRules) and
           not IsCommonDelphiTemp(lDirInfo.Name, (lDirInfo.Attr and faDirectory) <> 0) then
        begin
          if (lDirInfo.Attr and faDirectory) <> 0 then
            lDirs.Add(lDirInfo.Name)
          else
            lFiles.Add(lDirInfo.Name);
        end;
      until FindNext(lDirInfo) <> 0;
    finally
    System.SysUtils.FindClose(lDirInfo);
    end;
  end;

  // Sort directories and files for consistent output
  lDirs.Sort;
  lFiles.Sort;

  // Add files to the output with indentation
  lIndent := StringOfChar(' ', (aLevel + 1) * 2);
  for var fn in lFiles do
    aOutput.Add(lIndent + fn);

  // Recurse into subdirectories
  for var dir in lDirs do
    AddDirToTree(IncludeTrailingPathDelimiter(aDir) + dir, aRootDir, aLevel + 1, aOutput);
end;

function TFileProcessor.GenerateFileStructureTree(const aRootDir: string): string;
var
  lOutput: TStringList;
begin
  gc(lOutput, TStringList.Create);
  AddDirToTree(aRootDir, aRootDir, 0, lOutput);
  Result := lOutput.Text;
end;

procedure TFileProcessor.MergeFiles(aFileList, aOutput: TStringList;  aPasInterfaceSectionOnly: boolean);
var
  lContent: TStringList;
  lLang: string;
begin
  gc(lContent, TStringList.Create);

  for var lFileName in aFileList do
  begin
    lLang := fSettings.GetLanguageSpecifier(lFileName);
    aOutput.Add('## ' + ExtractFileName(lFileName));
    if aPasInterfaceSectionOnly and endsText('.pas', lFileName) then
      aOutput.Add(Format('interface section of file `%s`:', [lFileName]))
    else
      aOutput.Add(Format('Content of file `%s`:', [lFileName]));
    aOutput.Add('```' + lLang);

    try
      lContent.LoadFromFile(lFileName, TEncoding.UTF8);
    except
      lContent.LoadFromFile(lFileName);
    end;
    if aPasInterfaceSectionOnly and endsText('.pas', lFileName) then
      lContent.Text := ExtractInterfaceSetionFrompasFile(lContent.Text);



    aOutput.AddStrings(lContent);
    aOutput.Add('```');
    aOutput.Add('');
    aOutput.Add('---');
    aOutput.Add('');
  end;
end;

function TFileProcessor.QuoteCommandArg(const aValue: string): string;
begin
  Result := '"' + StringReplace(aValue, '"', '""', [rfReplaceAll]) + '"';
end;

function TFileProcessor.ExecuteShellCommand(const aCommand, aStdOutFile, aStdErrFile: string; out aExitCode: Cardinal): Boolean;
var
  lExecInfo: TShellExecuteInfo;
  lParams: string;
begin
  Result := False;
  aExitCode := 0;
  FillChar(lExecInfo, SizeOf(TShellExecuteInfo), 0);
  lParams := '/C ' + aCommand;

  lExecInfo.cbSize := SizeOf(TShellExecuteInfo);
  lExecInfo.fMask := SEE_MASK_NOCLOSEPROCESS;
  lExecInfo.nShow := SW_HIDE;
  lExecInfo.lpFile := 'cmd.exe';
  lExecInfo.lpParameters := PChar(lParams);
  lExecInfo.lpDirectory := nil;

  if not ShellExecuteEx(@lExecInfo) then
    Exit;

  try
    WaitForSingleObject(lExecInfo.hProcess, INFINITE);
    if not GetExitCodeProcess(lExecInfo.hProcess, aExitCode) then
      Exit;
    Result := (aExitCode = 0);
  finally
    CloseHandle(lExecInfo.hProcess);
  end;
end;

function TFileProcessor.EnsurePythonCommand: string;
var
  lOut, lErr: string;
  lExitCode: Cardinal;
  lCommand: string;
begin
  if fPythonCommand <> '' then
    Exit(fPythonCommand);

  lOut := TPath.GetTempFileName;
  lErr := TPath.GetTempFileName;
  try
    lCommand := Format('py --version > %s 2> %s', [QuoteCommandArg(lOut), QuoteCommandArg(lErr)]);
    if ExecuteShellCommand(lCommand, lOut, lErr, lExitCode) then
      fPythonCommand := 'py'
    else
    begin
      lCommand := Format('python --version > %s 2> %s', [QuoteCommandArg(lOut), QuoteCommandArg(lErr)]);
      if ExecuteShellCommand(lCommand, lOut, lErr, lExitCode) then
        fPythonCommand := 'python';
    end;
  finally
    if FileExists(lOut) then TFile.Delete(lOut);
    if FileExists(lErr) then TFile.Delete(lErr);
  end;
  Result := fPythonCommand;
end;

function TFileProcessor.EnsureTokenizerProcess: Boolean;
var
  lSecurity: TSecurityAttributes;
  lStdInRead: THandle;
  lStdOutWrite: THandle;
  lStartupInfo: TStartupInfo;
  lProcessInfo: TProcessInformation;
  lCommandLine: string;
  lBanner: string;
  lScript: string;
begin
  if fTokenizerReady then
    Exit(True);

  Result := False;
  if EnsurePythonCommand = '' then
    Exit(False);

  lStdInRead := 0;
  lStdOutWrite := 0;
  FillChar(lSecurity, SizeOf(lSecurity), 0);
  lSecurity.nLength := SizeOf(lSecurity);
  lSecurity.bInheritHandle := True;

  if not CreatePipe(lStdInRead, fTokenizerStdInWrite, @lSecurity, 0) then
    Exit(False);

  if not CreatePipe(fTokenizerStdOutRead, lStdOutWrite, @lSecurity, 0) then
  begin
    CloseHandle(lStdInRead);
    CloseHandle(fTokenizerStdInWrite);
    lStdInRead := 0;
    fTokenizerStdInWrite := 0;
    Exit(False);
  end;

  SetHandleInformation(fTokenizerStdInWrite, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(fTokenizerStdOutRead, HANDLE_FLAG_INHERIT, 0);

  lScript :=
    'import sys' + sLineBreak +
    'import base64' + sLineBreak +
    'import tiktoken' + sLineBreak +
    sLineBreak +
    'enc = tiktoken.encoding_for_model(''gpt-4o'')' + sLineBreak +
    'sys.stdout.write(''READY\n'')' + sLineBreak +
    'sys.stdout.flush()' + sLineBreak +
    sLineBreak +
    'for line in sys.stdin.buffer:' + sLineBreak +
    '    line = line.strip()' + sLineBreak +
    '    if not line:' + sLineBreak +
    '        continue' + sLineBreak +
    '    if line == b''__EXIT__'':' + sLineBreak +
    '        break' + sLineBreak +
    '    text = base64.b64decode(line).decode(''utf-8'')' + sLineBreak +
    '    sys.stdout.write(str(len(enc.encode(text))) + ''\n'')' + sLineBreak +
    '    sys.stdout.flush()' + sLineBreak;

  fTokenizerScriptFile := TPath.ChangeExtension(TPath.GetTempFileName, '.py');
  TFile.WriteAllText(fTokenizerScriptFile, lScript, TEncoding.UTF8);

  lCommandLine := Format('cmd.exe /C %s -u %s',
    [EnsurePythonCommand, QuoteCommandArg(fTokenizerScriptFile)]);

  FillChar(lStartupInfo, SizeOf(lStartupInfo), 0);
  lStartupInfo.cb := SizeOf(lStartupInfo);
  lStartupInfo.dwFlags := STARTF_USESHOWWINDOW or STARTF_USESTDHANDLES;
  lStartupInfo.wShowWindow := SW_HIDE;
  lStartupInfo.hStdInput := lStdInRead;
  lStartupInfo.hStdOutput := lStdOutWrite;
  lStartupInfo.hStdError := lStdOutWrite;

  FillChar(lProcessInfo, SizeOf(lProcessInfo), 0);
  if not CreateProcess(nil, PChar(lCommandLine), nil, nil, True, CREATE_NO_WINDOW, nil, nil, lStartupInfo, lProcessInfo) then
  begin
    CloseHandle(lStdInRead);
    CloseHandle(lStdOutWrite);
    CloseTokenizerProcess;
    Exit(False);
  end;

  CloseHandle(lStdInRead);
  CloseHandle(lStdOutWrite);
  CloseHandle(lProcessInfo.hThread);
  fTokenizerProcess := lProcessInfo.hProcess;
  fTokenizerStdOutBuffer := '';

  if not ReadTokenizerLine(lBanner) then
  begin
    CloseTokenizerProcess;
    Exit(False);
  end;

  fTokenizerReady := SameText(Trim(lBanner), 'READY');
  Result := fTokenizerReady;
  if not Result then
    CloseTokenizerProcess;
end;

function TFileProcessor.ReadTokenizerLine(out aLine: string): Boolean;
var
  lChunk: array[0..255] of AnsiChar;
  lBytesRead: Cardinal;
  lLineFeedPos: Integer;
  lLineBytes: RawByteString;
begin
  Result := False;
  aLine := '';

  while True do
  begin
    lLineFeedPos := Pos(#10, string(fTokenizerStdOutBuffer));
    if lLineFeedPos > 0 then
    begin
      lLineBytes := Copy(fTokenizerStdOutBuffer, 1, lLineFeedPos - 1);
      Delete(fTokenizerStdOutBuffer, 1, lLineFeedPos);
      aLine := string(lLineBytes);
      if (aLine <> '') and (aLine[Length(aLine)] = #13) then
        Delete(aLine, Length(aLine), 1);
      Exit(True);
    end;

    if not ReadFile(fTokenizerStdOutRead, lChunk[0], SizeOf(lChunk), lBytesRead, nil) then
      Exit(False);
    if lBytesRead = 0 then
      Exit(False);

    SetString(lLineBytes, PAnsiChar(@lChunk[0]), lBytesRead);
    fTokenizerStdOutBuffer := fTokenizerStdOutBuffer + lLineBytes;
  end;
end;

procedure TFileProcessor.CloseTokenizerProcess;
var
  lBytesWritten: Cardinal;
  lExitMarker: AnsiString;
begin
  if fTokenizerStdInWrite <> 0 then
  begin
    if fTokenizerProcess <> 0 then
    begin
      lExitMarker := '__EXIT__' + #10;
      WriteFile(fTokenizerStdInWrite, PAnsiChar(lExitMarker)^, Length(lExitMarker), lBytesWritten, nil);
    end;
    CloseHandle(fTokenizerStdInWrite);
    fTokenizerStdInWrite := 0;
  end;

  if fTokenizerStdOutRead <> 0 then
  begin
    CloseHandle(fTokenizerStdOutRead);
    fTokenizerStdOutRead := 0;
  end;

  if fTokenizerProcess <> 0 then
  begin
    WaitForSingleObject(fTokenizerProcess, 5000);
    CloseHandle(fTokenizerProcess);
    fTokenizerProcess := 0;
  end;

  if (fTokenizerScriptFile <> '') and FileExists(fTokenizerScriptFile) then
    TFile.Delete(fTokenizerScriptFile);
  fTokenizerScriptFile := '';

  fTokenizerStdOutBuffer := '';
  fTokenizerReady := False;
end;

function TFileProcessor.CountTokensWithPython(const aText: string; out aTokenCount: Int64): Boolean;
var
  lEncoded: string;
  lRequest: AnsiString;
  lBytesWritten: Cardinal;
  lResponse: string;
begin
  Result := False;
  aTokenCount := 0;

  if not EnsureTokenizerProcess then
    Exit(False);

  lEncoded := TNetEncoding.Base64.EncodeBytesToString(TEncoding.UTF8.GetBytes(aText));
  lEncoded := StringReplace(lEncoded, sLineBreak, '', [rfReplaceAll]);
  lRequest := AnsiString(lEncoded + #10);
  if not WriteFile(fTokenizerStdInWrite, PAnsiChar(lRequest)^, Length(lRequest), lBytesWritten, nil) then
  begin
    CloseTokenizerProcess;
    Exit(False);
  end;

  if not ReadTokenizerLine(lResponse) then
  begin
    CloseTokenizerProcess;
    Exit(False);
  end;

  lResponse := Trim(lResponse);
  if not TryStrToInt64(lResponse, aTokenCount) then
  begin
    CloseTokenizerProcess;
    Exit(False);
  end;

  Result := True;
end;

function TFileProcessor.TokenizeText(const aText: string; out aTokenCount: Int64): Boolean;
begin
  Result := CountTokensWithPython(aText, aTokenCount);
end;

function TFileProcessor.RenderFileSection(const aFileName: string; aPasInterfaceSectionOnly: Boolean): string;
var
  lLang: string;
  lContent, lOutput: TStringList;
begin
  gc(lContent, TStringList.Create);
  gc(lOutput, TStringList.Create);

  lLang := fSettings.GetLanguageSpecifier(aFileName);
  lOutput.Add('## ' + ExtractFileName(aFileName));
  if aPasInterfaceSectionOnly and endsText('.pas', aFileName) then
    lOutput.Add(Format('interface section of file `%s`:', [aFileName]))
  else
    lOutput.Add(Format('Content of file `%s`:', [aFileName]));
  lOutput.Add('```' + lLang);

  try
    lContent.LoadFromFile(aFileName, TEncoding.UTF8);
  except
    lContent.LoadFromFile(aFileName);
  end;

  if aPasInterfaceSectionOnly and endsText('.pas', aFileName) then
    lContent.Text := ExtractInterfaceSetionFrompasFile(lContent.Text);

  lOutput.AddStrings(lContent);
  lOutput.Add('```');
  lOutput.Add('');
  lOutput.Add('---');
  lOutput.Add('');

  Result := lOutput.Text;
end;

function TFileProcessor.BuildPartFilePath(const aBaseOutputFile: string; aPartIndex: Integer): string;
var
  lDir, lBase, lExt: string;
begin
  lDir := TPath.GetDirectoryName(aBaseOutputFile);
  lBase := TPath.GetFileNameWithoutExtension(aBaseOutputFile);
  lExt := TPath.GetExtension(aBaseOutputFile);
  if lExt = '' then
    lExt := '.md';

  Result := lBase + Format('.part%.3d', [aPartIndex]) + lExt;
  if lDir <> '' then
    Result := TPath.Combine(lDir, Result);
end;

procedure TFileProcessor.CleanupOutputArtifacts(const aBaseOutputFile: string; aSplitMode: Boolean);
var
  lDir, lBase, lExt: string;
begin
  lDir := TPath.GetDirectoryName(aBaseOutputFile);
  lBase := TPath.GetFileNameWithoutExtension(aBaseOutputFile);
  lExt := TPath.GetExtension(aBaseOutputFile);
  if lExt = '' then
    lExt := '.md';

  if lDir = '' then
    lDir := TDirectory.GetCurrentDirectory;

  if TDirectory.Exists(lDir) then
    for var lFileName in TDirectory.GetFiles(lDir, lBase + '.part*' + lExt, TSearchOption.soTopDirectoryOnly) do
      TFile.Delete(lFileName);

  if aSplitMode and TFile.Exists(aBaseOutputFile) then
    TFile.Delete(aBaseOutputFile);
end;

function TFileProcessor.BuildPartHeader(const aProject: TProject; const aOutputFileName: string; const aPartIndex: Integer;
  const aHasPrevPart, aHasNextPart: Boolean): string;
var
  lOutput: TStringList;
  lPrevPartName, lNextPartName: string;
begin
  gc(lOutput, TStringList.Create);

  lOutput.Add(Format('## Part %d', [aPartIndex]));

  if aHasPrevPart then
  begin
    lPrevPartName := ExtractFileName(BuildPartFilePath(aOutputFileName, aPartIndex - 1));
    lOutput.Add('- Previous part: [' + lPrevPartName + '](' + lPrevPartName + ')');
  end;

  if aHasNextPart then
  begin
    lNextPartName := ExtractFileName(BuildPartFilePath(aOutputFileName, aPartIndex + 1));
    lOutput.Add('- Next part: [' + lNextPartName + '](' + lNextPartName + ')');
  end;

  lOutput.Add('');
  if Trim(aProject.Name) <> '' then
  begin
    lOutput.Add('# ' + aProject.Name);
    lOutput.Add('');
  end;

  if Trim(aProject.Description) <> '' then
  begin
    lOutput.Add(aProject.Description);
    lOutput.Add('');
    lOutput.Add('---');
    lOutput.Add('');
  end;

  Result := lOutput.Text;
end;

function TFileProcessor.BuildFileMapText(const aRootDir: string; const aFilesInPart: TStringList): string;
var
  lMap: string;
begin
  if (aRootDir = '') or (aFilesInPart.Count = 0) then
    Exit('');

  lMap := GenerateFileStructureTreeForFiles(aRootDir, aFilesInPart);
  if lMap = '' then
    Exit('');

  Result := '## Project Structure' + sLineBreak +
    '```' + sLineBreak +
    lMap +
    '```' + sLineBreak + sLineBreak +
    '---' + sLineBreak + sLineBreak;
end;

function TFileProcessor.GenerateFileStructureTreeForFiles(const aRootDir: string; const aPartFiles: TStringList): string;
var
  lRelativeFiles, lOutput, lEmittedDirs, lDirPrefixes: TStringList;
  lRoot, lFullPath, lRelativePath, lDir, lFileName: string;
  lCurrentDir: string;
  i, j: Integer;
  lDepth: Integer;
begin
  Result := '';

  if (aRootDir = '') or (aPartFiles = nil) or (aPartFiles.Count = 0) then
    Exit;

  gc(lRelativeFiles, TStringList.Create);
  gc(lOutput, TStringList.Create);
  gc(lEmittedDirs, TStringList.Create);
  lEmittedDirs.CaseSensitive := False;
  lEmittedDirs.Sorted := True;
  lEmittedDirs.Duplicates := dupIgnore;

  lRoot := IncludeTrailingPathDelimiter(TPath.GetFullPath(aRootDir));

  for i := 0 to aPartFiles.Count - 1 do
  begin
    if not FileExists(aPartFiles[i]) then
      Continue;

    lFullPath := TPath.GetFullPath(aPartFiles[i]);
    if not SameText(Copy(lFullPath, 1, Length(lRoot)), lRoot) then
      Continue;
    lRelativePath := Copy(lFullPath, Length(lRoot) + 1, MaxInt);
    if lRelativePath = '' then
      Continue;

    lRelativePath := StringReplace(lRelativePath, '/', '\', [rfReplaceAll]);
    if (lRelativePath <> '') and (lRelativePath[1] = '\') then
      Delete(lRelativePath, 1, 1);

    if lRelativePath <> '' then
      lRelativeFiles.Add(lRelativePath);
  end;

  if lRelativeFiles.Count = 0 then
    Exit;

  lRelativeFiles.CaseSensitive := False;
  lRelativeFiles.Sorted := True;
  lRelativeFiles.Duplicates := dupIgnore;

  lOutput.Add(IncludeTrailingPathDelimiter(TPath.GetFullPath(aRootDir)));
  for i := 0 to lRelativeFiles.Count - 1 do
  begin
    lFileName := lRelativeFiles[i];
    lDir := ExtractFileDir(lFileName);
    if lDir = '.' then
      lDir := '';

    if lDir <> '' then
    begin
      gc(lDirPrefixes, TStringList.Create);
      lCurrentDir := lDir;
      while lCurrentDir <> '' do
      begin
        lDirPrefixes.Insert(0, lCurrentDir);
        lCurrentDir := ExtractFileDir(lCurrentDir);
      end;

      for j := 0 to lDirPrefixes.Count - 1 do
      begin
        if lEmittedDirs.IndexOf(lDirPrefixes[j]) >= 0 then
          Continue;

        lDepth := 0;
        for var lCharPos := 1 to Length(lDirPrefixes[j]) do
          if lDirPrefixes[j][lCharPos] = PathDelim then
            Inc(lDepth);
        lOutput.Add(StringOfChar(' ', lDepth * 2) + PathDelim + lDirPrefixes[j]);
        lEmittedDirs.Add(lDirPrefixes[j]);
      end;
    end;

    lDepth := 0;
    for var lCharPos := 1 to Length(lDir) do
      if lDir[lCharPos] = PathDelim then
        Inc(lDepth);
    lOutput.Add(StringOfChar(' ', lDepth * 2) + ExtractFileName(lFileName));
  end;

  Result := lOutput.Text;
end;

procedure TFileProcessor.ProcessProject(const aProject: TProject; const aOutputFileName: String; const aMaxTokenPerFile: Int64);
var
  lFileList, lOutput: TStringList;
  lSourceSections: TStringList;
  lSectionTokens: array of Int64;
  lPartFiles, lPartSections: TStringList;
  lSectionText: string;
  lSectionToken: Int64;
  lFileCount: Integer;
  lPartIndex: Integer;
  lCurrentPartTokens: Int64;
  lCandidateTokens: Int64;
  lCandidateHeaderTokens: Int64;
  lOutputPath: string;
  lCanSplit: Boolean;
  lProjectFileList: TStringList;

  function CountHeaderTokens(const aPartIndex: Integer; const aHasPrevPart, aHasNextPart: Boolean; const aFiles: TStringList): Int64;
  var
    lHeaderText: string;
    lHeaderToken: Int64;
  begin
    lHeaderText := BuildPartHeader(aProject, aOutputFileName, aPartIndex, aHasPrevPart, aHasNextPart);
    if aProject.IncludeFileStructure then
      lHeaderText := lHeaderText + BuildFileMapText(aProject.SourceDir, aFiles);
    if not TokenizeText(lHeaderText, lHeaderToken) then
      Exit(High(Int64));
    Result := lHeaderToken;
  end;

  procedure FallbackToSingleOutput;
  begin
    Writeln('Tokenization failed while calculating part budgets. Falling back to single output.');
    MergeFiles(lFileList, lOutput, aProject.PasInterfaceSectionOnly);
    lOutput.WriteBom;
    lOutput.SaveToFile(aOutputFileName, TEncoding.UTF8);
    Exit;
  end;

  procedure WritePart(const aPartIndex: Integer; const aPartFiles, aPartSections: TStringList; const aHasPrevPart, aHasNextPart: Boolean);
  var
    lPartOutput: TStringList;
    lMapText: string;
  begin
    lPartOutput := TStringList.Create;
    try
      lPartOutput.Add(BuildPartHeader(aProject, aOutputFileName, aPartIndex, aHasPrevPart, aHasNextPart));
      if aProject.IncludeFileStructure then
      begin
        lMapText := BuildFileMapText(aProject.SourceDir, aPartFiles);
        if lMapText <> '' then
          lPartOutput.Add(lMapText);
      end;

      for var lRow in aPartSections do
        lPartOutput.Add(lRow);

      lOutputPath := BuildPartFilePath(aOutputFileName, aPartIndex);
      lPartOutput.WriteBom;
      lPartOutput.SaveToFile(lOutputPath, TEncoding.UTF8);
    finally
      lPartOutput.Free;
    end;
  end;

begin
  CleanupOutputArtifacts(aOutputFileName, aMaxTokenPerFile > 0);
  gc(lOutput, TStringList.Create);
  gc(lFileList, TStringList.Create);
  gc(lSourceSections, TStringList.Create);
  lFileList.Sorted := True;
  lFileList.CaseSensitive := False;
  lFileList.Duplicates := dupIgnore;

  if (aProject.FileList<>'') and TFile.Exists(aProject.FileList) then
  begin
    lProjectFileList := TStringList.Create;
    gc(lProjectFileList);
    lProjectFileList.LoadFromFile(aProject.FileList, TEncoding.utf8);
    for var lRow in lProjectFileList do
      lFileList.Add(lRow);
  end else
    GatherFiles(aProject.SourceDir, aProject.FileMask, aProject.Recursive, lFileList);

  if aMaxTokenPerFile <= 0 then
  begin
    if Trim(aProject.Description) <> '' then
    begin
      lOutput.Add('# ' + aProject.Name);
      lOutput.Add(aProject.Description);
      lOutput.Add('');
      lOutput.Add('---');
      lOutput.Add('');
    end;
    if aProject.IncludeFileStructure and (aProject.SourceDir <> '') then
    begin
      lOutput.Add('## Project Structure');
      lOutput.Add('```');
      lOutput.Add(GenerateFileStructureTree(aProject.SourceDir));
      lOutput.Add('```');
      lOutput.Add('');
      lOutput.Add('---');
      lOutput.Add('');
    end;
    MergeFiles(lFileList, lOutput, aProject.PasInterfaceSectionOnly);
    lOutput.WriteBom;
    lOutput.SaveToFile(aOutputFileName, TEncoding.UTF8);
    Exit;
  end;

  SetLength(lSectionTokens, lFileList.Count);
  lCanSplit := True;
  for var i := 0 to lFileList.Count - 1 do
  begin
    lSectionText := RenderFileSection(lFileList[i], aProject.PasInterfaceSectionOnly);
    lSourceSections.Add(lSectionText);
    if not TokenizeText(lSectionText, lSectionToken) then
      lCanSplit := False;
    lSectionTokens[i] := lSectionToken;
  end;

  if not lCanSplit then
  begin
    Writeln('Python tokenizer unavailable (py/python + tiktoken missing). Falling back to single output.');
    MergeFiles(lFileList, lOutput, aProject.PasInterfaceSectionOnly);
    lOutput.WriteBom;
    lOutput.SaveToFile(aOutputFileName, TEncoding.UTF8);
    Exit;
  end;

  gc(lPartFiles, TStringList.Create);
  gc(lPartSections, TStringList.Create);
  lPartIndex := 1;
  lCurrentPartTokens := 0;
  lFileCount := lSourceSections.Count;

  for var i := 0 to lFileList.Count - 1 do
  begin
    lPartFiles.Add(lFileList[i]);
    lPartSections.Add(lSourceSections[i]);
    lCurrentPartTokens := lCurrentPartTokens + lSectionTokens[i];

    lCandidateHeaderTokens := CountHeaderTokens(lPartIndex, lPartIndex > 1, i < lFileCount - 1, lPartFiles);
    if lCandidateHeaderTokens = High(Int64) then
      FallbackToSingleOutput;
    lCandidateTokens := lCurrentPartTokens + lCandidateHeaderTokens;
    if lCandidateTokens <= aMaxTokenPerFile then
      Continue;

    if lPartFiles.Count = 1 then
    begin
      if lSectionTokens[i] > aMaxTokenPerFile then
        Writeln(Format('Warning: file section `%s` exceeds token limit and will be emitted oversized in its own part.', [lFileList[i]]))
      else
        Writeln(Format('Warning: file `%s` with part header exceeds token limit and will be emitted as oversized single-file part.', [lFileList[i]]));

      WritePart(lPartIndex, lPartFiles, lPartSections, lPartIndex > 1, i < lFileCount - 1);
      lPartIndex := lPartIndex + 1;
      lPartFiles.Clear;
      lPartSections.Clear;
      lCurrentPartTokens := 0;
      Continue;
    end;

    lPartSections.Delete(lPartSections.Count - 1);
    lPartFiles.Delete(lPartFiles.Count - 1);
    lCurrentPartTokens := lCurrentPartTokens - lSectionTokens[i];

    if lPartFiles.Count > 0 then
      WritePart(lPartIndex, lPartFiles, lPartSections, lPartIndex > 1, True);

    lPartIndex := lPartIndex + 1;
    lPartFiles.Clear;
    lPartSections.Clear;
    lCurrentPartTokens := 0;

    lPartFiles.Add(lFileList[i]);
    lPartSections.Add(lSourceSections[i]);
    lCurrentPartTokens := lSectionTokens[i];
    lCandidateHeaderTokens := CountHeaderTokens(lPartIndex, lPartIndex > 1, i < lFileCount - 1, lPartFiles);
    if lCandidateHeaderTokens = High(Int64) then
      FallbackToSingleOutput;
    if (lCurrentPartTokens + lCandidateHeaderTokens) <= aMaxTokenPerFile then
      Continue;

    if lSectionTokens[i] > aMaxTokenPerFile then
      Writeln(Format('Warning: file section `%s` exceeds token limit and will be emitted oversized in its own part.', [lFileList[i]]))
    else
      Writeln(Format('Warning: file `%s` with part header exceeds token limit and will be emitted as oversized single-file part.', [lFileList[i]]));
    WritePart(lPartIndex, lPartFiles, lPartSections, lPartIndex > 1, i < lFileCount - 1);
    lPartIndex := lPartIndex + 1;
    lPartFiles.Clear;
    lPartSections.Clear;
    lCurrentPartTokens := 0;
  end;

if lPartFiles.Count > 0 then
    WritePart(lPartIndex, lPartFiles, lPartSections, lPartIndex > 1, False);
end;
end.
