unit DigestBuilderMainForm;

interface

uses
  FileMergerLogic,
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.Mask, JvExMask,
  Vcl.Buttons, Vcl.ExtCtrls, Vcl.Menus, Vcl.Clipbrd, JvToolEdit;


type
  TFileMergerMainFrm = class(TForm)
    pnlRight: TPanel;
    StaticText1: TStaticText;
    edProjectName: TEdit;
    StaticText2: TStaticText;
    edSrcDIr: TJvDirectoryEdit;
    StaticText3: TStaticText;
    edFileMask: TComboBox;
    btnRun: TBitBtn;
    pnlLeft: TPanel;
    lblProjects: TLabel;
    lstProjects: TListBox;
    pmProjects: TPopupMenu;
    DeleteProject1: TMenuItem;
    RefreshProjects1: TMenuItem;
    StaticText4: TStaticText;
    memProjectDesc: TMemo;
    chkIncludeFileStructure: TCheckBox;
    chkCopyOutputToClipboard: TCheckBox;
    pnlFileMask: TPanel;
    btnDeleteFileMask: TBitBtn;
    ckbInterfaceOnly: TCheckBox;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnRunClick(Sender: TObject);
    procedure lstProjectsClick(Sender: TObject);
    procedure lstProjectsDblClick(Sender: TObject);
    procedure DeleteProject1Click(Sender: TObject);
    procedure lstProjectsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure RefreshProjects1Click(Sender: TObject);
    procedure btnDeleteFileMaskClick(Sender: TObject);
    procedure chkCopyOutputToClipboardClick(Sender: TObject);
  private
    // Business logic components
    fSettings: TFileMergerSettings;
    fProjectManager: TProjectManager;
    fFileProcessor: TFileProcessor;

    // UI-related methods
    procedure LoadProjects;
    procedure SaveCurrentProject;
    procedure LoadProject(const aProjectName: string);
    procedure DeleteSelectedProject;
    procedure ClearProjectForm;
    function GetIndexOfProject(const aName: String): Integer;
  end;

var
  FileMergerMainFrm: TFileMergerMainFrm;

implementation

uses
  autoFree, autoHourGlass, system.strutils, system.masks,
  MaxLogic.ioUtils;

{$R *.dfm}

procedure TFileMergerMainFrm.FormCreate(Sender: TObject);
var
  lLastProject: string;
  lIndex: Integer;
begin
  // Initialize business logic components
  fSettings := TFileMergerSettings.Create;
  fProjectManager := TProjectManager.Create(fSettings);
  fFileProcessor := TFileProcessor.Create(fSettings);

  // Load global file mask list
  edFileMask.Items.CommaText := fSettings.LoadFileMaskList;

  // Load projects list
  LoadProjects;

  // Restore clipboard checkbox state
  chkCopyOutputToClipboard.Checked := fSettings.GetCopyToClipboardFlag;

  // Select last used project
  lLastProject := fSettings.GetLastSelectedProject;
  if (lLastProject <> '') and (lstProjects.Items.Count > 0) then
  begin
    lIndex := GetIndexOfProject(lLastProject);
    if lIndex < 0 then
      lIndex := 0;

    lstProjects.ItemIndex := lIndex;
    LoadProject(lstProjects.Items[lIndex]);
  end
  else if lstProjects.Items.Count > 0 then
  begin
    lstProjects.ItemIndex := 0;
    LoadProject(lstProjects.Items[0]);
    fSettings.SaveLastSelectedProject(lstProjects.Items[0]);
  end;
end;

procedure TFileMergerMainFrm.FormDestroy(Sender: TObject);
begin
  fSettings.Free;
  fProjectManager.Free;
  fFileProcessor.Free;
end;

procedure TFileMergerMainFrm.btnRunClick(Sender: TObject);
var
  lProject: TProject;
  lOutputFile: string;
begin
  autohourglass.MakeCHG;

  // Default project name if empty
  lProject:= default(TProject);
  lProject.Name := Trim(edProjectName.Text);
  if lProject.Name = '' then
    lProject.Name := 'Project1';

  // Save project settings and update file mask list
  SaveCurrentProject;
  if (edFileMask.Text <> '') and (edFileMask.Items.IndexOf(edFileMask.Text) < 0) then
    edFileMask.Items.Add(edFileMask.Text);
  fSettings.SaveFileMaskList(edFileMask.Items);

  // Set up project data
  lProject.SourceDir := edSrcDir.Directory;
  lProject.FileMask := edFileMask.Text;
  lProject.Description := memProjectDesc.Lines.Text;
  lProject.IncludeFileStructure := chkIncludeFileStructure.Checked;
  lProject.PasInterfaceSectionOnly:= ckbInterfaceOnly.Checked;

  // Process project
  lOutputFile := CombinePath([GetInstallDir, 'Output', lProject.Name + '.md']);
  fFileProcessor.ProcessProject(lProject, lOutputFile);

  // Copy to clipboard if enabled
  if chkCopyOutputToClipboard.Checked then
    Clipboard.AsText := lOutputFile;

  Beep;
end;

procedure TFileMergerMainFrm.DeleteProject1Click(Sender: TObject);
begin
  DeleteSelectedProject;
end;

procedure TFileMergerMainFrm.DeleteSelectedProject;
var
  lIndex: Integer;
begin
  lIndex := lstProjects.ItemIndex;
  if lIndex < 0 then
    Exit;

  // Remove project from INI and list
  fProjectManager.DeleteProject(lstProjects.Items[lIndex]);
  lstProjects.Items.Delete(lIndex);

  // Adjust selection
  if lstProjects.Items.Count > 0 then
  begin
    if lIndex >= lstProjects.Items.Count then
      lIndex := lstProjects.Items.Count - 1;
    lstProjects.ItemIndex := lIndex;
    LoadProject(lstProjects.Items[lIndex]);
    fSettings.SaveLastSelectedProject(lstProjects.Items[lIndex]);
  end
  else
  begin
    ClearProjectForm;
    fSettings.SaveLastSelectedProject('');
  end;
