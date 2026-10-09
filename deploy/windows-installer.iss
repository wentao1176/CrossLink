#ifndef AppVersion
#define AppVersion "0.3.0"
#endif
#ifndef Channel
#define Channel "production"
#endif
#if Channel == "qa"
#define AppLabel "CrossLink QA"
#define AppIdentity "CrossLink-QA"
#define Suffix "-qa"
#else
#define AppLabel "CrossLink"
#define AppIdentity "CrossLink"
#define Suffix ""
#endif
[Setup]
AppId={#AppIdentity}
AppName={#AppLabel}
AppVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\{#AppIdentity}
DefaultGroupName={#AppLabel}
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=CrossLink-{#AppVersion}-windows-x64{#Suffix}-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\crosslink.exe
CloseApplications=yes
RestartApplications=no
[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\{#AppLabel}"; Filename: "{app}\crosslink.exe"
Name: "{group}\卸载 {#AppLabel}"; Filename: "{uninstallexe}"
[Run]
Filename: "{app}\crosslink.exe"; Description: "启动 {#AppLabel}"; Flags: nowait postinstall skipifsilent
[UninstallRun]
Filename: "{app}\crosslink.exe"; Parameters: "--remove-startup"; Flags: runhidden waituntilterminated; RunOnceId: "RemoveCrossLinkStartup"
