(**************************************************************)
(* Delphi Code Coverage                                       *)
(*                                                            *)
(* A quick hack of a Code Coverage Tool for Delphi 2010       *)
(* by Christer Fahlgren and Nick Ring                         *)
(**************************************************************)
(* Licensed under Mozilla Public License 1.1                  *)
(**************************************************************)

unit SonarCoverageReport;

interface

{$INCLUDE CodeCoverage.inc}

uses
  I_Report,
  I_CoverageStats,
  I_CoverageConfiguration,
  ClassInfoUnit,
  I_LogManager,
  JclSimpleXml,
  uConsoleOutput;

type
  THtmlDetails = record
    LinkFileName: string;
    LinkName: string;
    HasFile: Boolean;
  end;

type
  TCoverageStatsProc = function(const ACoverageModule: ICoverageStats): THtmlDetails of object;

type
  TSonarCoverageReport = class(TInterfacedObject, IReport)
  private
    FCoverageConfiguration : ICoverageConfiguration;

    function FindSourceFile(const ACoverageUnit: ICoverageStats;
                            var HtmlDetails: THtmlDetails): string;


    procedure GenerateCoverageTable(const ACoverageModule: ICoverageStats;
                                    Const aFileElement: TJclSimpleXMLElem; // Pointer
                                    const AInputFile: TextFile);



    function GenerateUnitReport(const ACoverageUnit: ICoverageStats;
                                const AXML: TJclSimpleXML): THtmlDetails;

  public
    constructor Create(const ACoverageConfiguration: ICoverageConfiguration);

    procedure Generate(
      const ACoverage: ICoverageStats;
      const AModuleInfoList: TModuleList;
      const ALogManager: ILogManager);
  end;



implementation

uses
  SysUtils,
  JclFileUtils;

procedure TSonarCoverageReport.Generate(
  const ACoverage: ICoverageStats;
  const AModuleInfoList: TModuleList;
  const ALogManager: ILogManager);
var
  OutputFile: TextFile;
  OutputFileName: string;
  XML: TJclSimpleXML;
  AllElement: TJclSimpleXMLElem; // Pointer
  StatIndex : integer;
  CurrentModule : ICoverageStats;
  CurrentUnit   : ICoverageStats;
  HtmlDetails : THtmlDetails;
  ModuleIndex : integer;
  UnitIndex: Integer;
begin
  ALogManager.Log('Generating Sonar Generic Test Coverage report');

  if (FCoverageConfiguration.SourcePaths.Count > 0) then
    VerboseOutput('Source dir: ' + FCoverageConfiguration.SourcePaths.Strings[0])
  else
    VerboseOutput('Source dir: <none>');

  VerboseOutput('Output dir: ' + FCoverageConfiguration.OutputDir);

  XML := TJclSimpleXML.Create;
  try
    XML.Root.Name := 'coverage';

    XML.Root.Properties.Add('version', '1');

    for ModuleIndex := 0 to Pred(ACoverage.Count) do
    begin
      CurrentModule := ACoverage.CoverageReport[ModuleIndex];

      for UnitIndex := 0 to pred(CurrentModule.Count) do
      Begin
        CurrentUnit := CurrentMOdule.CoverageReport[UnitIndex];
        GenerateUnitReport(CurrentUnit, XML);
      End;

    end;

    XML.SaveToFile(
      PathAppend(FCoverageConfiguration.OutputDir, 'SonarCodeCoverage.xml')
    );
  finally
    XML.Free;
  end;

end;



function TSonarCoverageReport.GenerateUnitReport(
  const ACoverageUnit: ICoverageStats;
    const AXML: TJclSimpleXML): THtmlDetails;
var
  SourceFileName: string;
  InputFile: TextFile;
  FileElement: TJclSimpleXMLElem; // Pointer

