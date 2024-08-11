#Persistent
#SingleInstance Force
#NoEnv
SetWorkingDir %A_ScriptDir%

; Ensure the script is running with admin privileges
if not A_IsAdmin
{
   Run *RunAs "%A_ScriptFullPath%"  ; Requires v1.0.92.01+
   ExitApp
}

global SuspendedProcesses := {}

; Hotkey to suspend the current process (Alt + S)
!s::
    ; Get the process ID of the active window
    WinGet, pid, PID, A
    WinGetActiveTitle, activeTitle
    ; Get the process name from the process ID
    ProcessName := GetProcessNameFromPID(pid)
    ; Check for exceptions
    if (ProcessName = "dwm.exe" or ProcessName = "explorer.exe") {
        ShowNotification("Cannot suspend", "Unable to suspend " . ProcessName, 3)
        return
    }
    ; Check if the process is fullscreen
    isFullscreen := IsWindowFullScreen("A")
    ; If fullscreen, force switch to desktop first
    if (isFullscreen) {
        ForceSwitchToDesktop()
        Sleep, 500 ; Give more time for the switch to complete
    }
    ; Suspend the process
    if SuspendProcess(pid) {
        ; Add to the list of suspended processes
        SuspendedProcesses[pid] := ProcessName . "|" . activeTitle
        UpdateTrayMenu()
    }
return

SuspendProcess(pid) {
    ; Open the process with all access rights
    hProcess := DllCall("OpenProcess", "UInt", 0x1F0FFF, "Int", 0, "UInt", pid, "Ptr")
    
    if !hProcess {
        ShowNotification("Error", "Failed to open process with PID " . pid, 3)
        return false
    }
    ; Get the NtSuspendProcess function address
    NtSuspendProcess := DllCall("GetProcAddress", "Ptr", DllCall("GetModuleHandle", "Str", "ntdll.dll", "Ptr"), "AStr", "NtSuspendProcess", "Ptr")
    if !NtSuspendProcess {
        ShowNotification("Error", "Failed to get NtSuspendProcess function address", 3)
        return false
    }
    ; Call NtSuspendProcess to suspend the process
    DllCall(NtSuspendProcess, "Ptr", hProcess)
    ; Close the process handle
    DllCall("CloseHandle", "Ptr", hProcess)
    ShowNotification("Process Suspended", "PID: " . pid . " (" . ProcessName . ")", 2)
    return true
}

ResumeProcess(pid) {
    ; Open the process with all access rights
    hProcess := DllCall("OpenProcess", "UInt", 0x1F0FFF, "Int", 0, "UInt", pid, "Ptr")
    
    if !hProcess {
        ShowNotification("Error", "Failed to open process with PID " . pid, 3)
        return false
    }
    ; Get the NtResumeProcess function address
    NtResumeProcess := DllCall("GetProcAddress", "Ptr", DllCall("GetModuleHandle", "Str", "ntdll.dll", "Ptr"), "AStr", "NtResumeProcess", "Ptr")
    if !NtResumeProcess {
        ShowNotification("Error", "Failed to get NtResumeProcess function address", 3)
        return false
    }
    ; Call NtResumeProcess to resume the process
    DllCall(NtResumeProcess, "Ptr", hProcess)
    ; Close the process handle
    DllCall("CloseHandle", "Ptr", hProcess)
    ShowNotification("Process Resumed", "PID: " . pid, 2)
    return true
}

GetProcessNameFromPID(pid) {
    for process in ComObjGet("winmgmts:").ExecQuery("Select * from Win32_Process where ProcessId=" pid)
        return process.Name
    return "Unknown"
}

UpdateTrayMenu() {
    Menu, Tray, NoStandard
    Menu, Tray, DeleteAll  ; Clear all existing menu items
    
    ; Add title
    Menu, Tray, Add, ▼ Process Manager, DoNothing
    Menu, Tray, Disable, ▼ Process Manager
    Menu, Tray, Add
    
    ; Add Resume All option with an icon
    Menu, Tray, Add, ▶ Resume All Processes, ResumeAllProcessesHandler
    Menu, Tray, Add
    
    ; Add suspended processes
    if (SuspendedProcesses.Count() > 0) {
        Menu, Tray, Add, ⏸ Suspended Processes:, DoNothing
        Menu, Tray, Disable, ⏸ Suspended Processes:
        for pid, info in SuspendedProcesses {
            parts := StrSplit(info, "|")
            processName := parts[1]
            windowTitle := parts[2]
            Menu, Tray, Add, % "  " processName " - " SubStr(windowTitle, 1, 30) "... (PID: " pid ")", ResumeProcessHandler
        }
    } else {
        Menu, Tray, Add, No suspended processes, DoNothing
        Menu, Tray, Disable, No suspended processes
    }
    
    Menu, Tray, Add
    Menu, Tray, Add, ℹ️ About, ShowAbout
    Menu, Tray, Add, ❌ Exit, ExitScript
}

ResumeProcessHandler:
    ; Get the selected menu item's PID from its name
    RegExMatch(A_ThisMenuItem, "PID: (\d+)", pid)
    pid := pid1
    ; Resume the process
    if ResumeProcess(pid) {
        ; Remove from the list of suspended processes
        SuspendedProcesses.Delete(pid)
        ; Update the tray menu
        UpdateTrayMenu()
    }
return

ResumeAllProcessesHandler:
    ResumeAllProcesses()
return

ResumeAllProcesses() {
    for pid, info in SuspendedProcesses.Clone() {
        if ResumeProcess(pid) {
            SuspendedProcesses.Delete(pid)
        }
    }
    UpdateTrayMenu()
}

IsWindowFullScreen(winTitle) {
    winID := WinExist(winTitle)
    
    if !winID
        return false

    WinGet style, Style, ahk_id %winID%
    WinGetPos ,,,winW,winH, %winTitle%
    return ((style & 0x20800000) or winH >= A_ScreenHeight and winW >= A_ScreenWidth)
}

ForceSwitchToDesktop() {
    ; Temporarily disable foreground lock
    DllCall("SystemParametersInfo", UInt, 0x2000, UInt, 0, Ptr, 0, UInt, 0)
    
    ; Switch to desktop
    Send, #d
    
    ; Force the desktop to be the foreground window
    WinActivate, ahk_class WorkerW
    WinActivate, ahk_class Progman
    
    ; Re-enable foreground lock (30000 milliseconds is default)
    DllCall("SystemParametersInfo", UInt, 0x2001, UInt, 0, Ptr, 30000, UInt, 0)
}

ShowNotification(title, message, duration := 2) {
    TrayTip, %title%, %message%, %duration%, 17
}

ShowAbout:
    MsgBox, 0, About Process Manager, Process Manager v1.0`nCreated with AutoHotkey`n`nUse Alt+S to suspend the active window's process.`nRight-click the tray icon to manage suspended processes.
return

DoNothing:
return

ExitScript:
    ExitApp
return

; Initial update of the tray menu
UpdateTrayMenu()
return
