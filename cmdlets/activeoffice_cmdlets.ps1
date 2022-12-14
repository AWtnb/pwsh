
<# ==============================

cmdlets for active office

                encoding: utf8bom
============================== #>


# By default, Add-Type references the System namespace. When the MemberDefinition
# parameter is used, Add-Type also references the System.Runtime.InteropServices
# namespace by default. The namespaces that you add by using the UsingNamespace
# parameter are referenced in addition to the default namespaces.
# https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/add-type?view=powershell-7.2
#
# thanks: https://qiita.com/SilkyFowl/items/e57f1fb165cf2ea33092

if (-not ('Pwsh.Marshal' -as [type]))
{Add-Type -Namespace "Pwsh" -Name "Marshal" -MemberDefinition @'

internal const String OLEAUT32 = "oleaut32.dll";
internal const String OLE32 = "ole32.dll";

public static Object GetActiveObject(String progID)
{
    Object obj = null;
    Guid clsid;

    try
    {
        CLSIDFromProgIDEx(progID, out clsid);
    }
    catch (Exception)
    {
        CLSIDFromProgID(progID, out clsid);
    }

    GetActiveObject(ref clsid, IntPtr.Zero, out obj);
    return obj;
}

[DllImport(OLE32, PreserveSig = false)]
private static extern void CLSIDFromProgIDEx([MarshalAs(UnmanagedType.LPWStr)] String progId, out Guid clsid);

[DllImport(OLE32, PreserveSig = false)]
private static extern void CLSIDFromProgID([MarshalAs(UnmanagedType.LPWStr)] String progId, out Guid clsid);

[DllImport(OLEAUT32, PreserveSig = false)]
private static extern void GetActiveObject(ref Guid rclsid, IntPtr reserved, [MarshalAs(UnmanagedType.Interface)] out Object ppunk);

'@ }

function Get-ActiveOffice {
    param (
        [parameter(Mandatory)]
        [ValidateSet("Word.Application", "Excel.Application", "PowerPoint.Application")][string]$app
    )
    try {
        $office = [Pwsh.Marshal]::GetActiveObject($app)
        if ($app -eq "Word.Application") {
            if ($office.Documents.Count -lt 1) {
                return $null
            }
        }
        elseif ($app -eq "Excel.Application") {
            if ($office.Sheets.Count -lt 1) {
                return $null
            }
        }
        elseif ($app -eq "PowerPoint.Application") {
            if ($office.Presentations.Count -lt 1) {
                return $null
            }
        }
        return $office
    }
    catch {
        return $null
    }
}

function Get-ActiveWordApp {
    return $(Get-ActiveOffice "Word.Application")
}
function Get-ActiveExcelApp {
    return $(Get-ActiveOffice "Excel.Application")
}
function Get-ActivePPtApp {
    return $(Get-ActiveOffice "PowerPoint.Application")
}

function Get-ActiveWordDocument {
    $word = Get-ActiveWordApp
    return ($word)? $word.ActiveDocument : $null
}
function Get-ActiveExcelSheet {
    $excel = Get-ActiveExcelApp
    return ($excel)? $excel.ActiveWorkbook.ActiveSheet : $null
}
function Get-ActivePptPresentation {
    $ppt = Get-ActivePPtApp
    return ($ppt)? $ppt.ActivePresentation : $null
}

function Set-ActiveWordCheckBoxStyle {
    $adoc = Get-ActiveWordDocument
    if (-not $adoc) { return }
    $wdContentControlCheckBox = 8
    $counter = 0
    $adoc.ContentControls | ForEach-Object {
        if ($_.type -eq $wdContentControlCheckBox) {
            try {
                $_.SetCheckedSymbol(254, "Wingdings")
                $counter++
            }
            catch {
            }
        }
    }
    "{0} content controls are formatted!" -f $counter | Write-Host
}

class OfficeColor {

    static [int] FromColorcode([string]$s) {
        $r = ([System.Convert]::ToInt32(-join $s[1..2], 16) -as [int])
        $g = ([System.Convert]::ToInt32(-join $s[3..4], 16) -as [int])
        $b = ([System.Convert]::ToInt32(-join $s[5..6], 16) -as [int])
        return $r + $g*256 + $b*256*256
    }

    static [int] $wdColorAutomatic = -16777216

}

class WdConst {

    static [int] $wdActiveEndAdjustedPageNumber = 1
    static [int] $wdFirstCharacterLineNumber = 10
    static [int] $wdLineStyleSingle = 1
    static [int] $wdLineWidth025pt = 2
    static [int] $wdLineWidth050pt = 4
    static [int] $wdLineWidth150pt = 12
    static [int] $wdRestartPage = 2
    static [int] $wdRevisionParagraphProperty = 10
    static [int] $wdRevisionProperty = 3
    static [int] $wdRevisionSectionProperty = 12
    static [int] $wdRevisionStyleDefinition = 13
    static [int] $wdRevisionTableProperty = 11
    static [int] $wdSentence = 3
    static [int] $wdStyleNormal = -1
    static [int] $wdStyleTypeCharacter = 2
    static [int] $wdStyleTypeParagraphOnly = 5
    static [int] $wdStyleTypeTable = 3
    static [int] $wdUnderlineDashHeavy = 23
    static [int] $wdUnderlineDotDashHeavy = 25
    static [int] $wdUnderlineDotDotDashHeavy = 26
    static [int] $wdUnderlineDottedHeavy = 20
    static [int] $wdUnderlineDouble = 3
    static [int] $wdUnderlineThick = 6
    static [int] $wdUnderlineWavyHeavy = 27
    static [int] $wdNumberParagraph = 1
    static [int] $wdNumberListNum = 2
    static [int] $wdNumberAllNumbers = 3
    static [int] $wdWord = 2

}

class ActiveDocument {

    [System.__ComObject]$Document

    ActiveDocument() {
        $wd = Get-ActiveWordApp
        if ($wd) {
            $this.Document = $wd.ActiveDocument
        }
    }

    [string[]] GetParagraphs() {
        $array = New-Object System.Collections.ArrayList
        if ($this.Document) {
            foreach ($p in $this.Document.Paragraphs) {
                $array.Add([ActiveDocument]::RemoveControlChar($p.Range.Text)) > $null
            }
        }
        return $array
    }

    [PSCustomObject[]] GetComments() {
        $array = New-Object System.Collections.ArrayList
        if ($this.Document) {
            foreach ($cmt in $this.Document.comments) {
                $t = $cmt.Scope.Text
                $array.Add([PSCustomObject]@{
                    "Target" = ((($t -as [string]).trim())? $t : "");
                    "Lines" = @($cmt.Range.Paragraphs | ForEach-Object {$_.Range.Text});
                    "Author" = $cmt.Author;
                    "Date" = $cmt.Date
                }) > $null
            }
        }
        return $array
    }

    static [string] RemoveControlChar([string] $s) {
        $reg = [regex]"[`u{00}-`u{001f}]"
        return $reg.Replace($s, "")
    }
}

function Get-ActiveWordDocumentParagraphs {
    $adoc = [ActiveDocument]::new()
    return $adoc.GetParagraphs()
}
function Get-CommentOnActiveWordDocument {
    $adoc = [ActiveDocument]::new()
    return $adoc.GetComments()
}

function Invoke-GrepOnActiveWordDocument {
    <#
        .SYNOPSIS
        現在開かれているアクティブなWord文書に対するGrep
        .PARAMETER pattern
        検索語
        .PARAMETER case
        指定時は大文字小文字を区別
        .PARAMETER context
        前後何行ずつを表示するかをカンマ区切りで指定
    #>
    param (
        [parameter(Mandatory)]$pattern
        ,[switch]$case
        ,[int[]]$context = 0
    )

    $adoc = [ActiveDocument]::new()
    $paragraphs = $adoc.GetParagraphs()
    if ($paragraphs.Count -lt 1) {
        return
    }

    $grep = $paragraphs | Select-String -Pattern $pattern -AllMatches -CaseSensitive:$case -Context $context
    foreach ($g in $grep) {

        $g.Context.PreContext | Where-Object {$_} | ForEach-Object {
            "    :{0}" -f $_ | Write-Host -ForegroundColor DarkGray
        }

        "{0:d4}:" -f $g.LineNumber | Write-Host -ForegroundColor DarkGray -NoNewline
        $g.Line | hilight -pattern $pattern -case:$case

        $g.Context.PostContext | Where-Object {$_} | ForEach-Object {
            "    :{0}" -f $_ | Write-Host -ForegroundColor DarkGray
        }

    }

    if ($grep.Matches.Count -gt 0) {
        "total match: {0}" -f $grep.Matches.Count | Write-Host -ForegroundColor Cyan
    }
}
Set-Alias grad Invoke-GrepOnActiveWordDocument



function Copy-ActiveWordDocument {
    $word = Get-ActiveWordApp
    if (-not $word) {
        return
    }
    if (-not $word.ActiveDocument.path) {
        Write-Host "unsaved document!!" -ForegroundColor Magenta
        return
    }
    $word.Documents.Add($word.ActiveDocument.Fullname) > $null
}


function Set-NotationShadingOnActiveWordDocument {
    <#
        .SYNOPSIS
        現在開いている Microsoft Word の本文中にある注番号に背景色を設定する
    #>
    $doc = Get-ActiveWordDocument
    if (-not $doc) { return }
    $col = [OfficeColor]::FromColorcode("#84daff")
    $doc.FootNotes | ForEach-Object {
        $note = $_.Range.Text
        if ($note.length -lt 30) {
            $content = $note
        }
        else {
            $content = "{0} ... {1}" -f ($note[0..15] -join ""), ($note.SubString($note.length - 10))
        }
        "FootNote {0:d2} ({1}) to :" -f $_.Index, $content | Write-Host -ForegroundColor Cyan
        $target = $_.Reference
        $target.MoveStart([wdConst]::wdSentence, -1) > $null
        $target.MoveEnd([wdConst]::wdSentence) > $null
        ($target.Text -replace [char]2).Trim() | Write-Host
        if ($_.Reference.Shading.BackgroundPatternColor -lt 0) {
            $_.Reference.Shading.BackgroundPatternColor = $col
        }
        else {
            "  - SKIPPED (already background color is set!)" | Write-Host -ForegroundColor Magenta
        }
    }
}

function Get-NotationTextOnActiveWordDocument {
    <#
        .SYNOPSIS
        現在開いている Microsoft Word 文書から脚注のテキスト情報を抽出する
    #>
    $doc = Get-ActiveWordDocument
    if (-not $doc) { return }

    $doc.FootNotes | ForEach-Object {
        [PSCustomObject]@{
            "Id" = $_.Index;
            "Note" = $_.Range.Text;
        } | Write-Output
    }
}

function Set-MarginOnActiveWordDocument {
    <#
        .SYNOPSIS
        現在開いている Microsoft Word 文書のすべてのセクションの余白を統一する
    #>
    param (
        [ValidateSet("normal", "mid-narrow", "narrow", "wide")][string]$style = "normal"
    )
    $doc = Get-ActiveWordDocument
    if (-not $doc) { return }
    $top, $bottom, $side = switch ($style) {
        "normal" { @(35, 30, 30) ; break}
        "mid-narrow" { @(25.4, 25.4, 19.05) ; break}
        "narrow" { @(12.7, 12.7, 12.7) ; break}
        "wide" { @(25.4, 25.4, 50.8) ; break}
    }
    $doc.Sections | ForEach-Object {
        $_.PageSetup.TopMargin = [double]$top
        $_.PageSetup.BottomMargin = [double]$bottom
        $_.PageSetup.LeftMargin = [double]$side
        $_.PageSetup.RightMargin = [double]$side
    }
}

function Invoke-GrepOnActiveWordDocumentComment {
    param (
        [string]$pattern
        ,[switch]$case
    )
    $adoc = [ActiveDocument]::new()
    if ($adoc.GetComments().Count -lt 1) {
        return
    }
    # $reg = ($case)? [regex]$pattern : [regex]"(?i)$pattern"
    $reg = ($case)? [regex]::new($pattern) : [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $adoc.GetComments() | ForEach-Object {
        $author = $_.Author
        $_.Lines | ForEach-Object {
            if ($reg.IsMatch($_)) {
                "{0}:" -f $author | Write-Host -ForegroundColor Blue
                $_ | hilight -pattern $pattern -case:$case
            }
        }
    }
}


function Invoke-AcceptFormatRevisionOnActiveWordDocument {
    <#
        .SYNOPSIS
        現在開いている Word 文書内の書式変更履歴を一括で承認する（改良版）
    #>
    $wd = Get-ActiveWordApp
    if (-not $wd) { return }

    $wd.ActiveWindow.View.RevisionsFilter.Markup = 2 #wdRevisionsMarkupAll
    $defaultStatus = @{}
    @(
        "ReviewShowComments",
        "ReviewShowInkMarkup",
        "ReviewShowInsertionsAndDeletions",
        "ReviewShowFormatting",
        "ReviewShowMarkupAreaHighlight",
        "ReviewShowRevisionsInBalloons",
        "ReviewShowRevisionsInline",
        "ReviewShowOnlyCommentsAndFormattingInBaloons",
        "ReviewHighlightUpdates",
        "ReviewOtherAuthors"
    ) | ForEach-Object {
        $name = $_
        try {
            $defaultStatus.Add($name, $wd.CommandBars.GetPressedMso($name))
        }
        catch {}
    }

    @{
        "ReviewShowInsertionsAndDeletions" = $false;
        "ReviewShowComments" = $false;
        "ReviewShowFormatting" = $true;
    }.GetEnumerator() | ForEach-Object {
        if ($wd.CommandBars.GetPressedMso($_.Key) -ne $_.Value) {
            try {
                $wd.CommandBars.ExecuteMso($_.Key)
                "Status changed: '{0}' ==> {1}" -f $_.Key, $_.Value | Write-Host -ForegroundColor DarkBlue
            }
            catch {}
        }
    }
    Write-Host "now only FORMAT revisions are displayed." -ForegroundColor Cyan
    $ask = Read-Host -Prompt "Accept the displayed revisions? (y/n)"
    if ($ask -eq "y") {
        $wd.ActiveDocument.AcceptAllRevisionsShown()
    }

    $defaultStatus.GetEnumerator() | ForEach-Object {
        if ($wd.CommandBars.GetPressedMso($_.Key) -ne $_.Value) {
            "Status recovered: '{0}' ==> {1}" -f $_.Key, $_.Value | Write-Host -ForegroundColor DarkBlue
            $wd.CommandBars.ExecuteMso($_.Key)
        }
    }

}

function Get-ActiveWordDocumentInsertedText {
    <#
        .SYNOPSIS
        現在開いている Word 文書に変更履歴で挿入された文字情報を取得する
    #>
    $doc = Get-ActiveWordDocument
    if (-not $doc) { return }
    $wdConst = @{
        1 = "Insert";
        15 = "Moved";
    }
    $doc.Revisions | ForEach-Object {
        if ($_.Type -in $wdConst.Keys) {
            [PSCustomObject]@{
                "Type" = $wdConst[$_.Type];
                "Text" = $_.Range.Text;
            } | Write-Output
        }
    }
}

function Get-ActiveWordDocumentInformation {
    <#
        .SYNOPSIS
        現在開いている Word 文書の体裁情報を取得する
    #>
    param (
        [switch]$acceptRevision
    )
    $wd = Get-ActiveWordApp
    if (-not $wd) {
        return
    }
    if ($acceptRevision) {
        $wd.ActiveDocument.TrackRevisions = $false
        $wd.ActiveDocument.AcceptAllRevisions()
    }

    $nPage = $wd.Selection.Information(4)
    $doc = $wd.Activedocument
    $normalStyleFontSize = $doc.Styles([WdConst]::wdStyleNormal).Font.Size

    $doc.Name | Write-Host -ForegroundColor Cyan
    $sections = $doc.Sections
    foreach ($sec in $sections) {
        $sec.PageSetup.LineNumbering.Active = $true
        $sec.PageSetup.LineNumbering.RestartMode = [WdConst]::wdRestartPage
        $charsSetup = $sec.PageSetup.CharsLine
        $linesSetup = $sec.PageSetup.LinesPage
        $fontSizes = $sec.Range.Paragraphs | ForEach-Object {$_.Range.Font.Size}
        $mainFontSize = ($fontSizes | Group-Object | Sort-Object Count | Select-Object -Last 1).Name
        $actualChars = [System.Math]::Floor($normalStyleFontSize * $charsSetup / $mainFontSize)
        $actualMaximum = $actualChars * $linesSetup * $nPage
        [PSCustomObject]@{
            "FontSize(most frequently used)" = $mainFontSize;
            "Lines(defined by page-setup)" = $linesSetup;
            "Chars(defined by page-setup)" = $charsSetup;
            "Chars(actually on paper)" = $actualChars;
            "Pages" = $nPage;
            "MaxChars(actually on paper)" = $actualMaximum;
        } | Write-Output

        "`n字詰め:{0} 行取り:{1} ページ:{2}" -f $actualChars, $linesSetup, $nPage | Write-Host -ForegroundColor Green
        if ($sections.Count -eq 1) {
            @($actualChars, $linesSetup, $nPage) -join "`t" | Set-Clipboard
        }
    }

    $wdStory = 6
    $wd.Selection.EndKey($wdStory) > $null

    if ($sections.Count -gt 1) {
        Write-Host "this document has multiple sections:" -ForegroundColor Magenta
    }
    else {
        "Copied above information!" | Write-Host
    }
    "行番号を強制的に表示しました。文書を閉じるときに保存しないようにご注意ください" | Write-Host -ForegroundColor Yellow
}
Set-Alias dInfo Get-ActiveWordDocumentInformation


function Copy-ActiveWordDocumentForCleanup {

    $doc = Get-ActiveWordDocument
    if (-not $doc) { return }

    $doc.TrackRevisions = $false
    Write-Host "Turned off track-revisions"
    $doc.AcceptAllRevisions()
    Write-Host "Accepted all revisions"
    $doc.Save()
    Write-Host "Saved '$($doc.Name)'"

    $orgPath = $doc.Fullname
    $newPath = $orgPath -replace "(\.docx?)$", '_cmtleft$1'
    Copy-Item -Path $orgPath -Destination $newPath
    Write-Host "Copied current document"

    $doc.DeleteAllComments()
    Write-Host "Removed all comments on this document"

}


class WdStyler {
    [System.__ComObject]$Document
    [System.__ComObject]$BaseStyle


    WdStyler() {
        $wd = Get-ActiveWordApp
        if ($wd) {
            $wd.ActiveDocument.TrackFormatting = $false
            $this.Document = $wd.ActiveDocument
            $this.BaseStyle = $this.Document.Styles([WdConst]::wdStyleNormal)
        }
    }

    [void] SetMarker () {
        $doc = $this.Document
        if (-not $doc) { return }
        @{
            "yMarker1" = [PSCustomObject]@{"fill"="#f5ff3d"; "border"="#1700c2"; "level"=[char]1};
            "yMarker2" = [PSCustomObject]@{"fill"="#97ff57"; "border"="#ff007b"; "level"=[char]2};
            "yMarker3" = [PSCustomObject]@{"fill"="#5efffc"; "border"="#ffaa00"; "level"=[char]3};
            "yMarker4" = [PSCustomObject]@{"fill"="#ff91fa"; "border"="#167335"; "level"=[char]4};
            "yMarker5" = [PSCustomObject]@{"fill"="#ffca59"; "border"="#2f5773"; "level"=[char]5};
            "yMarker6" = [PSCustomObject]@{"fill"="#d6d6d6"; "border"="#0f1c24"; "level"=[char]6};
        }.GetEnumerator() | ForEach-Object {
            $styleName = $_.Key
            $style = $doc.Styles.Add($styleName, [WdConst]::wdStyleTypeParagraphOnly)
            $style.ParagraphFormat = $this.BaseStyle.ParagraphFormat
            $fillColor = [OfficeColor]::FromColorcode($_.Value.fill)
            $borderColor = [OfficeColor]::FromColorcode($_.Value.border)
            $level = $_.Value.level
            foreach ($i in -4..-1) {
                $style.ParagraphFormat.Borders($i).LineStyle = [WdConst]::wdLineStyleSingle
                $style.ParagraphFormat.Borders($i).LineWidth = [WdConst]::wdLineWidth050pt
                $style.ParagraphFormat.Borders($i).Color = $borderColor
            }
            $style.Font = $this.BaseStyle.Font
            $style.NextParagraphStyle = $this.BaseStyle
            $style.ParagraphFormat.Shading.BackgroundPatternColor = $fillColor
            $style.ParagraphFormat.OutlineLevel = $level
            $style.QuickStyle = $true
        }
    }

    [void] SetCharacter () {
        $doc = $this.Document
        if (-not $doc) { return }
        @{
            "yChar1" = [PSCustomObject]@{"Color"="#ffda0a"; "Line"=[wdConst]::wdUnderlineThick;}
            "yChar2" = [PSCustomObject]@{"Color"="#66bdcc"; "Line"=[wdConst]::wdUnderlineDotDashHeavy;}
            "yChar3" = [PSCustomObject]@{"Color"="#a3ff52"; "Line"=[wdConst]::wdUnderlineDottedHeavy;}
            "yChar4" = [PSCustomObject]@{"Color"="#ff7d95"; "Line"=[wdConst]::wdUnderlineDouble;}
            "yChar5" = [PSCustomObject]@{"Color"="#bf3de3"; "Line"=[wdConst]::wdUnderlineDashHeavy;}
            "yChar6" = [PSCustomObject]@{"Color"="#ff9500"; "Line"=[wdConst]::wdUnderlineWavyHeavy;}
        }.GetEnumerator() | ForEach-Object {
            $styleName = $_.Key
            $style = $doc.Styles.Add($styleName, [WdConst]::wdStyleTypeCharacter)
            $style.Font = $this.BaseStyle.Font
            $style.Font.Shading.BackgroundPatternColor = [OfficeColor]::FromColorcode($_.Value.Color)
            $style.Font.Color = [OfficeColor]::FromColorcode("#111111")
            $style.Font.Underline = $_.Value.Line
            $style.QuickStyle = $true
        }
    }

    [void] SetTable () {
        $doc = $this.Document
        if (-not $doc) { return }
        @{
            "yTable1" = "#2b70ba";
            "yTable2" = "#fc035a";
            "yTable3" = "#0d942a";
            "yTable4" = "#ff4f14";
            "yTable5" = "#fffb00";
        }.GetEnumerator() | ForEach-Object {
            $styleName = $_.Key
            $style = $doc.Styles.Add($styleName, [WdConst]::wdStyleTypeTable)
            $style.Font = $this.BaseStyle.Font
            foreach ($i in -4..-1) {
                $style.Table.Borders($i).LineStyle = [WdConst]::wdLineStyleSingle
                $style.Table.Borders($i).LineWidth = [WdConst]::wdLineWidth150pt
                $style.Table.Borders($i).Color = [OfficeColor]::FromColorcode($_.Value)
                $style.Table.Shading.BackgroundPatternColor = [OfficeColor]::FromColorcode("#eeeeee")
            }
        }
    }

}

function Set-MyStyleToActiveWordDocument {
    <#
        .SYNOPSIS
        現在開いている Word 文書に自作スタイルを適用する
    #>
    $styler = [WdStyler]::new()
    $styler.SetMarker()
    $styler.SetCharacter()
    $styler.SetTable()
}

function Invoke-ConvertNumberToTextOnActiveWordDocument {
    <#
        .SYNOPSIS
        現在開いている Word 文書中の自動入力数値を文字列に変換する
    #>
    $doc = Get-ActiveWordDocument
    if (-not $doc) { return }
    $doc.ConvertNumbersToText([WdConst]::wdNumberAllNumbers)
}

function Set-ActiveWordDocumentMarkerEraser {
    $wd = Get-ActiveWordApp
    if (-not $wd) { return }
    $wdFindContinue = 1

    $wdStory = 6
    $wd.Selection.HomeKey($wdStory) > $null

    $wd.Selection.Find.ClearFormatting()
    $wd.Selection.Find.MatchFuzzy = $false
    $wd.Selection.Find.Forward = $true
    $wd.Selection.Find.Text = ""
    $wd.Selection.Find.Wrap = $wdFindContinue
    $wd.Selection.Find.Format = $true
    $wd.Selection.Find.Highlight = $true
    $wd.Selection.Find.Replacement.Text = ""
    $wd.Selection.Find.Replacement.Highlight = $true

    $wd.Selection.Range.HighlightColorIndex = 0

}



class DocDiff {

    static [datetime] GetLastSaveTime([string]$path) {
        $file = Get-Item -LiteralPath $path
        $shell = New-Object -ComObject Shell.Application
        $shellFolder = $shell.namespace($file.Directory.FullName)
        $shellFile = $shellFolder.parseName($file.Name)
        $s = $shellFolder.getDetailsOf($shellFile, 154)-split "[^\d]+"
        return Get-Date -Year $s[1] `
            -Month $s[2] `
            -Day $s[3] `
            -Hour $s[4] `
            -Minute $s[5] `
            -Second 0
    }

    static [int] $destination = 2
    static [int] $granularity = 0
    static [bool] $compareFormatting = $true
    static [bool] $compareCaseChanges = $true
    static [bool] $compareWhitespace = $true
    static [bool] $compareTables = $true
    static [bool] $compareHeaders = $true
    static [bool] $compareFootnotes = $true
    static [bool] $compareTextboxes = $true
    static [bool] $compareFields = $true
    static [bool] $compareComments = $true
    static [bool] $compareMoves = $true
    static [int] $wdShowSourceDocumentsBoth = 3
    static [bool] $IgnoreAllComparisonWarnings = $true

}


function Invoke-DiffFromActiveWordDocumnt {
    <#
        .SYNOPSIS
        現在開いている文書から比較する
    #>
    param (
        [parameter(Mandatory)][string]$diffTo
    )
    $wd = Get-ActiveOffice -app "Word.Application"
    if (-not $wd) { return }
    $origin = $wd.ActiveDocument
    $revPath = (Resolve-Path $diffTo).Path
    $revised = $null
    try {
        $revised = $wd.Documents($revPath)
    }
    catch {
        $revised = $wd.Documents.Open($revPath)
    }
    if (-not $revPath) {
        return
    }
    $wd.CompareDocuments(
        $origin,
        $revised,
        [DocDiff]::destination,
        [DocDiff]::granularity,
        [DocDiff]::compareFormatting,
        [DocDiff]::compareCaseChanges,
        [DocDiff]::compareWhitespace,
        [DocDiff]::compareTables,
        [DocDiff]::compareHeaders,
        [DocDiff]::compareFootnotes,
        [DocDiff]::compareTextboxes,
        [DocDiff]::compareFields,
        [DocDiff]::compareComments,
        [DocDiff]::compareMoves,
        [Type]::Missing,
        [DocDiff]::IgnoreAllComparisonWarnings
    ) > $null
    $wd.ActiveWindow.ShowSourceDocuments = [DocDiff]::wdShowSourceDocumentsBoth
}

function Invoke-MergeToActiveWordDocumnt {
    <#
        .SYNOPSIS
        現在開いている文書と組み込み比較する
    #>
    param (
        [parameter(Mandatory)][string]$pathToMerge
    )
    $wd = Get-ActiveWordApp
    if (-not $wd) { return }
    $origin = $wd.ActiveDocument
    $revPath = (Resolve-Path $pathToMerge).Path
    $revised = $null
    try {
        $revised = $wd.Documents($revPath)
    }
    catch{
        $revised = $wd.Documents.Open($revPath)
    }
    if (-not $revPath) {
        return
    }
    $wd.MergeDocuments(
        $origin,
        $revised,
        [DocDiff]::destination,
        [DocDiff]::granularity,
        [DocDiff]::compareFormatting,
        [DocDiff]::compareCaseChanges,
        [DocDiff]::compareWhitespace,
        [DocDiff]::compareTables,
        [DocDiff]::compareHeaders,
        [DocDiff]::compareFootnotes,
        [DocDiff]::compareTextboxes,
        [DocDiff]::compareFields,
        [DocDiff]::compareComments
    ) > $null
    $wd.ActiveWindow.ShowSourceDocuments = [DocDiff]::wdShowSourceDocumentsBoth
}


function Get-EmbeddedDataOnActiveWordDocument {
    $wd = Get-ActiveWordApp
    if (-not $wd) { return }

    $chart = $null
    if ($wd.Selection.Range.InlineShapes.Count -eq 1 -and $wd.Selection.Range.InlineShapes(1).HasChart) {
        $chart = $wd.Selection.Range.InlineShapes(1).Chart
    }
    if ($wd.Selection.ShapeRange.Count -eq 1 -and $wd.Selection.ShapeRange(1).HasChart) {
        $chart = $wd.Selection.ShapeRange(1).Chart
    }
    if (-not $chart) {
        "selecte ONE chart!" | Write-Host -ForegroundColor Magenta
        return
    }

    $nSeries = $chart.SeriesCollection().Count
    1..$nSeries | ForEach-Object {
        $label = $chart.SeriesCollection($_).Name
        $xVals = $chart.SeriesCollection($_).XValues
        $vals = $chart.SeriesCollection($_).Values
        $data = 1..$xVals.Count | ForEach-Object {
            return [PSCustomObject]@{
                "X" = $xVals.get($_);
                "Value" = $vals.get($_);
            }
        }
        return [PSCustomObject]@{
            "Label" = $label;
            "Data" = $data;
        }
    }

}



function Add-Image2ActivePptSlide {
    param (
        [int]$widthCm
    )

    Class ActivePresentation {
        static [int] $ppLayoutBlank = 12
    }

    $presen = Get-ActivePptPresentation
    if (-not $presen) { return }

    $images = @($input)
    if (-not $images) { return }

    if ((Read-Host "「ファイル内のイメージを圧縮しない」の設定はオンになっていますか？ (y/n)") -ne "y") {
        return
    }

    $slideWidth = $presen.PageSetup.SlideWidth
    $slideHeight = $presen.PageSetup.SlideHeight

    $images | ForEach-Object {
        $slideIdx = $presen.Slides.Count + 1
        $presen.Slides.Add($slideIdx, [ActivePresentation]::ppLayoutBlank) > $null
        $filePath = $_.Fullname
        $linkToFile = $false
        $saveWithDocument = $true
        $left = 0
        $top = 0
        $inserted = $presen.Slides($slideIdx).Shapes.AddPicture(
            $filePath,
            $linkToFile,
            $saveWithDocument,
            $left,
            $top
        )
        if ($widthCm) {
            $inserted.Width = [System.Math]::Round([int]$widthCm * 10 / 0.35)
        }
        $inserted.Left = ($slideWidth - $inserted.Width) / 2
        $inserted.Top = ($slideHeight - $inserted.Height) / 2
    }
}


function Copy-ActiveExcelSheet {
    <#
        .SYNOPSIS
        現在開いている Excel シートを複製する
    #>
    param (
        [ValidateSet("newBook", "before", "after")][string]$position = "newBook"
    )
    $sht = Get-ActiveExcelSheet
    if (-not $sht) { return }
    $default = [Type]::Missing
    switch ($position) {
        "newBook" { $sht.Copy() ; break }
        "after" { $sht.Copy($default, $sht) ; break }
        "before" { $sht.Copy($sht, $default) ; break }
    }
}

function Set-ActiveExcelBookPrintArea {
    <#
        .SYNOPSIS
        現在開いている Excel シートの印刷設定を統一する
    #>
    param(
        [switch]$landscape
        ,[switch]$minimalMargin
    )
    $exc = Get-ActiveExcelApp
    if (-not $exc) { return }
    $exc.ActiveWorkbook.Sheets | ForEach-Object {
        $_.PageSetup.Zoom = $false
        if ($minimalMargin) {
            # unit: inch
            $_.PageSetup.LeftMargin = 25
            $_.PageSetup.RightMargin = 25
            $_.PageSetup.TopMargin = 25
            $_.PageSetup.BottomMargin = 25
            $_.PageSetup.HeaderMargin = 20
            $_.PageSetup.FooterMargin = 20
        }
        $_.PageSetup.FitToPagesTall = 1
        $_.PageSetup.FitToPagesWide = 1
        $_.PageSetup.Orientation = ($landscape)? 2 : 1
        "setting print area: {0}" -f $_.Name | Write-Host
    }
    $exc.ActiveWorkbook.PrintOut([Type]::Missing, [Type]::Missing, 1, $true)
}


function Format-ActiveExcelChart {
    class XlConst {
        static $xlCategory = 1
        static $xlValue = 2
        static $xlSeriesAxisue = 3
        static $xlTickMarkCross = 4
        static $xlTickMarkInside = 2
        static $xlTickMarkNone = -4142
        static $xlTickMarkOutside = 3
        static $xlColumnClustered = 51
        static $xlColumnStacked = 52
        static $xlColumnStacked100 = 53
        static $xlBarClustered = 57
        static $xlBarStacked = 58
        static $xlBarStacked100 = 59
    }

    $e = Get-ActiveExcelApp
    if (-not $e) { return }
    $chart = $e.ActiveChart
    if (-not $chart) { return }

    $e.Selection.Format.Line.Visible = $false

    $verticalAxis = $chart.Axes([XlConst]::xlValue)
    $verticalAxis.Format.Line.Visible = $true
    $verticalAxis.MajorGridlines.Delete()
    $verticalAxis.Format.Line.ForeColor.RGB = [OfficeColor]::FromColorcode("#000000")
    $verticalAxis.MajorTickMark = [XlConst]::xlTickMarkOutside

    $horizontalAxis = $chart.Axes([XlConst]::xlCategory)
    $horizontalAxis.Format.Line.Visible = $true
    $horizontalAxis.AxisBetweenCategories = $true
    $horizontalAxis.MajorGridlines.Delete()
    $horizontalAxis.Format.Line.ForeColor.RGB = [OfficeColor]::FromColorcode("#000000")
    $horizontalAxis.MajorTickMark = [XlConst]::xlTickMarkNone

    $barChartType = @([XlConst]::xlColumnClustered, [XlConst]::xlColumnStacked, [XlConst]::xlColumnStacked100, [XlConst]::xlBarClustered, [XlConst]::xlBarStacked, [XlConst]::xlBarStacked100)
    if ($chart.ChartType -notin $barChartType) {
        $horizontalAxis.MinorTickMark = [XlConst]::xlTickMarkOutside
    }
    else {
        $horizontalAxis.MinorTickMark = [XlConst]::xlTickMarkNone
    }

}


function Remove-PaddingFromActiveWordSelectionTableCells {
    $wd = Get-ActiveWordApp
    if (-not $wd) {
        return
    }
    $wd.Selection.Cells | ForEach-Object {
        $_.TopPadding = 0
        $_.BottomPadding = 0
        $_.LeftPadding = 0
        $_.RightPadding = 0
    }
}