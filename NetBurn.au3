#include <File.au3>
#include <Array.au3>
#include <GUIConstants.au3>
#include <MsgBoxConstants.au3>
#include <Date.au3>

Global $Title  = "NetBurn"
Global $Version  = "1.00"

#pragma compile(ProductName, "NetBurn")
#pragma compile(ProductVersion, 1.00)
#pragma compile(CompanyName, "Digital Intelligence")
#pragma compile(Comments, Author: Edward C. Van Every")

Global $IniFile
Global $OptionCount
Global $OptionInfo[1][4]
Global $SelectedOption
Global $RemoteJobsFolder
Global $OpMode
Global $LogFile
Global $IPAddress
Global $WatchArray[1] = [0]
Global $PTBurnJobLog
Global $FullTitle = $Title & " v" & $Version

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
$RemoteJobsFolder = StringTrimRight(@ScriptFullPath,4) & "Jobs"
If NOT FileExists($RemoteJobsFolder) Then DirCreate($RemoteJobsFolder)

; Get Local IP Address (for Logging)
$IPAddress = GetLocalIP()

; Get Configuration Options
GetConfig()
$PTBurnJobLog = $JobRequestFolder & "\Log\SystemLog.txt"

; Get Pre-Defined Job Information (from INI File)
GetOptionInfo()

; Determine if Job Info should be sorted
if ($SortBy = "JobName") Then
	_ArraySort($OptionInfo, 0, 0, 0, 0)
Elseif ($SortBy = "Description") Then
	_ArraySort($OptionInfo, 0, 0, 0, 1)
ElseIf ($SortBy = "ImageFile") Then
	_ArraySort($OptionInfo, 0, 0, 0, 2)
EndIf

; Determine if we are the PTBurn Host or a Network Client
If FileExists($JobRequestFolder) Then
	$OpMode="Host"
Else
	$OpMode="Client"
EndIf

; Log Startup
LogMsg("Startup (v" & $Version & ")")

; Here we go!

$OptionSpace = 30
$OptionsHeight = ($OptionCount * $OptionSpace)
GUICreate($FullTitle & " (" & $OpMode & ")", 500, 80 + $OptionsHeight, -1, -1, $WS_SIZEBOX)

For $i = 0 To $OptionCount-1
	$OptionInfo[$i][3] = GUICtrlCreateButton($OptionInfo[$i][1], 20, 20 + ($i * $OptionSpace), 460, 20)
Next

$Search = GUICtrlCreateButton("Search", 125, $OptionsHeight + 25, 50, 20)
$Exit   = GUICtrlCreateButton("Exit", 325, $OptionsHeight + 25, 50, 20)

GUISetState()

$hTimer = TimerInit()
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
			PollJobs()
			$hTimer = TimerInit()
		EndIf
	EndIf

Until $msg = $GUI_EVENT_CLOSE

GUIDelete()

; Log Startup
LogMsg("ShutDown")

;-------------------------------------------------------------------------

