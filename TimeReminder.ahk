#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent true

; ========================
; ini 配置
; ========================
iniPath := A_ScriptDir "\TimeReminder.ini"

if !FileExist(iniPath) {
    IniWrite(11, iniPath, "Time", "TargetHour")
    IniWrite(0,  iniPath, "Time", "TargetMinute")
    IniWrite("11:00", iniPath, "Time", "Targets") ; 支持多时间：11:00,14:30
    IniWrite(0,  iniPath, "UI",   "AlwaysShowCountdown") ; 0/1
    IniWrite("", iniPath, "UI",   "CountdownX")
    IniWrite("", iniPath, "UI",   "CountdownY")
    IniWrite(230, iniPath, "UI",  "Alpha")  ; 0-255
    IniWrite(18, iniPath, "UI",   "Radius") ; 圆角半径
}

TargetHour   := IniRead(iniPath, "Time", "TargetHour", 11)
TargetMinute := IniRead(iniPath, "Time", "TargetMinute", 0)
TargetsStr   := IniRead(iniPath, "Time", "Targets", TargetHour ":" Format("{:02}", TargetMinute))

AlwaysShowCountdown := IniRead(iniPath, "UI", "AlwaysShowCountdown", 0)
CountdownX := IniRead(iniPath, "UI", "CountdownX", "")
CountdownY := IniRead(iniPath, "UI", "CountdownY", "")
Alpha     := IniRead(iniPath, "UI", "Alpha", 230)
Radius    := IniRead(iniPath, "UI", "Radius", 18)

; ========================
; 全局状态
; ========================
configGui := ""
countdownGui := 0
line1Ctrl := 0
line2Ctrl := 0

ReminderStages := [5, 2, 1]      ; 提前分钟
triggered := Map()              ; 当前目标的阶段触发记录
reachedNotified := false        ; 当前目标到点提醒是否已触发
lastRemainSec := ""             ; 用于阈值跨越检测
currentTargetSec := ""          ; 当前目标秒（用于目标切换检测）
isEnabled := true               ; 托盘“暂停/继续”

; ========================
; 托盘菜单（2）
; ========================
BuildTrayMenu()
BuildTrayMenu() {
    global AlwaysShowCountdown, isEnabled

    A_TrayMenu.Delete() ; 清空默认
    A_TrayMenu.Add("打开配置", (*) => ShowConfigDialog())
    A_TrayMenu.Add(isEnabled ? "暂停提醒" : "继续提醒", (*) => ToggleEnabled())
    A_TrayMenu.Add(AlwaysShowCountdown ? "关闭常驻浮窗" : "开启常驻浮窗", (*) => ToggleAlwaysShow())
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
    ; 关闭常驻时立刻隐藏
    if !AlwaysShowCountdown
        HideCountdown()
}

; ========================
; 配置窗口（支持多目标时间：7）
; ========================
ShowConfigDialog() {
    global configGui, TargetsStr, AlwaysShowCountdown, Alpha, Radius

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

    configGui.AddText("w320", "目标时间（支持多个，逗号分隔）：")
    configGui.AddEdit("xm w320 vTargetsValue", TargetsStr)
    configGui.AddText("xm c808080", "示例：11:00,14:30,18:00 （只提醒今天接下来最近的一次）")

    configGui.AddCheckbox("xm y+16 vAlwaysShow", "是否常驻浮窗").Value := AlwaysShowCountdown ? 1 : 0

    configGui.AddText("xm y+14", "透明度(0-255)：")
    configGui.AddEdit("x+8 w70 vAlphaValue", Alpha)

    configGui.AddText("x+18", "圆角半径：")
    configGui.AddEdit("x+8 w70 vRadiusValue", Radius)

    configGui.AddButton("xm y+18 w90 h30 Default", "ok").OnEvent("Click", ConfigOK)
    configGui.AddButton("x+10 w90 h30", "cancel").OnEvent("Click", ConfigCancel)

    configGui.OnEvent("Close", (*) => (configGui := ""))
    configGui.Show("w360 h260")
}

