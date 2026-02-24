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
}

TargetHour   := IniRead(iniPath, "Time", "TargetHour", 11)
TargetMinute := IniRead(iniPath, "Time", "TargetMinute", 0)

; ========================
; 全局变量声明
; ========================
configGui := ""

; ========================
; 启动时弹窗配置
; ========================

ShowConfigDialog() {
    global TargetHour, TargetMinute, configGui
    
    configGui := Gui()
    configGui.Title := "时间提醒器配置"
    configGui.MarginX := 15
    configGui.MarginY := 15
    
    configGui.AddText("w180", "请输入目标时间：")
    configGui.AddText("", "时Hour:")
    hourEdit := configGui.AddEdit("w50 vHourValue", TargetHour)
    configGui.AddText("", "分Minute:")
    minuteEdit := configGui.AddEdit("w50 vMinuteValue", TargetMinute)
    
    configGui.AddButton("w80 h30 Default", "ok").OnEvent("Click", ConfigOK)
    configGui.AddButton("w80 h30 x+10", "cancel").OnEvent("Click", ConfigCancel)
    
    configGui.Show("w350 h220")
}

ConfigOK(GuiCtrlObj, Info) {
    global configGui, TargetHour, TargetMinute, iniPath
    
    configGui.Submit()
    
    newHour := configGui["HourValue"].Value
    newMinute := configGui["MinuteValue"].Value
    
    ; 验证输入
    if !IsInteger(newHour) || !IsInteger(newMinute) {
        MsgBox("请输入有效的数字！")
        return
    }
    
    newHour := newHour + 0
    newMinute := newMinute + 0
    
    if (newHour < 0 || newHour > 23 || newMinute < 0 || newMinute > 59) {
        MsgBox("时间格式无效！小时应在0-23之间，分钟应在0-59之间。")
        return
    }
    
    ; 更新全局变量
    TargetHour := newHour
    TargetMinute := newMinute
    
    ; 保存到配置文件
    IniWrite(TargetHour, iniPath, "Time", "TargetHour")
    IniWrite(TargetMinute, iniPath, "Time", "TargetMinute")
    
    configGui.Destroy()
}

ConfigCancel(GuiCtrlObj, Info) {
    global configGui
    configGui.Destroy()
}

; 显示配置对话框
ShowConfigDialog()

; ========================
; 多阶段提醒配置（分钟）
; ========================

ReminderStages := [5, 2, 1]   ; 提前 5 / 2 / 1 分钟

; ========================
; 状态
; ========================

triggered := Map()    ; 记录已触发的阶段
countdownGui := 0

SetTimer(CheckTime, 1000)

; ========================
; 主逻辑
; ========================

CheckTime() {
    global TargetHour, TargetMinute, ReminderStages, triggered

    nowSec    := A_Hour * 3600 + A_Min * 60 + A_Sec
    targetSec := TargetHour * 3600 + TargetMinute * 60

    remainSec := targetSec - nowSec

    ; 跨天保护
    if (remainSec < -5) {
        triggered.Clear()
        HideCountdown()
        return
    }

    ; 多阶段提醒
    for _, m in ReminderStages {
        if (remainSec <= m * 60 && remainSec > (m * 60 - 1)) {
            if !triggered.Has(m) {
                triggered[m] := true
                ShowStageNotification(m)
            }
        }
    }

    ; 2 分钟内显示倒计时窗
    if (remainSec <= 120 && remainSec > 0) {
        ShowCountdown(remainSec)
    } else {
        HideCountdown()
    }
}

; ========================
; 通知
; ========================

ShowStageNotification(min) {
    global TargetHour, TargetMinute
    TrayTip(
        "还有 " min " 分钟到 " TargetHour ":" Format("{:02}", TargetMinute),
        "⏰ 时间提醒"
    )
}

; ========================
; 倒计时悬浮窗
; ========================

ShowCountdown(remainSec) {
    global countdownGui

    min := Floor(remainSec / 60)
    sec := Mod(remainSec, 60)
    text := Format("{:02}:{:02}", min, sec)

    if !countdownGui {
        countdownGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
        countdownGui.BackColor := "202020"
        countdownGui.SetFont("s22 cFFFFFF", "Segoe UI")
        countdownGui.AddText("vTimeText w120 Center", text)

        x := A_ScreenWidth - 140
        y := A_ScreenHeight - 120
        countdownGui.Show("x" x " y" y " NoActivate")
    } else {
        countdownGui["TimeText"].Text := text
    }
}

HideCountdown() {
    global countdownGui
    if countdownGui {
        countdownGui.Destroy()
        countdownGui := 0
    }
}
