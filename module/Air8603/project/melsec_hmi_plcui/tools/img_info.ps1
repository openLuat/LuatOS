param([string]$Dir)
Add-Type -AssemblyName System.Drawing
Get-ChildItem -LiteralPath $Dir -Filter *.png | ForEach-Object {
    $img = [System.Drawing.Image]::FromFile($_.FullName)
    Write-Output ("{0,-26} {1,4}x{2,-4} {3,5} KB" -f $_.Name, $img.Width, $img.Height, [int]($_.Length / 1024))
    $img.Dispose()
}
