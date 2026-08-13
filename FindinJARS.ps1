
$jarDirectory = "C:\Users\jad.abouibrahim\temp\service"

$targetFileName = "PopulateContainerDetails.class"

Get-ChildItem -Path $jarDirectory -Filter *.jar -Recurse | ForEach-Object {
    $jarPath = $_.FullName

    try {
       
        $entries = & jar tf $jarPath

        foreach ($entry in $entries) {
            if ($entry -like "*$targetFileName") {
                Write-Host "Found in: $jarPath --> $entry"
            }
        }
    }
    catch {
        Write-Warning "Failed to read jar: $jarPath. Error: $_"
    }
}
