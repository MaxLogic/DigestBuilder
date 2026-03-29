unit CliProcessor;

interface

uses
  winApi.Windows, system.SysUtils, system.classes, generics.collections,
  PasUnitInterfaceCleaner , FileMergerLogic ,
  maxLogic.CmdLineParams;

type
  TCliProcessor = class
  private
    fParams: iCmdLineparams ;
    function InternExecute: Boolean;
    procedure ShowHelp;
    procedure DoExport;
    function ParseMaxTokensPerFile(const aValue: string; out aIsValid: Boolean): Int64;
  public
    constructor Create;
    destructor Destroy; override;
    class function Execute: Boolean;
  end;

implementation

uses
  system.ioUtils, system.strUtils,
  autoFree, MaxLogic.strutils, MaxLogic.ioUtils;

{ TCliProcessor }

constructor TCliProcessor.Create;
begin
  inherited;
  fparams:= TCmdLineparams.Create;
end;

destructor TCliProcessor.Destroy;
begin

  inherited;
end;

procedure TCliProcessor.DoExport;
var
  lProject: TProject;
  fn, lOutputFile: string;
  lMaxTokenText: string;
  lFileProcessor: TFileProcessor;
  lSettings: TFileMergerSettings;
  lMaxTokenLimit: Int64;
  lIsValidMaxToken: Boolean;
begin
  lSettings:= TFileMergerSettings.Create;
  gc(lSettings);
  lFileProcessor:= TFileProcessor.Create(lSettings);
  gc(lFileProcessor);

  if not fParams.find('out', lOutputFile) then
    lOutputFile:= 'pas-api-map.md';
  lOutputFile:= ExpandFileName(lOutputFile);

  // Default project name if empty
  lProject:= default(TProject);
  //lProject.Name := Trim(edProjectName.Text);

  fParams.Find('title', lProject.Name);
  fParams.Find('file-list', lProject.FileList);
  if not fParams.find('path', lProject.SourceDir ) then
    lProject.SourceDir := TDirectory.GetCurrentDirectory;
  if not fParams.find('mask', lProject.FileMask ) then
    lProject.FileMask := '*.pas'; // `|` separated list
  lProject.Recursive:= MatchText(fParams.Get('recursive', 'yes'), ['y', 'yes', '1', 't', 'True']);
  if not fParams.Find('description', lProject.Description) then
  begin
    if fParams.find('desc-file', fn) then
  lProject.Description:= TFIle.ReadAllText(fn, TEncoding.Utf8);
  end;

  lProject.IncludeFileStructure := fParams.find('incl-map');
  lProject.PasInterfaceSectionOnly:= not fParams.Find('full') ;
  lIsValidMaxToken := True;
  if fParams.Find('max-token-per-file', lMaxTokenText) then
  begin
    lMaxTokenLimit := ParseMaxTokensPerFile(lMaxTokenText, lIsValidMaxToken);
    if not lIsValidMaxToken then
    begin
      Writeln('Error: invalid value for --max-token-per-file. Use a number (for example 30000), or suffixes K/k or M/m (for example 30k).');
      Exit;
    end;
  end
  else
    lMaxTokenLimit := 0;

  // Process project
  lFileProcessor.ProcessProject(lProject, lOutputFile, lMaxTokenLimit);
end;

function TCliProcessor.ParseMaxTokensPerFile(const aValue: string; out aIsValid: Boolean): Int64;
var
  lText, lSuffix: string;
  lValue: Int64;
begin
  aIsValid := True;
  lText := Trim(aValue);
  if lText = '' then
  begin
    aIsValid := False;
    Exit(0);
  end;

  lSuffix := LowerCase(RightStr(lText, 1));
  if lSuffix = 'k' then
  begin
    if Length(lText) <= 1 then
    begin
      aIsValid := False;
      Exit(0);
    end;
    if not TryStrToInt64(LeftStr(lText, Length(lText) - 1), lValue) then
    begin
      aIsValid := False;
      Exit(0);
    end;
    Exit(lValue * 1000);
  end;

  if lSuffix = 'm' then
  begin
    if Length(lText) <= 1 then
    begin
      aIsValid := False;
      Exit(0);
    end;
    if not TryStrToInt64(LeftStr(lText, Length(lText) - 1), lValue) then
    begin
      aIsValid := False;
      Exit(0);
    end;
    Exit(lValue * 1000000);
  end;

  if not TryStrToInt64(lText, lValue) then
  begin
    aIsValid := False;
    Exit(0);
  end;

  Result := lValue;
end;


class function TCliProcessor.Execute: Boolean;
var
  p: TCliProcessor ;
begin
  p:= TCliProcessor .Create;
  gc(p);
  Result:= p.InternExecute;
