$earPath = "C:\Infor\sce\wildfly-8.2.0.Final\scprd-reports1\deployments\scprd_scereports.war"
$pattern = "CBM"

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($earPath)

foreach ($entry in $zip.Entries) {
    if ($entry.FullName -like "*.rptdesign") {
        $reader = New-Object IO.StreamReader($entry.Open())
        $content = $reader.ReadToEnd()
        $reader.Close()

        if ($content -match $pattern) {
            Write-Host "Match in: $($entry.FullName)"
        }
    }
}

$zip.Dispose()