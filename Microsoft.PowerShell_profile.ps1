<# ==============================

pwsh profile

                encoding: utf8bom
============================== #>

@(
    "Scoop-Completion"
) | ForEach-Object { Import-Module $_ }

# disble progress bar
$progressPreference = "silentlyContinue"


#################################################################
# functions arround prompt customization
#################################################################

##############################
# ime
##############################

function Get-HostProcess {
    [OutputType([System.Diagnostics.Process])]
    $p = Get-Process -Id $PID
    $i = 0
    while ($p.MainWindowHandle -eq 0) {
        if ($i -gt 10) {
            return $null
        }
        $p = $p.Parent
        $i++
    }
    return $p
}

# thanks: https://stuncloud.wordpress.com/2014/11/19/powershell_turnoff_ime_automatically/
if(-not ('Pwsh.IME' -as [type]))
{Add-Type -Namespace Pwsh -Name IME -MemberDefinition @'

[DllImport("user32.dll")]
private static extern int SendMessage(IntPtr hWnd, uint Msg, int wParam, int lParam);

[DllImport("imm32.dll")]
private static extern IntPtr ImmGetDefaultIMEWnd(IntPtr hWnd);
public static int GetState(IntPtr hwnd) {
    IntPtr imeHwnd = ImmGetDefaultIMEWnd(hwnd);
    return SendMessage(imeHwnd, 0x0283, 0x0005, 0);
}

public static void SetState(IntPtr hwnd, bool state) {
    IntPtr imeHwnd = ImmGetDefaultIMEWnd(hwnd);
    SendMessage(imeHwnd, 0x0283, 0x0006, state?1:0);
}

'@ }

function Reset-ConsoleIME {
    $hostProc = Get-HostProcess
    if (-not $hostProc) {
        return 0
    }
    try {
        if ([Pwsh.IME]::GetState($hostProc.MainWindowHandle)) {
            [Pwsh.IME]::SetState($hostProc.MainWindowHandle, $false)
        }
        return 1
    }
    catch {
        return 0
    }
}

##############################
# window
##############################

if(-not ('Pwsh.Window' -as [type]))
{Add-Type -Namespace Pwsh -Name Window -MemberDefinition @'

[DllImport("user32.dll")]
private static extern bool SendMessage(IntPtr hWnd, uint Msg, int wParam, string lParam);
public static bool SetText(IntPtr hwnd, string text) {
    return SendMessage(hwnd, 0x000C, 0, text);
}

[DllImport("user32.dll")]
private static extern void SendMessage(IntPtr hWnd, uint Msg, int wParam, int lParam);
public static void Minimize(IntPtr hwnd) {
    SendMessage(hwnd, 0x0112, 0xF020, 0);
}

'@ }

function Set-ConsoleWindowTitle {
    param (
        [string]$title
    )
    $hostProc = Get-HostProcess
    if (-not $hostProc) {
        return $false
    }
    return [Pwsh.Window]::SetText($hostProc.MainWindowHandle, $title)
}

function Hide-ConsoleWindow {
    $hostProc = Get-HostProcess
    if ($hostProc -and ($env:TERM_PROGRAM -ne "vscode")) {
        [Pwsh.Window]::Minimize($hostProc.MainWindowHandle)
    }
}

##############################
# google ime setting sync
##############################

Class GoogleImeDb {
    [string]$name
    [string]$localDirPath
    [string]$cloudDirPath
    [System.IO.FileInfo]$localFile
    [System.IO.FileInfo]$cloudFile
    [string]$require
    [string[]]$missing = @()
    [string]$lastUpdate

    GoogleImeDb($name) {
        $this.name = $name
        $this.localDirPath = "C:\Users\{0}\AppData\LocalLow\Google\Google Japanese Input" -f $env:USERNAME
        $this.cloudDirPath = "C:\Users\{0}\Dropbox\develop\app_config\IME_google\db" -f $env:USERNAME
        $localPath = $this.localDirPath | Join-Path -ChildPath $this.name
        if (Test-Path $localPath) {
            $this.localFile = Get-Item -LiteralPath $localPath
        }
        else {
            $this.missing += $localPath
        }
        $cloudPath = $this.cloudDirPath | Join-Path -ChildPath $this.name
        if (Test-Path $cloudPath) {
            $this.cloudFile = Get-Item -LiteralPath $cloudPath
        }
        else {
            $this.missing += $cloudPath
        }
        if ($this.missing.Length -gt 0) {
            $this.require = "FINDFILE"
            return
        }
        $this.lastUpdate = @($this.localFile, $this.cloudFile) | Sort-Object LastWriteTime | Select-Object -Last 1 | Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        if ($this.cloudFile.LastWriteTime -lt $this.localFile.LastWriteTime) {
            $this.require = "UPLOAD"
            return
        }
        if ($this.localFile.LastWriteTime -lt $this.cloudFile.LastWriteTime) {
            $this.require = "DOWNLOAD"
            return
        }
        $this.require = "NOTHING"
    }

    [void] BackupCloud() {
        $ts = Get-Date -Format "yyyyMMddHHmmssff"
        $backupDest = $this.cloudDirPath | Join-Path -ChildPath $(".history\{0}_{1}.db" -f $this.cloudFile.Basename, $ts)
        $this.cloudFile | Copy-Item -Destination $backupDest
    }

    [void] Sync() {
        if ($this.require -in @("NOTHING", "FINDFILE")) {
            return
        }
        $origin, $dest = switch ($this.require) {
            "UPLOAD" {
                @($this.localFile, $this.cloudFile); break;
            }
            "DOWNLOAD" {
                @($this.cloudFile, $this.localFile); break;
            }
        }
        if ($origin.LastWriteTime -gt $dest.LastWriteTime) {
            if ($this.require -eq "UPLOAD") {
                $this.BackupCloud()
            }
            $origin | Copy-Item -Destination $dest.Directory.FullName
            if ($this.require -eq "DOWNLOAD") {
                Get-Process | Where-Object ProcessName -In @("GoogleIMEJaConverter", "GoogleIMEJaRenderer") | ForEach-Object {
                    $path = $_.Path
                    Stop-Process $_
                    Start-Process $path
                }
            }
        }
    }

    static [void] Dialog ([bool]$register) {
        $opt = ($register)? "--mode=word_register_dialog" : "--mode=dictionary_tool"
        Start-Process -FilePath "C:\Program Files (x86)\Google\Google Japanese Input\GoogleIMEJaTool.exe" -ArgumentList $opt
    }

    static [PSCustomObject[]] GetExportedData () {
        $path = "C:\Users\{0}\Dropbox\develop\app_config\IME_google\convertion_dict\main.txt" -f $env:USERNAME
        if (Test-Path $path) {
            return $(Get-Content $path | ConvertFrom-Csv -Delimiter "`t" -Header "Reading","Word","POS")
        }
        return @()
    }

}

function Test-GoogleIme {
    @("config1.db", "user_dictionary.db") | ForEach-Object {
        $db = [GoogleImeDb]::New($_)
        if ($db.require -eq "NOTHING") { return }
        if ($db.require -eq "FINDFILE") {
            $db.missing | ForEach-Object {
                "MISSING: '{0}'!" -f $_ | Write-Host -ForegroundColor Magenta
            }
            return
        }
        $psColor = $global:PSStyle
        $ansiSeq = @{
            "UPLOAD" = $psColor.Foreground.Green;
            "DOWNLOAD" = $psColor.Foreground.Cyan;
        }[$db.require]
        "[Google IME]`n{0} is required on '{1}'!`n(last update: {2})" -f @($db.require, $db.name, $db.lastUpdate | ForEach-Object {$ansiSeq + $_ + $psColor.Reset}) | Write-Host

        if ((Read-Host -Prompt "==> Execute Sync?(y/n)") -eq "y") {
            $db.Sync()
            "`u{2705}" | Write-Host -NoNewline -ForegroundColor (($db.require -eq "UPLOAD")? "Green" : "Cyan")
            " {0} completed: '{1}'`n" -f $db.require, $db.name | Write-Host
        }
        else {
            "`u{2716}" | Write-Host -ForegroundColor Red -NoNewline
            " skipped {0} of '{1}'.`n" -f $db.require, $db.name | Write-Host
        }
    }
}

Set-PSReadLineKeyHandler -Key "ctrl+F8" -ScriptBlock {
    [PSConsoleReadLine]::RevertLine()
    [PSConsoleReadLine]::Insert("[GoogleImeDb]::GetExportedData() | ? Word -match ")
}

##############################
# Pseudo-voicing mark fixer
##############################

class PseudoVoicing {
    [string]$origin
    [string]$formatted
    PseudoVoicing([string]$s) {
        $this.origin = $s
        $this.formatted = $this.origin
    }
    [void] FixVoicing() {
        $this.formatted = [regex]::new(".[\u309b\u3099]").Replace($this.formatted, {
            param($m)
            $c = $m.Value.Substring(0,1)
            if ($c -eq "`u{3046}") {
                return "`u{3094}"
            }
            if ($c -eq "`u{30a6}") {
                return "`u{30f4}"
            }
            return [string]([Convert]::ToChar([Convert]::ToInt32([char]$c) + 1))
        })
    }
    [void] FixHalfVoicing() {
        $this.formatted = [regex]::new(".[\u309a\u309c]").Replace($this.formatted, {
            param($m)
            $c = $m.Value.Substring(0,1)
            return [string]([Convert]::ToChar([Convert]::ToInt32([char]$c) + 2))
        })
    }
}

class MacOSFile {
    [System.IO.FileInfo[]]$files
    MacOSFile() {
        $this.files = @(Get-ChildItem -Path $PWD.Path | Where-Object {$_.BaseName -match "\u309a|\u309b|\u309c|\u3099"})
    }
    [void]Rename(){
        $this.files | ForEach-Object {
            "Pseudo voicing-mark on '{0}'!" -f $_.Name | Write-Host -ForegroundColor Magenta
            $ask = Read-Host "Fix? (y/n)"
            if ($ask -ne "y") {
                return
            }
            $n = [PseudoVoicing]::new($_.Name)
            $n.FixHalfVoicing()
            $n.FixVoicing()
            $_ | Rename-Item -NewName $n.formatted
            "==> Fixed!" | Write-Host
        }
    }
}



#################################################################
# prompt
#################################################################

Class Prompter {

    [string]$color
    [int]$bufferWidth
    [string]$accentFg
    [string]$accentBg
    [string]$markedFg
    [string]$subMarkerStart
    [string]$underlineStart
    [string]$stopDeco

    Prompter() {
        $this.color = @{
            "Sunday" = "Yellow";
            "Monday" = "BrightBlue";
            "Tuesday" = "Magenta";
            "Wednesday" = "BrightCyan";
            "Thursday" = "Green";
            "Friday" = "BrightYellow";
            "Saturday" = "White";
        }[ ((Get-Date).DayOfWeek -as [string]) ]
        $this.bufferWidth = [system.console]::BufferWidth
        $this.accentFg = $Global:PSStyle.Foreground.PSObject.Properties[$this.color].Value
        $this.accentBg = $Global:PSStyle.Background.PSObject.Properties[$this.color].Value
        $this.markedFg = $Global:PSStyle.Foreground.Black
        $this.subMarkerStart = $Global:PSStyle.Background.BrightBlack + $this.markedFg
        $this.underlineStart = $Global:PSStyle.Underline + $Global:PSStyle.Foreground.BrightBlack
        $this.stopDeco = $Global:PSStyle.Reset
    }

    [string] Fill () {
        $left = "#"
        $right = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $SJIS = [System.Text.Encoding]::GetEncoding("Shift_JIS")
        $filler = " " * ($this.bufferWidth - $SJIS.GetByteCount($left) - $SJIS.GetByteCount($right))
        return $($this.underlineStart`
            + $left `
            + $filler `
            + $this.accentFg `
            + $right `
            + $this.stopDeco)
    }

    [string] GetParent() {
        $dir = $pwd.ProviderPath | Split-Path -Parent
        $prefix = "~\"
        if (-not $dir -or $dir.EndsWith(":\")) {
            $prefix = ""
        }
        $suffix = "\"
        if (-not $dir -or $dir.EndsWith("\")) {
            $suffix = ""
        }
        $name = $dir | Split-Path -Leaf
        return $("#" + $prefix + $name + $suffix)
    }

    [string] GetWd() {
        return $($this.subMarkerStart `
            + $this.GetParent() `
            + $this.accentBg `
            + $this.markedFg `
            + ($pwd.ProviderPath | Split-Path -Leaf) `
            + $this.stopDeco)
    }

    [string] GetPrompt() {
        $warning = ""
        if (($pwd.Path | Split-Path -Leaf) -ne "Desktop") {
            $warning = $Global:PSStyle.Foreground.Red
        }
        return $warning + "#>" + $this.stopDeco
    }

    [void] Display() {
        $this.Fill() | Write-Host
        $this.GetWd() | Write-Host
    }

}


function prompt {
    $p = [Prompter]::New()
    $p.Display()

    if ( -not (Set-ConsoleWindowTitle -title $pwd.ProviderPath) ) {
        Write-Host "Failed to update window text..." -ForegroundColor Magenta
    }

    if (-not (Reset-ConsoleIME)) {
        "failed to reset ime..." | Write-Host -ForegroundColor Magenta
    }

    if ($pwd.Path.StartsWith("C:")) {
        $mf = [MacOSFile]::new()
        $mf.Rename()
    }

    Test-GoogleIme

    return $p.GetPrompt()
}

#################################################################
# variable / alias / function
#################################################################

Set-Alias gd Get-Date
Set-Alias f ForEach-Object
Set-Alias w Where-Object
Set-Alias v Set-Variable
Set-Alias wh Write-Host

function Out-FileUtil {
    param (
        [string]$basename
        ,[string]$extension = "txt"
        ,[switch]$force
    )
    if ($extension.StartsWith(".")) {
        $extension = $extension.Substring(1)
    }
    $outPath = (Get-Location).Path | Join-Path -ChildPath ($basename + "." + $extension)
    $input | Out-File -FilePath $outPath -Encoding utf8 -NoClobber:$(-not $force)
}
Set-Alias of Out-FileUtil

function Invoke-KeyhacMaster {
    $keyhacPath = Join-Path $env:USERPROFILE -ChildPath "Dropbox\develop\code\python\keyhac-master"
    if (Test-Path $keyhacPath) {
        'code "{0}"' -f $keyhacPath | Invoke-Expression
    }
}

function dsk {
    "{0}\desktop" -f $env:USERPROFILE | Set-Location
}

function d {
    Start-Process ("{0}\desktop" -f $env:USERPROFILE)
}

function sum {
    $n = 0
    $args | ForEach-Object {$n += $_}
    return $n
}

function ii. {
    Invoke-Item .
}

function iit {
    param (
        [parameter(ValueFromPipeline = $true)]$inputLine
    )
    begin {}
    process {
        $tablacus = $env:USERPROFILE | Join-Path -ChildPath "Dropbox\portable_apps\tablacus\TE64.exe"
        if ((Test-Path $tablacus) -and (Test-Path $inputLine -PathType Container)) {
            Start-Process $tablacus -ArgumentList $inputLine
        }
        else {
            Start-Process $inputLine
        }
    }
    end {}
}
function sieve ([switch]$net) {
    $input | Where-Object {return ($net)? ($_ -replace "\s") : $_} | Write-Output
}

function padZero ([int]$pad) {
    $input | ForEach-Object {"{0:d$($pad)}" -f [int]$_ | Write-Output}
}

function ml ([string]$pattern, [switch]$case, [switch]$negative){
    # ml: match line
    $reg = ($case)? [regex]::New($pattern) : [regex]::New($pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($negative) {
        return @($input).Where({-not $reg.IsMatch($_)})
    }
    return @($input).Where({$reg.IsMatch($_)})
}

function ato ([string]$s, [int]$linesAfter=0) {
    return $($input | ForEach-Object {[string]$_ + $s + "`n" * $linesAfter})
}

function saki ([string]$s, [int]$linesBefore=0) {
    return $($input | ForEach-Object {"`n" * $linesBefore + $b + $s + [string]$_})
}

function sand([string]$pair = "??????") {
    if($pair.Length -eq 2) {
        $pre = $pair[0]
        $post = $pair[1]
    }
    elseif ($pair.Length -eq 1) {
        $pre = $post = $pair
    }
    else {
        $pre = $post = ""
    }
    return $($input | ForEach-Object {$pre + $_ + $post})
}

function reverse {
    $a = @($input)
    for ($i = $a.Count - 1; $i -ge 0; $i--) {
        $a[$i] | Write-Output
    }
}

function Invoke-Taskview ([int]$waitMsec = 150) {
    Start-Sleep -Milliseconds $waitMsec
    Invoke-Command -ScriptBlock { [System.Windows.Forms.SendKeys]::SendWait("^%{Tab}") }
    # Start-Process Explorer.exe -ArgumentList @("shell:::{3080F90E-D7AD-11D9-BD98-0000947B0257}")
}

function c {
    @($input).ForEach({$_ -as [string]}) | Set-Clipboard
    # Invoke-Taskview -waitMsec 300
    Hide-ConsoleWindow
}

function Set-FileToClipboard {
    [Windows.Forms.Clipboard]::SetFileDropList($input)
}

function Get-ClipboardFile {
    return $([Windows.Forms.Clipboard]::GetFileDropList() | Get-Item -LiteralPath -ErrorAction SilentlyContinue)
}

function cds {
    $p = "X:\scan"
    if (Test-Path $p -PathType Container) {
        Set-Location $p
    }
}

function cdc {
    $clip = (Get-Clipboard | Select-Object -First 1) -replace '"'
    if (Test-Path $clip -PathType Container) {
        Set-Location $clip
    }
    else {
        "invalid-path!" | Write-Host -ForegroundColor Magenta
    }
}


function flb {
    $input | Format-List | Out-String -Stream | bat.exe --plain
}

function j ($i) {
    $h = [ordered]@{
        "??????" = 2018;
        "??????" = 1988;
        "??????" = 1925;
    }
    $now = (Get-Date).Year
    $h.GetEnumerator() | ForEach-Object {
        $y = $_.Value + $i
        $ansi = ($y -gt $now)? $Global:PSStyle.Foreground.BrightBlack : $Global:PSStyle.Foreground.BrightWhite
        [PSCustomObject]@{
            "??????" = $ansi + $_.Key + $Global:PSStyle.Reset;
            "??????" = $ansi + $y + $Global:PSStyle.Reset;
        } | Write-Output
    }
}


function Stop-PsStyleRendering {
    $global:PSStyle.OutputRendering = [System.Management.Automation.OutputRendering]::PlainText
}
function Start-PsStyleRendering {
    $global:PSStyle.OutputRendering = [System.Management.Automation.OutputRendering]::Ansi
}

# restart keyhac
function Restart-Keyhac {
    Get-Process | Where-Object {$_.Name -eq "keyhac"} | Stop-Process -Force
    Start-Process "C:\Personal\tools\keyhac\keyhac.exe"
}

# pip

function pipinst {
    Start-Process -Path python.exe -Wait -ArgumentList @("-m","pip","install","--upgrade","pip") -NoNewWindow
    Start-Process -Path python.exe -Wait -ArgumentList @("-m","pip","install","--upgrade",$args[0]) -NoNewWindow
}



# 7zip

function Invoke-7Z {
    param(
        [string]$path
        ,[string]$outname
        ,[switch]$compress
    )
    $target = Get-Item -LiteralPath $path
    if ($compress) {
        if (-not $outname) {
            $outname = $target.BaseName + ".zip"
        }
        "7z a '{0}' '{1}'" -f $outname, $target.FullName | Invoke-Expression
    }
    else {
        if ($target.Extension -notin @(".zip", ".7z")) {
            return
        }
        if (-not $outname) {
            $outname = $target.BaseName
        }
        "7z x '{0}' -o'{1}'" -f $target.FullName, $outname | Invoke-Expression
    }
}
Set-PSReadLineKeyHandler -Key "alt+'" -ScriptBlock {
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("Invoke-7Z -path ")
    [Microsoft.PowerShell.PSConsoleReadLine]::MenuComplete()
}

##############################
# update type data
##############################

Update-TypeData -TypeName "System.Object" -Force -MemberType ScriptMethod -MemberName GetProperties -Value {
    return $($this.PsObject.Members | Where-Object MemberType -eq noteproperty | Select-Object Name, Value)
}

Update-TypeData -TypeName "System.String" -Force -MemberType ScriptMethod -MemberName ToSha256 -Value {
    $bs = [System.Text.Encoding]::UTF8.GetBytes($this)
    $sha = New-Object System.Security.Cryptography.SHA256CryptoServiceProvider
    $hasyBytes = $sha.ComputeHash($bs)
    $sha.Dispose()
    return $(-join ($hasyBytes | ForEach-Object {
        $_.ToString("x2")
    }))
}

function ConvertTo-SHA256Hash {
    param (
        [parameter(ValueFromPipeline = $true)][string]$str
    )
    begin {}
    process {
        $str.ToSha256()
    }
    end {}
}

@("System.Double", "System.Int32") | ForEach-Object {

    Update-TypeData -TypeName $_ -Force -MemberType ScriptMethod -MemberName "ToHex" -Value {
        return $([System.Convert]::ToString($this,16))
    }

    Update-TypeData -TypeName $_ -Force -MemberType ScriptMethod -MemberName "RoundTo" -Value {
        param ([int]$n=2)
        $digit = [math]::Pow(10, $n)
        return $([math]::Round($this * $digit) / $digit)
    }

    Update-TypeData -TypeName $_ -Force -MemberType ScriptMethod -MemberName "FloorTo" -Value {
        param ([int]$n=2)
        $digit = [math]::Pow(10, $n)
        return $([math]::Floor($this * $digit) / $digit)
    }

    Update-TypeData -TypeName $_ -Force -MemberType ScriptMethod -MemberName "CeilingTo" -Value {
        param ([int]$n=2)
        $digit = [math]::Pow(10, $n)
        return $([math]::Ceiling($this * $digit) / $digit)
    }

    # 13q = 9pt, 4q = 1mm

    Update-TypeData -TypeName $_ -Force -MemberType ScriptMethod -MemberName "Pt2Q" -Value {
        $q = $this * (13 / 9)
        return $q.RoundTo(1)
    }
    Update-TypeData -TypeName $_ -Force -MemberType ScriptMethod -MemberName "Q2Pt" -Value {
        $pt = $this * (9 / 13)
        return $pt.RoundTo(1)
    }
    Update-TypeData -TypeName $_ -Force -MemberType ScriptMethod -MemberName "Q2Mm" -Value {
        return ($this / 4).RoundTo(1)
    }
    Update-TypeData -TypeName $_ -Force -MemberType ScriptMethod -MemberName "Mm2Q" -Value {
        return ($this * 4).RoundTo(1)
    }
    Update-TypeData -TypeName $_ -Force -MemberType ScriptMethod -MemberName "Mm2Pt" -Value {
        $q = $this * 4
        return $q.Q2Pt()
    }
    Update-TypeData -TypeName $_ -Force -MemberType ScriptMethod -MemberName "Pt2Mm" -Value {
        $q = $this.Pt2Q()
        return ($q / 4).RoundTo(1)
    }

    Update-TypeData -TypeName $_ -Force -MemberType ScriptMethod -MemberName "ToCJK" -Value {
        $s = $this -as [string]
        @{
            "0" = "???";
            "1" = "???";
            "2" = "???";
            "3" = "???";
            "4" = "???";
            "5" = "???";
            "6" = "???";
            "7" = "???";
            "8" = "???";
            "9" = "???";
        }.GetEnumerator() | ForEach-Object {
            $s = $s.Replace($_.key, $_.value)
        }
        return $s
    }
}

function  Convert-IntToCJK {
    $re = [regex]::new("\d")
    return $input | ForEach-Object {
        return $re.Replace($_, {
            param($m)
            return ($m.Value -as [int]).toCJK()
        })
    }
}

##############################
# github repo
##############################

class PwshRepo {
    [string]$activeDir
    [string]$repoDir

    PwshRepo([string]$repoDir) {
        $this.activeDir = $env:USERPROFILE | Join-Path -ChildPath "Documents\PowerShell"
        $this.repoDir = $repoDir
    }

    [System.Object[]]GetUnusedItems() {
        $activeFiles = $this.activeDir | Get-ChildItem -Recurse
        $rels = $activeFiles | ForEach-Object {
            return [System.IO.Path]::GetRelativePath($this.activeDir, $_.Fullname)
        }
        return $this.repoDir | Get-ChildItem -Recurse | Where-Object { $_.Name -notin @(".gitignore", "README.md") } | Where-Object {
            $rel = [System.IO.Path]::GetRelativePath($this.repoDir, $_.Fullname)
            return $rel -notin $rels
        }
    }


    [void]Sync() {
        $this.GetUnusedItems() | Where-Object {$_} | Sort-Object {$_.Fullname.split("\").Length} -Descending | Remove-Item
        $this.activeDir | Get-ChildItem -Exclude @("Modules", "Scripts") | Copy-Item -Recurse -Exclude @("*.dll", "*.txt") -Destination $this.repoDir -Force
    }

    [void]Invoke() {
        $this.Sync()
        Start-Process code -NoNewWindow -ArgumentList @($this.repoDir)
    }

}

function Invoke-Repository {
    $repoDir = "C:\Personal\tools\pwsh"
    if (Test-Path $repoDir) {
        $repo = [PwshRepo]::new($repoDir)
        $repo.Invoke()
    }
    else {
        "cannot find path..." | Write-Host -ForegroundColor Magenta
    }
}
Set-Alias repo Invoke-Repository

##############################
# temp dir
##############################

function Use-TempDir {
    <#
    .NOTES
    > Use-TempDir {$pwd.Path}
    Microsoft.PowerShell.Core\FileSystem::C:\Users\~~~~~~ # includes PSProvider

    > Use-TempDir {$pwd.ProviderPath}
    C:\Users\~~~~~~ # literal path without PSProvider

    #>
    param (
        [ScriptBlock]$script
    )
    $tmp = $env:TEMP | Join-Path -ChildPath $([System.Guid]::NewGuid().Guid)
    New-Item -ItemType Directory -Path $tmp | Push-Location
    "working on tempdir: {0}" -f $tmp | Write-Host -ForegroundColor DarkBlue
    $result = Invoke-Command -ScriptBlock $script
    Pop-Location
    $tmp | Remove-Item -Recurse
    return $result
}

##############################
# highlight string
##############################

Class PsHighlight {
    [regex]$reg
    [string]$color
    PsHighlight([string]$pattern, [string]$color, [switch]$case) {
        $this.reg = ($case)? [regex]::new($pattern) : [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $this.color = $color
    }
    [string]Markup([string]$s) {
        return $this.reg.Replace($s, {
            param($m)
            return $global:PSStyle.Background.PSObject.Properties[$this.color].Value + $global:PSStyle.Foreground.Black + $m.Value + $global:PSStyle.Reset
        })
    }
}

function Write-StringHighLight {
    param (
        [string]$pattern
        ,[switch]$case
        ,[ValidateSet("Black","Red","Green","Yellow","Blue","Magenta","Cyan","White","BrightBlack","BrightRed","BrightGreen","BrightYellow","BrightBlue","BrightMagenta","BrightCyan","BrightWhite")][string]$color = "Yellow"
        ,[switch]$continuous
    )
    $hi = [PsHighlight]::new($pattern, $color, $case)
    foreach ($line in $input) {
        $hi.Markup($line) | Write-Host -NoNewline:$continuous
    }
}
Set-Alias hilight Write-StringHighLight



#################################################################
# loading custom cmdlets
#################################################################

"loading custom cmdlets took {0:f0}ms." -f $(Measure-Command {
    $PSScriptRoot | Join-Path -ChildPath "cmdlets" | Get-ChildItem -Recurse -Include "*.ps1" | ForEach-Object {
        . $_.FullName
    }
}).TotalMilliseconds | Write-Host -ForegroundColor Cyan
