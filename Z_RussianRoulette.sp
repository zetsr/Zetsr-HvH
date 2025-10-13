#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <colors>

#define PLUGIN_VERSION "1.0"

// 游戏状态枚举
enum GameState {
    STATE_NONE = 0,
    STATE_VOTING,
    STATE_WAITING_NUMBERS,
    STATE_ROULETTE
}

// 使用新的枚举结构语法
enum struct PlayerData {
    bool isEligible;
    bool voted;
    bool accepted;
    bool sentNumber;
    int number;
    int rouletteTurn;
}

// 全局变量
GameState g_GameState;
Handle g_VoteTimer;
Handle g_NumberTimer;
Handle g_RouletteTimer;
int g_RoundCount;
int g_Players[2]; // 存储两个参与玩家的userid
PlayerData g_PlayerData[MAXPLAYERS + 1];
int g_CurrentTurn; // 当前开枪的玩家索引 (0或1)
int g_Chamber; // 当前枪膛位置 (1-6)
bool g_RoundRejected; // 标记本回合是否已拒绝

public Plugin myinfo = {
    name = "Russian Roulette",
    author = "Your Name",
    description = "Russian Roulette minigame when 1v1",
    version = PLUGIN_VERSION,
    url = "http://yourwebsite.com"
};

public void OnPluginStart() {
    HookEvent("round_start", Event_RoundStart);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
    
    RegConsoleCmd("say", Command_Say);
    RegConsoleCmd("say_team", Command_SayTeam);
    
    g_GameState = STATE_NONE;
}

public void OnMapStart() {
    g_GameState = STATE_NONE;
    g_RoundCount = 0;
    g_RoundRejected = false;
}

public void OnClientDisconnect(int client) {
    ResetPlayerData(client);
    
    // 如果断线的玩家正在参与游戏，取消游戏
    if (g_GameState != STATE_NONE && IsValidClient(client)) {
        CancelGame("一名玩家离开了游戏");
    }
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
    g_GameState = STATE_NONE;
    g_RoundCount++;
    g_RoundRejected = false;
    
    // 清理计时器
    ClearTimers();
    
    // 重置所有玩家数据
    for (int i = 1; i <= MaxClients; i++) {
        ResetPlayerData(i);
    }
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
    CancelGame("回合结束");
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    int victim = GetClientOfUserId(event.GetInt("userid"));
    
    if (g_GameState != STATE_NONE && IsValidClient(victim)) {
        // 检查死亡的玩家是否在游戏中
        for (int i = 0; i < 2; i++) {
            if (GetClientOfUserId(g_Players[i]) == victim) {
                CancelGame("一名玩家死亡");
                return;
            }
        }
    }
    
    // 检查是否满足1v1条件
    CheckFor1v1();
}

public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    if (g_GameState != STATE_NONE && IsValidClient(client)) {
        for (int i = 0; i < 2; i++) {
            if (GetClientOfUserId(g_Players[i]) == client) {
                // 延迟取消，确保玩家已经完全断开
                CreateTimer(0.1, Timer_CheckDisconnect, _, TIMER_FLAG_NO_MAPCHANGE);
                return;
            }
        }
    }
}

public Action Timer_CheckDisconnect(Handle timer) {
    CancelGame("一名玩家离开了游戏");
    return Plugin_Stop;
}

public void OnGameFrame() {
    if (g_GameState == STATE_NONE && !g_RoundRejected) {
        CheckFor1v1();
    }
}

void CheckFor1v1() {
    // 如果已经在游戏中，不检查
    if (g_GameState != STATE_NONE || g_RoundRejected) {
        return;
    }
    
    // 检查是否满足1v1条件
    int terrorists[MAXPLAYERS], ct[MAXPLAYERS];
    int tCount = 0, ctCount = 0;
    
    for (int i = 1; i <= MaxClients; i++) {
        // 忽略BOT和非游戏玩家
        if (IsValidClient(i) && IsPlayerAlive(i) && GetClientTeam(i) > 1 && !IsFakeClient(i)) {
            if (GetClientTeam(i) == 2) { // Terrorist
                terrorists[tCount++] = i;
            } else if (GetClientTeam(i) == 3) { // CT
                ct[ctCount++] = i;
            }
        }
    }
    
    // 每个阵营只剩1人
    if (tCount == 1 && ctCount == 1) {
        StartVote(terrorists[0], ct[0]);
    }
}

