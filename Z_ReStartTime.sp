#include <sourcemod>
#include <sdktools>
#include <colors>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0"

// 插件信息
public Plugin myinfo = 
{
    name = "服务器重启倒计时",
    author = "New Dawn",
    description = "在指定重启时间前显示倒计时",
    version = PLUGIN_VERSION,
    url = ""
};

// 全局变量
Handle g_hRestartTimer = INVALID_HANDLE;
Handle g_hCountdownTimer = INVALID_HANDLE;
int g_iRestartHour = -1;
int g_iRestartMinute = -1;
int g_iCountdownSeconds = 60;
bool g_bCountdownStarted = false;

public void OnPluginStart()
{
    // 创建定时器，每秒检查一次时间
    CreateTimer(1.0, Timer_CheckRestartTime, _, TIMER_REPEAT);
    
    // 加载配置
    LoadRestartConfig();
}

public void OnMapStart()
{
    // 地图开始时重新加载配置
    LoadRestartConfig();
}

void LoadRestartConfig()
{
    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, sizeof(sPath), "configs/restart_time.ini");
    
    // 检查配置文件是否存在
    if (!FileExists(sPath))
    {
        LogError("配置文件未找到: %s", sPath);
        return;
    }
    
    File file = OpenFile(sPath, "r");
    if (file == null)
    {
        LogError("无法打开配置文件: %s", sPath);
        return;
    }
    
    char sLine[32];
    if (!file.ReadLine(sLine, sizeof(sLine)))
    {
        LogError("配置文件为空或读取失败");
        delete file;
        return;
    }
    
    delete file;
    
    // 清理字符串中的换行符和空格
    TrimString(sLine);
    
    // 验证格式
    if (strlen(sLine) != 4)
    {
        LogError("重启时间格式错误，应为4位数字: %s", sLine);
        return;
    }
    
    char sHour[3], sMinute[3];
    strcopy(sHour, 3, sLine);
    strcopy(sMinute, 3, sLine[2]);
    
    g_iRestartHour = StringToInt(sHour);
    g_iRestartMinute = StringToInt(sMinute);
    
    // 验证时间有效性
    if (g_iRestartHour < 0 || g_iRestartHour > 23 || g_iRestartMinute < 0 || g_iRestartMinute > 59)
    {
        LogError("重启时间无效: %02d%02d", g_iRestartHour, g_iRestartMinute);
        g_iRestartHour = -1;
        g_iRestartMinute = -1;
        return;
    }
    
    PrintToServer("[New Dawn] 已设置重启时间: %02d:%02d", g_iRestartHour, g_iRestartMinute);
}

public Action Timer_CheckRestartTime(Handle timer)
{
    // 如果配置未加载成功，不执行检查
    if (g_iRestartHour == -1 || g_iRestartMinute == -1)
        return Plugin_Continue;
    
    // 如果倒计时已经开始，不再重复触发
    if (g_bCountdownStarted)
        return Plugin_Continue;
    
    // 获取当前时间
    int iHour, iMinute, iSecond;
    GetSystemTime(iHour, iMinute, iSecond);
    
    // 计算重启时间的前一分钟
    int iTargetHour = g_iRestartHour;
    int iTargetMinute = g_iRestartMinute - 1;
    
    // 处理分钟进位
    if (iTargetMinute < 0)
    {
        iTargetMinute = 59;
        iTargetHour--;
        if (iTargetHour < 0)
            iTargetHour = 23;
    }
    
    // 检查是否到达重启前一分钟的00秒
    if (iHour == iTargetHour && iMinute == iTargetMinute && iSecond == 0)
    {
        StartCountdown();
    }
    
    return Plugin_Continue;
}

void StartCountdown()
{
    g_bCountdownStarted = true;
    g_iCountdownSeconds = 60;
    
    PrintToServer("[New Dawn] 开始重启倒计时");
    
    // 启动每秒更新的倒计时定时器
    g_hCountdownTimer = CreateTimer(5.0, Timer_UpdateCountdown, _, TIMER_REPEAT);
    
    // 立即显示第一次提示
    UpdateCountdownDisplay();
}

public Action Timer_UpdateCountdown(Handle timer)
{
    g_iCountdownSeconds = g_iCountdownSeconds -5;
    
    if (g_iCountdownSeconds <= 0)
    {
        // 倒计时结束，停止定时器
        g_hCountdownTimer = INVALID_HANDLE;
        g_bCountdownStarted = false;
        
        PrintToServer("[New Dawn] 重启倒计时结束");
        return Plugin_Stop;
    }
    
    UpdateCountdownDisplay();
    return Plugin_Continue;
}

void UpdateCountdownDisplay()
{
    // 更新MVP面板显示
    UpdateMVPPanel();
    
    // 更新聊天框显示
    UpdateChatMessage();
}

void UpdateMVPPanel()
{
    char sMessage[128];
    
    if (g_iCountdownSeconds > 5)
    {
        Format(sMessage, sizeof(sMessage), "服务器重启倒计时: %d秒", g_iCountdownSeconds);
    }
    else
    {
        Format(sMessage, sizeof(sMessage), "服务器即将重启!\n稍等片刻即可重新连接!");
    }
    
    // 向所有玩家显示MVP面板
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            // 使用HintText模拟MVP面板显示
            PrintHintText(i, sMessage);
        }
    }
}

void UpdateChatMessage()
{
    char sMessage[256];
    
    if (g_iCountdownSeconds > 5)
    {
        Format(sMessage, sizeof(sMessage), "新曙光 - 服务器还有%d秒就要重启！重启预计耗时一分钟！", g_iCountdownSeconds);
        CPrintToChatAll("{grey}新曙光 - {default}服务器还有{red}%d{default}秒就要重启！重启预计耗时一分钟！", g_iCountdownSeconds);
    }
    else
    {
        CPrintToChatAll("{grey}新曙光 - {default}服务器即将重启！稍等片刻即可重新连接！");
    }
}

void GetSystemTime(int &hour, int &minute, int &second)
{
    // 获取系统时间
    char sTime[32];
    FormatTime(sTime, sizeof(sTime), "%H %M %S");
    
    char sBuffer[3][8];
    ExplodeString(sTime, " ", sBuffer, 3, 8);
    
    hour = StringToInt(sBuffer[0]);
    minute = StringToInt(sBuffer[1]);
    second = StringToInt(sBuffer[2]);
}

public void OnPluginEnd()
{
    // 清理定时器
    if (g_hRestartTimer != INVALID_HANDLE)
    {
        KillTimer(g_hRestartTimer);
        g_hRestartTimer = INVALID_HANDLE;
    }
    
    if (g_hCountdownTimer != INVALID_HANDLE)
    {
        KillTimer(g_hCountdownTimer);
        g_hCountdownTimer = INVALID_HANDLE;
    }
}