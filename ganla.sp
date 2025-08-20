#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
    name    = "Crouch & Idle Penalty",
    author  = "ChatGPT & Optimized by Grok",
    description = "Crouch damage scale and idle punishment",
    version = "1.0.3",
    url     = ""
};

#define CHECK_INTERVAL 1.0        // 每秒检测一次
#define MOVE_THRESHOLD 100.0      // 单次检测阈值：100 单位
#define WARN_TIME 5               // 5秒开始提示
#define DAMAGE_TIME 10            // 10秒开始扣血
#define CROUCH_SCALE 0.5          // 下蹲伤害倍率

float g_LastPos[MAXPLAYERS + 1][3];
int   g_IdleTime[MAXPLAYERS + 1];
Handle g_hIdleTimer = INVALID_HANDLE;

// ——— 工具函数 ———
static bool IsValidAliveClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client));
}

static void CopyVec3(const float src[3], float dest[3])
{
    dest[0] = src[0]; dest[1] = src[1]; dest[2] = src[2];
}

// ——— 插件入口 ———
public void OnPluginStart()
{
    HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);
    g_hIdleTimer = CreateTimer(CHECK_INTERVAL, Timer_CheckIdle, _, TIMER_REPEAT);

    // 为所有已连接的玩家注册 SDKHook
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client))
        {
            SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
        }
    }
}

// 玩家进入服务器时，挂钩伤害并初始化位置
public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);

    float pos[3];
    if (IsClientInGame(client) && IsPlayerAlive(client))
        GetClientAbsOrigin(client, pos);
    else
        pos[0] = pos[1] = pos[2] = 0.0;

    CopyVec3(pos, g_LastPos[client]);
    g_IdleTime[client] = 0;
}

// 玩家离开时解除挂钩
public void OnClientDisconnect(int client)
{
    SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

// 复活时重置位置与计时，并重新挂钩
public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0) return;

    if (IsClientInGame(client))
    {
        SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage); // 确保复活时重新挂钩
        float pos[3];
        GetClientAbsOrigin(client, pos);
        CopyVec3(pos, g_LastPos[client]);
        g_IdleTime[client] = 0;
    }
}

// ——— 下蹲伤害减半 ———
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    // 调试日志：确认回调被触发
    LogMessage("OnTakeDamage 触发: victim=%d, attacker=%d, damage=%.1f, damagetype=%d", victim, attacker, damage, damagetype);

    // 确保受害者和攻击者是有效玩家，且处理的是武器伤害
    if (!IsValidAliveClient(victim) || !IsValidAliveClient(attacker))
    {
        LogMessage("无效的 victim=%d 或 attacker=%d，跳过处理", victim, attacker);
        return Plugin_Continue;
    }

    // 检查攻击者是否处于下蹲状态
    if (GetClientButtons(attacker) & IN_DUCK)
    {
        damage *= CROUCH_SCALE;
        PrintHintText(attacker, "您处于下蹲状态，伤害降低50%%");
        LogMessage("玩家 %N 下蹲攻击，伤害从 %.1f 缩放至 %.1f", attacker, damage / CROUCH_SCALE, damage);
        return Plugin_Changed;
    }

    LogMessage("玩家 %N 未下蹲，伤害未修改：%.1f", attacker, damage);
    return Plugin_Continue;
}

// ——— 每秒检测移动/处理挂机惩罚 & 下蹲提示 ———
public Action Timer_CheckIdle(Handle timer, any data)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidAliveClient(client))
            continue;

        // 每秒给下蹲玩家提示
        if (GetClientButtons(client) & IN_DUCK)
        {
            PrintHintText(client, "您处于下蹲状态，伤害降低50%%");
        }

        // 移动检测
        float pos[3];
        GetClientAbsOrigin(client, pos);
        float dist = GetVectorDistance(g_LastPos[client], pos);

        if (dist < MOVE_THRESHOLD)
        {
            g_IdleTime[client]++;

            // 5~9秒：每秒提示倒计时
            if (g_IdleTime[client] >= WARN_TIME && g_IdleTime[client] < DAMAGE_TIME)
            {
                int left = DAMAGE_TIME - g_IdleTime[client];
                PrintCenterText(client, "您因持续不移动还有 %d 秒将扣血", left);
            }

            // ≥10秒：每秒-1HP（保底不扣死）
            if (g_IdleTime[client] >= DAMAGE_TIME)
            {
                int hp = GetClientHealth(client);
                if (hp > 1)
                {
                    SetEntityHealth(client, hp - 1);
                }
            }
        }
        else
        {
            // 单次移动≥阈值：重置
            g_IdleTime[client] = 0;
        }

        // 更新记录位置
        CopyVec3(pos, g_LastPos[client]);
    }

    return Plugin_Continue;
}