void StartVote(int terrorist, int ct) {
    if (g_GameState != STATE_NONE || g_RoundRejected) {
        return;
    }
    
    g_GameState = STATE_VOTING;
    g_Players[0] = GetClientUserId(terrorist);
    g_Players[1] = GetClientUserId(ct);
    
    // 设置玩家数据
    for (int i = 0; i < 2; i++) {
        int client = GetClientOfUserId(g_Players[i]);
        if (client > 0) {
            g_PlayerData[client].isEligible = true;
            g_PlayerData[client].voted = false;
            g_PlayerData[client].accepted = false;
        }
    }
    
    // 显示投票菜单
    ShowVoteMenu(terrorist);
    ShowVoteMenu(ct);
    
    // 设置投票超时（15秒）
    g_VoteTimer = CreateTimer(15.0, Timer_VoteTimeout, _, TIMER_FLAG_NO_MAPCHANGE);
}

void ShowVoteMenu(int client) {
    Menu menu = new Menu(VoteMenuHandler);
    menu.SetTitle("是否开始俄罗斯转盘游戏？");
    menu.AddItem("accept", "同意");
    menu.AddItem("deny", "拒绝");
    menu.ExitButton = false;
    menu.Display(client, 15);
}

public int VoteMenuHandler(Menu menu, MenuAction action, int client, int param2) {
    if (action == MenuAction_Select && g_GameState == STATE_VOTING) {
        if (!g_PlayerData[client].isEligible || g_PlayerData[client].voted) {
            return 0;
        }
        
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        g_PlayerData[client].voted = true;
        
        if (StrEqual(info, "accept")) {
            g_PlayerData[client].accepted = true;
            CPrintToChat(client, "{grey}新曙光 - {default}已同意，等待对方确认。");
            
            // 检查是否双方都同意
            CheckVoteResult();
        } else {
            g_PlayerData[client].accepted = false;
            CPrintToChat(client, "{grey}新曙光 - {default}已拒绝，对局正常继续！");
            // 设置本回合已拒绝，不再询问
            g_RoundRejected = true;
            CancelGame("一名玩家拒绝了游戏");
        }
    } else if (action == MenuAction_End) {
        delete menu;
    }
    
    return 0;
}

void CheckVoteResult() {
    if (g_GameState != STATE_VOTING) {
        return;
    }
    
    int accepted = 0;
    int totalVoted = 0;
    
    for (int i = 0; i < 2; i++) {
        int client = GetClientOfUserId(g_Players[i]);
        if (client > 0) {
            if (g_PlayerData[client].voted) {
                totalVoted++;
                if (g_PlayerData[client].accepted) {
                    accepted++;
                }
            }
        }
    }
    
    // 双方都同意
    if (totalVoted == 2 && accepted == 2) {
        StartNumberSelection();
    } else if (totalVoted == 2 && accepted < 2) {
        g_RoundRejected = true; // 设置本回合已拒绝
        CancelGame("投票未通过");
    }
}

public Action Timer_VoteTimeout(Handle timer) {
    if (g_GameState == STATE_VOTING) {
        g_RoundRejected = true; // 设置本回合已拒绝
        CancelGame("投票超时");
    }
    g_VoteTimer = null;
    return Plugin_Stop;
}

void StartNumberSelection() {
    g_GameState = STATE_WAITING_NUMBERS;
    
    // 清理投票计时器
    ClearTimer(g_VoteTimer);
    
    // 冻结玩家移动和清空武器
    for (int i = 0; i < 2; i++) {
        int client = GetClientOfUserId(g_Players[i]);
        if (client > 0) {
            FreezePlayer(client);
        }
    }
    
    // 通知玩家输入数字并详细说明规则
    for (int i = 0; i < 2; i++) {
        int client = GetClientOfUserId(g_Players[i]);
        if (client > 0) {
            // 分多条消息发送规则说明，避免消息过长被截断
            CPrintToChat(client, "{grey}新曙光 - {default}双方都同意！请在20秒内在{green}队伍频道{default}输入0-100之间的数字");
            CPrintToChat(client, "{grey}规则说明:");
            CPrintToChat(client, "• {default}在{green}队伍频道{default}输入数字（按U键）");
            CPrintToChat(client, "• {default}数字{green}大{default}的人获胜（如果两人数字和≤100）");
            CPrintToChat(client, "• {default}数字{green}小{default}的人获胜（如果两人数字和>100）");
            CPrintToChat(client, "• {default}数字相同则随机决定获胜者");
            CPrintToChat(client, "• {default}获胜者先开始俄罗斯转盘");
            CPrintToChat(client, "{grey}新曙光 - {default}现在请在{green}队伍频道{default}输入你的数字（0-100）");
            
            g_PlayerData[client].sentNumber = false;
            g_PlayerData[client].number = -1;
        }
    }
    
    // 设置数字选择超时（20秒）
    g_NumberTimer = CreateTimer(20.0, Timer_NumberTimeout, _, TIMER_FLAG_NO_MAPCHANGE);
}

