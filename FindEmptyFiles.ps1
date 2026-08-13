Get-ChildItem -Path "E:\infor\sce\" -Recurse -File |
Where-Object { $_.Length -eq 0 } |
Select-Object @{Name='Full Path'; Expression={$_.FullName}},
              @{Name='Last Modified'; Expression={$_.LastWriteTime}} |
Format-Table  -AutoSize
