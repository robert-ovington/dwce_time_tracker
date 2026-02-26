Attribute VB_Name = "ReverseGeocodeStreet"
Option Explicit

' Reverse geocode lat/lon to full address using OpenStreetMap Nominatim
' Sheet1: Lat in F, Lon in G, full address output in D, rows 2-88
' Nominatim allows 1 request per second - code includes delay

Public Sub GeocodeToStreetName()
    Dim ws As Worksheet
    Dim i As Long
    Dim lat As Double
    Dim lon As Double
    Dim address As String
    Dim lastRow As Long
    
    Set ws = ThisWorkbook.Worksheets("Sheet1")
    lastRow = 88
    
    Application.ScreenUpdating = False
    Application.Calculation = xlCalculationManual
    
    On Error GoTo CleanUp
    
    For i = 2 To lastRow
        lat = ws.Cells(i, 6).Value   ' Column F
        lon = ws.Cells(i, 7).Value   ' Column G
        
        If IsEmpty(ws.Cells(i, 6).Value) Or IsEmpty(ws.Cells(i, 7).Value) Then
            ws.Cells(i, 4).Value = ""
        Else
            address = GetAddressFromCoords(lat, lon)
            ws.Cells(i, 4).Value = address
        End If
        
        ' Nominatim: max 1 request per second
        If i < lastRow Then
            Application.Wait Now + TimeValue("00:00:01")
        End If
    Next i
    
CleanUp:
    Application.ScreenUpdating = True
    Application.Calculation = xlCalculationAutomatic
End Sub

Private Function GetAddressFromCoords(lat As Double, lon As Double) As String
    Dim url As String
    Dim http As Object
    Dim jsonResponse As String
    Dim regex As Object
    Dim matches As Object
    Dim errNum As Long
    Dim errDesc As String
    
    On Error GoTo ErrHandler
    
    url = "https://nominatim.openstreetmap.org/reverse?lat=" & lat & "&lon=" & lon & "&format=json&addressdetails=1"
    
    ' Try WinHttp first (better TLS support); fallback to MSXML2
    On Error Resume Next
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    If http Is Nothing Then Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
    If http Is Nothing Then Set http = CreateObject("MSXML2.XMLHTTP.6.0")
    On Error GoTo ErrHandler
    
    If http Is Nothing Then
        GetAddressFromCoords = "Error: HTTP object not available"
        Exit Function
    End If
    
    http.Open "GET", url, False
    http.setRequestHeader "User-Agent", "ExcelGeocoder/1.0 dwce_time_tracker"
    On Error Resume Next
    http.SetTimeouts 10000, 10000, 10000, 10000  ' WinHttp
    If Err.Number <> 0 Then http.setTimeout 10000, 10000  ' MSXML2 fallback
    On Error GoTo ErrHandler
    http.Send
    
    If http.Status <> 200 Then
        GetAddressFromCoords = "Error: HTTP " & http.Status
        Set http = Nothing
        Exit Function
    End If
    
    jsonResponse = http.responseText
    Set http = Nothing
    
    ' Extract "display_name" - full formatted address (always present in Nominatim)
    Set regex = CreateObject("VBScript.RegExp")
    regex.Global = False
    regex.Pattern = """display_name""\s*:\s*""((?:[^""\\]|\\.)*)"""
    
    Set matches = regex.Execute(jsonResponse)
    If matches.Count > 0 Then
        GetAddressFromCoords = DecodeJsonString(matches(0).SubMatches(0))
    Else
        GetAddressFromCoords = ""
    End If
    
    Set regex = Nothing
    Exit Function
    
ErrHandler:
    errNum = Err.Number
    errDesc = Err.Description
    GetAddressFromCoords = "Error: " & errNum & " - " & errDesc
    Set http = Nothing
    Set regex = Nothing
End Function

' Decode JSON escape sequences (\", \\, \n, etc.)
Private Function DecodeJsonString(s As String) As String
    DecodeJsonString = Replace(s, "\""", """")
    DecodeJsonString = Replace(DecodeJsonString, "\\", "\")
    DecodeJsonString = Replace(DecodeJsonString, "\n", vbLf)
    DecodeJsonString = Replace(DecodeJsonString, "\/", "/")
End Function
