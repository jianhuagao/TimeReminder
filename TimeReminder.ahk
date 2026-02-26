#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent true

; =========================================================
; TimeReminder 成品版（输入 1717 1818 / 上部拖动条 / 下部点击配置 / 圆角稳定）
; =========================================================

iniPath := A_ScriptDir "\TimeReminder.ini"

if !FileExist(iniPath) {
    IniWrite("1717", iniPath, "Time", "Targets")                ; 多目标：1717 1818 2030
    IniWrite(0,      iniPath, "UI",   "AlwaysShowCountdown")    ; 0/1 常驻浮窗
    IniWrite(230,    iniPath, "UI",   "Alpha")                  ; 0-255
    IniWrite(18,     iniPath, "UI",   "Radius")                 ; 0-80
    IniWrite("",     iniPath, "UI",   "CountdownX")
    IniWrite("",     iniPath, "UI",   "CountdownY")
    IniWrite(0,      iniPath, "App",  "StartWithWindows")       ; 0/1 开机启动
    IniWrite(0,      iniPath, "App",  "ShowConfigOnStart")      ; 0/1 启动弹配置
    IniWrite(0,      iniPath, "App",  "DoNotDisturb")           ; 0/1 勿扰
    IniWrite(1,      iniPath, "App",  "MuteOnFullscreen")       ; 0/1 全屏静音
}

; ------------------------
; 读取配置
; ------------------------
TargetsStr := IniRead(iniPath, "Time", "Targets", "1717")
AlwaysShowCountdown := IniRead(iniPath, "UI", "AlwaysShowCountdown", 0)
Alpha     := IniRead(iniPath, "UI", "Alpha", 230)
Radius    := IniRead(iniPath, "UI", "Radius", 18)
CountdownX := IniRead(iniPath, "UI", "CountdownX", "")
CountdownY := IniRead(iniPath, "UI", "CountdownY", "")
StartWithWindows := IniRead(iniPath, "App", "StartWithWindows", 0)
ShowConfigOnStart := IniRead(iniPath, "App", "ShowConfigOnStart", 0)
DoNotDisturb := IniRead(iniPath, "App", "DoNotDisturb", 0)
MuteOnFullscreen := IniRead(iniPath, "App", "MuteOnFullscreen", 1)

; ------------------------
; 全局状态
; ------------------------
configGui := ""
countdownGui := 0
line1Ctrl := 0
line2Ctrl := 0

ReminderStages := [5, 2, 1]      ; 提前分钟

TargetsArr := []                ; ["1717","1818"]
TargetsSec := []                ; [62220, ...]
RebuildTargets()

isEnabled := true
triggered := Map()
reachedNotified := false
lastRemainSec := ""
currentTargetSec := ""

; 浮窗位置写入节流（更稳）
lastX := ""
lastY := ""

; ------------------------
; 托盘菜单
; ------------------------
BuildTrayMenu()
ApplyStartupSetting(StartWithWindows)

BuildTrayMenu() {
    global isEnabled, AlwaysShowCountdown, DoNotDisturb, StartWithWindows

    A_TrayMenu.Delete()
    A_TrayMenu.Add("打开配置", (*) => ShowConfigDialog())
    A_TrayMenu.Add(isEnabled ? "暂停提醒" : "继续提醒", (*) => ToggleEnabled())
    A_TrayMenu.Add(DoNotDisturb ? "关闭勿扰模式" : "开启勿扰模式", (*) => ToggleDND())
    A_TrayMenu.Add(AlwaysShowCountdown ? "关闭常驻浮窗" : "开启常驻浮窗", (*) => ToggleAlwaysShow())
    A_TrayMenu.Add(StartWithWindows ? "关闭开机启动" : "开启开机启动", (*) => ToggleStartup())
    A_TrayMenu.Add("立即刷新", (*) => ForceRefresh())
    A_TrayMenu.Add()
    A_TrayMenu.Add("退出", (*) => ExitApp())
}

ToggleEnabled() {
    global isEnabled
    isEnabled := !isEnabled
    BuildTrayMenu()
}

