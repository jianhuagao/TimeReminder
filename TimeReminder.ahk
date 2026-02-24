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