' ============================================================================
' Access VBA Code: Sync Project to Supabase
' ============================================================================
' 
' Add this code to a VBA module in your Access database to sync projects
' to Supabase when creating or updating projects.
'
' USAGE:
'   - Call SyncProjectToSupabase("A6-0001") after saving a project
'   - Add to form AfterUpdate event
'   - Add to button OnClick event
' ============================================================================

Option Compare Database
Option Explicit

' ============================================================================
' Configuration - Update these paths to match your setup
' ============================================================================
Private Const PYTHON_PATH As String = "python"  ' Use "python" if in PATH, or full path like "C:\Python311\python.exe"
Private Const SCRIPT_PATH As String = "C:\Users\robie\dwce_time_tracker\sync_projects_production.py"
Private Const LOG_DIR As String = "C:\Users\robie\dwce_time_tracker\logs"

' ============================================================================
' Main Function: Sync a Single Project to Supabase
' ============================================================================
' Parameters:
'   ProjectNumber - The Job_Number/Project_Number to sync (e.g., "A6-0001")
'   ShowProgress - Optional: Show progress message to user (default: True)
'   WaitForCompletion - Optional: Wait for script to finish (default: True)
' Returns:
'   Boolean - True if sync started successfully (or completed if WaitForCompletion=True)
' ============================================================================
Public Function SyncProjectToSupabase(ProjectNumber As String, _
                                      Optional ShowProgress As Boolean = True, _
                                      Optional WaitForCompletion As Boolean = True) As Boolean
    
    On Error GoTo ErrorHandler
    
    ' Validate inputs
    If Trim(ProjectNumber) = "" Then
        MsgBox "Error: Project number cannot be empty.", vbExclamation, "Sync Error"
        SyncProjectToSupabase = False
        Exit Function
    End If
    
    ' Validate script path exists
    If Dir(SCRIPT_PATH) = "" Then
        MsgBox "Error: Python script not found at:" & vbCrLf & SCRIPT_PATH, vbCritical, "Sync Error"
        SyncProjectToSupabase = False
        Exit Function
    End If
    
    ' Show progress message if requested
    If ShowProgress Then
        If WaitForCompletion Then
            DoCmd.Hourglass True
            MsgBox "Syncing project " & ProjectNumber & " to Supabase..." & vbCrLf & _
                   "Please wait...", vbInformation, "Syncing to Supabase"
        Else
            MsgBox "Starting sync for project " & ProjectNumber & "..." & vbCrLf & _
                   "This will run in the background.", vbInformation, "Starting Sync"
        End If
    End If
    
    ' Build command
    Dim cmd As String
    Dim quotedScriptPath As String
    quotedScriptPath = """" & SCRIPT_PATH & """"
    cmd = PYTHON_PATH & " " & quotedScriptPath & " -p " & ProjectNumber
    
    ' Run the script
    Dim shell As Object
    Set shell = CreateObject("WScript.Shell")
    Dim windowStyle As Integer
    Dim waitOnReturn As Boolean
    
    windowStyle = 0  ' Hidden window (use 1 for normal window, 7 for minimized)
    waitOnReturn = WaitForCompletion
    
    Dim exitCode As Integer
    exitCode = shell.Run(cmd, windowStyle, waitOnReturn)
    
    ' Check result
    If WaitForCompletion Then
        DoCmd.Hourglass False
        
        If exitCode = 0 Then
            If ShowProgress Then
                MsgBox "Project " & ProjectNumber & " successfully synced to Supabase!", _
                       vbInformation, "Sync Complete"
            End If
            SyncProjectToSupabase = True
        Else
            MsgBox "Sync failed for project " & ProjectNumber & "." & vbCrLf & _
                   "Exit code: " & exitCode & vbCrLf & vbCrLf & _
                   "Check the log file for details:" & vbCrLf & LOG_DIR, _
                   vbExclamation, "Sync Failed"
            SyncProjectToSupabase = False
        End If
    Else
        ' Background sync - can't check exit code
        If ShowProgress Then
            MsgBox "Sync started in background for project " & ProjectNumber & "." & vbCrLf & _
                   "Check the log file for results: " & LOG_DIR, vbInformation, "Sync Started"
        End If
        SyncProjectToSupabase = True
    End If
    
    Set shell = Nothing
    Exit Function
    
ErrorHandler:
    DoCmd.Hourglass False
    MsgBox "Error syncing project to Supabase:" & vbCrLf & Err.Description, _
           vbCritical, "Sync Error"
    SyncProjectToSupabase = False
End Function

' ============================================================================
' Alternative: Sync Current Record's Project
' ============================================================================
' Call this from a form to sync the project number in the current record
' Assumes the form has a field named "Job_Number" or "Project_Number"
' ============================================================================
Public Function SyncCurrentProject(Optional FormName As Form = Nothing) As Boolean
    
    On Error GoTo ErrorHandler
    
    Dim frm As Form
    Dim projectNumber As String
    
    ' Get form reference
    If FormName Is Nothing Then
        Set frm = Screen.ActiveForm
    Else
        Set frm = FormName
    End If
    
    If frm Is Nothing Then
        MsgBox "Error: No active form found.", vbExclamation, "Sync Error"
        SyncCurrentProject = False
        Exit Function
    End If
    
    ' Try to get project number from common field names
    If Not IsNull(frm("Job_Number")) Then
        projectNumber = Trim(frm("Job_Number").Value)
    ElseIf Not IsNull(frm("Project_Number")) Then
        projectNumber = Trim(frm("Project_Number").Value)
    ElseIf Not IsNull(frm("project_number")) Then
        projectNumber = Trim(frm("project_number").Value)
    Else
        MsgBox "Error: Could not find Job_Number or Project_Number field in form.", _
               vbExclamation, "Sync Error"
        SyncCurrentProject = False
        Exit Function
    End If
    
    ' Sync the project
    SyncCurrentProject = SyncProjectToSupabase(projectNumber, True, True)
    
    Exit Function
    
ErrorHandler:
    MsgBox "Error: " & Err.Description, vbCritical, "Sync Error"
    SyncCurrentProject = False
End Function

' ============================================================================
' Get Latest Log Entry (for checking sync status)
' ============================================================================
Public Function GetLatestSyncLog() As String
    
    On Error GoTo ErrorHandler
    
    Dim logFile As String
    Dim fso As Object
    Dim file As Object
    Dim logContent As String
    Dim lines As Variant
    Dim i As Long
    
    ' Find today's log file
    Dim logFileName As String
    logFileName = "sync_projects_" & Format(Date, "yyyymmdd") & ".log"
    logFile = LOG_DIR & "\" & logFileName
    
    ' Check if log file exists
    If Dir(logFile) = "" Then
        GetLatestSyncLog = "Log file not found: " & logFile
        Exit Function
    End If
    
    ' Read last 20 lines of log file
    Set fso = CreateObject("Scripting.FileSystemObject")
    Set file = fso.OpenTextFile(logFile, 1)  ' 1 = ForReading
    
    logContent = file.ReadAll
    file.Close
    
    lines = Split(logContent, vbCrLf)
    
    ' Get last 20 lines
    Dim result As String
    result = ""
    Dim startLine As Long
    startLine = UBound(lines) - 19
    If startLine < 0 Then startLine = 0
    
    For i = startLine To UBound(lines)
        If Trim(lines(i)) <> "" Then
            result = result & lines(i) & vbCrLf
        End If
    Next i
    
    GetLatestSyncLog = result
    Set file = Nothing
    Set fso = Nothing
    Exit Function
    
ErrorHandler:
    GetLatestSyncLog = "Error reading log file: " & Err.Description
End Function
