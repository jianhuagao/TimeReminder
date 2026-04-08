#Requires AutoHotkey v2.0

; 自动请求管理员权限
if !A_IsAdmin
{
    try Run '*RunAs "' A_ScriptFullPath '"'
    catch
        MsgBox "警告：未获得管理员权限，部分窗口可能无法交换。"
}

^!s::
{
    ; 禁用窗口缩放动画（可选，进一步提升视觉速度）
    ; DllCall("user32\SystemParametersInfo", "UInt", 0x0049, "UInt", 0, "Ptr", 0, "UInt", 0)

    monitorCount := MonitorGetCount()
    if (monitorCount < 2)
        return

    ; 获取两个显示器的完整坐标 (用于判断位置)
    MonitorGet(1, &L1, &T1, &R1, &B1)
    MonitorGet(2, &L2, &T2, &R2, &B2)
    
    ; 获取两个显示器的工作区坐标 (扣除任务栏后的区域)
    MonitorGetWorkArea(1, &WL1, &WT1, &WR1, &WB1)
    MonitorGetWorkArea(2, &WL2, &WT2, &WR2, &WB2)

    ids := WinGetList(,, "Program Manager")

    for this_id in ids
    {
        style := WinGetStyle(this_id)
        if !(style & 0x10000000) ; 仅处理可见窗口
            continue
            
        title := WinGetTitle(this_id)
        if (title = "" || title = "Start" || title = "Taskbar" || title = "Program Manager")
            continue

        try {
            minMaxState := WinGetMinMax(this_id)
            if (minMaxState = -1) ; 跳过最小化
                continue

            WinGetPos(&X, &Y, &W, &H, this_id)
            centerX := X + W/2
            centerY := Y + H/2

            ; 判断并执行移动
            if (centerX >= L1 && centerX <= R1 && centerY >= T1 && centerY <= B1)
            {
                if (minMaxState = 1) {
                    ; 屏幕1最大化窗口 -> 屏幕2工作区 (瞬移，不触发动画)
                    WinMove(WL2, WT2, WR2-WL2, WB2-WT2, this_id)
                } else {
                    ; 普通窗口按比例移动
                    WinMove(X - L1 + L2, Y - T1 + T2,,, this_id)
                }
            }
            else if (centerX >= L2 && centerX <= R2 && centerY >= T2 && centerY <= B2)
            {
                if (minMaxState = 1) {
                    ; 屏幕2最大化窗口 -> 屏幕1工作区 (瞬移，不触发动画)
                    WinMove(WL1, WT1, WR1-WL1, WB1-WT1, this_id)
                } else {
                    ; 普通窗口按比例移动
                    WinMove(X - L2 + L1, Y - T2 + T1,,, this_id)
                }
            }
        }
    }
}
