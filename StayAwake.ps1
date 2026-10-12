# StayAwake script to keep windows awake by two options:
# moving the mouse randomly 
# sending space evet 5 seconds 
Add-Type -AssemblyName System.Windows.Forms
Add-Type '[DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);' -Name Keyboard -Namespace Win32
Add-Type '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags);' -Name Power -Namespace Win32

while (1) {
  # this is usueful to track time. Open empty editor and devide by 12 to get time in minutes 
  [Win32.Keyboard]::keybd_event(0x20, 0, 0, [UIntPtr]::Zero)  # Space down
  [Win32.Keyboard]::keybd_event(0x20, 0, 2, [UIntPtr]::Zero)  # Space up


  $positionX = Get-Random -Minimum 1 -Maximum 1000
  $positionY = Get-Random -Minimum 1 -Maximum 1000 # keeping the maximum below the screen limits of 1920*1080 
  [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($positionX, $positionY) # move the mouse 


  #Had to add this since new powerpolicy was not registering the update and thus screen was locking 
  [void][Win32.Power]::SetThreadExecutionState(2147483651)
   
  Start-Sleep -seconds 5
}   