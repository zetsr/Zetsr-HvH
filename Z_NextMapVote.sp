#include <sourcemod>
#include <sdktools>
#include <colors>

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
bool g_bVoteEnded = false; // 投票是否已经结束
int g_iEligibleVoters = 0; // 记录有资格投票的玩家数量
int g_iVotesCast = 0; // 记录已投票的玩家数量
bool g_bVoteInProgress = false; // 投票是否正在进行
int g_iRTVUses[MAXPLAYERS + 1]; // 记录每个玩家的RTV发起次数
int g_iVoteTimeLeft = 0; // 投票剩余时间（替换static）

public Plugin myinfo = 
{
    name = "半场换地图投票",
    author = "zetsr + ChatGPT改进",
    description = "半场换边后投票决定下一局地图",
    version = "2.2",
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
    AddCommandListener(Command_Say, "say");
    AddCommandListener(Command_Say, "say_team");
    RegConsoleCmd("rtv", Command_RTV, "Initiate RTV vote");
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
    // 重置每个玩家的RTV发起次数
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i))
        {
            g_iRTVUses[i] = 0;
        }
    }
    g_iVoteTimeLeft = 0; // 确保重置
}

bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
}

public Action Command_RTV(int client, int args)
{
    if (client == 0)
    {
        // 控制台直接发起
        if (!g_bVoteInProgress)
        {
            StartMapVote();
            CPrintToChatAll("{orange}[地图投票] {red}控制台 {default}发起了地图投票！");
        }
        else
        {
            ReplyToCommand(client, "{orange}[地图投票] {default}投票正在进行中，无法再次发起。");
        }
        return Plugin_Handled;
    }
    else
    {
        return AttemptStartRTV(client);
    }
}

public Action Command_Say(int client, const char[] command, int args)
{
    if (client == 0 || !IsValidClient(client) || IsFakeClient(client))
    {
        return Plugin_Continue;
    }

    char text[192];
    GetCmdArgString(text, sizeof(text));
    StripQuotes(text);
    TrimString(text);

    if (StrEqual(text, "!rtv", false) || StrEqual(text, "rtv", false))
    {
        return AttemptStartRTV(client);
    }
    return Plugin_Continue;
}

public Action AttemptStartRTV(int client)
{
    AdminId admin = GetUserAdmin(client);
    bool isAdmin = (admin != INVALID_ADMIN_ID && GetAdminFlag(admin, Admin_Generic));

    if (g_bVoteInProgress)
    {
        CPrintToChat(client, "{orange}[地图投票] {default}投票正在进行中，无法再次发起。");
        return Plugin_Handled;
    }

    if (isAdmin)
    {
        // 管理员无限发起
        StartMapVote();
        CPrintToChatAll("{orange}[地图投票] {red}%N {default}发起了地图投票！", client);
    }
    else
    {
        // 非管理员检查发起次数
        if (g_iRTVUses[client] >= 1)
        {
            CPrintToChat(client, "{orange}[地图投票] {default}您在本场比赛中已经发起过一次RTV，无法再次发起。");
        }
        else
        {
            g_iRTVUses[client]++;
            StartMapVote();
            CPrintToChatAll("{orange}[地图投票] {red}%N {default}发起了地图投票！", client);
        }
    }
    return Plugin_Handled;
}

void StartMapVote()
{
    if (g_iMapCount == 0)
    {
        CPrintToChatAll("{orange}[地图投票] {default}没有可供投票的地图！");
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
    g_iEligibleVoters = 0;
    g_iVotesCast = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i) && !IsFakeClient(i))
        {
            players[g_iEligibleVoters++] = i;
            g_iVotes[i] = -1; // 初始化玩家投票记录
        }
    }
    g_hVoteMenu.DisplayVote(players, g_iEligibleVoters, 20.0);

    if (g_hCountdownTimer != null && IsValidHandle(g_hCountdownTimer))
    {
        KillTimer(g_hCountdownTimer);
    }
    g_hCountdownTimer = null;
    g_bVoteEnded = false; // 重置投票结束标志
    g_bVoteInProgress = true; // 设置投票进行中
    g_iVoteTimeLeft = 20; // 重置倒计时
    g_hCountdownTimer = CreateTimer(1.0, Timer_Countdown, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    int maxRounds = g_hMaxRounds.IntValue;
    int halfTimeRound = maxRounds / 2;
    int roundsPlayed = GetTeamScore(2) + GetTeamScore(3);

    if (roundsPlayed == halfTimeRound && !g_bVoteInProgress)
    {
        StartMapVote();
        CPrintToChatAll("{orange}[地图投票] {default}半场换边！请投票选择下一张地图（剩余20秒）。");
    }
    return Plugin_Continue;
}

