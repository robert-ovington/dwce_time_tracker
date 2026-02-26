# Access Form Integration Examples

This guide shows how to integrate the Supabase sync functionality into your Access database forms.

## Setup Steps

### 1. Add VBA Code to Access

1. Open your Access database
2. Press `Alt + F11` to open the VBA editor
3. Click `Insert` → `Module`
4. Copy and paste the code from `Access_VBA_Sync_Integration.vba`
5. Update the paths at the top of the module:
   ```vba
   Private Const PYTHON_PATH As String = "python"  ' Or "C:\Python311\python.exe"
   Private Const SCRIPT_PATH As String = "C:\Users\robie\dwce_time_tracker\sync_projects_production.py"
   Private Const LOG_DIR As String = "C:\Users\robie\dwce_time_tracker\logs"
   ```
6. Save the module (Ctrl+S) and name it something like "SyncToSupabase"

### 2. Ensure Python is Accessible

- **Option A**: Add Python to Windows PATH
- **Option B**: Use full path in `PYTHON_PATH` constant (e.g., `"C:\Python311\python.exe"`)

---

## Integration Methods

### Method 1: Sync Button on Form (Recommended)

**Best for:** User-initiated syncs when they want to sync after making changes

1. Open your project form in Design View
2. Add a button (Command Button) to your form
3. Set button properties:
   - **Name**: `btnSyncToSupabase`
   - **Caption**: `Sync to Supabase`
4. Right-click the button → **Build Event** → **Code Builder**
5. Add this code:

```vba
Private Sub btnSyncToSupabase_Click()
    ' Sync the current project
    Dim projectNumber As String
    
    ' Get project number from current record
    If Not IsNull(Me!Job_Number) Then
        projectNumber = Trim(Me!Job_Number.Value)
        
        ' Sync to Supabase
        If SyncProjectToSupabase(projectNumber, True, True) Then
            ' Optional: Show success message or refresh data
            Me.Refresh
        End If
    Else
        MsgBox "Job_Number is required for syncing.", vbExclamation, "Sync Error"
    End If
End Sub
```

---

### Method 2: Auto-Sync After Save (Form AfterUpdate Event)

**Best for:** Automatically syncing whenever a record is saved/updated

1. Open your project form in Design View
2. Open the form's **Property Sheet** (F4)
3. Go to the **Event** tab
4. Find **AfterUpdate** event
5. Click the **...** button → **Code Builder**
6. Add this code:

```vba
Private Sub Form_AfterUpdate()
    ' Auto-sync after saving/updating a record
    Dim projectNumber As String
    
    ' Only sync if Job_Number exists
    If Not IsNull(Me!Job_Number) Then
        projectNumber = Trim(Me!Job_Number.Value)
        
        ' Sync in background (doesn't block user)
        ' Set last parameter to False for background sync
        Call SyncProjectToSupabase(projectNumber, False, False)
        
        ' Optional: Show a small notification
        Application.SetOption "Show Status Bar", True
        Application.StatusBar = "Syncing " & projectNumber & " to Supabase..."
        
        ' Clear status bar after 3 seconds
        Dim StartTime As Double
        StartTime = Timer
        Do While Timer < StartTime + 3
            DoEvents
        Loop
        Application.StatusBar = ""
    End If
End Sub
```

**Note:** Background sync (`WaitForCompletion=False`) means the sync happens asynchronously and won't block Access. The user can continue working.

---

### Method 3: Sync on New Record (Form AfterInsert Event)

**Best for:** Auto-syncing when creating a new project

1. Open your project form in Design View
2. Open the form's **Property Sheet** (F4)
3. Go to the **Event** tab
4. Find **AfterInsert** event
5. Click the **...** button → **Code Builder**
6. Add this code:

```vba
Private Sub Form_AfterInsert()
    ' Auto-sync new records
    Dim projectNumber As String
    
    If Not IsNull(Me!Job_Number) Then
        projectNumber = Trim(Me!Job_Number.Value)
        
        ' Ask user if they want to sync
        Dim response As VbMsgBoxResult
        response = MsgBox("Sync this new project to Supabase?", _
                         vbYesNo + vbQuestion, "Sync New Project")
        
        If response = vbYes Then
            Call SyncProjectToSupabase(projectNumber, True, True)
        End If
    End If
End Sub
```

---

### Method 4: Batch Sync Button (Sync Multiple Projects)

**Best for:** Syncing multiple selected projects at once

1. Add a button to your form or create a separate form
2. Add this code:

