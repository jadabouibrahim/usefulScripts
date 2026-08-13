$cred = Get-Credential
Invoke-Command -ComputerName qnie -ScriptBlock { NET TIME /SET /YES } -Credential $cred
