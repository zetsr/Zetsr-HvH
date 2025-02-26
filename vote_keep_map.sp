#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

bool g_bVotePassed = false;
bool g_bHasVoted[MAXPLAYERS + 1] = {false, ...};
int g_iYesVotes = 0;
int g_iNoVotes = 0;
char g_sCurrentMap[PLATFORM_MAX_PATH];
ConVar g_hMaxRounds;
ConVar g_hNextLevel;
Handle g_hCountdownTimer = null;

public Plugin myinfo = 
{
    name = "半场续玩投票",
    author = "zetsr",
    description = "半场后投票决定是否再玩一次当前地图",
    version = "1.8",
    url = "https://github.com/zetsr"
};

public void OnPluginStart()
{
    HookEvent("round_start", Event_RoundStart);
    RegConsoleCmd("sm_mapvote", Command_ShowVoteResult, "显示当前投票结果");
    g_hMaxRounds = FindConVar("mp_maxrounds");
    g_hNextLevel = FindConVar("nextlevel");
    if (g_hNextLevel == null)
    {
        SetFailState("无法找到 'nextlevel' ConVar，插件无法工作。");
    }
}

public void OnMapStart()
{
    GetCurrentMap(g_sCurrentMap, sizeof(g_sCurrentMap));
    g_bVotePassed = false;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    int maxRounds = g_hMaxRounds.IntValue;
    int halfTimeRound = maxRounds / 2;
    int roundsPlayed = GetTeamScore(2) + GetTeamScore(3);

    if (roundsPlayed == halfTimeRound)
    {
        ResetVote();
        CreateTimer(5.0, Timer_ShowVoteMenu, _, TIMER_FLAG_NO_MAPCHANGE);
    }
    return Plugin_Continue;
}

public Action Timer_ShowVoteMenu(Handle timer)
{
    if (IsVoteInProgress())
    {
        return Plugin_Continue;
    }

    Menu menu = new Menu(Menu_VoteHandler);
    menu.SetTitle("下一局是否再玩一次当前地图？");
    menu.AddItem("yes", "是");
    menu.AddItem("no", "否");
    menu.ExitButton = false;
    
    int players[MAXPLAYERS + 1];
    int playerCount = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            players[playerCount++] = i;
        }
    }
    menu.DisplayVote(players, playerCount, 20);
    
    if (g_hCountdownTimer != null)
    {
        KillTimer(g_hCountdownTimer);
        g_hCountdownTimer = null;
    }
    g_hCountdownTimer = CreateTimer(1.0, Timer_Countdown, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    
    return Plugin_Continue;
}

public Action Timer_Countdown(Handle timer)
{
    static int timeLeft = 20;
    timeLeft--;
    
    if (timeLeft > 0)
    {
        PrintCenterTextAll("地图续玩投票剩余时间: %d秒", timeLeft);
        return Plugin_Continue;
    }
    
    PrintCenterTextAll("投票已结束，正在统计结果...");
    timeLeft = 20;
    g_hCountdownTimer = null;
    CheckVoteResult();
    return Plugin_Stop;
}

public int Menu_VoteHandler(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_VoteEnd)
    {
        int votes, totalVotes;
        GetMenuVoteInfo(param2, votes, totalVotes);
        
        if (param1 == 0) // Yes选项
        {
            g_iYesVotes = votes;
            g_iNoVotes = totalVotes - votes;
        }
        else // No选项
        {
            g_iNoVotes = votes;
            g_iYesVotes = totalVotes - votes;
        }
    }
    else if (action == MenuAction_Select)
    {
        int client = param1;
        char choice[32];
        menu.GetItem(param2, choice, sizeof(choice));
        
        char clientName[MAX_NAME_LENGTH];
        GetClientName(client, clientName, sizeof(clientName));
        
        if (StrEqual(choice, "yes"))
        {
            PrintToChatAll("\x04[地图续玩投票] %s 投票: 同意", clientName);
            g_iYesVotes++;
        }
        else if (StrEqual(choice, "no"))
        {
            PrintToChatAll("\x04[地图续玩投票] %s 投票: 反对", clientName);
            g_iNoVotes++;
            if (g_hCountdownTimer != null)
            {
                KillTimer(g_hCountdownTimer);
                g_hCountdownTimer = null;
            }
            PrintCenterTextAll("投票已结束，正在统计结果...");
            PrintToChatAll("\x04[地图续玩投票] 投票未通过，将按正常流程切换地图。(赞成: %d, 反对: %d)", g_iYesVotes, g_iNoVotes);
            return 0;
        }
        g_bHasVoted[client] = true;
    }
    return 0;
}

void ResetVote()
{
    g_iYesVotes = 0;
    g_iNoVotes = 0;
    g_bVotePassed = false;
    for (int i = 1; i <= MaxClients; i++)
    {
        g_bHasVoted[i] = false;
    }
}

void CheckVoteResult()
{
    int players = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            players++;
        }
    }
    
    if (players == 0)
    {
        PrintToChatAll("\x04[地图续玩投票] 无有效玩家，投票无效。");
        return;
    }
    
    // 输出未投票的玩家
    bool hasUnvoted = false;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && !g_bHasVoted[i])
        {
            if (!hasUnvoted)
            {
                PrintToChatAll("\x04[地图续玩投票] 未投票的玩家：");
                hasUnvoted = true;
            }
            char clientName[MAX_NAME_LENGTH];
            GetClientName(i, clientName, sizeof(clientName));
            PrintToChatAll("\x04- %s", clientName);
        }
    }
    
    // 判断投票结果，未投票视为弃票
    if (g_iNoVotes >= 1)
    {
        PrintToChatAll("\x04[地图续玩投票] 投票未通过，将按正常流程切换地图。(赞成: %d, 反对: %d)", g_iYesVotes, g_iNoVotes);
    }
    else if (g_iYesVotes >= 1)
    {
        g_bVotePassed = true;
        PrintToChatAll("\x04[地图续玩投票] 投票通过！下一局将继续玩当前地图！(赞成: %d/%d)", g_iYesVotes, players);
        SetNextLevel();
    }
    else // 无人投票的情况
    {
        PrintToChatAll("\x04[地图续玩投票] 所有玩家未投票，投票未通过，将按正常流程切换地图。");
    }
}

void SetNextLevel()
{
    if (g_bVotePassed)
    {
        g_hNextLevel.SetString(g_sCurrentMap);
    }
}

public Action Command_ShowVoteResult(int client, int args)
{
    if (client == 0)
    {
        PrintToServer("赞成票: %d, 反对票: %d", g_iYesVotes, g_iNoVotes);
    }
    else
    {
        PrintToChat(client, "\x04[地图续玩投票] 赞成: %d, 反对: %d", g_iYesVotes, g_iNoVotes);
    }
    return Plugin_Handled;
}