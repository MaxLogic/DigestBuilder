program DigestBuilder;

uses
  Vcl.Forms,
  DigestBuilderMainForm in 'DigestBuilderMainForm.pas' {FileMergerMainFrm},
  FileMergerLogic in 'FileMergerLogic.pas',
  PasUnitInterfaceCleaner in 'PasUnitInterfaceCleaner.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TFileMergerMainFrm, FileMergerMainFrm);
  Application.Run;
end.