// 冻结玩家移动并清空武器
void FreezePlayer(int client) {
    if (!IsValidClient(client)) return;
    
    // 冻结移动
    SetEntityMoveType(client, MOVETYPE_NONE);
    
    // 禁止受到伤害
    SetEntProp(client, Prop_Data, "m_takedamage", 0, 1);
    
    // 清空所有武器
    RemoveAllWeapons(client);
    
    // 设置玩家速度为零
    SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 0.0);
}

// 移除玩家所有武器
void RemoveAllWeapons(int client) {
    if (!IsValidClient(client)) return;
    
    // 移除所有武器
    int weapon;
    for (int i = 0; i < 5; i++) {
        while ((weapon = GetPlayerWeaponSlot(client, i)) != -1) {
            RemovePlayerItem(client, weapon);
            AcceptEntityInput(weapon, "Kill");
        }
    }
    
    // 确保玩家没有武器
    SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", -1);
}

// 解冻玩家（不恢复武器，因为游戏结束后回合会重置）
void UnfreezePlayer(int client) {
    if (!IsValidClient(client)) return;
    
    // 恢复移动
    SetEntityMoveType(client, MOVETYPE_WALK);
    
    // 恢复受到伤害
    SetEntProp(client, Prop_Data, "m_takedamage", 2, 1);
    
    // 恢复玩家速度
    SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 1.0);
}

public Action Command_Say(int client, int args) {
    if (g_GameState == STATE_WAITING_NUMBERS && IsValidClient(client)) {
        return HandleNumberInput(client, false);
    }
    return Plugin_Continue;
}

public Action Command_SayTeam(int client, int args) {
    if (g_GameState == STATE_WAITING_NUMBERS && IsValidClient(client)) {
        return HandleNumberInput(client, true);
    }
    return Plugin_Continue;
}

Action HandleNumberInput(int client, bool isTeamChat) {
    // 检查是否是参与游戏的玩家
    bool isParticipant = false;
    for (int i = 0; i < 2; i++) {
        if (GetClientOfUserId(g_Players[i]) == client) {
            isParticipant = true;
            break;
        }
    }
    
    if (!isParticipant) {
        return Plugin_Continue;
    }
    
    if (!isTeamChat) {
        // 在公屏发送数字，提示错误
        CPrintToChat(client, "{grey}新曙光 - {red}错误！请在{green}队伍频道{default}输入数字，而不是公屏。");
        CPrintToChat(client, "{grey}提示: {default}按{green}U键{default}在队伍频道输入");
        return Plugin_Handled;
    }
    
    if (g_PlayerData[client].sentNumber) {
        CPrintToChat(client, "{grey}新曙光 - {default}你已经提交过数字了，请等待对方。");
        return Plugin_Handled;
    }
    
    char text[32];
    GetCmdArgString(text, sizeof(text));
    StripQuotes(text);
    TrimString(text);
    
    int number = StringToInt(text);
    if (number < 0 || number > 100) {
        CPrintToChat(client, "{grey}新曙光 - {red}错误！请输入0-100之间的数字。");
        return Plugin_Handled;
    }
    
    g_PlayerData[client].sentNumber = true;
    g_PlayerData[client].number = number;
    
    CPrintToChat(client, "{grey}新曙光 - {default}你选择了数字: {green}%d{default}，等待对方选择...", number);
    
    // 检查是否双方都发送了数字
    CheckNumbersReceived();
    
    return Plugin_Handled;
}

void CheckNumbersReceived() {
    if (g_GameState != STATE_WAITING_NUMBERS) {
        return;
    }
    
    int numbersReceived = 0;
    for (int i = 0; i < 2; i++) {
        int client = GetClientOfUserId(g_Players[i]);
        if (client > 0 && g_PlayerData[client].sentNumber) {
            numbersReceived++;
        }
    }
    
    if (numbersReceived == 2) {
        DetermineWinner();
    }
}

public Action Timer_NumberTimeout(Handle timer) {
    if (g_GameState == STATE_WAITING_NUMBERS) {
        DetermineWinner();
    }
    g_NumberTimer = null;
    return Plugin_Stop;
}

