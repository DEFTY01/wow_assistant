' Runs the uploader once without showing a console window (for the Windows Task Scheduler).
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(fso.GetParentFolderName(WScript.ScriptFullName))
Set shell = CreateObject("WScript.Shell")
shell.CurrentDirectory = root
shell.Run "cmd /c node scripts\uploader.mjs --once >> .wrangler\uploader.log 2>&1", 0, False
