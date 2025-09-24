#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <cstrike>
#include <colors>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
    name    = "Anti-DoubleTap",
    author  = "ChatGPT & Optimized by Grok",
    description = "Robust anti-double-tap for specific weapons",
    version = "1.0.0",
    url     = ""
};

// ========== 配置 ==========
#define DEFAULT_ALLOW_DT_TICKS 5  // 双击容忍 ticks
#define DT_BLOCK_DELAY 0.2        // 双击拦截后强制延时（秒）
#define MSG_COOLDOWN_TICKS 10

int g_allow_dt_ticks = DEFAULT_ALLOW_DT_TICKS;
bool g_show_msg = true;

// ========== 全局数据 ==========
char g_DtWeapons[][] = {
    "weapon_scar20",
    "weapon_g3sg1",
    "weapon_deagle"
};

int g_LastShotTick[MAXPLAYERS + 1];
int g_ShotWindowStartTick[MAXPLAYERS + 1];
int g_ShotCountInWindow[MAXPLAYERS + 1];
bool g_bShotBlocked[MAXPLAYERS + 1];
Handle g_hUnblockTimer[MAXPLAYERS + 1];
Handle g_hApplyTimer[MAXPLAYERS + 1];
int g_LastMsgTick[MAXPLAYERS + 1];

// ========== 工具函数 ==========
static bool IsValidAliveClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client));
}

static bool IsDtWeaponByClass(const char[] weapon)
{
    for (int i = 0; i < sizeof(g_DtWeapons); i++)
    {
        if (StrEqual(weapon, g_DtWeapons[i], false))
            return true;
    }
    return false;
}

static void GetWeaponDisplayName(const char[] weapon, char[] displayName, int maxLength)
{
    if (StrEqual(weapon, "weapon_scar20")) strcopy(displayName, maxLength, "SCAR-20");
    else if (StrEqual(weapon, "weapon_g3sg1")) strcopy(displayName, maxLength, "G3SG1");
    else if (StrEqual(weapon, "weapon_deagle")) strcopy(displayName, maxLength, "Desert Eagle");
    else strcopy(displayName, maxLength, weapon);
}

// ========== 插件初始化 ==========
public void OnPluginStart()
{
    HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);
    HookEvent("weapon_fire", OnWeaponFire, EventHookMode_Post);

    for (int client = 1; client <= MaxClients; client++)
    {
        g_LastShotTick[client] = 0;
        g_ShotWindowStartTick[client] = 0;
        g_ShotCountInWindow[client] = 0;
        g_bShotBlocked[client] = false;
        g_hUnblockTimer[client] = INVALID_HANDLE;
        g_hApplyTimer[client] = INVALID_HANDLE;
        g_LastMsgTick[client] = 0;

        if (IsClientInGame(client))
        {
            SDKHook(client, SDKHook_FireBulletsPost, FireBulletsHook);
        }
    }

    PrintToServer("[anti_dt] 插件加载：Anti-DT 已启用。默认允许间隔 ticks = %d", g_allow_dt_ticks);
}

// ========== OnMapStart ==========
public void OnMapStart()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        g_LastShotTick[client] = 0;
        g_ShotWindowStartTick[client] = 0;
        g_ShotCountInWindow[client] = 0;
        g_bShotBlocked[client] = false;
        g_LastMsgTick[client] = 0;

        if (g_hUnblockTimer[client] != INVALID_HANDLE)
        {
            CloseHandle(g_hUnblockTimer[client]);
            g_hUnblockTimer[client] = INVALID_HANDLE;
        }
        if (g_hApplyTimer[client] != INVALID_HANDLE)
        {
            CloseHandle(g_hApplyTimer[client]);
            g_hApplyTimer[client] = INVALID_HANDLE;
        }
    }
}

// ========== 客户端生命周期钩子 ==========
public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_FireBulletsPost, FireBulletsHook);

    g_LastShotTick[client] = 0;
    g_ShotWindowStartTick[client] = 0;
    g_ShotCountInWindow[client] = 0;
    g_bShotBlocked[client] = false;
    g_hUnblockTimer[client] = INVALID_HANDLE;
    g_hApplyTimer[client] = INVALID_HANDLE;
    g_LastMsgTick[client] = 0;
}

public void OnClientDisconnect(int client)
{
    SDKUnhook(client, SDKHook_FireBulletsPost, FireBulletsHook);

    g_LastShotTick[client] = 0;
    g_ShotWindowStartTick[client] = 0;
    g_ShotCountInWindow[client] = 0;
    g_bShotBlocked[client] = false;
    g_LastMsgTick[client] = 0;

    if (g_hUnblockTimer[client] != INVALID_HANDLE)
    {
        CloseHandle(g_hUnblockTimer[client]);
        g_hUnblockTimer[client] = INVALID_HANDLE;
    }
    if (g_hApplyTimer[client] != INVALID_HANDLE)
    {
        CloseHandle(g_hApplyTimer[client]);
        g_hApplyTimer[client] = INVALID_HANDLE;
    }
}

