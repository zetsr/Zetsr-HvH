#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
    name    = "Crouch Damage Scale",
    author  = "ChatGPT & Optimized by Grok",
    description = "Crouch damage scale and prompt",
    version = "1.0.0",
    url     = ""
};

// ========== 配置 ==========
#define CROUCH_SCALE 0.25         // 下蹲伤害倍率
#define CROUCH_MSG_COOLDOWN_TICKS 10

// ========== 全局数据 ==========
int g_LastDamageScaledTick[MAXPLAYERS + 1];
int g_LastCrouchMsgTick[MAXPLAYERS + 1];

// ========== 工具函数 ==========
static bool IsValidAliveClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client));
}

static int GetCrouchReductionPercent()
{
    float reduction = (1.0 - CROUCH_SCALE) * 100.0;
    return RoundToNearest(reduction);
}

// ========== 插件初始化 ==========
public void OnPluginStart()
{
    HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);

    for (int client = 1; client <= MaxClients; client++)
    {
        g_LastDamageScaledTick[client] = 0;
        g_LastCrouchMsgTick[client] = 0;

        if (IsClientInGame(client))
        {
            SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
        }
    }

    int reduction = GetCrouchReductionPercent();
    PrintToServer("[crouch_damage] 插件加载：下蹲减伤 %d%%", reduction);
}

// ========== 客户端生命周期钩子 ==========
public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    g_LastDamageScaledTick[client] = 0;
    g_LastCrouchMsgTick[client] = 0;
}

public void OnClientDisconnect(int client)
{
    SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    g_LastDamageScaledTick[client] = 0;
    g_LastCrouchMsgTick[client] = 0;
}

public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !IsClientInGame(client)) return;

    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    g_LastDamageScaledTick[client] = 0;
    g_LastCrouchMsgTick[client] = 0;
}

// ========== 下蹲伤害缩放 ==========
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (!IsValidAliveClient(victim) || attacker <= 0 || attacker > MaxClients) return Plugin_Continue;
    if (!IsValidAliveClient(attacker)) return Plugin_Continue;

    if (GetClientButtons(attacker) & IN_DUCK)
    {
        int currentTick = GetGameTickCount();
        if (g_LastDamageScaledTick[attacker] == currentTick)
        {
            return Plugin_Continue;
        }

        float original = damage;
        damage *= CROUCH_SCALE;
        g_LastDamageScaledTick[attacker] = currentTick;

        int reduction = GetCrouchReductionPercent();
        PrintHintText(attacker, "您处于下蹲状态，伤害降低%d%%", reduction);
        LogMessage("玩家 %N 下蹲攻击, damage %.2f -> %.2f (tick=%d, reduction=%d%%)", attacker, original, damage, currentTick, reduction);

        return Plugin_Changed;
    }

    return Plugin_Continue;
}

// ========== RunCmd：即时下蹲提示 ==========
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if (!IsValidAliveClient(client)) return Plugin_Continue;

    int currentTick = GetGameTickCount();

    if (buttons & IN_DUCK)
    {
        if (currentTick - g_LastCrouchMsgTick[client] >= CROUCH_MSG_COOLDOWN_TICKS)
        {
            int reduction = GetCrouchReductionPercent();
            PrintHintText(client, "您处于下蹲状态，伤害降低%d%%", reduction);
            g_LastCrouchMsgTick[client] = currentTick;
            LogMessage("RunCmd Crouch Hint: client %d (tick=%d, reduction=%d%%)", client, currentTick, reduction);
        }
    }
    else
    {
        if (currentTick - g_LastCrouchMsgTick[client] > CROUCH_MSG_COOLDOWN_TICKS * 2)
        {
            g_LastCrouchMsgTick[client] = 0;
        }
    }

    return Plugin_Continue;
}

// ========== OnMapEnd ==========
public void OnMapEnd()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        g_LastDamageScaledTick[i] = 0;
        g_LastCrouchMsgTick[i] = 0;
    }
}