public Action Timer_Countdown(Handle timer)
{
    g_iVoteTimeLeft--;

    if (g_iVoteTimeLeft > 0)
    {
        PrintCenterTextAll("地图投票剩余时间: %d秒", g_iVoteTimeLeft);
        return Plugin_Continue;
    }

    PrintCenterTextAll("投票结束，统计结果中...");
    g_hCountdownTimer = null;
    g_iVoteTimeLeft = 20; // 重置为下次使用
    g_bVoteEnded = true; // 设置投票结束标志
    EndVote();
    return Plugin_Stop;
}

public int Menu_VoteHandler(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        if (g_bVoteEnded)
        {
            // 投票已经结束，忽略此投票
            return 0;
        }
        int client = param1;
        char mapName[PLATFORM_MAX_PATH];
        menu.GetItem(param2, mapName, sizeof(mapName));

        for (int i = 0; i < g_iMapCount; i++)
        {
            if (StrEqual(g_sMapNames[i], mapName))
            {
                g_iMapVotes[i]++;
                g_iVotes[client] = i;
                g_iVotesCast++;
                break;
            }
        }

        char clientName[MAX_NAME_LENGTH];
        GetClientName(client, clientName, sizeof(clientName));
        CPrintToChatAll("{orange}[地图投票] {red}%s {default}投票给了 {red}%s", clientName, mapName);

        // 检查是否所有玩家都已投票
        if (g_iVotesCast >= g_iEligibleVoters)
        {
            g_bVoteEnded = true;
            PrintCenterTextAll("所有玩家已投票，统计结果中...");
            if (g_hCountdownTimer != null && IsValidHandle(g_hCountdownTimer))
            {
                KillTimer(g_hCountdownTimer);
                g_hCountdownTimer = null;
            }
            g_iVoteTimeLeft = 20; // 重置时间
            EndVote();
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    return 0;
}

void EndVote()
{
    // 取消所有玩家的投票菜单
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i) && !IsFakeClient(i))
        {
            CancelClientMenu(i);
        }
    }

    int totalVotes = 0;
    for (int i = 0; i < g_iMapCount; i++)
    {
        totalVotes += g_iMapVotes[i];
    }

    if (totalVotes == 0)
    {
        CPrintToChatAll("{orange}[地图投票] {default}没有收到有效投票，继续当前默认流程！");
        g_bVoteInProgress = false; // 重置投票进行中标志
        return;
    }

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

    int selected = winnerIndices[GetRandomInt(0, winnerCount - 1)];
    char nextMap[PLATFORM_MAX_PATH];
    strcopy(nextMap, sizeof(nextMap), g_sMapNames[selected]);
    
    g_hNextLevel.SetString(nextMap);

    CPrintToChatAll("{orange}[地图投票] {default}投票结果：下一局地图为 {red}%s{default}！", nextMap);

    // 显示每张地图的得票数和百分比
    for (int i = 0; i < g_iMapCount; i++)
    {
        if (g_iMapVotes[i] > 0)
        {
            float percentage = (float(g_iMapVotes[i]) / float(totalVotes)) * 100.0;
            CPrintToChatAll("{orange}[地图投票] {red}%s: {red}%d {default}票 {red}(%.2f%%)", g_sMapNames[i], g_iMapVotes[i], percentage);
        }
    }

    g_bVoteInProgress = false; // 重置投票进行中标志
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