void DetermineWinner() {
    ClearTimer(g_NumberTimer);
    
    int client1 = GetClientOfUserId(g_Players[0]);
    int client2 = GetClientOfUserId(g_Players[1]);
    
    if (client1 <= 0 || client2 <= 0) {
        CancelGame("玩家不存在");
        return;
    }
    
    int number1 = g_PlayerData[client1].sentNumber ? g_PlayerData[client1].number : -1;
    int number2 = g_PlayerData[client2].sentNumber ? g_PlayerData[client2].number : -1;
    
    // 处理未发送数字的情况
    if (number1 == -1 && number2 == -1) {
        // 双方都没发送，随机选择
        g_CurrentTurn = GetRandomInt(0, 1);
        CPrintToChatAll("{grey}新曙光 - {default}双方都未在时限内输入数字，随机选择先手玩家");
    } else if (number1 == -1) {
        // 玩家1没发送，玩家2赢
        g_CurrentTurn = 1;
        CPrintToChatAll("{grey}新曙光 - {default}一名玩家未输入数字，对方自动获胜");
    } else if (number2 == -1) {
        // 玩家2没发送，玩家1赢
        g_CurrentTurn = 0;
        CPrintToChatAll("{grey}新曙光 - {default}一名玩家未输入数字，对方自动获胜");
    } else {
        // 双方都发送了数字，根据规则判断
        int sum = number1 + number2;
        char ruleExplanation[128];
        
        if (sum > 100) {
            // 和大于100，数字小的赢
            g_CurrentTurn = (number1 < number2) ? 0 : 1;
            Format(ruleExplanation, sizeof(ruleExplanation), "数字和(%d) > 100，数字小的人获胜", sum);
        } else {
            // 和小于等于100，数字大的赢
            g_CurrentTurn = (number1 > number2) ? 0 : 1;
            Format(ruleExplanation, sizeof(ruleExplanation), "数字和(%d) ≤ 100，数字大的人获胜", sum);
        }
        
        // 如果数字相同，随机选择
        if (number1 == number2) {
            g_CurrentTurn = GetRandomInt(0, 1);
            Format(ruleExplanation, sizeof(ruleExplanation), "数字相同，随机选择先手");
        }
        
        CPrintToChatAll("{grey}新曙光 - {default}%s", ruleExplanation);
    }
    
    // 通知结果
    char name1[32], name2[32];
    GetClientName(client1, name1, sizeof(name1));
    GetClientName(client2, name2, sizeof(name2));
    
    if (number1 != -1 && number2 != -1) {
        CPrintToChatAll("{grey}新曙光 - {default}%s 选择了 {green}%d{default}, %s 选择了 {green}%d{default}, {green}%s {default}先开枪!", 
                       name1, number1, name2, number2, (g_CurrentTurn == 0) ? name1 : name2);
    } else {
        CPrintToChatAll("{grey}新曙光 - {default}{green}%s {default}先开枪!", (g_CurrentTurn == 0) ? name1 : name2);
    }
    
    // 开始俄罗斯转盘
    StartRussianRoulette();
}

void StartRussianRoulette() {
    g_GameState = STATE_ROULETTE;
    g_Chamber = 1;
    
    // 向所有玩家说明俄罗斯转盘规则
    CPrintToChatAll("{grey}俄罗斯转盘规则:");
    CPrintToChatAll("• {default}六发左轮，只有一发实弹");
    CPrintToChatAll("• {default}轮流对自己开枪");
    CPrintToChatAll("• {default}中弹概率随开枪次数增加而提高");
    CPrintToChatAll("• {default}第六枪必中");
    CPrintToChatAll("• {default}中弹者死亡，游戏结束");
    
    // 开始第一轮倒计时
    StartRouletteCountdown();
}