begin
  Result.HasFile:= False;
  Result.LinkFileName:= ACoverageUnit.ReportFileName + '.html';
  Result.LinkName:= ACoverageUnit.Name;

  if FCoverageConfiguration.ExcludedUnits.IndexOf(StringReplace(ExtractFileName(ACoverageUnit.Name), ExtractFileExt(ACoverageUnit.Name), '', [rfReplaceAll, rfIgnoreCase])) < 0 then
  try
    SourceFileName := FindSourceFile(ACoverageUnit, Result);

    FileElement := aXML.Root.Items.add('file');
    FileElement.Properties.Add('path', SourceFileName);

    AssignFile(InputFile, SourceFileName);
    try
      try
        System.FileMode := fmOpenRead;
        Reset(InputFile);
      except
        on E: EInOutError do
        begin
          ConsoleOutput(
            'Exception during generation of unit coverage for:' + ACoverageUnit.Name
            + ' could not open:' + SourceFileName
          );
          ConsoleOutput('Current directory:' + GetCurrentDir);
          raise;
        end;
      end;
      GenerateCoverageTable(ACoverageUnit, FileElement, InputFile);
      Result.HasFile := True;
    finally
      CloseFile(InputFile);
    end;
  except
    on E: EInOutError do
      ConsoleOutput(
        'Exception during generation of unit coverage for:' + ACoverageUnit.Name
        + ' exception:' + E.message
      )
    else
      raise;
  end;
end;


constructor TSonarCoverageReport.Create(
  const ACoverageConfiguration: ICoverageConfiguration);
begin
  inherited Create;
  FCoverageConfiguration := ACoverageConfiguration;
end;

function TSonarCoverageReport.FindSourceFile(
  const ACoverageUnit: ICoverageStats;
  var HtmlDetails: THtmlDetails): string;
var
  SourceFound: Boolean;
  CurrentSourcePath: string;
  SourcePathIndex: Integer;
  UnitIndex: Integer;
  ACoverageModule: ICoverageStats;
begin
  SourceFound := False;

  SourcePathIndex := 0;
  while (SourcePathIndex < FCoverageConfiguration.SourcePaths.Count)
  and not SourceFound do
  begin
    CurrentSourcePath := FCoverageConfiguration.SourcePaths[SourcePathIndex];
    Result := PathAppend(CurrentSourcePath, ACoverageUnit.Name);

    if not FileExists(Result) then
    begin
      ACoverageModule := ACoverageUnit.Parent;

      UnitIndex := 0;
      while (UnitIndex < ACoverageModule.Count)
      and not SourceFound do
      begin
        Result := PathAppend(
          PathAppend(
            CurrentSourcePath,
            ExtractFilePath(ACoverageModule.CoverageReport[UnitIndex].Name)
          ),
          ACoverageUnit.Name
        );

        if FileExists(Result) then
        begin
          HtmlDetails.LinkName := PathAppend(
            ExtractFilePath(ACoverageModule.CoverageReport[UnitIndex].Name),
            HtmlDetails.LinkName
          );
          SourceFound := True;
        end;

        Inc(UnitIndex, 1);
      end;
    end
    else
      SourceFound := True;

    Inc(SourcePathIndex, 1);
  end;

  if (not SourceFound) then
    Result := ACoverageUnit.Name;
end;

procedure TSonarCoverageReport.GenerateCoverageTable(
  const ACoverageModule: ICoverageStats;
  Const aFileElement: TJclSimpleXMLElem; // Pointer
  const AInputFile: TextFile);
var
  LineCoverage     : TCoverageLine;
  InputLine        : string;
  LineCoverageIter : Integer;
  LineCount        : Integer;
  LineElement      : TJclSimpleXMLElem; // Pointer

begin
  LineCoverageIter := 0;
  LineCount := 1;


  while (not Eof(AInputFile)) do
  begin
    ReadLn(AInputFile, InputLine);
    LineCoverage := ACoverageModule.CoverageLine[LineCoverageIter];

    if (LineCount = LineCoverage.LineNumber) then
    begin
      LineElement := aFileElement.Items.Add('lineToCover');

      LineElement.Properties.Add('lineNumber',IntToStr(LineCount));
      if linecoverage.IsCovered then
      begin
        LineElement.Properties.Add('covered','true');
      end
      else
      begin
        LineElement.Properties.Add('covered','false');
      end;
      Inc(LineCoverageIter);
    end;

    Inc(LineCount);
  end;
end;

end.