end;

function TCliProcessor.InternExecute: Boolean;
begin
  Result:= True;
  if fParams.find('help') then
    showHelp
  else
    DoExport;
end;

procedure TCliProcessor.ShowHelp;

  procedure PrintOpt(const aName, aValue, aDesc: string; const aIsFlag: Boolean = False);
  var
    lFmt: string;
  begin
    if aIsFlag then
      lFmt := '  --%-14s %s (current: %s)'
    else
      lFmt := '  --%-14s %s'#13#10'%-19s(current: %s)';
    if aIsFlag then
      Writeln(Format(lFmt, [aName, aDesc, aValue]))
    else
      Writeln(Format(lFmt, [aName + '=<' + aName + '>', aDesc, '', aValue]));
  end;

var
  lExeName: string;
  lOutFile: string;
  lPath: string;
  lMask: string;
  lDesc: string;
  lDescFile: string;
  lInclMap: Boolean;
  lFull: Boolean;
  lMaxTokens: string;
  lCwd: string;
  lTitle: String;
  s, lFileList: String;
begin
  lExeName := TPath.GetFileName(ParamStr(0));
  lCwd := TDirectory.GetCurrentDirectory;

  // defaults (same logic as DoExport)
  lPath := lCwd;
  lMask := '*.pas';
  lDesc := '';
  lDescFile := '';
  lInclMap := fParams.find('incl-map'); // flag-present = True
  lFull := fParams.find('full');
  lOutFile:= 'pas-api-map.md';

  // override with provided params if present
  if fParams.find('out', s) then
    lOutFile := s;

  if fParams.find('path', s) then
    lPath := s;

  if fParams.find('mask', s) then
    lMask := s;

  if fParams.find('description', s) then
    lDesc := s;

  if fParams.find('desc-file', s) then
    lDescFile := s;

  if fParams.find('title', s) then
    lTitle:= s;
  if fParams.Find('file-list', s) then
    lFileList:= s;
  lMaxTokens := fParams.Get('max-token-per-file', '0');

  Writeln;
  Writeln(Format('%s - Pascal Interface Exporter / File Merger', [lExeName]));
  Writeln('Usage:');
  Writeln(Format('  %s --out=<file> [options]', [lExeName]));
  Writeln;
  Writeln('Options:');

  PrintOpt('out',       IfThen(lOutFile<>'', ExpandFileName(lOutFile), 'pas-api-map.md'),
           'Output file to generate (required)');

  PrintOpt('title', lTitle,
           'Project title');

  PrintOpt('file-list', lFileList,
           'filename of a text file containing a list (one file per row) with files that should be included. Disables scanning for files and the file mask');

  PrintOpt('path',      lPath,
           'Source root folder to scan for .pas files');
  PrintOpt('mask',      lMask,
           'File mask(s) to include. Use | to separate multiple masks, e.g. "*.pas|*.inc"');

  PrintOpt('recursive',      '',
           'Search all sub folders. Default: "yes". '+
          '(accepts "y", "yes", "1", "t", "true" as Values for true)');

  PrintOpt('description', IfThen(lDesc<>'', '"' + lDesc + '"', '<empty>'),
           'Free-form project description text (UTF-8)');
  PrintOpt('desc-file', IfThen(lDescFile<>'', ExpandFileName(lDescFile), '<none>'),
           'Read description text from a UTF-8 file');
  PrintOpt('incl-map',  BoolToStr(lInclMap, True),
           'Include file structure map in the output', True);
  PrintOpt('max-token-per-file', lMaxTokens,
           'Split output into chunks based on max tokens (supports 5000, 30k/K, 2m/M; case-insensitive). Omit to keep single file');
  PrintOpt('full',      BoolToStr(lFull, True),
           'Include full units (not just interface sections)', True);
  PrintOpt('help',      'True',
           'Show this help and exit', True);

  Writeln;
  Writeln('Notes:');
  Writeln('  • When neither --description nor --desc-file is provided, description stays empty.');
  Writeln('  • By default only interface sections are merged; pass --full to include implementation.');
  Writeln('  • --incl-map adds a tree of files/units at the top of the output.');
  Writeln('  • --max-token-per-file=30k (or --max-token-per-file=30000) is optional. Omit it to keep single-file output.');
  Writeln;
  Writeln('Examples:');
  Writeln(Format('  %s --out=merged.md --path="%s" --mask="*.pas|*.inc" --incl-map',
          [lExeName, lCwd]));
  Writeln(Format('  %s --out=api.md --description="Public API" --full', [lExeName]));
  Writeln(Format('  %s --out=report.md --desc-file=about.txt --path=src\core', [lExeName]));
  Writeln;
end;

end.
