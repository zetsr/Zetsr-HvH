#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

char g_sCurrentMap[PLATFORM_MAX_PATH];
ConVar g_hMaxRounds;
ConVar g_hNextLevel;
Handle g_hCountdownTimer = null;
Menu g_hVoteMenu = null;
ArrayList g_aMapList;

int g_iVotes[MAXPLAYERS + 1]; // 记录每个玩家投了哪张地图
int g_iMapVotes[128]; // 记录每张地图被投了多少票
int g_iMapCount = 0;
char g_sMapNames[128][PLATFORM_MAX_PATH];

public Plugin myinfo = 
{
    name = "半场换地图投票",
    author = "zetsr + ChatGPT改进",
    description = "半场换边后投票决定下一局地图",
    version = "2.0",
    url = "https://github.com/zetsr"
};

public void OnPluginStart()
{
    HookEvent("round_start", Event_RoundStart);
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
    if (g_aMapList != null)
    {
        g_aMapList.Clear();
    }
    else
    {
        g_aMapList = new ArrayList(PLATFORM_MAX_PATH);
    }
    LoadMapList();
}

void LoadMapList()
{
    File file = OpenFile("maplist.txt", "r");
    if (file == null)
    {
        LogError("无法打开 maplist.txt");
        return;
    }

    g_iMapCount = 0;
    while (!file.EndOfFile() && g_iMapCount < sizeof(g_sMapNames))
    {
        char line[PLATFORM_MAX_PATH];
        file.ReadLine(line, sizeof(line));
        TrimString(line);
        if (line[0] != '\0' && !StrEqual(line, g_sCurrentMap, false)) // 不包括当前地图
        {
            strcopy(g_sMapNames[g_iMapCount], sizeof(g_sMapNames[]), line);
            g_aMapList.PushString(line);
            g_iMapCount++;
        }
    }
    file.Close();
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    int maxRounds = g_hMaxRounds.IntValue;
    int halfTimeRound = maxRounds / 2;
    int roundsPlayed = GetTeamScore(2) + GetTeamScore(3);

    if (roundsPlayed == halfTimeRound)
    {
        StartMapVote();
    }
    return Plugin_Continue;
}

void StartMapVote()
{
    if (g_iMapCount == 0)
    {
        PrintToChatAll("\x04[地图投票] 没有可供投票的地图！");
        return;
    }

    if (g_hVoteMenu != null && IsValidHandle(g_hVoteMenu))
    {
        delete g_hVoteMenu;
    }
    g_hVoteMenu = null;

    g_hVoteMenu = new Menu(Menu_VoteHandler);
    g_hVoteMenu.SetTitle("请选择下一张地图");

    for (int i = 0; i < g_iMapCount; i++)
    {
        g_hVoteMenu.AddItem(g_sMapNames[i], g_sMapNames[i]);
        g_iMapVotes[i] = 0;
    }

    g_hVoteMenu.ExitButton = false;

    int players[MAXPLAYERS + 1];
    int playerCount = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            players[playerCount++] = i;
        }
    }
    g_hVoteMenu.DisplayVote(players, playerCount, 20.0);

    if (g_hCountdownTimer != null && IsValidHandle(g_hCountdownTimer))
    {
        KillTimer(g_hCountdownTimer);
    }
    g_hCountdownTimer = null;
    g_hCountdownTimer = CreateTimer(1.0, Timer_Countdown, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_Countdown(Handle timer)
{
    static int timeLeft = 20;
    timeLeft--;

    if (timeLeft > 0)
    {
        PrintCenterTextAll("地图投票剩余时间: %d秒", timeLeft);
        return Plugin_Continue;
    }

    PrintCenterTextAll("投票结束，统计结果中...");
    g_hCountdownTimer = null;
    timeLeft = 20;
    EndVote();
    return Plugin_Stop;
}

public int Menu_VoteHandler(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        int client = param1;
        char mapName[PLATFORM_MAX_PATH];
        menu.GetItem(param2, mapName, sizeof(mapName));

        for (int i = 0; i < g_iMapCount; i++)
        {
            if (StrEqual(g_sMapNames[i], mapName))
            {
                g_iMapVotes[i]++;
                g_iVotes[client] = i;
                break;
            }
        }

        char clientName[MAX_NAME_LENGTH];
        GetClientName(client, clientName, sizeof(clientName));
        PrintToChatAll("\x04[地图投票] %s 投票给了 %s", clientName, mapName);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    return 0;
}

void EndVote()
{
    int highestVotes = -1;
    int winnerIndices[128];
    int winnerCount = 0;

    for (int i = 0; i < g_iMapCount; i++)
    {
        if (g_iMapVotes[i] > highestVotes)
        {
            highestVotes = g_iMapVotes[i];
            winnerIndices[0] = i;
            winnerCount = 1;
        }
        else if (g_iMapVotes[i] == highestVotes)
        {
            winnerIndices[winnerCount++] = i;
        }
    }

    if (winnerCount == 0)
    {
        PrintToChatAll("\x04[地图投票] 没有收到有效投票，继续当前默认流程！");
        return;
    }

    int selected = winnerIndices[GetRandomInt(0, winnerCount - 1)];
    char nextMap[PLATFORM_MAX_PATH];
    strcopy(nextMap, sizeof(nextMap), g_sMapNames[selected]);
    
    g_hNextLevel.SetString(nextMap);

    PrintToChatAll("\x04[地图投票] 投票结果：下一局地图为 \x03%s\x04！", nextMap);
}
