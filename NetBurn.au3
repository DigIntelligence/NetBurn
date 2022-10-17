#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_AU3Check_Parameters=-d
#EndRegion ;**** Directives created by AutoIt3Wrapper_GUI ****
#include <File.au3>
#include <Array.au3>
#include <GUIConstants.au3>
#include <MsgBoxConstants.au3>
#include <StringConstants.au3>
#include <Date.au3>
#include <GUIEdit.au3>
#include <FontConstants.au3>
#include <FileConstants.au3>

Global $Title  = "NetBurn"
Global $Version  = "1.25"

#pragma compile(ProductName, "NetBurn")
#pragma compile(ProductVersion, 1.25)
#pragma compile(CompanyName, "Digital Intelligence")
#pragma compile(Comments, Author: Edward C. Van Every")

Global $IniFile
Global $OpMode
Global $LogFile
Global $IPAddress
Global $WatchArray[1] = [0]
Global $PTBurnJobLog
Global $FullTitle = $Title & " v" & $Version
Global $LogCtrlID
Global $LogArray

; INI File Settings
Global $SearchFolder=""
Global $JobRequestFolder="C:\PTBurnJobs"
Global $SortBy="None"
Global $PollTime
Global $PTBurnOptions

; Ensure we are running as Administrator (If Needed)
;If Not IsAdmin() Then
;    ShellExecute(@AutoItExe, "", "", "runas")
;    ProcessClose(@AutoItPID)
;EndIf

; Ensure Master Script Directory is Set As Working Dir
FileChangeDir(@ScriptDir)

; Determine INI Config file name based on Name of the Script
$IniFile = StringTrimRight(@ScriptFullPath,4) & ".ini"

; Determine Log file name based on Name of the Script
$LogFile = StringTrimRight(@ScriptFullPath,4) & ".log"

; Determine Remote Jobs Submission sub-folder (NetBurnJobs)
; Run this App from a Network Share for polled remote retrieval of jobs
; This allows Image files to be copied down (cached) to a local drive for processing (then auto-deleted)
Local $RemoteJobsFolder = StringTrimRight(@ScriptFullPath,4) & "Jobs"
If NOT FileExists($RemoteJobsFolder) Then DirCreate($RemoteJobsFolder)

; Get Local IP Address (for Logging)
$IPAddress = GetLocalIP()

; Get Configuration Options
GetConfig()
$PTBurnJobLog = $JobRequestFolder & "\Log\SystemLog.txt"

; Get Pre-Defined Job Information (from INI File)
Local $OptionInfo = GetOptionInfo()
Local $OptionCount = UBound($OptionInfo)

; Determine if Job Info should be sorted
if ($SortBy = "JobName") Then
	_ArraySort($OptionInfo, 0, 0, 0, 0)
Elseif ($SortBy = "Description") Then
	_ArraySort($OptionInfo, 0, 0, 0, 1)
ElseIf ($SortBy = "ImageFile") Then
	_ArraySort($OptionInfo, 0, 0, 0, 2)
EndIf

; Determine if we are the PTBurn Host or a Network Client
Local $LogLines = 0
Local $LogWindowHeight = 0
If FileExists($JobRequestFolder) Then
	$OpMode="Host"
	$LogLines = 11
	$LogWindowHeight = ($LogLines * 14) + 46
Else
	$OpMode="Client"
EndIf

; Init the Tail
If $OpMode = "Host" Then
	$LogArray = TailInit($LogFile, $LogLines)
	If $LogArray[0] = -1 Then
		MsgBox($MB_ICONERROR, $FullTitle, "Fatal Error: Unable to Open Log File: " & $LogFile)
		Exit
	EndIf
EndIf

