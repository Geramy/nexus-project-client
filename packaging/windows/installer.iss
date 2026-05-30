; Inno Setup script for Nexus Projects (Windows installer).
; Compiled in CI: ISCC.exe /DAppVersion=<version> packaging\windows\installer.iss
; Paths are relative to this .iss file's directory.

#define AppName "Nexus Projects"
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppPublisher "Geramy Loveless DBA Nexus Projects"
#define AppExeName "nexus_projects_client.exe"
#define BuildDir "..\..\build\windows\x64\runner\Release"

[Setup]
; Keep AppId stable across versions so upgrades replace in place.
AppId={{A7E2C9F4-3B1D-4E6A-8C2F-9D5B7A1E0C34}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://nexus-projects.ai
DefaultDirName={autopf}\Nexus Projects
DefaultGroupName=Nexus Projects
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#AppExeName}
OutputDir=..\..\dist
OutputBaseFilename=nexus_projects_client-{#AppVersion}-windows-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\Nexus Projects"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,Nexus Projects}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Nexus Projects"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,Nexus Projects}"; Flags: nowait postinstall skipifsilent
