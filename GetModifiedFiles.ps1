# Root folder to search
$folder = "C:\dev"

# Get today's and yesterday's dates (without time component)
$today = (Get-Date).Date
$yesterday = $today.AddDays(-1)

# Find all .java files recursively and filter by LastWriteTime
Get-ChildItem -Path $folder -Recurse -Include *.*  -Exclude *.class|
    Where-Object {
        $_.LastWriteTime.Date -eq $today -or $_.LastWriteTime.Date -gt $yesterday
    } |
    Select-Object FullName, LastWriteTime |
    Sort-Object LastWriteTim