Func PollJobs()

	; Check for the PTBurn Bug which displays a Window requesting a disc to be inserted after the jobs complete (and close it)
	; WinClose("Insert disc","Please insert a disc into drive")

	; Watch for any "live" Jobs that have been fully completed by PTBurn
	CheckWatchedJobs()

	; Poll for Jobs submitted by Clients
	$hSearch = FileFindFirstFile($RemoteJobsFolder & "\*.ini")
    If $hSearch <> -1 Then

		While 1
			$sFileName = FileFindNextFile($hSearch)
			If @error Then ExitLoop
			$FullFileName = $RemoteJobsFolder & "\" & $sFileName
			$JobID = GetBaseFileName($FullFileName)

			$ImageFile = IniRead($FullFileName, "Config", "ImageFile", "")
			$Copies    = Int(IniRead($FullFileName, "Config", "Copies", "0"))

			LogMsg($JobId & " Polled = " & $FullFileName )

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

	$JobNames = IniReadSectionNames($BatchFile)
	If @error Then
		MsgBox(4096, "", "Error occurred, Batch File Not Found: " & $BatchFile)
		Return
	EndIf

	LogMsg("Batching = " & $BatchFile & " (Copies: " & $Copies & ")")

	For $i = 1 To $JobNames[0]
		if ($JobNames[$i] = "Config") then ContinueLoop
		$ImageFile = IniRead($BatchFile, $JobNames[$i], "ImageFile", "")
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
	$ImageFileExt = GetFileExtension($ImageFile)
	If $ImageFileExt = ".nbb" Then
		SubmitBatchJob($ImageFile, $Copies, $Mode, $JobID)
		Return
	ElseIf ($ImageFileExt <> ".gi") AND ($ImageFileExt <> ".iso") Then
		MsgBox(4096,$FullTitle,"Unsupported Image File: " & $ImageFile)
		Return
	EndIf

	; Calculate Base File Name
	$BaseFileName=GetBaseFileName($ImageFile)

	; Calculate Label File
	$LabelFile = StringTrimRight($ImageFile, StringLen($ImageFileExt)) & ".std"

	; Confirm Label File Exists
	If NOT FileExists($LabelFile) Then
		MsgBox(4096,$FullTitle,"Label File Does Not Exist: " & $LabelFile)
		Return
	EndIf

	; Calculate/Check Image Options File (Optional)
	$ImageOptionsFile = StringTrimRight($LabelFile, 4) & ".ini"
	If NOT FileExists($ImageOptionsFile) Then $ImageOptionsFile = ""

	; Generate a unique JobID (If Not Provided)
	If $JobID = "" Then $JobID = @YEAR & @MON & @MDAY & @HOUR & @MIN & @SEC & @MSEC

	If $Mode = "Client" Then
		$JobFileName = $RemoteJobsFolder & "\" & $JobID & ".ini"
		IniWrite($JobFileName, "Config", "ImageFile", $ImageFile)
		IniWrite($JobFileName, "Config", "Copies", $Copies)

		If NOT FileExists($JobFileName) Then
			MsgBox($MB_ICONERROR, $FullTitle, "Warning:  Unable to Create Network Job File!" & @CRLF & @CRLF & $JobFileName & @CRLF & @CRLF & "Check Network Permissions!")
		Else
			MsgBox($MB_ICONINFORMATION, $FullTitle, "Job has been Submitted" & @CRLF & @CRLF & $BaseFileName & @CRLF & @CRLF & "Copies: " & $Copies)
			LogMsg($JobId & " Staged = " & $ImageFile & " (Copies: " & $Copies & ")")
		EndIf

		Return
	EndIf

	; Host Side Processing

	; Create Job Folder (Required for auto file deletion)
	$JobFolder = $JobRequestFolder & "\" & $JobID
	DirCreate($JobFolder)

	; Calculate Destination IMAGE and LABEL file names
	$ImageFileDest = $JobFolder & "\" & $BaseFileName & $ImageFileExt
	$LabelFileDest = $JobFolder & "\" & $BaseFileName & ".std"

	; Generate Job File Contents
	$JobFileContents  = "JobID = " & $JobID & @CRLF
	$JobFileContents &= "ImageFile = " & $ImageFileDest & @CRLF
	$JobFileContents &= "PrintLabel = " & $LabelFileDest & @CRLF
	$JobFileContents &= "Copies = " & $Copies & @CRLF

	; Determine PTBurn Options
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
			$Found = 0
			For $j = 1 To $PTBurnOptions[0][0]
				If $PTBurnOptions[$j][0] = $ImageOptions[$i][0] Then $Found = 1
			Next
			If $Found = 0 Then $JobFileContents &= $ImageOptions[$i][0] & " = " & $ImageOptions[$i][1] & @CRLF
		Next
	EndIf

	; Copy IMAGE and LABEL files to Job Request Folder
	If $Mode = "Host" Then
		SplashTextOn($FullTitle, "Job: " & $JobID & @CRLF & @CRLF &"Caching IMAGE and LABEL Files...")
	Else	; $Mode = "Poll"
		SplashTextOn($FullTitle,"Polled Job: " & $JobID & @CRLF & @CRLF & "Caching IMAGE and LABEL Files...")
	EndIf
		$hCacheTimer = TimerInit()

		$FileSize = FileGetSize($ImageFile)
		LogMsg($JobID & " Caching (" & Int($FileSize/1048576) & " MB) = " & $ImageFile & " -> " & $ImageFileDest)
		FileCopy($ImageFile, $ImageFileDest)

		$FileSize = FileGetSize($ImageFile)
		LogMsg($JobID & " Caching (" & Int($FileSize/1024) & " KB) = " & $LabelFile & " -> " & $LabelFileDest)
		FileCopy($LabelFile, $LabelFileDest)

		LogMsg($JobID & " Caching Complete (" & ElapsedHHMMSS(TimerDiff($hCacheTimer)/1000) & ")")
	SplashOff()

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

	$Index = _ArraySearch($WatchArray, $ID)
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

	$PTBurnLogEntries = FileReadToArray($PTBurnJobLog)
	If @error Then Return
	$LinesRead = @extended

	$Found = 0
	For $i = 1 To $WatchArray[0]
		$JobComplete = "Job Completed (" & $WatchArray[$i] & ")"
		For $j = 0 To ($LinesRead - 1)
			If StringInStr($PTBurnLogEntries[$j], $JobComplete) Then
				$JobStarted = "Job Started (" & $WatchArray[$i] & ")"
				For $k = 0 To $j
					If StringInStr($PTBurnLogEntries[$k], $JobStarted) Then
						$Found += 1

						$FieldArray = StringSplit($PTBurnLogEntries[$k], ",")
						$ATime = $FieldArray[3]
						$FieldArray = StringSplit($ATime, "/ ")
						$StartTime = $FieldArray[3] & "/" & $FieldArray[1] & "/" & $FieldArray[2] & " " & $FieldArray[4]

						$FieldArray = StringSplit($PTBurnLogEntries[$j], ",")
						$ATime = $FieldArray[3]
						$FieldArray = StringSplit($ATime, "/ ")
						$EndTime = $FieldArray[3] & "/" & $FieldArray[1] & "/" & $FieldArray[2] & " " & $FieldArray[4]

						LogJobSummary($WatchArray[$i], $StartTime, $EndTime)

						$WatchArray[$i] = ""
						ExitLoop
					EndIf
				Next
				ExitLoop
			EndIf
		Next
	Next

	$PTBurnLogEntries = ""
	If $Found > 0 Then PurgeWatchArray()
