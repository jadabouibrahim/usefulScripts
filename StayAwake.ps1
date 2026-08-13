# StayAwake script to keep windows awake by two options:
# moving the mouse randomly 
# sending space evet 5 seconds 
$wsh = New-Object -ComObject WScript.Shell
while (1) {

  $wsh.SendKeys(' ')# this is usueful to track time. Open empty editor and devide by 12 to get time in minutes 

  $positionX = Get-Random -Minimum 1 -Maximum 1000
  $positionY = Get-Random -Minimum 1 -Maximum 1000 # keeping the maximum below the screen limits of 1920*1080 
  [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($positionX, $positionY) # move the mouse 
  Start-Sleep -seconds 5
}  