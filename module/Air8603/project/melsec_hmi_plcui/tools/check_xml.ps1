param([string]$Path)

$ErrorActionPreference = "Stop"
try {
    $doc = New-Object System.Xml.XmlDocument
    $doc.Load($Path)
    $pages = $doc.SelectNodes("//page").Count
    $ids = $doc.SelectNodes("//*[@id]")
    $dups = $ids | Group-Object -Property id | Where-Object { $_.Count -gt 1 }
    Write-Output ("XML OK  pages={0}  id-nodes={1}" -f $pages, $ids.Count)
    if ($dups) {
        Write-Output "DUPLICATE IDS:"
        $dups | ForEach-Object { Write-Output ("  " + $_.Name + " x" + $_.Count) }
    } else {
        Write-Output "no duplicate ids"
    }
} catch {
    Write-Output ("XML ERROR: " + $_.Exception.Message)
}
