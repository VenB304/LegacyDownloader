' LegacyDownloader.vbs - flash-free launcher for the GUI.
'
' Double-click this (or LegacyDownloader.bat, which just calls this) to start
' the windowed Legacy Downloader with no console window at all. For the text
' menu, use LegacyDownloader-Console.bat instead.

Option Explicit

Dim shell, fso, here, cmd
Set shell = CreateObject("WScript.Shell")
Set fso   = CreateObject("Scripting.FileSystemObject")

here = fso.GetParentFolderName(WScript.ScriptFullName)
shell.CurrentDirectory = here

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & _
      here & "\LegacyDownloader.ps1"""

' 0 = hidden window, False = don't wait for it to exit
shell.Run cmd, 0, False
