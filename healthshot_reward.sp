#include <sourcemod>
#include <sdktools>

// 定义全局数组，存储玩家的击杀计数
int g_KillCount[MAXPLAYERS + 1];

public void OnPluginStart()
{
    // 钩住回合开始事件，用于重置击杀计数和移除治疗针
    HookEvent("round_start", Event_RoundStart);
    // 钩住玩家死亡事件，用于统计击杀
    HookEvent("player_death", Event_PlayerDeath);
}

public void OnClientDisconnect(int client)
{
    // 玩家断开连接时，重置击杀计数
    g_KillCount[client] = 0;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    // 回合开始时重置所有玩家的击杀计数，并移除治疗针
    for (int i = 1; i <= MaxClients; i++)
    {
        g_KillCount[i] = 0;
        
        // 检查玩家是否在游戏中且活着，移除治疗针
        if (IsClientInGame(i) && IsPlayerAlive(i))
        {
            RemoveHealthshots(i);
        }
    }
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    // 如果是热身阶段，直接跳过
    if (GameRules_GetProp("m_bWarmupPeriod") == 1)
    {
        return;
    }

    // 获取受害者和击杀者的客户端索引
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    // 检查击杀者是否有效：必须是玩家、在游戏中、不是自杀、不是团队击杀
    if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) && 
        attacker != victim && GetClientTeam(attacker) != GetClientTeam(victim))
    {
        // 获取击杀信息
        bool headshot = event.GetBool("headshot");
        char weapon[32];
        event.GetString("weapon", weapon, sizeof(weapon));

        // 判断是否为符合条件的击杀：爆头、电击枪或匕首
        if (headshot || StrEqual(weapon, "taser", false) || StrEqual(weapon, "knife", false))
        {
            // 增加击杀者的击杀计数
            g_KillCount[attacker]++;

            // 检查是否达到2次击杀，若是则发放治疗针并重置计数
            if (g_KillCount[attacker] == 2)
            {
                GivePlayerItem(attacker, "weapon_healthshot");
                g_KillCount[attacker] = 0; // 重置计数器
            }
        }
    }
}

// 自定义函数：移除玩家的所有治疗针
void RemoveHealthshots(int client)
{
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "weapon_healthshot")) != -1)
    {
        if (IsValidEntity(entity) && GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") == client)
        {
            AcceptEntityInput(entity, "Kill"); // 删除治疗针实体
        }
    }
}