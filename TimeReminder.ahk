#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent true

; =========================================================
; TimeReminder 小组件风格成品版（1717 1818 / 标题栏拖动 / 右下角齿轮 / 圆角稳定）
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
gearCtrl := 0
closeCtrl := 0

gearHover := false
closeHover := false

widgetHidden := false  ; 点 × 后仅隐藏小组件（不退出）

ReminderStages := [5, 2, 1]      ; 提前分钟

TargetsArr := []
TargetsSec := []
RebuildTargets()

isEnabled := true
triggered := Map()
reachedNotified := false
lastRemainSec := ""
currentTargetSec := ""

; 位置写入节流
lastX := ""
lastY := ""

; ------------------------
; 托盘菜单
; ------------------------
BuildTrayMenu()
ApplyStartupSetting(StartWithWindows)

BuildTrayMenu() {
    global isEnabled, AlwaysShowCountdown, DoNotDisturb, StartWithWindows, widgetHidden

    A_TrayMenu.Delete()
    A_TrayMenu.Add("打开配置", (*) => ShowConfigDialog())

    ; 显示/隐藏小组件
    A_TrayMenu.Add(widgetHidden ? "显示小组件" : "隐藏小组件", (*) => ToggleWidgetVisibility())

    A_TrayMenu.Add(isEnabled ? "暂停提醒" : "继续提醒", (*) => ToggleEnabled())
    A_TrayMenu.Add(DoNotDisturb ? "关闭勿扰模式" : "开启勿扰模式", (*) => ToggleDND())
    A_TrayMenu.Add(AlwaysShowCountdown ? "关闭常驻浮窗" : "开启常驻浮窗", (*) => ToggleAlwaysShow())
    A_TrayMenu.Add(StartWithWindows ? "关闭开机启动" : "开启开机启动", (*) => ToggleStartup())
    A_TrayMenu.Add("立即刷新", (*) => ForceRefresh())
    A_TrayMenu.Add()
    A_TrayMenu.Add("退出", (*) => ExitApp())
}