ToggleAlwaysShow() {
    global AlwaysShowCountdown, iniPath
    AlwaysShowCountdown := !AlwaysShowCountdown
    IniWrite(AlwaysShowCountdown ? 1 : 0, iniPath, "UI", "AlwaysShowCountdown")
    BuildTrayMenu()
    if !AlwaysShowCountdown
        HideCountdown()
}

ToggleDND() {
    global DoNotDisturb, iniPath
    DoNotDisturb := !DoNotDisturb
    IniWrite(DoNotDisturb ? 1 : 0, iniPath, "App", "DoNotDisturb")
    BuildTrayMenu()
}

ToggleStartup() {
    global StartWithWindows, iniPath
    StartWithWindows := !StartWithWindows
    IniWrite(StartWithWindows ? 1 : 0, iniPath, "App", "StartWithWindows")
    ApplyStartupSetting(StartWithWindows)
    BuildTrayMenu()
}

ForceRefresh() {
    global triggered, reachedNotified, lastRemainSec, currentTargetSec
    triggered.Clear()
    reachedNotified := false
    lastRemainSec := ""
    currentTargetSec := ""
}

; ------------------------
; 启动是否弹配置
; ------------------------
if (ShowConfigOnStart + 0 = 1) {
    ShowConfigDialog()
}

; ------------------------
; 主循环
; ------------------------
SetTimer(CheckTime, 1000)
SetTimer(SaveCountdownPos, 1000) ; 位置记忆更稳

CheckTime() {
    global isEnabled, AlwaysShowCountdown
    global triggered, reachedNotified, lastRemainSec, currentTargetSec
    global DoNotDisturb, MuteOnFullscreen

    if !isEnabled {
        if AlwaysShowCountdown
            ShowCountdownStatus("提醒已暂停", "")
        else
            HideCountdown()
        return
    }

    nowSec := A_Hour * 3600 + A_Min * 60 + A_Sec
    nextTargetSec := GetNextTargetSec(nowSec)

    ; 今天无后续目标
    if (nextTargetSec = 0) {
        triggered.Clear()
        reachedNotified := false
        lastRemainSec := ""
        currentTargetSec := ""

        if AlwaysShowCountdown
            ShowCountdownStatus("今日无后续提醒", "")
        else
            HideCountdown()
        return
    }

    ; 目标切换
    if (currentTargetSec != nextTargetSec) {
        currentTargetSec := nextTargetSec
        triggered.Clear()
        reachedNotified := false
        lastRemainSec := ""
    }

    remainSec := nextTargetSec - nowSec
    if (lastRemainSec = "")
        lastRemainSec := remainSec

    ; 阈值跨越触发（不卡顿不漏）
    for _, m in ReminderStages {
        threshold := m * 60
        if (lastRemainSec > threshold && remainSec <= threshold) {
            if !triggered.Has(m) {
                triggered[m] := true
                Notify("还有 " m " 分钟到 " SecToHHMM(nextTargetSec))
            }
        }
    }

    ; 到点提醒一次：跨过0
    if (!reachedNotified && lastRemainSec > 0 && remainSec <= 0) {
        reachedNotified := true
        Notify("已到 " SecToHHMM(nextTargetSec))
    }

    lastRemainSec := remainSec

    ; 浮窗显示
    if AlwaysShowCountdown {
        ShowCountdown(remainSec, nextTargetSec)
    } else {
        if (remainSec <= 120 && remainSec > 0)
            ShowCountdown(remainSec, nextTargetSec)
        else
            HideCountdown()
    }
}

Notify(text) {
    global DoNotDisturb, MuteOnFullscreen
    if DoNotDisturb
        return
    if (MuteOnFullscreen && IsFullscreenActive())
        return
    TrayTip(text, "⏰ 时间提醒")
}

IsFullscreenActive() {
    try {
        hwnd := WinGetID("A")
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        return (x <= 0 && y <= 0 && w >= A_ScreenWidth && h >= A_ScreenHeight)
    } catch {
        return false
    }
}

; =========================================================
; 倒计时浮窗（上部拖动条 / 下部点击配置 / 圆角稳定）
; =========================================================

