#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

Handle g_hBombTimer = INVALID_HANDLE;
float g_fBombPlantTime;
bool g_bBombPlanted = false;

public Plugin myinfo = 
{
    name = "Simple Bomb Timer Display",
    author = "Grok",
    description = "Displays bomb countdown with simple color changes",
    version = "2.1",
    url = "https://xai.com"
};

public void OnPluginStart()
{
    HookEvent("bomb_planted", Event_BombPlanted);
    HookEvent("bomb_defused", Event_BombEnd);
    HookEvent("bomb_exploded", Event_BombEnd);
    HookEvent("round_start", Event_RoundStart);
}

public void Event_BombPlanted(Event event, const char[] name, bool dontBroadcast)
{
    if (g_hBombTimer != INVALID_HANDLE)
    {
        KillTimer(g_hBombTimer);
        g_hBombTimer = INVALID_HANDLE;
    }
    
    g_fBombPlantTime = GetGameTime();
    g_bBombPlanted = true;
    
    g_hBombTimer = CreateTimer(0.1, Timer_BombCountdown, _, TIMER_REPEAT);
}

public void Event_BombEnd(Event event, const char[] name, bool dontBroadcast)
{
    StopBombTimer();
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    StopBombTimer();
}

public Action Timer_BombCountdown(Handle timer)
{
    if (!g_bBombPlanted)
    {
        return Plugin_Stop;
    }
    
    float currentTime = GetGameTime();
    float timeElapsed = currentTime - g_fBombPlantTime;
    float bombTime = GetConVarFloat(FindConVar("mp_c4timer"));
    float timeLeft = bombTime - timeElapsed;
    
    if (timeLeft <= 0.0)
    {
        StopBombTimer();
        return Plugin_Stop;
    }
    
    char timeDisplay[64];
    char color[16];
    GetTimerColor(timeLeft, color, sizeof(color));
    Format(timeDisplay, sizeof(timeDisplay), "<font color='%s'>炸弹倒计时: %.1f秒</font>", color, timeLeft);
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            PrintCenterText(i, timeDisplay);
        }
    }
    
    return Plugin_Continue;
}

void StopBombTimer()
{
    if (g_hBombTimer != INVALID_HANDLE)
    {
        KillTimer(g_hBombTimer);
        g_hBombTimer = INVALID_HANDLE;
    }
    g_bBombPlanted = false;
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            PrintCenterText(i, "");
        }
    }
}

public void OnMapEnd()
{
    StopBombTimer();
}

void GetTimerColor(float timeLeft, char[] color, int maxlen)
{
    if (timeLeft < 5.0)
    {
        strcopy(color, maxlen, "#FF0000"); // 红色
    }
    else if (timeLeft < 10.0)
    {
        strcopy(color, maxlen, "#FFA500"); // 橙色
    }
    else
    {
        strcopy(color, maxlen, "#FFFFFF"); // 白色
    }
}