public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !IsClientInGame(client)) return;

    SDKHook(client, SDKHook_FireBulletsPost, FireBulletsHook);

    g_LastShotTick[client] = 0;
    g_ShotWindowStartTick[client] = 0;
    g_ShotCountInWindow[client] = 0;
    g_bShotBlocked[client] = false;
    g_LastMsgTick[client] = 0;

    if (g_hUnblockTimer[client] != INVALID_HANDLE)
    {
        CloseHandle(g_hUnblockTimer[client]);
        g_hUnblockTimer[client] = INVALID_HANDLE;
    }
    if (g_hApplyTimer[client] != INVALID_HANDLE)
    {
        CloseHandle(g_hApplyTimer[client]);
        g_hApplyTimer[client] = INVALID_HANDLE;
    }
}

// ========== RunCmd：双击检测 ==========
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if (!IsValidAliveClient(client)) return Plugin_Continue;

    if (!(buttons & IN_ATTACK)) return Plugin_Continue;

    int allow = g_allow_dt_ticks;
    bool show = g_show_msg;

    int hWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (hWeapon == -1 || !IsValidEntity(hWeapon)) return Plugin_Continue;

    char wname[64];
    GetEntityClassname(hWeapon, wname, sizeof(wname));
    if (!IsDtWeaponByClass(wname)) return Plugin_Continue;

    if (g_LastShotTick[client] > 0 && (GetGameTickCount() - g_LastShotTick[client]) <= allow)
    {
        buttons &= ~IN_ATTACK;
        buttons &= ~IN_ATTACK2;

        float nextTime = GetGameTime() + DT_BLOCK_DELAY;
        SetEntPropFloat(hWeapon, Prop_Send, "m_flNextPrimaryAttack", nextTime);
        SetEntPropFloat(client, Prop_Send, "m_flNextAttack", nextTime);

        if (show && (GetGameTickCount() - g_LastMsgTick[client] > MSG_COOLDOWN_TICKS))
        {
            char disp[64];
            GetWeaponDisplayName(wname, disp, sizeof(disp));
            CPrintToChat(client, "{red}新曙光 - {default}%s 禁止 DT", disp);
            g_LastMsgTick[client] = GetGameTickCount();
            LogMessage("Sync Print: client %d 双击被阻止 (weapon %s, forced delay %.2f sec)", client, wname, DT_BLOCK_DELAY);
        }
        else
        {
            LogMessage("Sync Block (no print): client %d 双击被阻止 (weapon %s, cooldown active)", client, wname);
        }

        return Plugin_Changed;
    }

    return Plugin_Continue;
}

// ========== weapon_fire（记录开火）==========
public Action OnWeaponFire(Event event, const char[] name, bool dontBroadcast)
{
    int userid = event.GetInt("userid");
    if (userid <= 0) return Plugin_Continue;

    int client = GetClientOfUserId(userid);
    if (!IsValidAliveClient(client)) return Plugin_Continue;

    char wpn[64];
    event.GetString("weapon", wpn, sizeof(wpn));

    if (!IsDtWeaponByClass(wpn)) return Plugin_Continue;

    int tick = GetGameTickCount();
    g_LastShotTick[client] = tick;

    int allow = g_allow_dt_ticks;
    int start = g_ShotWindowStartTick[client];
    int delta = 999999;
    if (start > 0) delta = tick - start;

    if (start == 0 || delta > allow)
    {
        g_ShotWindowStartTick[client] = tick;
        g_ShotCountInWindow[client] = 1;
    }
    else
    {
        g_ShotCountInWindow[client]++;
    }

    if (g_show_msg && g_ShotCountInWindow[client] > 1 && (tick - g_LastMsgTick[client] > MSG_COOLDOWN_TICKS))
    {
        char disp[64];
        GetWeaponDisplayName(wpn, disp, sizeof(disp));
        CPrintToChat(client, "{red}新曙光 - {default}%s 禁止 DT", disp);
        g_LastMsgTick[client] = tick;
        LogMessage("Async Print: client %d 双击滥用提交 (weapon %s, window_count=%d, delta=%d)", client, wpn, g_ShotCountInWindow[client], delta);
    }

    LogMessage("OnWeaponFire: client %d weapon %s tick %d (window_count=%d)", client, wpn, tick, g_ShotCountInWindow[client]);
    return Plugin_Continue;
}

// ========== FireBulletsPost 备份 ==========
public void FireBulletsHook(int client, int shots, const char[] weaponname)
{
    if (!IsValidAliveClient(client)) return;
    if (!IsDtWeaponByClass(weaponname)) return;

    int tick = GetGameTickCount();
    if (g_LastShotTick[client] == 0) g_LastShotTick[client] = tick;

    LogMessage("FireBulletsHook: client %d fired %s (shots=%d) tick=%d", client, weaponname, shots, tick);
}

// ========== OnMapEnd ==========
public void OnMapEnd()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        g_LastShotTick[i] = 0;
        g_ShotWindowStartTick[i] = 0;
        g_ShotCountInWindow[i] = 0;
        g_bShotBlocked[i] = false;
        g_LastMsgTick[i] = 0;

        if (g_hUnblockTimer[i] != INVALID_HANDLE)
        {
            CloseHandle(g_hUnblockTimer[i]);
            g_hUnblockTimer[i] = INVALID_HANDLE;
        }
        if (g_hApplyTimer[i] != INVALID_HANDLE)
        {
            CloseHandle(g_hApplyTimer[i]);
            g_hApplyTimer[i] = INVALID_HANDLE;
        }
    }

    PrintToServer("[anti_dt] OnMapEnd: 清理完成。");
}