ToggleWidgetVisibility() {
    global widgetHidden
    widgetHidden := !widgetHidden
    if widgetHidden {
        HideWidgetOnly()
    } else {
        ShowWidgetOnly()
    }
    BuildTrayMenu()
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
if (ShowConfigOnStart + 0 = 1)
    ShowConfigDialog()

; ------------------------
; 主循环
; ------------------------
SetTimer(CheckTime, 1000)
SetTimer(SaveCountdownPos, 1000)

CheckTime() {
    global isEnabled, AlwaysShowCountdown, widgetHidden
    global triggered, reachedNotified, lastRemainSec, currentTargetSec

    if widgetHidden {
        ; 小组件被用户隐藏时，不要自动弹出来
        ; 但后台逻辑照常跑（提醒仍会发）
        ; 如果你希望隐藏后连提醒也停：可以在这里 return
    }

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
; 小组件浮窗（标题栏拖动 + × 隐藏 + 右下角齿轮 + 底部分割线）
; =========================================================

EnsureCountdownGui() {
    global countdownGui, line1Ctrl, line2Ctrl, gearCtrl, closeCtrl
    global Alpha, Radius, CountdownX, CountdownY
    global gearHover, closeHover

    if countdownGui
        return

    ; 尺寸
    W := 276
    H := 132
    TitleH := 34

    countdownGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
    countdownGui.BackColor := "202020"

    ; ---- 标题栏背景（深色，可拖动）----
    titleBg := countdownGui.AddText("x0 y0 w" W " h" TitleH " Background0F0F0F", "")
    titleBg.OnEvent("Click", (*) => StartDragCountdown())

    ; 图标
    countdownGui.SetFont("s11 cEDEDED", "Segoe UI")
    icon := countdownGui.AddText("x12 y7 w20 h20 Center Background0F0F0F", "🕒")
    icon.OnEvent("Click", (*) => StartDragCountdown())

    ; 标题（y=8 + TitleH=34 视觉更居中）
    countdownGui.SetFont("s11 cEDEDED", "Segoe UI Semibold")
    title := countdownGui.AddText("x36 y8 w190 h18 Background0F0F0F", "Time Reminder")
    title.OnEvent("Click", (*) => StartDragCountdown())

    ; × 关闭按钮（只隐藏小组件）
    countdownGui.SetFont("s12 cBFBFBF", "Segoe UI")
    closeCtrl := countdownGui.AddText("x" (W-34) " y6 w28 h22 Center Background0F0F0F 0x100", "✕")
    closeCtrl.OnEvent("Click", (*) => HideWidgetOnly())
    closeHover := false

    ; 标题栏底部细分割线（更精致）
    countdownGui.AddText("x0 y" (TitleH-1) " w" W " h1 Background2A2A2A", "")

    ; ---- 内容区背景（略浅）----
    contentBg := countdownGui.AddText("x0 y" TitleH " w" W " h" (H-TitleH) " Background202020", "")
    contentBg.OnEvent("Click", (*) => ShowConfigDialog())

    ; 两行文字
    countdownGui.SetFont("s11 cDADADA", "Segoe UI")
    line1Ctrl := countdownGui.AddText("x0 y" (TitleH+10) " w" W " h18 Center Background202020", "提醒时间：--:--")
    line1Ctrl.OnEvent("Click", (*) => ShowConfigDialog())

    countdownGui.SetFont("s22 cFFFFFF", "Segoe UI Semibold")
    line2Ctrl := countdownGui.AddText("x0 y" (TitleH+34) " w" W " h40 Center Background202020", "倒计时--:--")
    line2Ctrl.OnEvent("Click", (*) => ShowConfigDialog())

    ; ⚙ 齿轮移动到右下角（你要的）
    countdownGui.SetFont("s12 cBFBFBF", "Segoe UI")
    gearCtrl  := countdownGui.AddText("x" (W-34) " y" (H-28) " w28 h20 Center Background202020 0x100", "⚙")
    gearCtrl.OnEvent("Click", (*) => ShowConfigDialog())
    gearHover := false

    ; 底部分割线（你要的 ②）
    countdownGui.AddText("x0 y" (H-1) " w" W " h1 Background2A2A2A", "")

    ; 显示位置：优先 ini 记忆
    if (CountdownX != "" && CountdownY != "")
        countdownGui.Show("x" CountdownX " y" CountdownY " w" W " h" H " NoActivate")
    else {
        x := A_ScreenWidth - (W + 18)
        y := A_ScreenHeight - (H + 60)
        countdownGui.Show("x" x " y" y " w" W " h" H " NoActivate")
    }

    ; 半透明
    try WinSetTransparent(Alpha, "ahk_id " countdownGui.Hwnd)

    ; 圆角（稳定）
    ApplyRoundedRegion()

    ; hover（×/⚙ 变亮）
    OnMessage(0x200, WM_MOUSEMOVE_WIDGET) ; WM_MOUSEMOVE
}

WM_MOUSEMOVE_WIDGET(wParam, lParam, msg, hwnd) {
    global countdownGui, gearCtrl, closeCtrl, gearHover, closeHover
    if !countdownGui
        return
    if (hwnd != countdownGui.Hwnd)
        return

    try ctrlHwnd := DllCall("user32\ChildWindowFromPointEx", "ptr", hwnd, "int64", lParam, "uint", 1, "ptr")
    catch
        return

    overGear := (gearCtrl && ctrlHwnd = gearCtrl.Hwnd)
    overClose := (closeCtrl && ctrlHwnd = closeCtrl.Hwnd)

    if (overGear && !gearHover) {
        gearHover := true
        try gearCtrl.Opt("cFFFFFF")
    } else if (!overGear && gearHover) {
        gearHover := false
        try gearCtrl.Opt("cBFBFBF")
    }

    if (overClose && !closeHover) {
        closeHover := true
        try closeCtrl.Opt("cFFFFFF")
    } else if (!overClose && closeHover) {
        closeHover := false
        try closeCtrl.Opt("cBFBFBF")
    }
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
    global countdownGui, iniPath, lastX, lastY, CountdownX, CountdownY
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
}

ShowCountdownStatus(line1, line2) {
    EnsureCountdownGui()
    global line1Ctrl, line2Ctrl
    line1Ctrl.Text := line1
    line2Ctrl.Text := line2
}

; ×：只隐藏小组件
HideWidgetOnly() {
    global countdownGui, widgetHidden
    widgetHidden := true
    try if countdownGui
        countdownGui.Hide()
    BuildTrayMenu()
}

ShowWidgetOnly() {
    global countdownGui, widgetHidden, CountdownX, CountdownY
    widgetHidden := false
    EnsureCountdownGui()
    try {
        if (CountdownX != "" && CountdownY != "")
            countdownGui.Show("x" CountdownX " y" CountdownY " NoActivate")
        else
            countdownGui.Show("NoActivate")
    }
}

; 非常驻模式下需要彻底销毁窗口（省资源）
HideCountdown() {
    global countdownGui
    if countdownGui {
        try countdownGui.Destroy()
        countdownGui := 0
    }
}

; =========================================================
; 配置窗口（1717 1818 2030）
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

    ; 去重 + 插入排序
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