EndFunc

Func LogJobSummary($ID, $PTStart, $PTEnd)
	$LogEntries = FileReadToArray($LogFile)
	If @error Then Return
	$LinesRead = @extended

	$FirstSeen = ""
	$CachingTime = ""
	$CachingComplete = $ID & " Caching Complete"

	For $i = 0 To ($LinesRead - 1)

		If $FirstSeen = "" Then
			If StringInStr($LogEntries[$i], $ID) Then
				$FieldArray = StringSplit($LogEntries[$i], " .")
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

	$JobTotalTime = ElapsedHHMMSS(_DateDiff('s', $FirstSeen, $PTEnd))
	$PTBurnTime = ElapsedHHMMSS(_DateDiff('s', $PTStart, $PTEnd))

	LogMsg($Id & " Job Total Time = " & $JobTotalTime & " (Caching = " & $CachingTime & ", PTBurn Time = " & $PTBurnTime & ")")

EndFunc

Func ElapsedHHMMSS($seconds)

	$ss = Mod($seconds, 60)
	$mm = Mod($seconds / 60, 60)
	$hh = Floor($seconds / 60 ^ 2)

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

	$OptionNames = IniReadSectionNames($IniFile)
	If @error Then
		MsgBox(4096, "", "Error occurred, probably no INI file.")
	Else

		Global $OptionInfo[$OptionNames[0]][4]

		$OptionCount = 0
		For $i = 1 To $OptionNames[0]
			if ($OptionNames[$i] = "Config") OR ($OptionNames[$i] = "PTBurn Options") then ContinueLoop
			$OptionInfo[$OptionCount][0] = $OptionNames[$i]
			$OptionInfo[$OptionCount][1] = IniRead($IniFile, $OptionNames[$i], "Description", "{Undefined}")
			$OptionInfo[$OptionCount][2] = IniRead($IniFile, $OptionNames[$i], "ImageFile", "{Undefined}")
			;$OptionInfo[$OptionCount][3] will ultimately be used to hold CtrlID for GUI Selection
			$OptionCount += 1
		Next

	EndIf
	Return $OptionCount
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
	if (@IPAddress1 <> "127.0.0.1") AND (@IPAddress1 <> "0.0.0.0") Then Return @IPAddress1
	if (@IPAddress2 <> "127.0.0.1") AND (@IPAddress2 <> "0.0.0.0") Then Return @IPAddress2
	if (@IPAddress3 <> "127.0.0.1") AND (@IPAddress3 <> "0.0.0.0") Then Return @IPAddress3
	if (@IPAddress4 <> "127.0.0.1") AND (@IPAddress4 <> "0.0.0.0") Then Return @IPAddress4

	return @IPAddress1
EndFunc

Func LogMsg($msg)

	$TimeStamp = @YEAR & "/" & @MON & "/" & @MDAY & " @ " & @HOUR & ":" & @MIN & ":" & @SEC & "." & @MSEC

	$LogEntry = StringFormat("%s %-8s %-15s : %s\n", $TimeStamp, "(" & $OpMode & ")", $IPAddress, $msg)

	FileWrite($LogFile, $LogEntry)

EndFunc