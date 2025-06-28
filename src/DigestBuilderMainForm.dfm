object FileMergerMainFrm: TFileMergerMainFrm
  Left = 0
  Top = 0
  Caption = 'File Merger'
  ClientHeight = 353
  ClientWidth = 836
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  OnCreate = FormCreate
  TextHeight = 15
  object pnlRight: TPanel
    Left = 209
    Top = 0
    Width = 627
    Height = 353
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 0
    object edProjectName: TEdit
      AlignWithMargins = True
      Left = 3
      Top = 25
      Width = 621
      Height = 23
      Align = alTop
      TabOrder = 1
    end
    object StaticText1: TStaticText
      AlignWithMargins = True
      Left = 3
      Top = 3
      Width = 621
      Height = 19
      Margins.Bottom = 0
      Align = alTop
      Caption = 'Project name:'
      TabOrder = 0
    end
    object edSrcDir: TJvDirectoryEdit
      AlignWithMargins = True
      Left = 3
      Top = 76
      Width = 621
      Height = 23
      Align = alTop
      TabOrder = 3
      Text = ''
    end
    object StaticText2: TStaticText
      AlignWithMargins = True
      Left = 3
      Top = 54
      Width = 621
      Height = 19
      Margins.Bottom = 0
      Align = alTop
      Caption = 'Source directory'
      TabOrder = 2
    end
    object pnlFileMask: TPanel
      Left = 0
      Top = 102
      Width = 627
      Height = 51
      Margins.Right = 40
      Align = alTop
      AutoSize = True
      BevelOuter = bvNone
      TabOrder = 4
      DesignSize = (
        627
        51)
      object edFileMask: TComboBox
        AlignWithMargins = True
        Left = 3
        Top = 25
        Width = 584
        Height = 23
        Margins.Right = 40
        Align = alTop
        TabOrder = 0
      end
      object StaticText3: TStaticText
        AlignWithMargins = True
        Left = 3
        Top = 3
        Width = 621
        Height = 19
        Margins.Bottom = 0
        Align = alTop
        Caption = 'File Mask (use | as separator)'
        TabOrder = 2
      end
      object btnDeleteFileMask: TBitBtn
        Left = 597
        Top = 25
        Width = 26
        Height = 23
        Hint = 'Delete current file mask'
        Anchors = [akTop, akRight]
        ParentShowHint = False
        ShowHint = True
        TabOrder = 1
      end
    end
    object memProjectDesc: TMemo
      AlignWithMargins = True
      Left = 3
      Top = 178
      Width = 621
      Height = 60
      Align = alTop
      TabOrder = 6
    end
    object StaticText4: TStaticText
      AlignWithMargins = True
      Left = 3
      Top = 156
      Width = 621
      Height = 19
      Margins.Bottom = 0
      Align = alTop
      Caption = 'Project Description:'
      TabOrder = 5
    end
    object chkIncludeFileStructure: TCheckBox
      AlignWithMargins = True
      Left = 3
      Top = 244
      Width = 621
      Height = 30
      Margins.Bottom = 0
      Align = alTop
      Caption = 
        'Include file structure tree in output (Ignores common delphi tem' +
        'p patterns and also a simple .gitignore parser)'
      Checked = True
      State = cbChecked
      TabOrder = 7
      WordWrap = True
    end
    object btnRun: TBitBtn
      AlignWithMargins = True
      Left = 3
      Top = 313
      Width = 621
      Height = 40
      Margins.Top = 9
      Align = alTop
      Caption = '&Start process'
      TabOrder = 9
      WordWrap = True
      OnClick = btnRunClick
    end
    object ckbInterfaceOnly: TCheckBox
      AlignWithMargins = True
      Left = 3
      Top = 274
      Width = 621
      Height = 30
      Margins.Top = 0
      Margins.Bottom = 0
      Align = alTop
      Caption = 
        'Interface only - for *.pas files ignore the implementation secti' +
        'on and the copyright information before the interface section'
      TabOrder = 8
      WordWrap = True
    end
  end
  object pnlLeft: TPanel
    Left = 0
    Top = 0
    Width = 209
    Height = 353
    Align = alLeft
    BevelOuter = bvNone
    TabOrder = 1
    object lblProjects: TLabel
      Left = 8
      Top = 3
      Width = 45
      Height = 15
      Caption = 'Projects:'
    end
    object lstProjects: TListBox
      Left = 8
      Top = 24
      Width = 193
      Height = 234
      ItemHeight = 15
      PopupMenu = pmProjects
      Sorted = True
      TabOrder = 0
      OnClick = lstProjectsClick
      OnDblClick = lstProjectsDblClick
      OnKeyDown = lstProjectsKeyDown
    end
    object chkCopyOutputToClipboard: TCheckBox
      Left = 8
      Top = 270
      Width = 193
      Height = 17
      Caption = 'Copy output file to clipboard'
      TabOrder = 1
    end
  end
  object pmProjects: TPopupMenu
    Left = 104
    Top = 96
    object DeleteProject1: TMenuItem
      Caption = 'Delete Project'
      OnClick = DeleteProject1Click
    end
    object RefreshProjects1: TMenuItem
      Caption = 'Refresh Project List'
      OnClick = RefreshProjects1Click
    end
  end
end