; Log Startup (Can't Log till AFTER the tail Array is established as LogMsg uses it...)
LogMsg("Startup (v" & $Version & ")")

; Here we go!
Local $OptionSpace = 30
Local $OptionsHeight = Ceiling($OptionCount/2) * $OptionSpace
Local $GUIWidth = 800

GUICreate($FullTitle & " (" & $OpMode & ")", $GUIWidth, 60 + $OptionsHeight + $LogWindowHeight, -1, -1)

Local $VIndex
Local $HPos
For $i = 0 To $OptionCount-1
	$VIndex = Floor($i/2)
	$HPos = 20
	If BitAND($i, 1) Then $HPos += ($GUIWidth/2)
	$OptionInfo[$i][3] = GUICtrlCreateButton($OptionInfo[$i][1], $HPos, 20 + ($VIndex * $OptionSpace), ($GUIWidth/2) - 40 , 20)
Next

If $OpMode = "Host" Then
	$LogCtrlID = GuiCtrlCreateEdit("", 20, $OptionsHeight + 25, $GUIWidth - 40, $LogWindowHeight - 20, $WS_HSCROLL + $ES_READONLY)
	GuiCtrlSetFont($LogCtrlID, 8.5, $FW_DONTCARE, $GUI_FONTNORMAL, "Courier New")
EndIf

Local $x = (($GuiWidth - (2 * 50)) / 3)
Local $Search = GUICtrlCreateButton("Search", $x, $OptionsHeight + $LogWindowHeight + 25, 50, 20)
Local $Exit   = GUICtrlCreateButton("Exit", (2 * $x) + 50, $OptionsHeight + $LogWindowHeight + 25, 50, 20)

GUISetState()

GUICtrlSetData($LogCtrlID, _ArrayToString($LogArray, @CRLF, 1))

Local $msg
Local $hTimer = TimerInit()
Do
	$msg = GUIGetMsg()

	Switch $msg
		Case $Search
			SubmitJob("", 0, $OpMode)
		Case $Exit
			ExitLoop
	EndSwitch

	For $i = 0 To $OptionCount-1
		if $msg = $OptionInfo[$i][3] then
			SubmitJob($OptionInfo[$i][2], 0, $OpMode)
			ExitLoop
		EndIf
	Next

	; Do Remote Polling Here (Only the Host)
	If $OpMode = "Host" Then
		If (TimerDiff($hTimer)/1000) > $PollTime Then

			; Any Client Jobs Submitted?
			PollJobs($RemoteJobsFolder)

			; Watch for any "live" Jobs that have been fully completed by PTBurn (and log them)
			CheckWatchedJobs()

			; Check to see if we need to update the log Control
			If Tail($LogArray) > 0 Then GUICtrlSetData($LogCtrlID, _ArrayToString($LogArray, @CRLF, 1))

			$hTimer = TimerInit()
		EndIf
	EndIf

Until $msg = $GUI_EVENT_CLOSE

GUIDelete()

; Log Shutdown
LogMsg("ShutDown")

; Clean Up The Tail
If $OpMode= "Host" Then TailTerminate($LogArray)

Exit

;-------------------------------------------------------------------------

Func PollJobs($RemoteJobsFolder)

	; Check for the PTBurn Bug which displays a Window requesting a disc to be inserted after the jobs complete (and close it)
	; WinClose("Insert disc","Please insert a disc into drive")

	Local $hSearch, $FileName, $FullFileName, $JobID, $ImageFile, $Copies

	; Poll for Jobs submitted by Clients
	$hSearch = FileFindFirstFile($RemoteJobsFolder & "\*.ini")
    If $hSearch <> -1 Then

		While 1
			$FileName = FileFindNextFile($hSearch)
			If @error Then ExitLoop
			$FullFileName = $RemoteJobsFolder & "\" & $FileName
			$JobID = GetBaseFileName($FullFileName)

			$ImageFile = IniRead($FullFileName, "Config", "ImageFile", "")
			$Copies    = Int(IniRead($FullFileName, "Config", "Copies", "0"))

			LogMsg($JobId & " Accepted = " & $FullFileName )

			; Delete "Polled" Job info (*.ini) as sson as the needed data is extracted (BEFORE Caching).  This will HELP prevent duplicate HOSTs from Polling the same job after the first Host has grabbed it.
			FileDelete($FullFileName)

			; If Network Permissions are not correct, then files may NOT get deleted which can cause them to get "polled" (run) over and over...
			While FileExists($FullFileName)
				MsgBox($MB_ICONERROR, $FullTitle, "Warning:  Unable to Delete Network Job File!" & @CRLF & @CRLF & $FullFileName & @CRLF & @CRLF & "Check Network Permissions!"& @CRLF & "(Manually Delete File to Continue)")
				FileDelete($FullFileName)
			WEnd
;			LogMsg($JobId & " Deleted = " & $FullFileName )

			If ($ImageFile <> "") AND ($Copies > 0) Then
				SubmitJob($ImageFile, $Copies, "Poll", $JobID)
			EndIf

		WEnd

		FileClose($hSearch)
	EndIf

EndFunc

Func SubmitBatchJob($BatchFile, $Copies, $Mode, $JobID)

	Local $JobNames = IniReadSectionNames($BatchFile)
	If @error Then
		MsgBox(4096, "", "Error occurred, Batch File Not Found: " & $BatchFile)
		Return
	EndIf

	LogMsg("Batching = " & $BatchFile & " (Copies: " & $Copies & ")")

	For $i = 1 To $JobNames[0]
		if ($JobNames[$i] = "Config") then ContinueLoop
		Local $ImageFile = IniRead($BatchFile, $JobNames[$i], "ImageFile", "")
		If $ImageFile <> "" Then
			SubmitJob($ImageFile, $Copies, $Mode, $JobID)
			Sleep(100)
		EndIf
	Next

EndFunc

Func SubmitJob($ImageFile, $Copies=0, $Mode="Host", $JobID="")

	If $ImageFile = "" Then
		$ImageFile = FileOpenDialog($FullTitle & ": Please Select an Image file", $SearchFolder, "Images (*.gi;*.iso;*.nbb)", 1 + 2 )
		If @error Then
			MsgBox(4096,$FullTitle,"No File Chosen...")
			Return
		EndIf
	EndIf

	; Get Number of Discs Required
	If $Copies = 0 Then $Copies = InputBox($FullTitle, "How Many Discs Would You Like to Make?", "1")

	; Is this a Batch Job?
	Local $ImageFileExt = GetFileExtension($ImageFile)
	If $ImageFileExt = ".nbb" Then
		SubmitBatchJob($ImageFile, $Copies, $Mode, $JobID)
		Return
	ElseIf ($ImageFileExt <> ".gi") AND ($ImageFileExt <> ".iso") Then
		MsgBox(4096,$FullTitle,"Unsupported Image File: " & $ImageFile)
		Return
	EndIf

	; Calculate Base File Name
	Local $BaseFileName=GetBaseFileName($ImageFile)

	; Calculate Label File
	Local $LabelFile = StringTrimRight($ImageFile, StringLen($ImageFileExt)) & ".std"

	; Confirm Label File Exists
	If NOT FileExists($LabelFile) Then
		MsgBox(4096,$FullTitle,"Label File Does Not Exist: " & $LabelFile)
		Return
	EndIf

	; Calculate/Check Image Options File (Optional)
	Local $ImageOptionsFile = StringTrimRight($LabelFile, 4) & ".ini"
	If NOT FileExists($ImageOptionsFile) Then $ImageOptionsFile = ""

	; Generate a unique JobID (If Not Provided)
	If $JobID = "" Then $JobID = @YEAR & @MON & @MDAY & @HOUR & @MIN & @SEC & @MSEC

	Local $JobFileName
	If $Mode = "Client" Then
		$JobFileName = $RemoteJobsFolder & "\" & $JobID & ".ini"
		IniWrite($JobFileName, "Config", "ImageFile", $ImageFile)
		IniWrite($JobFileName, "Config", "Copies", $Copies)

		If NOT FileExists($JobFileName) Then
			MsgBox($MB_ICONERROR, $FullTitle, "Warning:  Unable to Create Network Job File!" & @CRLF & @CRLF & $JobFileName & @CRLF & @CRLF & "Check Network Permissions!")
		Else
			MsgBox($MB_ICONINFORMATION, $FullTitle, "Job has been Submitted" & @CRLF & @CRLF & $BaseFileName & @CRLF & @CRLF & "Copies: " & $Copies)
			LogMsg($JobId & " Requested = " & $ImageFile & " (Copies: " & $Copies & ")")
		EndIf

		Return
	EndIf

	; Host Side Processing

	; Create Job Folder (Required for auto file deletion)
	Local $JobFolder = $JobRequestFolder & "\" & $JobID
	DirCreate($JobFolder)

	; Calculate Destination IMAGE and LABEL file names
	Local $ImageFileDest = $JobFolder & "\" & $BaseFileName & $ImageFileExt
	Local $LabelFileDest = $JobFolder & "\" & $BaseFileName & ".std"

	; Generate Job File Contents
	Local $JobFileContents  = "JobID = " & $JobID & @CRLF
	$JobFileContents &= "ImageFile = " & $ImageFileDest & @CRLF
	$JobFileContents &= "PrintLabel = " & $LabelFileDest & @CRLF
	$JobFileContents &= "Copies = " & $Copies & @CRLF

	; Determine PTBurn Options
	Local $ImageOptions
	$PTBurnOptions = IniReadSection($IniFile, "PTBurn Options")
	If @error Then $PTBurnOptions[0][0] = 0

	If $ImageOptionsFile <> "" Then
		$ImageOptions = IniReadSection($ImageOptionsFile, "PTBurn Options")
		If @error Then
			$ImageOptionsFile = ""
		Else
			For $i = 1 To $PTBurnOptions[0][0]
				For $j = 1 To $ImageOptions[0][0]
					If $ImageOptions[$j][0] = $PTBurnOptions[$i][0] Then $PTBurnOptions[$i][1] = $ImageOptions[$j][1]
				Next
			Next
		EndIf
	EndIf

	For $i = 1 To $PTBurnOptions[0][0]
		$JobFileContents &= $PTBurnOptions[$i][0] & " = " & $PTBurnOptions[$i][1] & @CRLF
	Next

	If $ImageOptionsFile <> "" Then
		For $i = 1 To $ImageOptions[0][0]
			Local $Found = 0
			For $j = 1 To $PTBurnOptions[0][0]
				If $PTBurnOptions[$j][0] = $ImageOptions[$i][0] Then $Found = 1
			Next
			If $Found = 0 Then $JobFileContents &= $ImageOptions[$i][0] & " = " & $ImageOptions[$i][1] & @CRLF
		Next
	EndIf

	; Copy IMAGE and LABEL files to Job Request Folder
	Local $hCacheTimer = TimerInit()

	Local $FileSize = FileGetSize($ImageFile)
	LogMsg($JobID & " Caching (" & Int($FileSize/1048576) & " MB) = " & $ImageFile & " -> " & $ImageFileDest)
	FileCopy($ImageFile, $ImageFileDest)

	$FileSize = FileGetSize($LabelFile)
	LogMsg($JobID & " Caching (" & Int($FileSize/1024) & " KB) = " & $LabelFile & " -> " & $LabelFileDest)
	FileCopy($LabelFile, $LabelFileDest)

	LogMsg($JobID & " Caching Complete (" & ElapsedHHMMSS(TimerDiff($hCacheTimer)/1000) & ")")

	; Log if an Image Options File is being used to Override/Augment the Global PTBurn Option Settings
	If $ImageOptionsFile <> "" Then LogMsg($JobId & " Image Options = " & $ImageOptionsFile)

	; Submit (Write) Job File in Job Request Folder
	$JobFileName = $JobRequestFolder & "\" & $JobID & ".jrq"
	FileWrite($JobFileName, $JobFileContents)
	LogMsg($JobId & " Submitted = " & $ImageFile & " (Copies: " & $Copies & ")")

	; Add Job to Watch List (monitor for completion at polling intervals)
	WatchJob($JobID)

EndFunc

Func WatchJob($ID)
	$WatchArray[0] = _ArrayAdd($WatchArray, $ID)
EndFunc

Func UnWatchJob($ID)
	If $WatchArray[0] = 0 Then Return 0

	Local $Index = _ArraySearch($WatchArray, $ID)
	If $Index > 0 Then
		If _ArrayDelete($WatchArray, $Index) > 0 Then
			$WatchArray[0] -= 1
			Return 1
		EndIf
	EndIf
	Return 0
EndFunc

Func PurgeWatchArray()
	While UnWatchJob("")
	Wend
EndFunc

Func CheckWatchedJobs()
	If $WatchArray[0] = 0 Then Return

	Local $PTBurnLogEntries = FileReadToArray($PTBurnJobLog)
	If @error Then Return
	Local $LinesRead = @extended

	Local $Found = 0
	For $i = 1 To $WatchArray[0]
		Local $JobComplete = "Job Completed (" & $WatchArray[$i] & ")"
		For $j = 0 To ($LinesRead - 1)
			If StringInStr($PTBurnLogEntries[$j], $JobComplete) Then						; PTBurn has completed this job
				Local $JobStarted = "Job Started (" & $WatchArray[$i] & ")"
				For $k = 0 To $j
					If StringInStr($PTBurnLogEntries[$k], $JobStarted) Then
						$Found += 1

						Local $FieldArray = StringSplit($PTBurnLogEntries[$k], ",")
						Local $ATime = $FieldArray[3]
						$FieldArray = StringSplit($ATime, "/ ")
						Local $StartTime = $FieldArray[3] & "/" & $FieldArray[1] & "/" & $FieldArray[2] & " " & $FieldArray[4]

						$FieldArray = StringSplit($PTBurnLogEntries[$j], ",")
						$ATime = $FieldArray[3]
						$FieldArray = StringSplit($ATime, "/ ")
						Local $EndTime = $FieldArray[3] & "/" & $FieldArray[1] & "/" & $FieldArray[2] & " " & $FieldArray[4]

						LogJobSummary($WatchArray[$i], $StartTime, $EndTime)

						$WatchArray[$i] = ""
						ExitLoop
					EndIf
				Next
				ExitLoop

				; Could Potentially do any additional job cleanup here (IE. If PTBurn "DeleteFiles = YES" option wasn't performing as needed)

			EndIf
		Next
	Next

	$PTBurnLogEntries = ""
	If $Found > 0 Then PurgeWatchArray()
EndFunc

Func LogJobSummary($ID, $PTStart, $PTEnd)
	Local $LogEntries = FileReadToArray($LogFile)
	If @error Then Return
	Local $LinesRead = @extended

	Local $FirstSeen = ""
	Local $CachingTime = ""
	Local $CachingComplete = $ID & " Caching Complete"

	For $i = 0 To ($LinesRead - 1)

		If $FirstSeen = "" Then
			If StringInStr($LogEntries[$i], $ID) Then
				Local $FieldArray = StringSplit($LogEntries[$i], " .")
				$FirstSeen = $FieldArray[1] & " " & $FieldArray[3]
				ContinueLoop
			EndIf
		EndIf

		If StringInStr($LogEntries[$i], $CachingComplete) Then
			$FieldArray = StringSplit($LogEntries[$i], "()")
			$CachingTime = $FieldArray[4]
			ExitLoop
		EndIf

	Next

	$LogEntries = ""

	Local $JobTotalTime = ElapsedHHMMSS(_DateDiff('s', $FirstSeen, $PTEnd))
	Local $PTBurnTime = ElapsedHHMMSS(_DateDiff('s', $PTStart, $PTEnd))

	LogMsg($Id & " Job Total Time = " & $JobTotalTime & " (Caching = " & $CachingTime & ", PTBurn Time = " & $PTBurnTime & ")")

EndFunc

Func ElapsedHHMMSS($seconds)

	Local $ss = Mod($seconds, 60)
	Local $mm = Mod($seconds / 60, 60)
	Local $hh = Floor($seconds / 60 ^ 2)

	return StringFormat("%02i:%02i:%02i", $hh, $mm, $ss)

EndFunc

Func GetConfig()
	If FileExists($IniFile) then
		$SearchFolder         = IniRead($IniFile, "Config", "SearchFolder", $SearchFolder)
		$JobRequestFolder     = IniRead($IniFile, "Config", "JobRequestFolder", $JobRequestFolder)
		$SortBy               = IniRead($IniFile, "Config", "SortBy", $SortBy)
		$PollTime             = Int(IniRead($IniFile, "Config", "PollTime", "60"))
	Else
		MsgBox(16, $FullTitle, "Config File (" & $IniFile & ") Not Found!")
		Exit (2)
	EndIf
EndFunc

Func GetOptionInfo()

	Local $OptionNames = IniReadSectionNames($IniFile)
	If @error Then
		MsgBox(4096, "", "Error occurred, probably no INI file.")
	Else

		Local $InfoArray[$OptionNames[0]][4]

		$OptionCount = 0
		For $i = 1 To $OptionNames[0]
			if ($OptionNames[$i] = "Config") OR ($OptionNames[$i] = "PTBurn Options") then ContinueLoop
			$InfoArray[$OptionCount][0] = $OptionNames[$i]
			$InfoArray[$OptionCount][1] = IniRead($IniFile, $OptionNames[$i], "Description", "{Undefined}")
			$InfoArray[$OptionCount][2] = IniRead($IniFile, $OptionNames[$i], "ImageFile", "{Undefined}")
			;$InfoArray[$OptionCount][3] will ultimately be used to hold CtrlID for GUI Selection
			$OptionCount += 1
		Next

		ReDim $InfoArray[$OptionCount][4]

	EndIf
	Return $InfoArray
EndFunc

Func GetBaseFileName($FN)
	Local $sDrive = "", $sDir = "", $sFileName = "", $sExtension = ""
	_PathSplit($FN, $sDrive, $sDir, $sFileName, $sExtension)
	return $sFileName
EndFunc

Func GetFileExtension($FN)
	Local $sDrive = "", $sDir = "", $sFileName = "", $sExtension = ""
	_PathSplit($FN, $sDrive, $sDir, $sFileName, $sExtension)
	return $sExtension
EndFunc

Func GetLocalIP()

	Local $IP=""
	Local $IFCount=0

	if (@IPAddress1 <> "127.0.0.1") AND (@IPAddress1 <> "0.0.0.0") Then
		$IFCount += 1
		If $IP = "" Then $IP = @IPAddress1
	EndIf

	if (@IPAddress2 <> "127.0.0.1") AND (@IPAddress2 <> "0.0.0.0") Then
		$IFCount += 1
		If $IP = "" Then $IP = @IPAddress2
	EndIf

	if (@IPAddress3 <> "127.0.0.1") AND (@IPAddress3 <> "0.0.0.0") Then
		$IFCount += 1
		If $IP = "" Then $IP = @IPAddress3
	EndIf

	if (@IPAddress4 <> "127.0.0.1") AND (@IPAddress4 <> "0.0.0.0") Then
		$IFCount += 1
		If $IP = "" Then $IP = @IPAddress4
	EndIf

	If $IFCount = 1 Then return $IP			; Only One IP Defined.  Good to Go!

	; If we have multiple Local IP Addresses then we should to dig a little further to eliminate any Virtual (internal) addresses
	; Find the first adapter which has an associated Gateway...

	Local $IPConfig = GetDosAppStdOutput("ipconfig")
	Local $IPInfoArray = StringSplit($IPConfig, @CRLF, 1)

	Local $BetterIP = ""
	Local $GW = ""
	For $i = 1 to $IPInfoArray[0]

		If $BetterIP = "" Then

			If StringInStr($IPInfoArray[$i], "IPv4 Address") Then
				Local $FieldArray = StringSplit($IPInfoArray[$i], ":")
				If $FieldArray[0] = 2 Then $BetterIP = StringStripWS($FieldArray[2], $STR_STRIPALL)
			EndIf

		Else

			If StringInStr($IPInfoArray[$i], "Default Gateway") Then
				$FieldArray = StringSplit($IPInfoArray[$i], ":")
				If $FieldArray[0] = 2 Then
					$GW = StringStripWS($FieldArray[2], $STR_STRIPALL)
					If $GW <> "" Then Return $BetterIP
				EndIf
				$BetterIP = ""
			EndIf

		EndIf

	Next

	; No adapter found with a valid gateway so just return the first one we found earlier
	If $IP <> "" Then Return $IP

	; Unable to detect
	Return "0.0.0.0"

EndFunc

Func GetDOSAppStdOutput($DOSAppCmd)

	Local $Output

	Local $cPID = Run($DOSAppCmd, @ScriptDir, @SW_HIDE, $STDOUT_CHILD)
	If $cPID = 0 and @error <> 0 Then
		$Output = "RunFail: " & $DOSAppCmd & " (Run Error Code = " & @error & ")"
	Else
		ProcessWaitClose($cPID)
		$Output = StdoutRead($cPID)
	EndIf
	StdioClose($cPID)

	return $Output
EndFunc

Func LogMsg($msg)

	Local $TimeStamp = @YEAR & "/" & @MON & "/" & @MDAY & " @ " & @HOUR & ":" & @MIN & ":" & @SEC & "." & @MSEC

	Local $LogEntry = StringFormat("%s %-8s %-15s : %s\n", $TimeStamp, "(" & $OpMode & ")", $IPAddress, $msg)

	FileWrite($LogFile, $LogEntry)

	If $OpMode = "Host" Then
		If Tail($LogArray) > 0 Then GUICtrlSetData($LogCtrlID, _ArrayToString($LogArray, @CRLF, 1))
	EndIf
EndFunc

Func TailInit($FileName, $NumLines)
	Local $hFile = FileOpen($FileName, $FO_READ)
	Local $LArray[$Numlines + 1]

	$LArray[0] = $hFile
	Tail($LArray)
	Return $LArray
EndFunc

Func Tail(ByRef $LArray)
	Static Local $FilePos = 0
	Static Local $LastChar = ""

	Local $hFile = $LArray[0]

	Local $LinesRead = 0
	While TRUE
		Local $Line = FileReadLine($hFile)
		If @error = -1 Then 					; EOF
			Local $NewFilePos = FileGetPos($hFile)
			If $NewFilePos <> $FilePos Then
				FileSetPos($hFile, -1, $FILE_CURRENT)
				$LastChar = FileRead($hFile, 1)
				$FilePos = $NewFilePos
			EndIf
			ExitLoop
		ElseIf @error = 1 Then 					; Error
			$LinesRead = -1
			ExitLoop
		EndIf

		$LinesRead += 1
		If ($LinesRead = 1) AND $LastChar <> @LF Then
			$LArray[UBound($LArray) - 1] &= $Line
		Else
			_ArrayPush($LArray, $Line)
		EndIf
	WEnd

	$LArray[0] = $hFile
	Return $LinesRead

EndFunc

Func TailTerminate(ByRef $LArray)
	FileClose($LArray[0])
	ReDim $LArray[1]
EndFunc


