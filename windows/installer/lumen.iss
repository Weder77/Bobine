; Lumen — installateur Windows (Inno Setup 6).
; Compilé par le CI :  iscc /DAppVersion=1.1.0 /DSourceDir=<build\windows\x64\runner\Release> lumen.iss
;
; Installation par utilisateur (pas de droits administrateur), ce qui permet
; aussi à la mise à jour intégrée de lancer l'installateur en silence :
;   Lumen-Setup-x.y.z.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /relaunch=1

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{1B672A75-F4A5-489D-B558-2ACB3E3A28ED}
AppName=Lumen
AppVersion={#AppVersion}
AppVerName=Lumen {#AppVersion}
AppPublisher=Lumen
VersionInfoVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\Lumen
DefaultGroupName=Lumen
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
OutputDir=..\..\dist
OutputBaseFilename=Lumen-Setup-{#AppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\lumen.exe
UninstallDisplayName=Lumen
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
MinVersion=10.0

[Languages]
Name: "fr"; MessagesFile: "compiler:Languages\French.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; Files of an older version that the new one no longer ships.
Type: filesandordirs; Name: "{app}\data\flutter_assets"

[Icons]
Name: "{autoprograms}\Lumen"; Filename: "{app}\lumen.exe"
Name: "{autodesktop}\Lumen"; Filename: "{app}\lumen.exe"; Tasks: desktopicon

[Run]
; Normal installation: offer to start Lumen at the end.
Filename: "{app}\lumen.exe"; Description: "{cm:LaunchProgram,Lumen}"; Flags: nowait postinstall skipifsilent
; Update from inside the app (silent): start it again.
Filename: "{app}\lumen.exe"; Flags: nowait; Check: Relaunch

[Code]
function Relaunch: Boolean;
begin
  Result := WizardSilent and (ExpandConstant('{param:relaunch|0}') = '1');
end;