EnsureCountdownGui() {
    global countdownGui, line1Ctrl, line2Ctrl
    global Alpha, Radius
    global CountdownX, CountdownY

    if countdownGui
        return

    countdownGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
    countdownGui.BackColor := "202020"

    ; ===== 上部拖动条（深色）=====
    countdownGui.SetFont("s10 cFFFFFF", "Segoe UI")
    dragBar := countdownGui.AddText("x0 y3 w260 h28 Center Background101010", "Time Reminder")
dragBar.SetFont("s10", "Segoe UI")
    dragBar.OnEvent("Click", (*) => StartDragCountdown())

    ; ===== 下部内容区（浅一点）=====
    bg := countdownGui.AddText("x0 y28 w260 h88 Background202020", "")

    countdownGui.SetFont("s12 cFFFFFF", "Segoe UI")
    line1Ctrl := countdownGui.AddText("x0 y34 w260 Center", "提醒时间：--:--")

    countdownGui.SetFont("s22 cFFFFFF", "Segoe UI")
    line2Ctrl := countdownGui.AddText("x0 y58 w260 Center", "倒计时--:--")

    ; 下部点击打开配置
    bg.OnEvent("Click", (*) => ShowConfigDialog())
    line1Ctrl.OnEvent("Click", (*) => ShowConfigDialog())
    line2Ctrl.OnEvent("Click", (*) => ShowConfigDialog())

    ; 显示位置：优先 ini 记忆
    if (CountdownX != "" && CountdownY != "") {
        countdownGui.Show("x" CountdownX " y" CountdownY " NoActivate")
    } else {
        x := A_ScreenWidth - 280
        y := A_ScreenHeight - 180
        countdownGui.Show("x" x " y" y " NoActivate")
    }

    ; 半透明
    try WinSetTransparent(Alpha, "ahk_id " countdownGui.Hwnd)

    ; 圆角（WinAPI 稳定版）
    ApplyRoundedRegion()
}

StartDragCountdown() {
    global countdownGui
    if !countdownGui
        return
    PostMessage(0xA1, 2, 0, , "ahk_id " countdownGui.Hwnd) ; WM_NCLBUTTONDOWN + HTCAPTION
}

ApplyRoundedRegion() {
    global countdownGui, Radius
    if !countdownGui
        return
    try {
        WinGetPos(, , &w, &h, "ahk_id " countdownGui.Hwnd)
        r := Radius + 0
        if (r <= 0)
            return

        hrgn := DllCall("gdi32\CreateRoundRectRgn"
            , "int", 0, "int", 0, "int", w, "int", h
            , "int", r, "int", r
            , "ptr")

        DllCall("user32\SetWindowRgn", "ptr", countdownGui.Hwnd, "ptr", hrgn, "int", true)
    }
}

SaveCountdownPos() {
    global countdownGui, iniPath, lastX, lastY
    global CountdownX, CountdownY
    if !countdownGui
        return
    try {
        WinGetPos(&x, &y, , , "ahk_id " countdownGui.Hwnd)
        if (x != lastX || y != lastY) {
            lastX := x, lastY := y
            CountdownX := x, CountdownY := y
            IniWrite(x, iniPath, "UI", "CountdownX")
            IniWrite(y, iniPath, "UI", "CountdownY")
        }
    }
}

ShowCountdown(remainSec, targetSec) {
    EnsureCountdownGui()
    global line1Ctrl, line2Ctrl

    line1Ctrl.Text := "提醒时间：" SecToHHMM(targetSec)

    if (remainSec <= 0) {
        line2Ctrl.Text := "已到点"
    } else {
        m := Floor(remainSec / 60)
        s := Mod(remainSec, 60)
        line2Ctrl.Text := "倒计时" Format("{:02}:{:02}", m, s)
    }

    ; 防止某些系统首次不刷新 region
    ApplyRoundedRegion()
}

ShowCountdownStatus(line1, line2) {
    EnsureCountdownGui()
    global line1Ctrl, line2Ctrl
    line1Ctrl.Text := line1
    line2Ctrl.Text := line2
    ApplyRoundedRegion()
}

HideCountdown() {
    global countdownGui
    if countdownGui {
        try countdownGui.Destroy()
        countdownGui := 0
    }
}

