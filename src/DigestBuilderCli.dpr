program DigestBuilderCli;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  FileMergerLogic in 'FileMergerLogic.pas',
  PasUnitInterfaceCleaner in 'PasUnitInterfaceCleaner.pas',
  CliProcessor in 'CliProcessor.pas';


begin
  try
    TCliProcessor.Execute
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