```vba
Private Sub btnBatchSync_Click()
    ' Sync multiple projects from a list
    Dim db As DAO.Database
    Dim rs As DAO.Recordset
    Dim projectNumber As String
    Dim syncedCount As Integer
    Dim failedCount As Integer
    
    Set db = CurrentDb
    ' Adjust SQL to match your table/query
    Set rs = db.OpenRecordset("SELECT Job_Number FROM [2026] WHERE [Enabled] = True", dbOpenSnapshot)
    
    syncedCount = 0
    failedCount = 0
    
    Do While Not rs.EOF
        projectNumber = Trim(rs!Job_Number.Value)
        
        If SyncProjectToSupabase(projectNumber, False, True) Then
            syncedCount = syncedCount + 1
        Else
            failedCount = failedCount + 1
        End If
        
        rs.MoveNext
    Loop
    
    rs.Close
    Set rs = Nothing
    Set db = Nothing
    
    MsgBox "Batch sync complete!" & vbCrLf & _
           "Synced: " & syncedCount & vbCrLf & _
           "Failed: " & failedCount, vbInformation, "Batch Sync Complete"
End Sub
```

---

### Method 5: Sync from Access Macro

**Best for:** Simple triggers without VBA

1. Create a new Macro
2. Add action: **RunCode**
3. In the **Function Name** field, enter:
   ```
   SyncProjectToSupabase("A6-0001")
   ```
   (Replace "A6-0001" with your project number, or use a control reference)

**Note:** Macros are less flexible than VBA, but they work if you want to avoid VBA.

---

## Using the SyncCurrentProject Function

If your form field names match, you can use the helper function:

```vba
Private Sub btnSync_Click()
    ' Automatically gets project number from current form record
    Call SyncCurrentProject
End Sub
```

This function automatically looks for fields named:
- `Job_Number`
- `Project_Number`
- `project_number`

---

## Advanced: Check Sync Status

Add a button to view the latest sync log:

```vba
Private Sub btnViewSyncLog_Click()
    Dim logContent As String
    logContent = GetLatestSyncLog()
    
    ' Display in a message box (truncated)
    MsgBox Left(logContent, 2000), vbInformation, "Latest Sync Log"
    
    ' Or open in Notepad for full view
    ' Shell "notepad.exe " & LOG_DIR & "\sync_projects_" & Format(Date, "yyyymmdd") & ".log", vbNormalFocus
End Sub
```

---

## Troubleshooting

### Python Not Found Error
**Solution:** Update `PYTHON_PATH` in the VBA module to the full path:
```vba
Private Const PYTHON_PATH As String = "C:\Python311\python.exe"
```

### Script Path Not Found
**Solution:** Verify the script path is correct and use double quotes if path has spaces:
```vba
Private Const SCRIPT_PATH As String = """C:\Users\robie\dwce time tracker\sync_projects_production.py"""
```

### Sync Runs But Doesn't Complete
**Solution:** 
- Check that `WaitForCompletion = True` in your function call
- Check the log file for errors
- Verify the project number exists in Access

### Access Freezes During Sync
**Solution:**
- Use `WaitForCompletion = False` for background sync
- Use `ShowProgress = False` to avoid message boxes
- Reduce the sync frequency (don't sync on every keystroke!)

---

## Best Practices

1. **For New Records:** Use Method 3 (AfterInsert) with a confirmation dialog
2. **For Updates:** Use Method 2 (AfterUpdate) with background sync
3. **For Manual Control:** Use Method 1 (Button) for user-initiated syncs
4. **Error Handling:** Always check if `Job_Number` exists before syncing
5. **User Feedback:** Show progress messages but don't block the UI unnecessarily
6. **Logging:** Check logs regularly to ensure syncs are working

---

## Example: Complete Form with Auto-Sync

Here's a complete example form with both auto-sync and manual sync:

```vba
Option Compare Database
Option Explicit

' Auto-sync after updating a record (background)
Private Sub Form_AfterUpdate()
    If Not IsNull(Me!Job_Number) Then
        Call SyncProjectToSupabase(Trim(Me!Job_Number.Value), False, False)
        Application.StatusBar = "Syncing " & Me!Job_Number.Value & " to Supabase..."
    End If
End Sub

' Manual sync button
Private Sub btnSyncToSupabase_Click()
    If Not IsNull(Me!Job_Number) Then
        Call SyncProjectToSupabase(Trim(Me!Job_Number.Value), True, True)
    Else
        MsgBox "Please enter a Job_Number first.", vbExclamation
    End If
End Sub

' Check sync status
Private Sub btnCheckSyncStatus_Click()
    Dim logContent As String
    logContent = GetLatestSyncLog()
    
    ' Create a simple form or message box to display log
    MsgBox logContent, vbInformation, "Sync Status"
End Sub
```

---

## Security Note

⚠️ **Important:** The VBA code runs the Python script with the service_role key. Ensure:
- Only authorized users can run the sync functions
- Consider adding user permission checks before allowing syncs
- The service_role key is stored securely (not hardcoded in Access if possible)

---

## Testing

1. **Test with a known project:**
   ```vba
   Call SyncProjectToSupabase("A6-0001", True, True)
   ```

2. **Check the log file** at: `C:\Users\robie\dwce_time_tracker\logs\sync_projects_YYYYMMDD.log`

3. **Verify in Supabase** that the project was updated

4. **Test error handling** by using an invalid project number

Once set up, the sync will work seamlessly from within Access! 🎉
