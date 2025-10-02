program DigestBuilder;

uses
  madExcept,
  madLinkDisAsm,
  madListHardware,
  madListProcesses,
  madListModules,
  Vcl.Forms,
  DigestBuilderMainForm in 'DigestBuilderMainForm.pas' {FileMergerMainFrm},
  FileMergerLogic in 'FileMergerLogic.pas',
  PasUnitInterfaceCleaner in 'PasUnitInterfaceCleaner.pas',
  CliProcessor in 'CliProcessor.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TFileMergerMainFrm, FileMergerMainFrm);
  Application.Run;
end.