; =========================================================
; 配置窗口（提示改成 1717 1818 2030）
; =========================================================

ShowConfigDialog() {
    global configGui
    global TargetsStr, AlwaysShowCountdown, Alpha, Radius
    global StartWithWindows, ShowConfigOnStart, DoNotDisturb, MuteOnFullscreen

    try {
        if IsObject(configGui) {
            configGui.Show()
            return
        }
    }

    configGui := Gui()
    configGui.Title := "时间提醒器配置"
    configGui.MarginX := 15
    configGui.MarginY := 15

    configGui.AddText("w380", "目标时间（空格分隔，每组4位：HHMM）：")
    configGui.AddEdit("xm w380 vTargetsValue", TargetsStr)
    configGui.AddText("xm c808080", "示例：1717 1818 2030（分别代表 17:17、18:18、20:30）")

    configGui.AddCheckbox("xm y+12 vAlwaysShow", "是否常驻浮窗").Value := AlwaysShowCountdown ? 1 : 0

    configGui.AddText("xm y+10", "透明度(0-255)：")
    configGui.AddEdit("x+8 w70 vAlphaValue", Alpha)
    configGui.AddText("x+18", "圆角半径(0-80)：")
    configGui.AddEdit("x+8 w70 vRadiusValue", Radius)

    configGui.AddCheckbox("xm y+12 vDND", "勿扰模式（不弹出提醒）").Value := DoNotDisturb ? 1 : 0
    configGui.AddCheckbox("xm y+6 vMuteFS", "全屏时静音（不弹出提醒）").Value := MuteOnFullscreen ? 1 : 0
    configGui.AddCheckbox("xm y+6 vStartup", "开机启动").Value := StartWithWindows ? 1 : 0
    configGui.AddCheckbox("xm y+6 vShowOnStart", "启动时弹出配置窗口").Value := ShowConfigOnStart ? 1 : 0

    configGui.AddButton("xm y+14 w90 h30 Default", "保存").OnEvent("Click", ConfigOK)
    configGui.AddButton("x+10 w90 h30", "取消").OnEvent("Click", ConfigCancel)

    configGui.OnEvent("Close", (*) => (configGui := ""))
    configGui.Show("w420 h360")
}

ConfigOK(*) {
    global configGui, iniPath
    global TargetsStr, AlwaysShowCountdown, Alpha, Radius
    global StartWithWindows, ShowConfigOnStart, DoNotDisturb, MuteOnFullscreen

    configGui.Submit()

    newTargets := Trim(configGui["TargetsValue"].Value)
    if (newTargets = "") {
        MsgBox("请至少输入一个时间，例如：1717")
        return
    }

    arr := ParseTargets(newTargets)
    if (arr.Length = 0) {
        MsgBox("时间格式无效！请输入 4 位数字一组，用空格分隔，例如：1717 1818")
        return
    }

    newAlpha := Trim(configGui["AlphaValue"].Value)
    newRadius := Trim(configGui["RadiusValue"].Value)
    if !IsInteger(newAlpha) || (newAlpha+0 < 0 || newAlpha+0 > 255) {
        MsgBox("透明度应为 0-255 的整数。")
        return
    }
    if !IsInteger(newRadius) || (newRadius+0 < 0 || newRadius+0 > 80) {
        MsgBox("圆角半径建议 0-80 的整数。")
        return
    }

    TargetsStr := JoinTargets(arr)
    AlwaysShowCountdown := configGui["AlwaysShow"].Value ? 1 : 0
    Alpha := newAlpha + 0
    Radius := newRadius + 0
    DoNotDisturb := configGui["DND"].Value ? 1 : 0
    MuteOnFullscreen := configGui["MuteFS"].Value ? 1 : 0
    StartWithWindows := configGui["Startup"].Value ? 1 : 0
    ShowConfigOnStart := configGui["ShowOnStart"].Value ? 1 : 0

    IniWrite(TargetsStr, iniPath, "Time", "Targets")
    IniWrite(AlwaysShowCountdown, iniPath, "UI", "AlwaysShowCountdown")
    IniWrite(Alpha, iniPath, "UI", "Alpha")
    IniWrite(Radius, iniPath, "UI", "Radius")
    IniWrite(DoNotDisturb, iniPath, "App", "DoNotDisturb")
    IniWrite(MuteOnFullscreen, iniPath, "App", "MuteOnFullscreen")
    IniWrite(StartWithWindows, iniPath, "App", "StartWithWindows")
    IniWrite(ShowConfigOnStart, iniPath, "App", "ShowConfigOnStart")

    ApplyStartupSetting(StartWithWindows)
    RebuildTargets()
    ForceRefresh()
    BuildTrayMenu()

    ; 立即应用 UI
    if (countdownGui) {
        try WinSetTransparent(Alpha, "ahk_id " countdownGui.Hwnd)
        ApplyRoundedRegion()
    }
    if !AlwaysShowCountdown
        HideCountdown()

    configGui.Destroy()
    configGui := ""
}

