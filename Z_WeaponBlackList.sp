#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <cstrike>
#include <colors>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
    name    = "Weapon Blacklist",
    author  = "ChatGPT & Optimized by Grok",
    description = "Weapon purchase restrictions",
    version = "1.0.0",
    url     = ""
};

// ========== 配置 ==========
char g_RestrictedWeapons[][] = {
    "weapon_awp",
    "weapon_ssg08",
    "weapon_hegrenade",
    "weapon_flashbang",
    "weapon_smokegrenade",
    "weapon_molotov",
    "weapon_incgrenade",
    "weapon_decoy",
    "weapon_tagrenade"
};

int g_LastMsgTick[MAXPLAYERS + 1];

// ========== 工具函数 ==========
static bool IsValidAliveClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client));
}

static bool IsRestrictedWeapon(const char[] weapon)
{
    for (int i = 0; i < sizeof(g_RestrictedWeapons); i++)
    {
        if (StrEqual(weapon, g_RestrictedWeapons[i], false))
            return true;
    }
    return false;
}

static void GetWeaponDisplayName(const char[] weapon, char[] displayName, int maxLength)
{
    if (StrEqual(weapon, "weapon_awp")) strcopy(displayName, maxLength, "AWP");
    else if (StrEqual(weapon, "weapon_ssg08")) strcopy(displayName, maxLength, "SSG08");
    else if (StrEqual(weapon, "weapon_hegrenade")) strcopy(displayName, maxLength, "HE Grenade");
    else if (StrEqual(weapon, "weapon_flashbang")) strcopy(displayName, maxLength, "Flashbang");
    else if (StrEqual(weapon, "weapon_smokegrenade")) strcopy(displayName, maxLength, "Smoke Grenade");
    else if (StrEqual(weapon, "weapon_molotov") || StrEqual(weapon, "weapon_incgrenade")) strcopy(displayName, maxLength, "Molotov");
    else if (StrEqual(weapon, "weapon_decoy")) strcopy(displayName, maxLength, "Decoy Grenade");
    else if (StrEqual(weapon, "weapon_tagrenade")) strcopy(displayName, maxLength, "Tactical Awareness Grenade");
    else strcopy(displayName, maxLength, weapon);
}

// ========== 插件初始化 ==========
public void OnPluginStart()
{
    HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);

    for (int client = 1; client <= MaxClients; client++)
    {
        g_LastMsgTick[client] = 0;

        if (IsClientInGame(client))
        {
            SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquipPost);
        }
    }

    PrintToServer("[weapon_blacklist] 插件加载：武器限制已启用。");
}

// ========== OnMapStart ==========
public void OnMapStart()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        g_LastMsgTick[client] = 0;
    }
}

// ========== 客户端生命周期钩子 ==========
public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquipPost);

    g_LastMsgTick[client] = 0;
}

public void OnClientDisconnect(int client)
{
    SDKUnhook(client, SDKHook_WeaponEquipPost, OnWeaponEquipPost);

    g_LastMsgTick[client] = 0;
}

public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !IsClientInGame(client)) return;

    SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquipPost);

    g_LastMsgTick[client] = 0;
}

// ========== 购买限制：直接拦截购买命令 ==========
public Action CS_OnBuyCommand(int client, const char[] weapon)
{
    if (!IsValidAliveClient(client)) return Plugin_Continue;

    char fullWeapon[64];
    Format(fullWeapon, sizeof(fullWeapon), "weapon_%s", weapon);

    if (IsRestrictedWeapon(fullWeapon))
    {
        char displayName[64];
        GetWeaponDisplayName(fullWeapon, displayName, sizeof(displayName));
        CPrintToChat(client, "{grey}新曙光 - {default}不能购买 %s", displayName);
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

// ========== 装备后检查并移除被禁止的武器 ==========
public void OnWeaponEquipPost(int client, int weapon)
{
    if (!IsValidAliveClient(client)) return;

    char weaponName[64];
    GetEntityClassname(weapon, weaponName, sizeof(weaponName));

    if (IsRestrictedWeapon(weaponName))
    {
        char displayName[64];
        GetWeaponDisplayName(weaponName, displayName, sizeof(displayName));
        CPrintToChat(client, "{grey}新曙光 - {default}不能使用 %s，已移除", displayName);

        if (IsValidEntity(weapon))
        {
            RemovePlayerItem(client, weapon);
            AcceptEntityInput(weapon, "Kill");
        }
    }
}

// ========== OnMapEnd ==========
public void OnMapEnd()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        g_LastMsgTick[i] = 0;
    }

    PrintToServer("[weapon_blacklist] OnMapEnd: 清理完成。");
}