ConfigOK(*) {
    global configGui, iniPath
    global TargetsStr, TargetHour, TargetMinute
    global AlwaysShowCountdown, Alpha, Radius
    global triggered, reachedNotified, lastRemainSec, currentTargetSec

    configGui.Submit()

    newTargets := Trim(configGui["TargetsValue"].Value)
    newAlways := configGui["AlwaysShow"].Value
    newAlpha  := Trim(configGui["AlphaValue"].Value)
    newRadius := Trim(configGui["RadiusValue"].Value)

    if (newTargets = "") {
        MsgBox("请至少输入一个时间，例如 11:00")
        return
    }

    parsed := ParseTargets(newTargets)
    if (parsed.Length = 0) {
        MsgBox("时间格式无效！请使用 HH:MM，例如 11:00,14:30")
        return
    }

    if !IsInteger(newAlpha) || (newAlpha+0 < 0 || newAlpha+0 > 255) {
        MsgBox("透明度应为 0-255 的整数。")
        return
    }
    if !IsInteger(newRadius) || (newRadius+0 < 0 || newRadius+0 > 80) {
        MsgBox("圆角半径建议 0-80 的整数。")
        return
    }

    ; 以第一个时间回填旧字段（兼容）
    first := parsed[1] ; "HH:MM"
    parts := StrSplit(first, ":")
    TargetHour := parts[1] + 0
    TargetMinute := parts[2] + 0

    TargetsStr := JoinTargets(parsed)
    AlwaysShowCountdown := newAlways ? 1 : 0
    Alpha := newAlpha + 0
    Radius := newRadius + 0

    IniWrite(TargetHour, iniPath, "Time", "TargetHour")
    IniWrite(TargetMinute, iniPath, "Time", "TargetMinute")
    IniWrite(TargetsStr, iniPath, "Time", "Targets")
    IniWrite(AlwaysShowCountdown, iniPath, "UI", "AlwaysShowCountdown")
    IniWrite(Alpha, iniPath, "UI", "Alpha")
    IniWrite(Radius, iniPath, "UI", "Radius")

    ; 配置变更后重置当前目标状态（6）
    triggered.Clear()
    reachedNotified := false
    lastRemainSec := ""
    currentTargetSec := ""

    BuildTrayMenu()

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

; ========================
; 解析/工具（7）
; ========================
ParseTargets(str) {
    ; 返回数组：["11:00","14:30"]（已去重、排序）

    times := []
    seen := Map()

    for _, raw in StrSplit(str, ",") {
        t := Trim(raw)
        if (t = "")
            continue

        if !RegExMatch(t, "^\s*(\d{1,2})\s*:\s*(\d{1,2})\s*$", &m)
            continue

        hh := m[1] + 0
        mm := m[2] + 0
        if (hh < 0 || hh > 23 || mm < 0 || mm > 59)
            continue

        norm := Format("{:02}:{:02}", hh, mm)
        if !seen.Has(norm) {
            seen[norm] := true
            times.Push(norm)
        }
    }

    ; ===== 手写排序（按时间先后）=====
    ; 插入排序：稳定且适合小数组
    sorted := []

    for _, t in times {
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
    for i, t in arr {
        out .= (i=1 ? "" : ",") t
    }
    return out
}

TimeToSec(hhmm) {
    p := StrSplit(hhmm, ":")
    return (p[1] + 0) * 3600 + (p[2] + 0) * 60
}

GetNextTargetSec(nowSec) {
    global TargetsStr
    arr := ParseTargets(TargetsStr)
    for _, t in arr {
        sec := TimeToSec(t)
        if (sec > nowSec)
            return sec
    }
    return 0 ; 今天已无后续目标
}

SecToHHMM(sec) {
    hh := Floor(sec / 3600)
    mm := Floor(Mod(sec, 3600) / 60)
    return Format("{:02}:{:02}", hh, mm)
}

; ========================
; 主循环
; ========================
SetTimer(CheckTime, 1000)

CheckTime() {
    global isEnabled
    if !isEnabled {
        ; 暂停时：常驻浮窗就显示“已暂停”，非常驻则隐藏
        global AlwaysShowCountdown
        if AlwaysShowCountdown
            ShowCountdownPaused()
        else
            HideCountdown()
        return
    }

    global ReminderStages, triggered, reachedNotified
    global lastRemainSec, currentTargetSec
    global AlwaysShowCountdown

    nowSec := A_Hour * 3600 + A_Min * 60 + A_Sec
    nextTargetSec := GetNextTargetSec(nowSec)

    ; 今天没有后续目标
    if (nextTargetSec = 0) {
        ; 状态清空
        triggered.Clear()
        reachedNotified := false
        lastRemainSec := ""
        currentTargetSec := ""

        if AlwaysShowCountdown
            ShowCountdownNoMore()
        else
            HideCountdown()
        return
    }

    ; 目标切换（例如刚过一个目标，进入下一个）
    if (currentTargetSec != nextTargetSec) {
        currentTargetSec := nextTargetSec
        triggered.Clear()
        reachedNotified := false
        lastRemainSec := ""
    }

    remainSec := nextTargetSec - nowSec

    ; ================
    ; 6 阈值跨越触发（不会漏）
    ; ================
    if (lastRemainSec = "") {
        lastRemainSec := remainSec
    }

    ; 多阶段提醒：当 lastRemainSec > threshold 且 remainSec <= threshold 时触发
    for _, m in ReminderStages {
        threshold := m * 60
        if (lastRemainSec > threshold && remainSec <= threshold) {
            if !triggered.Has(m) {
                triggered[m] := true
                ShowStageNotification(m, SecToHHMM(nextTargetSec))
            }
        }
    }

    ; 到点提醒一次：跨过 0
    if (!reachedNotified && lastRemainSec > 0 && remainSec <= 0) {
        reachedNotified := true
        TrayTip("已到 " SecToHHMM(nextTargetSec), "⏰ 时间提醒")
    }

    lastRemainSec := remainSec

    ; ================
    ; 倒计时显示逻辑
    ; ================
    if AlwaysShowCountdown {
        ShowCountdown(remainSec, nextTargetSec)
    } else {
        if (remainSec <= 120 && remainSec > 0)
            ShowCountdown(remainSec, nextTargetSec)
        else
            HideCountdown()
    }
}

ShowStageNotification(min, hhmm) {
    TrayTip("还有 " min " 分钟到 " hhmm, "⏰ 时间提醒")
}

; ========================
; 倒计时悬浮窗（4/5）
; - 可拖动（点击拖动）
; - 记住位置（写入 ini）
; - 半透明 + 圆角
; ========================

EnsureCountdownGui() {
    global countdownGui, line1Ctrl, line2Ctrl
    global Alpha, Radius

    if countdownGui
        return

    countdownGui := Gui("+AlwaysOnTop -Caption +ToolWindow +LastFound")
    countdownGui.BackColor := "202020"

    countdownGui.SetFont("s12 cFFFFFF", "Segoe UI")
    line1Ctrl := countdownGui.AddText("vLine1 w220 Center", "提醒时间：--:--")

    countdownGui.SetFont("s22 cFFFFFF", "Segoe UI")
    line2Ctrl := countdownGui.AddText("vLine2 w220 Center", "倒计时--:--")

    ; 点击任意行打开配置（你之前要的）
    line1Ctrl.OnEvent("Click", (*) => ShowConfigDialog())
    line2Ctrl.OnEvent("Click", (*) => ShowConfigDialog())

    ; 可拖动：按下左键即拖动窗口
    OnMessage(0x201, WM_LBUTTONDOWN) ; WM_LBUTTONDOWN
    OnMessage(0x232, WM_EXITSIZEMOVE) ; 结束移动/调整大小

    ; 透明度
    try WinSetTransparent(Alpha, "ahk_id " countdownGui.Hwnd)

    ; 圆角（region）
    ApplyRoundedRegion()

    ; 初始显示位置：优先 ini 记住的位置，否则右下角
    ShowCountdownAtSavedPos()
}

ApplyRoundedRegion() {
    global countdownGui, Radius
    if !countdownGui
        return

    ; 需要窗口已创建
    try {
        WinGetPos(&x, &y, &w, &h, "ahk_id " countdownGui.Hwnd)
        r := Radius + 0
        if (r <= 0) {
            WinSetRegion("", "ahk_id " countdownGui.Hwnd)
            return
        }
        ; RoundRect region
        ; WinSetRegion 的格式：x-y w h Rw Rh（AHK v2 支持与 v1 类似 region 字符串）
        WinSetRegion("0-0 " w "-" h " R" r "-" r, "ahk_id " countdownGui.Hwnd)
    }
}

ShowCountdownAtSavedPos() {
    global countdownGui, CountdownX, CountdownY

    if (CountdownX != "" && CountdownY != "") {
        countdownGui.Show("x" CountdownX " y" CountdownY " NoActivate")
    } else {
        x := A_ScreenWidth - 250
        y := A_ScreenHeight - 160
        countdownGui.Show("x" x " y" y " NoActivate")
    }
}

WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    global countdownGui
    if !countdownGui
        return

    if (hwnd != countdownGui.Hwnd)
        return

    ; 让整个窗口像标题栏一样可拖动
    PostMessage(0xA1, 2, 0, , "ahk_id " hwnd) ; WM_NCLBUTTONDOWN, HTCAPTION=2
}

WM_EXITSIZEMOVE(wParam, lParam, msg, hwnd) {
    global countdownGui, iniPath
    global CountdownX, CountdownY

    if !countdownGui
        return
    if (hwnd != countdownGui.Hwnd)
        return

    try {
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        CountdownX := x, CountdownY := y
        IniWrite(x, iniPath, "UI", "CountdownX")
        IniWrite(y, iniPath, "UI", "CountdownY")
    }
}

ShowCountdown(remainSec, targetSec) {
    EnsureCountdownGui()

    global countdownGui, line1Ctrl, line2Ctrl

    hhmm := SecToHHMM(targetSec)
    line1Ctrl.Text := "提醒时间：" hhmm

    if (remainSec <= 0) {
        line2Ctrl.Text := "已到点"
    } else {
        m := Floor(remainSec / 60)
        s := Mod(remainSec, 60)
        line2Ctrl.Text := "倒计时" Format("{:02}:{:02}", m, s)
    }

    ; region 可能因字体/布局变动，保险起见偶尔刷新（轻量）
    ApplyRoundedRegion()

    ; 若还没显示则显示（NoActivate）
    try {
        if !WinExist("ahk_id " countdownGui.Hwnd)
            ShowCountdownAtSavedPos()
    }
}

ShowCountdownPaused() {
    EnsureCountdownGui()
    global line1Ctrl, line2Ctrl
    line1Ctrl.Text := "提醒时间：--:--"
    line2Ctrl.Text := "已暂停"
    ApplyRoundedRegion()
}

ShowCountdownNoMore() {
    EnsureCountdownGui()
    global line1Ctrl, line2Ctrl
    line1Ctrl.Text := "提醒时间：--:--"
    line2Ctrl.Text := "今日无后续提醒"
    ApplyRoundedRegion()
}

HideCountdown() {
    global countdownGui
    if countdownGui {
        try countdownGui.Destroy()
        countdownGui := 0
    }
}