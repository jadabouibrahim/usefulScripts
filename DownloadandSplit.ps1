# loading winscp as our connection adapter
Add-Type -Path "C:\Users\Infor\AppData\Local\Programs\WinSCP\WinSCPnet.dll"

#configure the session options for the connection
$sessionOptions = New-Object WinSCP.SessionOptions -Property @{
    Protocol = [WinSCP.Protocol]::Sftp
    HostName = "FTP_HOST"
    UserName = "FTP_USER"
    Password = "FTP_PASSWORD"
    PortNumber = "FTP_PORT"

}

$sessionOptions.GiveUpSecurityAndAcceptAnySshHostKey = $True


$session = New-Object WinSCP.Session


try {

    # Open the session
    $session.Open($sessionOptions)

    # Define the remote paths
    $remoteDirectory = "SFC/IN/"


    
    $remoteFiles = $session.ListDirectory($remoteDirectory)

    # ONLY DOWNLOADING THE SKU FILE (MFD000*.DAT)
    $filteredFiles = $remoteFiles.Files | Where-Object { $_.Name -like "MFD000*.dat" }

    # Loop through the filtered files and download them
    foreach ($file in $filteredFiles) {
        $remoteFilePath = $remoteDirectory + $file.Name
        $localFilePath = "C:\Integration\IN\" + $file.Name

        # Download each file
        $transferOptions = New-Object WinSCP.TransferOptions
        $transferOptions.TransferMode = [WinSCP.TransferMode]::Binary

        Write-Host "Downloading file: $($file.Name)"


        $transferResult = $session.GetFiles($remoteFilePath, $localFilePath, $False, $transferOptions)

        # Check if the transfer was successful
        if ($transferResult.IsSuccess) {
            Write-Output "Successfully downloaded: $($file.Name)"
            $session.RemoveFile($remoteFilePath)

        } else {
            foreach ($failure in $transferResult.Failures) {
                Write-Error "Transfer failure: $($failure.Message)"
            }
        }
    }
}
catch {
       Write-Error "Error occurred: $($_.Exception.Message)"
}
finally {
    # Ensure the session is closed, even in case of an error
    if ($session.Opened) {
        $session.Dispose()
    }
}


################################################### 

# Splitting and compressing the file
 
cd "C:\Integration\IN"

# Getting all the MFD00* files in case we had more than one (realistically only one file will be processed at a time)
$files = Get-ChildItem -Path "." -Filter "mfd000*.dat"


# setting how many sku per file 
$maxLinesPerFile = 5000

md -Force ".\split"


foreach ($file in $files) {
    
    $fileCount = 1
	$lineCount = 0
    $splitLines = @()
    $lastSku = ""

    # the uft8 noBom encoding is necessary so that ION can correctly read the file 
	$utf8NoBom = New-Object System.Text.UTF8Encoding $false
	
	
	# reading the file line by line 
	 $lines = Get-Content -Path $file.FullName
    # reversing the array so that the last line (mosr recent sku) comes firts 
	[array]::Reverse($lines)
	
	
	
	#intializng the output array
	$output = @()

    # removing duplicates 
	foreach ($line in $lines) {
		if ($lastSku -eq ""){
			$output += $line
			$lastsku = $line.Substring(54, 9)   # sku is of 9 characters starting for index 54     
		
		} elseif ($lastSku -ne   $line.Substring(54, 9)){
			$output += $line
			$lastsku = $line.Substring(54, 9)   
		}
	}
	
	
	# spliting the output array ( clear from duplicates ) into the respective sub files
	foreach ($line in $output) {
		
		
		$splitLines += $line.Substring(0,261)# sometimes garbage data is passed after real data so we are taking only the valid part 
		$lineCount++
        
         #initializing a new writer for the new file 
            if($lineCount -eq 1) {
		        #intialize the writer on the first line    
                $writer = New-Object System.IO.StreamWriter ("$PWD\split\{0}_{1}.dat" -f $file.BaseName, $fileCount), $false, $utf8NoBom
                
            }
        
	
	    # when we reach the target lines per file we write the final line and then reset the params 
		if ($lineCount -eq $maxLinesPerFile) {
			
			try {
			    foreach ($l in $splitLines) {
                    $writer.WriteLine($l)
                }
			}
            catch {
                Write-Host  $lineCount + " " + $fileCount
            }
			finally {
                #disposing the writer after the final line is written 
			    $writer.Dispose()
			}
			
	
	        #resetting the params 
			$splitLines = @()
			$lineCount = 0
			$fileCount++
            
           
		}
	}
	
	
	if ($splitLines.Count -gt 0) {
        
        if ($writer -and $writer.BaseStream -ne $null) {
           $writer.Dispose()
          }
        
        $writer = New-Object System.IO.StreamWriter ("$PWD\split\{0}_{1}.dat" -f $file.BaseName, $fileCount), $false, $utf8NoBom

        #writing content 
	    $content = $splitLines -join [Environment]::NewLine
		$writer.Write($content)
			
			
	}

    # in case the last file was not a full split (aka $lineCount not equal $maxLinesPerFile in the last file) the writer would still be open and this needs to be disposed 
    if ($writer -and $writer.BaseStream -ne $null) {
        $writer.Dispose()
    }
    
    
	# compressing the processed file and copying it to the Arch directory 
	Compress-Archive -Path $file.FullName -Destination ("$PWD\Arch\{0}.zip" -f $file.BaseName)
	
	if (Test-Path ("$PWD\Arch\{0}.zip" -f $file.BaseName)) {
        # if archiving was successful we can remove the processed file 
		Remove-Item -Path $file.FullName  -Force
	}
    
}