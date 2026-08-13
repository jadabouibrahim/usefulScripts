mkdir C:\TempShare

icacls C:\TempShare /grant USER_FROM_WHOAMI:(OI)(CI)F

net share TempShare=C:\TempShare /GRANT:USER_FROM_WHOAMI,FULL

REM to make sure that the file the share setup is correct run 
net share