void StartRouletteCountdown() {
    int shooter = GetClientOfUserId(g_Players[g_CurrentTurn]);
    if (shooter > 0) {
        char name[32];
        GetClientName(shooter, name, sizeof(name));
        CPrintToChatAll("{grey}新曙光 - {default}%s 准备开枪...", name);
    }
    
    CreateTimer(1.0, Timer_Countdown3, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_Countdown3(Handle timer) {
    if (g_GameState != STATE_ROULETTE) return Plugin_Stop;
    
    CPrintToChatAll("{grey}新曙光 - {red}3");
    CreateTimer(1.0, Timer_Countdown2, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Timer_Countdown2(Handle timer) {
    if (g_GameState != STATE_ROULETTE) return Plugin_Stop;
    
    CPrintToChatAll("{grey}新曙光 - {red}2");
    CreateTimer(1.0, Timer_Countdown1, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Timer_Countdown1(Handle timer) {
    if (g_GameState != STATE_ROULETTE) return Plugin_Stop;
    
    CPrintToChatAll("{grey}新曙光 - {red}1");
    CreateTimer(1.0, Timer_FireShot, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Timer_FireShot(Handle timer) {
    if (g_GameState != STATE_ROULETTE) return Plugin_Stop;
    
    FireShot();
    return Plugin_Stop;
}

void FireShot() {
    int shooter = GetClientOfUserId(g_Players[g_CurrentTurn]);
    
    if (shooter <= 0) {
        CancelGame("玩家不存在");
        return;
    }
    
    char shooterName[32];
    GetClientName(shooter, shooterName, sizeof(shooterName));
    
    // 检查是否中弹 - 概率随开枪次数增加
    // 第一枪: 1/6 概率中弹
    // 第二枪: 1/5 概率中弹
    // 第三枪: 1/4 概率中弹
    // 第四枪: 1/3 概率中弹
    // 第五枪: 1/2 概率中弹
    // 第六枪: 1/1 概率中弹
    int maxChamber = 7 - g_Chamber; // 计算剩余膛室数
    bool hit = (GetRandomInt(1, maxChamber) == 1);
    
    if (hit) {
        // 中弹死亡
        CPrintToChatAll("{grey}新曙光 - {red}💥 砰！ %s 中弹了！", shooterName);
        
        // 强制玩家自杀
        ForcePlayerSuicide(shooter);
        
        // 结束游戏
        CreateTimer(2.0, Timer_EndGame, _, TIMER_FLAG_NO_MAPCHANGE);
    } else {
        // 未中弹
        CPrintToChatAll("{grey}新曙光 - {green}咔嚓！ %s 幸运地活了下来！", shooterName);
        
        // 显示当前中弹概率
        int nextMaxChamber = 7 - (g_Chamber + 1);
        if (nextMaxChamber > 1) {
            CPrintToChatAll("{grey}新曙光 - {default}下一枪中弹概率: 1/%d", nextMaxChamber);
        }
        
        // 移动到下一个膛室
        g_Chamber++;
        
        // 切换到另一个玩家
        g_CurrentTurn = (g_CurrentTurn == 0) ? 1 : 0;
        
        // 如果是第六枪，必中
        if (g_Chamber >= 6) {
            g_Chamber = 6;
            CPrintToChatAll("{grey}新曙光 - {default}这是最后一枪，必中！");
        }
        
        // 继续下一轮
        CreateTimer(2.0, Timer_NextTurn, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_NextTurn(Handle timer) {
    if (g_GameState != STATE_ROULETTE) return Plugin_Stop;
    
    int nextShooter = GetClientOfUserId(g_Players[g_CurrentTurn]);
    if (nextShooter > 0) {
        char name[32];
        GetClientName(nextShooter, name, sizeof(name));
        CPrintToChatAll("{grey}新曙光 - {default}轮到 %s 开枪...", name);
        
        StartRouletteCountdown();
    }
    return Plugin_Stop;
}

public Action Timer_EndGame(Handle timer) {
    CancelGame("游戏结束");
    return Plugin_Stop;
}

void CancelGame(const char[] reason) {
    if (g_GameState == STATE_NONE) {
        return;
    }
    
    CPrintToChatAll("{grey}新曙光 - {default}俄罗斯转盘游戏取消: %s", reason);
    
    // 解除玩家冻结
    for (int i = 0; i < 2; i++) {
        int client = GetClientOfUserId(g_Players[i]);
        if (client > 0 && IsClientInGame(client)) {
            UnfreezePlayer(client);
        }
    }
    
    // 重置状态
    g_GameState = STATE_NONE;
    
    // 清理计时器
    ClearTimers();
    
    // 重置玩家数据
    for (int i = 0; i < 2; i++) {
        int client = GetClientOfUserId(g_Players[i]);
        if (client > 0) {
            ResetPlayerData(client);
        }
    }
}

void ClearTimers() {
    ClearTimer(g_VoteTimer);
    ClearTimer(g_NumberTimer);
    ClearTimer(g_RouletteTimer);
}

void ClearTimer(Handle &timer) {
    if (timer != null) {
        KillTimer(timer);
        timer = null;
    }
}

void ResetPlayerData(int client) {
    g_PlayerData[client].isEligible = false;
    g_PlayerData[client].voted = false;
    g_PlayerData[client].accepted = false;
    g_PlayerData[client].sentNumber = false;
    g_PlayerData[client].number = 0;
    g_PlayerData[client].rouletteTurn = 0;
}

// 重命名函数以避免冲突
bool IsValidClient(int client) {
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}