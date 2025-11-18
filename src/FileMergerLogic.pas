unit FileMergerLogic;

interface

uses
  System.SysUtils, System.Classes, System.IniFiles;


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

    // Directory tree generation helpers
    function IsCommonDelphiTemp(const aName: string; aIsDir: Boolean): Boolean;
    function ShouldIgnore(const aName: string; const aIgnoreRules: TArray<string>): Boolean;
    procedure AddDirToTree(const aDir, aRootDir: string; const aLevel: Integer;
                          aOutput: TStringList);
  public
    constructor Create(aSettings: TFileMergerSettings);

    // File gathering and processing
    procedure GatherFiles(const aSourceDir, aFileMask: string; aRecursive: Boolean; aFileList: TStringList);

    procedure MergeFiles(aFileList, aOutput: TStringList; aPasInterfaceSectionOnly: boolean);
    function ExtractInterfaceSetionFrompasFile(const aPasFileContent: String): String;
    function GenerateFileStructureTree(const aRootDir: string): string;

    // Main processing function
    procedure ProcessProject(const aProject: TProject; const aOutputFileName: String);
  end;

implementation

uses
  PasUnitInterfaceCleaner, System.IOUtils, System.StrUtils, System.Masks, MaxLogic.IOUtils, autoFree;

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
      FindClose(lDirInfo);
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

procedure TFileProcessor.ProcessProject(const aProject: TProject; const aOutputFileName: String);
var
  lFileList, lOutput: TStringList;
begin
  // Set up output and file list
  gc(lOutput, TStringList.Create);
  gc(lFileList, TStringList.Create);
  lFileList.Sorted := True;
  lFileList.CaseSensitive := False;
  lFileList.Duplicates := dupIgnore;

  // Add project header
  if Trim(aProject.Description) <> '' then
  begin
    lOutput.Add('# ' + aProject.Name);
    lOutput.Add(aProject.Description);
    lOutput.Add('');
    lOutput.Add('---');
    lOutput.Add('');
  end;

  // Add file structure if enabled
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

  if (aProject.FileList<>'') and TFile.Exists(aProject.FileList) then
  begin
    var l:= TStringList.Create;
    gc(l);
    l.LoadFromFile(aProject.FileList, TEncoding.utf8);
    for var lRow in l do
      lFileList.Add(lRow); // ensures no duplicates will be present
  end else
    GatherFiles(aProject.SourceDir, aProject.FileMask, aProject.Recursive, lFileList);

  MergeFiles(lFileList, lOutput, aProject.PasInterfaceSectionOnly);
  lOutput.WriteBom;


  lOutput.SaveToFile(aOutputFileName, TEncoding.UTF8);
end;

end.
