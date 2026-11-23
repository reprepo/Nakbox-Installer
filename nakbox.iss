; Nakbox installers for Windows (Inno Setup 6).
;
;   ISCC nakbox.iss              -> output\Nakbox-Setup.exe
;       Standard install: needs administrator rights, adds Start menu and
;       desktop shortcuts and an uninstaller.
;   ISCC /DPORTABLE nakbox.iss   -> output\Nakbox-Portable-Setup.exe
;       Portable install: no administrator rights, no shortcuts, no registry.
;       Everything stays in the chosen folder.
;
; Both ask where Nakbox goes (Windows or WSL), the folder and a GitHub token,
; then install.ps1 downloads the newest release from GitHub.
; A Linux machine is installed with nakbox-install.sh instead.
;
; This folder is self-contained: install.ps1 and nakbox-install.sh lie next to
; this file, nothing else from the Nakbox folder is needed.

#ifndef AppVersion
  #define AppVersion "dev"
#endif

[Setup]
AppName=Nakbox
AppVersion={#AppVersion}
AppPublisher=Aksulaattori
AppPublisherURL=https://github.com/Aksulaattori/Nakbox
OutputDir=output
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
DisableWelcomePage=no
DisableDirPage=no
DisableProgramGroupPage=yes
#ifdef PORTABLE
AppId={{5D0E3B52-7C0B-4A3B-9C2B-2F7A7E9D1B02}
OutputBaseFilename=Nakbox-Portable-Setup
PrivilegesRequired=lowest
DefaultDirName={%USERPROFILE}\Nakbox
Uninstallable=no
CreateUninstallRegKey=no
#else
AppId={{8C1F4E0A-6B7D-4B4E-9A55-3E1B6F0C7A21}
OutputBaseFilename=Nakbox-Setup
PrivilegesRequired=admin
; Not Program Files: Nakbox keeps saves, games and settings in its own folder.
DefaultDirName={sd}\Nakbox
UninstallDisplayName=Nakbox
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "finnish"; MessagesFile: "compiler:Languages\Finnish.isl"

[CustomMessages]
english.TargetTitle=Where do you want Nakbox?
english.TargetDesc=Pick the version to install.
english.TargetSub=Setup downloads the newest version from GitHub.
english.TargetWindows=Windows
english.TargetWsl=WSL (Linux version inside Windows Subsystem for Linux)
english.TargetLinuxNote=For a Linux machine, run nakbox-install.sh on that machine instead.
english.WslMissing=WSL has no working Linux distribution on this computer. Install one first (wsl --install) or pick Windows.
english.WslDirTitle=Folder inside WSL
english.WslDirDesc=Where should Nakbox go in Linux?
english.WslDirSub=Give a Linux path. ~ means your Linux home folder.
english.WslDirLabel=Linux folder:
english.WslDirBad=Give a Linux path that starts with / or ~, for example ~/Nakbox.
english.TokenTitle=GitHub token
english.TokenDesc=The Nakbox repository is private.
english.TokenSub=Paste a GitHub token that can read Aksulaattori/Nakbox (GitHub: Settings > Developer settings > Fine-grained tokens, Contents: Read-only). The token is saved in the Nakbox folder so Nakbox can look for updates when it starts. Leave empty if the repository is public.
english.TokenLabel=Token:
english.PythonTitle=Python
english.PythonDesc=Which Python should Nakbox use?
english.PythonSub=These Python installs (3.10 or newer) were found on this computer; for a WSL install they were looked up inside WSL. Nakbox builds its own environment from the one you pick. That Python itself is not changed.
english.NoPowerShell=Could not start PowerShell.
english.InstallFailed=Downloading or setting up Nakbox failed. Details: %TEMP%\nakbox-install.log
english.DesktopIcon=Create a desktop shortcut
english.LaunchNakbox=Start Nakbox
english.RemoveData=Also delete the Nakbox folder with saves, games and settings?%n%n%1
finnish.TargetTitle=Minne haluat Nakboxin?
finnish.TargetDesc=Valitse asennettava versio.
finnish.TargetSub=Asennusohjelma hakee uusimman version GitHubista.
finnish.TargetWindows=Windows
finnish.TargetWsl=WSL (Linux-versio Windows Subsystem for Linuxin sisään)
finnish.TargetLinuxNote=Linux-koneelle Nakbox asennetaan ajamalla nakbox-install.sh sillä koneella.
finnish.WslMissing=Tässä koneessa ei ole toimivaa WSL-jakelua. Asenna se ensin (wsl --install) tai valitse Windows.
finnish.WslDirTitle=Kansio WSL:n sisällä
finnish.WslDirDesc=Minne Nakbox asennetaan Linuxissa?
finnish.WslDirSub=Anna Linux-polku. ~ tarkoittaa Linux-kotikansiotasi.
finnish.WslDirLabel=Linux-kansio:
finnish.WslDirBad=Anna Linux-polku, joka alkaa merkillä / tai ~, esimerkiksi ~/Nakbox.
finnish.TokenTitle=GitHub-token
finnish.TokenDesc=Nakboxin repo on yksityinen.
finnish.TokenSub=Liitä GitHub-token, jolla on lukuoikeus repoon Aksulaattori/Nakbox (GitHub: Settings > Developer settings > Fine-grained tokens, Contents: Read-only). Token tallennetaan Nakbox-kansioon, jotta Nakbox voi hakea päivityksiä käynnistyessään. Jätä tyhjäksi, jos repo on julkinen.
finnish.TokenLabel=Token:
finnish.PythonTitle=Python
finnish.PythonDesc=Mitä Pythonia Nakbox käyttää?
finnish.PythonSub=Koneelta löytyivät nämä Python-asennukset (3.10 tai uudempi); WSL-asennuksessa ne haettiin WSL:n sisältä. Nakbox tekee valitsemastasi Pythonista oman ympäristönsä. Itse Pythoniin ei tehdä muutoksia.
finnish.NoPowerShell=PowerShellin käynnistys ei onnistunut.
finnish.InstallFailed=Nakboxin lataus tai asennus epäonnistui. Lisätiedot: %TEMP%\nakbox-install.log
finnish.DesktopIcon=Luo pikakuvake työpöydälle
finnish.LaunchNakbox=Käynnistä Nakbox
finnish.RemoveData=Poistetaanko myös Nakbox-kansio tallennuksineen, peleineen ja asetuksineen?%n%n%1

[Files]
; Extracted by PrepareToInstall; the Nakbox files themselves come from GitHub.
Source: "install.ps1"; Flags: dontcopy
Source: "nakbox-install.sh"; Flags: dontcopy

#ifndef PORTABLE
[Tasks]
Name: "desktopicon"; Description: "{cm:DesktopIcon}"

[Dirs]
; Nakbox writes saves and settings into its own folder, also for other users.
Name: "{app}"; Permissions: users-modify

[Icons]
Name: "{autoprograms}\Nakbox"; Filename: "{app}\run_windows.bat"; WorkingDir: "{app}"; Flags: runminimized; Check: IsWindowsTarget
Name: "{autodesktop}\Nakbox"; Filename: "{app}\run_windows.bat"; WorkingDir: "{app}"; Flags: runminimized; Tasks: desktopicon; Check: IsWindowsTarget
Name: "{autoprograms}\Nakbox (WSL)"; Filename: "{app}\Nakbox (WSL).bat"; WorkingDir: "{app}"; Flags: runminimized; Check: IsWslTarget
Name: "{autodesktop}\Nakbox (WSL)"; Filename: "{app}\Nakbox (WSL).bat"; WorkingDir: "{app}"; Flags: runminimized; Tasks: desktopicon; Check: IsWslTarget

[UninstallDelete]
Type: filesandordirs; Name: "{app}\.venv"
Type: files; Name: "{app}\config\update_token"
Type: filesandordirs; Name: "{app}\.update"
Type: files; Name: "{app}\Nakbox (WSL).bat"
#endif

[Run]
Filename: "{app}\run_windows.bat"; WorkingDir: "{app}"; Description: "{cm:LaunchNakbox}"; Flags: postinstall nowait skipifsilent shellexec runminimized; Check: IsWindowsTarget
Filename: "{app}\Nakbox (WSL).bat"; WorkingDir: "{app}"; Description: "{cm:LaunchNakbox}"; Flags: postinstall nowait skipifsilent shellexec runminimized; Check: IsWslTarget

[Code]
var
  TargetPage: TInputOptionWizardPage;
  WslDirPage: TInputQueryWizardPage;
  TokenPage: TInputQueryWizardPage;
  PythonPage: TInputOptionWizardPage;
  { Paths of the Pythons listed on PythonPage, in the same order, and the
    target (0 Windows, 1 WSL) they were looked up for; -1 = not yet. }
  PythonPaths: TArrayOfString;
  PythonScanTarget: Integer;

function IsWslTarget: Boolean;
begin
  Result := (TargetPage <> nil) and (TargetPage.SelectedValueIndex = 1);
end;

function IsWindowsTarget: Boolean;
begin
  Result := not IsWslTarget;
end;

procedure InitializeWizard;
begin
  TargetPage := CreateInputOptionPage(wpWelcome,
    CustomMessage('TargetTitle'), CustomMessage('TargetDesc'),
    CustomMessage('TargetSub') + #13#10 + CustomMessage('TargetLinuxNote'),
    True, False);
  TargetPage.Add(CustomMessage('TargetWindows'));
  TargetPage.Add(CustomMessage('TargetWsl'));
  TargetPage.SelectedValueIndex := 0;

  WslDirPage := CreateInputQueryPage(TargetPage.ID,
    CustomMessage('WslDirTitle'), CustomMessage('WslDirDesc'),
    CustomMessage('WslDirSub'));
  WslDirPage.Add(CustomMessage('WslDirLabel'), False);
#ifdef PORTABLE
  WslDirPage.Values[0] := '~/Nakbox';
#else
  WslDirPage.Values[0] := '/opt/nakbox';
#endif

  TokenPage := CreateInputQueryPage(wpSelectDir,
    CustomMessage('TokenTitle'), CustomMessage('TokenDesc'),
    CustomMessage('TokenSub'));
  TokenPage.Add(CustomMessage('TokenLabel'), True);

  PythonPage := CreateInputOptionPage(TokenPage.ID,
    CustomMessage('PythonTitle'), CustomMessage('PythonDesc'),
    CustomMessage('PythonSub'), True, True);
  PythonScanTarget := -1;
end;

{ A quoted argument must not end in a single backslash: it would escape the quote. }
function QuoteArg(const S: String): String;
begin
  Result := S;
  if (Length(Result) > 0) and (Result[Length(Result)] = '\') then
    Result := Result + '\';
  Result := '"' + Result + '"';
end;

function PowerShellExe: String;
begin
  { sysnative: Setup is a 32-bit program; this is the 64-bit PowerShell. }
  Result := ExpandConstant('{sysnative}\WindowsPowerShell\v1.0\powershell.exe');
end;

{ Fills PythonPage with the Pythons install.ps1 finds for the chosen target
  (Windows, or inside WSL). Looked up again only when the target changes. }
procedure ScanPythons;
var
  OutFile, Params: String;
  Lines: TArrayOfString;
  I, P, N, Target, ResultCode: Integer;
begin
  if IsWslTarget then Target := 1 else Target := 0;
  if PythonScanTarget = Target then
    Exit;
  PythonScanTarget := Target;
  PythonPage.CheckListBox.Items.Clear;
  SetArrayLength(PythonPaths, 0);

  ExtractTemporaryFile('install.ps1');
  ExtractTemporaryFile('nakbox-install.sh');
  OutFile := ExpandConstant('{tmp}\pythons.txt');
  DeleteFile(OutFile);
  Params := '-NoProfile -ExecutionPolicy Bypass -File ' + QuoteArg(ExpandConstant('{tmp}\install.ps1')) +
    ' -ListPythons -OutFile ' + QuoteArg(OutFile);
  if Target = 1 then
    Params := Params + ' -Target wsl';
  if Exec(PowerShellExe, Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and
      LoadStringsFromFile(OutFile, Lines) then
    for I := 0 to GetArrayLength(Lines) - 1 do
    begin
      { label<TAB>path }
      P := Pos(#9, Lines[I]);
      if (P > 1) and (P < Length(Lines[I])) then
      begin
        N := GetArrayLength(PythonPaths);
        SetArrayLength(PythonPaths, N + 1);
        PythonPaths[N] := Copy(Lines[I], P + 1, Length(Lines[I]));
        PythonPage.Add(Copy(Lines[I], 1, P - 1) + '   ' + PythonPaths[N]);
      end;
    end;
  if GetArrayLength(PythonPaths) > 0 then
    PythonPage.SelectedValueIndex := 0;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if PageID = WslDirPage.ID then
    Result := not IsWslTarget
  else if PageID = wpSelectDir then
    { WSL: the Linux folder was asked already; the Windows folder only
      holds the launcher, so the default is used. }
    Result := IsWslTarget
  else if PageID = PythonPage.ID then
  begin
    { No Python found: nothing to pick. install.ps1 then looks for one
      itself and offers to install it. }
    ScanPythons;
    Result := GetArrayLength(PythonPaths) = 0;
  end;
end;

{ A Linux path, or a Windows path that install.ps1 converts to one
  (\\wsl.localhost\Ubuntu\home\me\Nakbox, C:\Games\Nakbox). A relative path
  would land under whatever folder the installer happens to run in. }
function IsWslDirOk(const S: String): Boolean;
begin
  Result := (S = '~') or (Copy(S, 1, 2) = '~/') or (Copy(S, 1, 2) = '\\') or
    ((Copy(S, 1, 1) = '/') and (Pos('\', S) = 0)) or
    ((Length(S) >= 3) and (S[2] = ':') and ((S[3] = '\') or (S[3] = '/')));
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  ResultCode: Integer;
begin
  Result := True;
  if (CurPageID = TargetPage.ID) and IsWslTarget then
  begin
    { sysnative: Setup is a 32-bit program and wsl.exe exists only as 64-bit. }
    if (not Exec(ExpandConstant('{sysnative}\wsl.exe'), '-e true', '', SW_HIDE,
        ewWaitUntilTerminated, ResultCode)) or (ResultCode <> 0) then
    begin
      MsgBox(CustomMessage('WslMissing'), mbError, MB_OK);
      Result := False;
    end;
  end
  else if CurPageID = WslDirPage.ID then
  begin
    if Trim(WslDirPage.Values[0]) = '' then
      Result := False
    else if not IsWslDirOk(Trim(WslDirPage.Values[0])) then
    begin
      MsgBox(CustomMessage('WslDirBad'), mbError, MB_OK);
      Result := False;
    end;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  TokenFile, Params: String;
  ResultCode, Target, Picked: Integer;
begin
  Result := '';
  ExtractTemporaryFile('install.ps1');
  ExtractTemporaryFile('nakbox-install.sh');

  { The token travels in a file inside Setup's private temp folder, not on
    the command line. install.ps1 deletes it after reading. }
  TokenFile := ExpandConstant('{tmp}\token.txt');
  SaveStringToFile(TokenFile, Trim(TokenPage.Values[0]), False);

  Params := '-NoProfile -ExecutionPolicy Bypass -File ' + QuoteArg(ExpandConstant('{tmp}\install.ps1')) +
    ' -InstallDir ' + QuoteArg(WizardDirValue) +
    ' -TokenFile ' + QuoteArg(TokenFile);
  if IsWslTarget then
    Params := Params + ' -Target wsl -WslDir ' + QuoteArg(Trim(WslDirPage.Values[0]))
  else
    Params := Params + ' -Target windows';
  { The Python picked on PythonPage, if the list there is for this target. }
  if IsWslTarget then Target := 1 else Target := 0;
  Picked := PythonPage.SelectedValueIndex;
  if (PythonScanTarget = Target) and (Picked >= 0) and (Picked < GetArrayLength(PythonPaths)) then
    Params := Params + ' -Python ' + QuoteArg(PythonPaths[Picked]);
#ifdef PORTABLE
  Params := Params + ' -Portable';
#endif

  { 64-bit PowerShell, in a visible window so the download and the Python
    package install show their progress. }
  if not Exec(PowerShellExe, Params, '',
      SW_SHOW, ewWaitUntilTerminated, ResultCode) then
    Result := CustomMessage('NoPowerShell')
  else if ResultCode <> 0 then
    Result := CustomMessage('InstallFailed');
  DeleteFile(TokenFile);
end;

#ifndef PORTABLE
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  AppDir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    AppDir := ExpandConstant('{app}');
    if DirExists(AppDir) then
      if MsgBox(FmtMessage(CustomMessage('RemoveData'), [AppDir]), mbConfirmation,
          MB_YESNO or MB_DEFBUTTON2) = IDYES then
        DelTree(AppDir, True, True, True);
  end;
end;
#endif
