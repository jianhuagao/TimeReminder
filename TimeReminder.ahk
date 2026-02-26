#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent true

; =========================================================
; TimeReminder 小组件风格成品版（稳定版）
; - 输入：1717 1818（空格分隔，每组4位；兼容 17:17,18:18 自动清洗）
; - 标题栏拖动（窗口级坐标命中，稳定）
; - 右下角“...”弹出菜单（与托盘菜单同功能）
; - 不用 Func() / 不用 lambda，兼容旧 v2，避免 Invalid base
; =========================================================

; ------------------------
; ini
; ------------------------
iniPath := A_ScriptDir "\TimeReminder.ini"

if !FileExist(iniPath) {
    IniWrite("1717", iniPath, "Time", "Targets")
    IniWrite(1,      iniPath, "UI",   "AlwaysShowCountdown")
    IniWrite(230,    iniPath, "UI",   "Alpha")
    IniWrite(18,     iniPath, "UI",   "Radius")
    IniWrite("",     iniPath, "UI",   "CountdownX")
    IniWrite("",     iniPath, "UI",   "CountdownY")
    IniWrite(0,      iniPath, "App",  "StartWithWindows")
    IniWrite(1,      iniPath, "App",  "ShowConfigOnStart")
    IniWrite(0,      iniPath, "App",  "DoNotDisturb")
    IniWrite(1,      iniPath, "App",  "MuteOnFullscreen")
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
; 小组件尺寸/布局（用于坐标命中判断）
; ------------------------
WidgetW := 276
WidgetH := 132
TitleH  := 34
MenuBtnW := 34
MenuBtnH := 28

; ------------------------
; 全局状态
; ------------------------
configGui := ""
countdownGui := 0
line1Ctrl := 0
line2Ctrl := 0
menuBtnCtrl := 0

widgetHidden := false

ReminderStages := [5, 2, 1]
TargetsArr := []
TargetsSec := []

isEnabled := true
triggered := Map()
reachedNotified := false
lastRemainSec := ""
currentTargetSec := ""

lastX := ""
lastY := ""

widgetMenu := Menu()

; =========================================================
; 逻辑函数
; =========================================================

CheckTime(*) {
    global isEnabled, AlwaysShowCountdown, widgetHidden
    global triggered, reachedNotified, lastRemainSec, currentTargetSec

    if !isEnabled {
        if AlwaysShowCountdown && !widgetHidden
            ShowCountdownStatus("提醒已暂停", "")
        else if !AlwaysShowCountdown
            HideCountdown()
        return
    }

    nowSec := A_Hour * 3600 + A_Min * 60 + A_Sec
    nextTargetSec := GetNextTargetSec(nowSec)

    if (nextTargetSec = 0) {
        triggered.Clear(), reachedNotified := false, lastRemainSec := "", currentTargetSec := ""
        if AlwaysShowCountdown && !widgetHidden
            ShowCountdownStatus("今日无后续提醒", "")
        else if !AlwaysShowCountdown
            HideCountdown()
        return
    }

    if (currentTargetSec != nextTargetSec) {
        currentTargetSec := nextTargetSec
        triggered.Clear()
        reachedNotified := false
        lastRemainSec := ""
    }

    remainSec := nextTargetSec - nowSec
    if (lastRemainSec = "")
        lastRemainSec := remainSec

    for _, m in ReminderStages {
        threshold := m * 60
        if (lastRemainSec > threshold && remainSec <= threshold) {
            if !triggered.Has(m) {
                triggered[m] := true
                Notify("还有 " m " 分钟到 " SecToHHMM(nextTargetSec))
            }
        }
    }

    if (!reachedNotified && lastRemainSec > 0 && remainSec <= 0) {
        reachedNotified := true
        Notify("已到 " SecToHHMM(nextTargetSec))
    }

    lastRemainSec := remainSec

    if widgetHidden
        return

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
; 小组件 UI
; =========================================================

EnsureCountdownGui() {
    global countdownGui, line1Ctrl, line2Ctrl, menuBtnCtrl
    global Alpha, CountdownX, CountdownY
    global WidgetW, WidgetH, TitleH, MenuBtnW, MenuBtnH

    if countdownGui
        return

    W := WidgetW, H := WidgetH, TH := TitleH

    countdownGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
    countdownGui.BackColor := "202020"

    ; ---- 标题栏背景（深色）----
    countdownGui.AddText("x0 y0 w" W " h" TH " Background0F0F0F", "")
    ; 标题栏底部分割线
    countdownGui.AddText("x0 y" (TH-1) " w" W " h1 Background2A2A2A", "")

    ; 图标
    countdownGui.SetFont("s11 cEDEDED", "Segoe UI")
    countdownGui.AddText("x12 y7 w20 h20 Center Background0F0F0F", "🕒")

    ; 标题
    countdownGui.SetFont("s11 cEDEDED", "Segoe UI Semibold")
    countdownGui.AddText("x36 y8 w190 h18 Background0F0F0F", "Time Reminder")

    ; ---- 内容区背景（先画背景，再画文字，最后画按钮，避免被盖住）----
    countdownGui.AddText("x0 y" TH " w" W " h" (H-TH) " Background202020", "")
    ; 底部分割线
    countdownGui.AddText("x0 y" (H-1) " w" W " h1 Background2A2A2A", "")

    ; 两行文字
    countdownGui.SetFont("s11 cDADADA", "Segoe UI")
    line1Ctrl := countdownGui.AddText(
        "x0 y" (TH+10) " w" W " h18 Center Background202020",
        "提醒时间：--:--"
    )

    countdownGui.SetFont("s22 cFFFFFF", "Segoe UI Semibold")
    line2Ctrl := countdownGui.AddText(
        "x0 y" (TH+34) " w" W " h40 Center Background202020",
        "倒计时--:--"
    )

    ; ✅ 右下角菜单按钮：最后创建，保证在最上层可见
    countdownGui.SetFont("s13 cBFBFBF", "Segoe UI")
    menuBtnCtrl := countdownGui.AddText(
        "x" (W-MenuBtnW) " y" (H-MenuBtnH) " w" MenuBtnW " h" MenuBtnH " Center Background202020",
        "⋯"  ; 若仍不显示，可改为 "..."
    )

    ; ---- 显示位置：优先 ini 记忆 ----
    if (CountdownX != "" && CountdownY != "") {
        countdownGui.Show("x" CountdownX " y" CountdownY " w" W " h" H " NoActivate")
    } else {
        x := A_ScreenWidth - (W + 18)
        y := A_ScreenHeight - (H + 60)
        countdownGui.Show("x" x " y" y " w" W " h" H " NoActivate")
    }

    ; 半透明
    try WinSetTransparent(Alpha, "ahk_id " countdownGui.Hwnd)

    ; 圆角（你的 ApplyRoundedRegion() 保持不变）
    ApplyRoundedRegion()
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

SaveCountdownPos(*) {
    global countdownGui, iniPath, lastX, lastY, CountdownX, CountdownY, widgetHidden
    if !countdownGui || widgetHidden
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
}

ShowCountdownStatus(line1, line2) {
    EnsureCountdownGui()
    global line1Ctrl, line2Ctrl
    line1Ctrl.Text := line1
    line2Ctrl.Text := line2
}

HideCountdown() {
    global countdownGui
    if countdownGui {
        try countdownGui.Destroy()
        countdownGui := 0
    }
}

HideWidgetOnly(*) {
    global countdownGui, widgetHidden
    widgetHidden := true
    try if countdownGui
        countdownGui.Hide()
    BuildTrayMenu()
    BuildWidgetMenu()
}

ShowWidgetOnly(*) {
    global countdownGui, widgetHidden, CountdownX, CountdownY, WidgetW, WidgetH
    widgetHidden := false
    EnsureCountdownGui()
    try {
        if (CountdownX != "" && CountdownY != "")
            countdownGui.Show("x" CountdownX " y" CountdownY " w" WidgetW " h" WidgetH " NoActivate")
        else
            countdownGui.Show("NoActivate")
    }
    BuildTrayMenu()
    BuildWidgetMenu()
}

StartDragCountdown() {
    global countdownGui
    if !countdownGui
        return
    PostMessage(0xA1, 2, 0, , "ahk_id " countdownGui.Hwnd)
}

; =========================================================
; 窗口级点击命中（稳定）
; =========================================================
WM_LBUTTONDOWN_WIDGET(wParam, lParam, msg, hwnd) {
    global countdownGui, widgetHidden
    global WidgetW, WidgetH, TitleH, MenuBtnW, MenuBtnH

    if !countdownGui || widgetHidden
        return
    if (hwnd != countdownGui.Hwnd)
        return

    x := lParam & 0xFFFF
    y := (lParam >> 16) & 0xFFFF

    if (x >= WidgetW - MenuBtnW && y >= WidgetH - MenuBtnH) {
        ShowWidgetMenu()
        return 0
    }

    if (y < TitleH) {
        StartDragCountdown()
        return 0
    }

    ShowConfigDialog()
    return 0
}

; =========================================================
; 菜单（托盘 & 小组件共用）
; =========================================================

ShowWidgetMenu(*) {
    BuildWidgetMenu()
    try widgetMenu.Show()
}

BuildWidgetMenu() {
    global widgetMenu, widgetHidden, isEnabled, DoNotDisturb, AlwaysShowCountdown, StartWithWindows
    widgetMenu.Delete()
    widgetMenu.Add("打开配置", ShowConfigDialog)
    widgetMenu.Add(widgetHidden ? "显示小组件" : "隐藏小组件", ToggleWidgetVisibility)
    widgetMenu.Add(isEnabled ? "暂停提醒" : "继续提醒", ToggleEnabled)
    widgetMenu.Add(DoNotDisturb ? "关闭勿扰模式" : "开启勿扰模式", ToggleDND)
    widgetMenu.Add(AlwaysShowCountdown ? "关闭常驻浮窗" : "开启常驻浮窗", ToggleAlwaysShow)
    widgetMenu.Add(StartWithWindows ? "关闭开机启动" : "开启开机启动", ToggleStartup)
    widgetMenu.Add("立即刷新", ForceRefresh)
    widgetMenu.Add()
    widgetMenu.Add("退出", (*) => ExitApp()) ; 这个直接用 lambda 最兼容
}

BuildTrayMenu() {
    global isEnabled, AlwaysShowCountdown, DoNotDisturb, StartWithWindows, widgetHidden
    A_TrayMenu.Delete()
    A_TrayMenu.Add("打开配置", ShowConfigDialog)
    A_TrayMenu.Add(widgetHidden ? "显示小组件" : "隐藏小组件", ToggleWidgetVisibility)
    A_TrayMenu.Add(isEnabled ? "暂停提醒" : "继续提醒", ToggleEnabled)
    A_TrayMenu.Add(DoNotDisturb ? "关闭勿扰模式" : "开启勿扰模式", ToggleDND)
    A_TrayMenu.Add(AlwaysShowCountdown ? "关闭常驻浮窗" : "开启常驻浮窗", ToggleAlwaysShow)
    A_TrayMenu.Add(StartWithWindows ? "关闭开机启动" : "开启开机启动", ToggleStartup)
    A_TrayMenu.Add("立即刷新", ForceRefresh)
    A_TrayMenu.Add()
    A_TrayMenu.Add("退出", (*) => ExitApp())
}

ToggleWidgetVisibility(*) {
    global widgetHidden
    if widgetHidden
        ShowWidgetOnly()
    else
        HideWidgetOnly()
}

ToggleEnabled(*) {
    global isEnabled
    isEnabled := !isEnabled
    BuildTrayMenu()
    BuildWidgetMenu()
}

ToggleAlwaysShow(*) {
    global AlwaysShowCountdown, iniPath
    AlwaysShowCountdown := !AlwaysShowCountdown
    IniWrite(AlwaysShowCountdown ? 1 : 0, iniPath, "UI", "AlwaysShowCountdown")
    BuildTrayMenu()
    BuildWidgetMenu()
    if !AlwaysShowCountdown
        HideCountdown()
}

ToggleDND(*) {
    global DoNotDisturb, iniPath
    DoNotDisturb := !DoNotDisturb
    IniWrite(DoNotDisturb ? 1 : 0, iniPath, "App", "DoNotDisturb")
    BuildTrayMenu()
    BuildWidgetMenu()
}

ToggleStartup(*) {
    global StartWithWindows, iniPath
    StartWithWindows := !StartWithWindows
    IniWrite(StartWithWindows ? 1 : 0, iniPath, "App", "StartWithWindows")
    ApplyStartupSetting(StartWithWindows)
    BuildTrayMenu()
    BuildWidgetMenu()
}

ForceRefresh(*) {
    global triggered, reachedNotified, lastRemainSec, currentTargetSec
    triggered.Clear()
    reachedNotified := false
    lastRemainSec := ""
    currentTargetSec := ""
}

; =========================================================
; 配置窗口
; =========================================================

ShowConfigDialog(*) {
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
    global countdownGui

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
    BuildWidgetMenu()

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
; 多目标解析
; =========================================================

RebuildTargets() {
    global TargetsStr, TargetsArr, TargetsSec
    TargetsArr := ParseTargets(TargetsStr)
    TargetsSec := []
    for _, t in TargetsArr
        TargetsSec.Push(TimeToSec(t))
}

ParseTargets(str) {
    cleaned := Trim(str)
    cleaned := StrReplace(cleaned, ",", " ")
    cleaned := StrReplace(cleaned, ";", " ")
    cleaned := StrReplace(cleaned, "`n", " ")
    cleaned := StrReplace(cleaned, "`r", " ")
    cleaned := StrReplace(cleaned, ":", "")
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
; 开机启动
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

; =========================================================
; 初始化（必须放最后，避免旧解析器误判）
; =========================================================

RebuildTargets()
BuildWidgetMenu()
BuildTrayMenu()
ApplyStartupSetting(StartWithWindows)

SetTimer(CheckTime, 1000)
SetTimer(SaveCountdownPos, 1000)

OnMessage(0x201, WM_LBUTTONDOWN_WIDGET)

if (ShowConfigOnStart + 0 = 1)
    ShowConfigDialog()