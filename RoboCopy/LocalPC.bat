net use \\targetServerIP\TempShare /user:USER_FROM_WHOAMI PASSWORD


REM  To make sure you are using the correct user and have acess of the network run 
dir \\targetServerIP\TempShare


robocopy SOURCE_DIRECTORY \\targetServerIP\TempShare fileName /Z /MT:8 /R:1 /W:1