ConfigCancel(*) {
    global configGui
    try configGui.Destroy()
    configGui := ""
}

; =========================================================
; 多目标解析（输入：1717 1818；兼容：17:17,18:18）
; =========================================================

RebuildTargets() {
    global TargetsStr, TargetsArr, TargetsSec
    TargetsArr := ParseTargets(TargetsStr)
    TargetsSec := []
    for _, t in TargetsArr
        TargetsSec.Push(TimeToSec(t))
}

ParseTargets(str) {
    ; 支持：1717 1818（空格/换行分隔，每组4位）
    ; 兼容旧：17:17,18:18 -> 清洗成 1717 1818
    cleaned := Trim(str)

    cleaned := StrReplace(cleaned, ",", " ")
    cleaned := StrReplace(cleaned, ";", " ")
    cleaned := StrReplace(cleaned, "`n", " ")
    cleaned := StrReplace(cleaned, "`r", " ")
    cleaned := StrReplace(cleaned, ":", "") ; 17:17 -> 1717

    while InStr(cleaned, "  ")
        cleaned := StrReplace(cleaned, "  ", " ")

    tokens := []
    for _, raw in StrSplit(cleaned, " ") {
        t := Trim(raw)
        if (t = "")
            continue
        if !RegExMatch(t, "^\d{4}$")
            continue

        hh := SubStr(t, 1, 2) + 0
        mm := SubStr(t, 3, 2) + 0
        if (hh < 0 || hh > 23 || mm < 0 || mm > 59)
            continue

        tokens.Push(Format("{:02}{:02}", hh, mm))
    }

    ; 去重 + 插入排序（兼容所有 v2）
    seen := Map()
    sorted := []
    for _, t in tokens {
        if seen.Has(t)
            continue
        seen[t] := true

        inserted := false
        tSec := TimeToSec(t)
        for i, s in sorted {
            if (tSec < TimeToSec(s)) {
                sorted.InsertAt(i, t)
                inserted := true
                break
            }
        }
        if !inserted
            sorted.Push(t)
    }
    return sorted
}

JoinTargets(arr) {
    out := ""
    for i, t in arr
        out .= (i = 1 ? "" : " ") t
    return out
}

TimeToSec(hhmm) {
    hh := SubStr(hhmm, 1, 2) + 0
    mm := SubStr(hhmm, 3, 2) + 0
    return hh * 3600 + mm * 60
}

SecToHHMM(sec) {
    hh := Floor(sec / 3600)
    mm := Floor(Mod(sec, 3600) / 60)
    return Format("{:02}:{:02}", hh, mm)
}

GetNextTargetSec(nowSec) {
    global TargetsSec
    for _, sec in TargetsSec {
        if (sec > nowSec)
            return sec
    }
    return 0
}

; =========================================================
; 开机启动：写 Startup 快捷方式
; =========================================================

ApplyStartupSetting(enable) {
    link := A_Startup "\TimeReminder.lnk"
    if (enable + 0 = 1) {
        try {
            FileCreateShortcut(
                A_AhkPath,
                link,
                A_ScriptDir,
                '"' A_ScriptFullPath '"',
                "TimeReminder",
                A_ScriptFullPath
            )
        }
    } else {
        try if FileExist(link)
            FileDelete(link)
    }
}