end;

procedure TFileMergerMainFrm.btnDeleteFileMaskClick(Sender: TObject);
begin
  // Remove selected file mask and update INI
  if edFileMask.ItemIndex >= 0 then
  begin
    edFileMask.Items.Delete(edFileMask.ItemIndex);
    fSettings.SaveFileMaskList(edFileMask.Items);
  end;
end;

procedure TFileMergerMainFrm.chkCopyOutputToClipboardClick(Sender: TObject);
begin
  if not chkCopyOutputToClipboard.Focused then
    Exit;// note: this event is triggered also when we set the checked property in code...
  // Save checkbox state when user changes it
  fSettings.SetCopyToClipboardFlag(chkCopyOutputToClipboard.Checked);
end;

procedure TFileMergerMainFrm.LoadProjects;
var
  lProjectList: TStringList;
begin
  lstProjects.Items.Clear;
  gc(lProjectList, fProjectManager.LoadProjectList);
  lstProjects.Items.AddStrings(lProjectList);
end;

procedure TFileMergerMainFrm.lstProjectsClick(Sender: TObject);
begin
  if lstProjects.ItemIndex >= 0 then
  begin
    LoadProject(lstProjects.Items[lstProjects.ItemIndex]);
    fSettings.SaveLastSelectedProject(lstProjects.Items[lstProjects.ItemIndex]);
  end;
end;

procedure TFileMergerMainFrm.lstProjectsDblClick(Sender: TObject);
begin
  if lstProjects.ItemIndex >= 0 then
  begin
    LoadProject(lstProjects.Items[lstProjects.ItemIndex]);
    fSettings.SaveLastSelectedProject(lstProjects.Items[lstProjects.ItemIndex]);
    btnRun.Click;
  end;
end;

procedure TFileMergerMainFrm.lstProjectsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_DELETE) and (lstProjects.ItemIndex >= 0) then
    DeleteSelectedProject;
end;

procedure TFileMergerMainFrm.LoadProject(const aProjectName: string);
var
  lProject: TProject;
begin
  fProjectManager.LoadProject(aProjectName, lProject);

  edProjectName.Text := lProject.Name;
  edSrcDir.Directory := lProject.SourceDir;
  edFileMask.Text := lProject.FileMask;
  memProjectDesc.Lines.Text := lProject.Description;
  chkIncludeFileStructure.Checked := lProject.IncludeFileStructure;
  ckbInterfaceOnly.Checked :=lProject.PasInterfaceSectionOnly;
end;

procedure TFileMergerMainFrm.RefreshProjects1Click(Sender: TObject);
var
  lSelectedProject: string;
begin
  if lstProjects.ItemIndex >= 0 then
    lSelectedProject := lstProjects.Items[lstProjects.ItemIndex]
  else
    lSelectedProject := '';

  LoadProjects;

  if lSelectedProject <> '' then
  begin
    var lIndex := GetIndexOfProject(lSelectedProject);
    if lIndex >= 0 then
    begin
      lstProjects.ItemIndex := lIndex;
      LoadProject(lSelectedProject);
    end
    else if lstProjects.Items.Count > 0 then
    begin
      lstProjects.ItemIndex := 0;
      LoadProject(lstProjects.Items[0]);
      fSettings.SaveLastSelectedProject(lstProjects.Items[0]);
    end
    else
      ClearProjectForm;
  end
  else if lstProjects.Items.Count > 0 then
  begin
    lstProjects.ItemIndex := 0;
    LoadProject(lstProjects.Items[0]);
    fSettings.SaveLastSelectedProject(lstProjects.Items[0]);
  end
  else
    ClearProjectForm;
end;

procedure TFileMergerMainFrm.SaveCurrentProject;
var
  lProject: TProject;
  lProjectName: string;
begin
  lProjectName := Trim(edProjectName.Text);
  while StartsText('$', lProjectName) do
    Delete(lProjectName, 1, 1);
  lProjectName := Trim(lProjectName);

  if lProjectName <> edProjectName.Text then
    edProjectName.Text := lProjectName;

  if lProjectName = '' then
    Exit;

  // Save project data
  lProject.Name := lProjectName;
  lProject.SourceDir := edSrcDir.Directory;
  lProject.FileMask := edFileMask.Text;
  lProject.Description := memProjectDesc.Lines.Text;
  lProject.IncludeFileStructure := chkIncludeFileStructure.Checked;
  lProject.PasInterfaceSectionOnly:= ckbInterfaceOnly.Checked;

  fProjectManager.SaveProject(lProject);

  // Update project list if new
  if GetIndexOfProject(lProjectName) < 0 then
  begin
    lstProjects.ItemIndex := lstProjects.Items.Add(lProjectName);
    fSettings.SaveLastSelectedProject(lProjectName);
  end;
end;

procedure TFileMergerMainFrm.ClearProjectForm;
begin
  edProjectName.Text := '';
  edSrcDir.Directory := '';
  edFileMask.Text := '';
  memProjectDesc.Lines.Clear;
  chkIncludeFileStructure.Checked := False;
  ckbInterfaceOnly.Checked :=False;
end;

function TFileMergerMainFrm.GetIndexOfProject(const aName: String): Integer;
var
  lTempList: TStringList;
begin
  gc(lTempList, TStringList.Create);
  lTempList.Assign(lstProjects.Items);
  lTempList.CaseSensitive := False;
  Result := lTempList.IndexOf(aName);
end;

end.
