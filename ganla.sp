/**
 * ganla.sp - Anti double-tap (block 2nd shot) using weapon_fire event + RunCmd interception
 * 1) 使用 weapon_fire 事件尽早记录“开火事实”
 * 2) 在 OnPlayerRunCmd 阶段拦截第二次按键（清除 IN_ATTACK 并返回 Plugin_Changed）
 * 3) 修复下蹲伤害重复缩放（同 tick 只缩放一次）
 * 4) 保留购买限制 / 持有移除 / 挂机检测等功能
 *
 * 注意：此版本为兼容性优先，未使用 CreateConVar（避免不同 SM 版本签名差异导致编译错误）。
 * 如需 ConVar 可配置版，请回复我，我会直接发回兼容多版本的ConVar实现。
 */

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
    name    = "Crouch & Idle Penalty with Weapon Restrictions + Improved Anti-DoubleTap",
    author  = "ChatGPT & Optimized by Grok",
    description = "Crouch damage scale, idle punishment, weapon purchase restrictions, and robust anti-double-tap (blocks 2nd shot)",
    version = "1.5.1",
    url     = ""
};

// ========== 配置（如需修改请直接改这些值） ==========
#define CHECK_INTERVAL 1.0        // 每秒检测一次
#define MOVE_THRESHOLD 100.0      // 移动阈值（单位）
#define WARN_TIME 5               // 警告时间（秒）
#define DAMAGE_TIME 10            // 扣血时间（秒）
#define CROUCH_SCALE 0.5          // 下蹲伤害倍率
#define DEFAULT_ALLOW_DT_TICKS 5  // 默认允许的最小间隔（tick），小于等于视为 double-tap

// 如果你希望管理员可以在线调整，把下面改成 ConVar 版本（需要我提供）
int g_allow_dt_ticks = DEFAULT_ALLOW_DT_TICKS;
bool g_show_msg = true; // 被阻止时是否显示中心提示

// ========== 全局数据 ==========
float g_LastPos[MAXPLAYERS + 1][3];
int   g_IdleTime[MAXPLAYERS + 1];
Handle g_hIdleTimer = INVALID_HANDLE;

// 购买受限武器（classnames）
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

// 关注的可 double-tap 武器（classnames）
char g_DtWeapons[][] = {
    "weapon_scar20",
    "weapon_g3sg1",
    "weapon_deagle"
};

// 记录：上次“开火事实”的 tick（由 weapon_fire 事件写入）
int g_LastShotTick[MAXPLAYERS + 1];

// 下蹲伤害缩放保护（按 attacker），避免在同一 tick 重复缩放
int g_LastDamageScaledTick[MAXPLAYERS + 1];

// 备用字段（若以后加入 m_flNextPrimaryAttack 备份可以用）
int g_ShotWindowStartTick[MAXPLAYERS + 1];
int g_ShotCountInWindow[MAXPLAYERS + 1];
bool g_bShotBlocked[MAXPLAYERS + 1];
Handle g_hUnblockTimer[MAXPLAYERS + 1];
Handle g_hApplyTimer[MAXPLAYERS + 1];

// ========== 工具函数 ==========
static bool IsValidAliveClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client));
}

static void CopyVec3(const float src[3], float dest[3])
{
    dest[0] = src[0]; dest[1] = src[1]; dest[2] = src[2];
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
    if (StrEqual(weapon, "weapon_awp")) strcopy(displayName, maxLength, "AWP");
    else if (StrEqual(weapon, "weapon_ssg08")) strcopy(displayName, maxLength, "SSG08");
    else if (StrEqual(weapon, "weapon_hegrenade")) strcopy(displayName, maxLength, "HE Grenade");
    else if (StrEqual(weapon, "weapon_flashbang")) strcopy(displayName, maxLength, "Flashbang");
    else if (StrEqual(weapon, "weapon_smokegrenade")) strcopy(displayName, maxLength, "Smoke Grenade");
    else if (StrEqual(weapon, "weapon_molotov") || StrEqual(weapon, "weapon_incgrenade")) strcopy(displayName, maxLength, "Molotov");
    else if (StrEqual(weapon, "weapon_decoy")) strcopy(displayName, maxLength, "Decoy Grenade");
    else if (StrEqual(weapon, "weapon_tagrenade")) strcopy(displayName, maxLength, "Tactical Awareness Grenade");
    else if (StrEqual(weapon, "weapon_scar20")) strcopy(displayName, maxLength, "SCAR-20");
    else if (StrEqual(weapon, "weapon_g3sg1")) strcopy(displayName, maxLength, "G3SG1");
    else if (StrEqual(weapon, "weapon_deagle")) strcopy(displayName, maxLength, "Desert Eagle");
    else strcopy(displayName, maxLength, weapon);
}

// ========== 插件初始化 ==========
public void OnPluginStart()
{
    HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);
    HookEvent("item_purchase", OnItemPurchase, EventHookMode_Post);

    // 监听 weapon_fire（作为尽早的“开火事实”来源）
    HookEvent("weapon_fire", OnWeaponFire, EventHookMode_Post);

    // Idle 检测 timer，用明确 data=0 避免占位符问题
    g_hIdleTimer = CreateTimer(CHECK_INTERVAL, Timer_CheckIdle, 0, TIMER_REPEAT);

    // 初始化数组并为当前已在线玩家注册 hooks
    for (int client = 1; client <= MaxClients; client++)
    {
        g_LastPos[client][0] = g_LastPos[client][1] = g_LastPos[client][2] = 0.0;
        g_IdleTime[client] = 0;
        g_LastShotTick[client] = 0;
        g_LastDamageScaledTick[client] = 0;
        g_ShotWindowStartTick[client] = 0;
        g_ShotCountInWindow[client] = 0;
        g_bShotBlocked[client] = false;
        g_hUnblockTimer[client] = INVALID_HANDLE;
        g_hApplyTimer[client] = INVALID_HANDLE;

        if (IsClientInGame(client))
        {
            SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
            SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquipPost);
            SDKHook(client, SDKHook_FireBulletsPost, FireBulletsHook); // 备份
        }
    }

    PrintToServer("[ganla] 插件加载：Anti-DoubleTap (weapon_fire + RunCmd) 启用。默认允许间隔 ticks = %d", g_allow_dt_ticks);
}

// ========== 客户端生命周期钩子 ==========
public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquipPost);
    SDKHook(client, SDKHook_FireBulletsPost, FireBulletsHook);

    float pos[3];
    if (IsClientInGame(client) && IsPlayerAlive(client))
        GetClientAbsOrigin(client, pos);
    else
        pos[0] = pos[1] = pos[2] = 0.0;

    CopyVec3(pos, g_LastPos[client]);
    g_IdleTime[client] = 0;
    g_LastShotTick[client] = 0;
    g_LastDamageScaledTick[client] = 0;
    g_ShotWindowStartTick[client] = 0;
    g_ShotCountInWindow[client] = 0;
    g_bShotBlocked[client] = false;
    g_hUnblockTimer[client] = INVALID_HANDLE;
    g_hApplyTimer[client] = INVALID_HANDLE;
}

public void OnClientDisconnect(int client)
{
    SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    SDKUnhook(client, SDKHook_WeaponEquipPost, OnWeaponEquipPost);
    SDKUnhook(client, SDKHook_FireBulletsPost, FireBulletsHook);

    g_LastPos[client][0] = g_LastPos[client][1] = g_LastPos[client][2] = 0.0;
    g_IdleTime[client] = 0;
    g_LastShotTick[client] = 0;
    g_LastDamageScaledTick[client] = 0;
    g_ShotWindowStartTick[client] = 0;
    g_ShotCountInWindow[client] = 0;
    g_bShotBlocked[client] = false;

    if (g_hUnblockTimer[client] != INVALID_HANDLE) { CloseHandle(g_hUnblockTimer[client]); g_hUnblockTimer[client] = INVALID_HANDLE; }
    if (g_hApplyTimer[client] != INVALID_HANDLE)  { CloseHandle(g_hApplyTimer[client]);  g_hApplyTimer[client] = INVALID_HANDLE; }
}

public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0) return;

    if (IsClientInGame(client))
    {
        SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
        SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquipPost);
        SDKHook(client, SDKHook_FireBulletsPost, FireBulletsHook);

        float pos[3];
        GetClientAbsOrigin(client, pos);
        CopyVec3(pos, g_LastPos[client]);
        g_IdleTime[client] = 0;
        g_LastShotTick[client] = 0;
        g_LastDamageScaledTick[client] = 0;
        g_ShotWindowStartTick[client] = 0;
        g_ShotCountInWindow[client] = 0;
        g_bShotBlocked[client] = false;

        if (g_hUnblockTimer[client] != INVALID_HANDLE) { CloseHandle(g_hUnblockTimer[client]); g_hUnblockTimer[client] = INVALID_HANDLE; }
        if (g_hApplyTimer[client] != INVALID_HANDLE)  { CloseHandle(g_hApplyTimer[client]);  g_hApplyTimer[client] = INVALID_HANDLE; }
    }
}

// ========== 购买限制 ========== 
public Action OnItemPurchase(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidAliveClient(client)) return Plugin_Continue;

    char weapon[64];
    event.GetString("weapon", weapon, sizeof(weapon));

    if (IsRestrictedWeapon(weapon))
    {
        char displayName[64];
        GetWeaponDisplayName(weapon, displayName, sizeof(displayName));
        PrintToChat(client, "\x04[限制]\x01 不能购买 %s", displayName);
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
        PrintToChat(client, "\x04[限制]\x01 不能使用 %s，已移除", displayName);
        
        if (IsValidEntity(weapon))
        {
            RemovePlayerItem(client, weapon);
            AcceptEntityInput(weapon, "Kill");
        }
    }
}

// ========== 下蹲伤害 BUG 修复（同一 tick 只缩放一次） ==========
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (!IsValidAliveClient(victim) || attacker <= 0 || attacker > MaxClients) return Plugin_Continue;
    if (!IsValidAliveClient(attacker)) return Plugin_Continue;

    if (GetClientButtons(attacker) & IN_DUCK)
    {
        int currentTick = GetGameTickCount();
        if (g_LastDamageScaledTick[attacker] == currentTick)
        {
            // 已在当前 tick 缩放过
            return Plugin_Continue;
        }

        float original = damage;
        damage *= CROUCH_SCALE;
        g_LastDamageScaledTick[attacker] = currentTick;

        PrintHintText(attacker, "您处于下蹲状态，伤害降低50%%");
        LogMessage("玩家 %N 下蹲攻击, damage %.2f -> %.2f (tick=%d)", attacker, original, damage, currentTick);

        return Plugin_Changed;
    }

    return Plugin_Continue;
}

// ========== 每秒检测：挂机惩罚 & 下蹲提示 & 武器移除 ==========
public Action Timer_CheckIdle(Handle timer, any data)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidAliveClient(client)) continue;

        if (GetClientButtons(client) & IN_DUCK)
        {
            PrintHintText(client, "您处于下蹲状态，伤害降低50%%");
        }

        float pos[3];
        GetClientAbsOrigin(client, pos);
        float dist = GetVectorDistance(g_LastPos[client], pos);

        if (dist < MOVE_THRESHOLD)
        {
            g_IdleTime[client]++;

            if (g_IdleTime[client] >= WARN_TIME && g_IdleTime[client] < DAMAGE_TIME)
            {
                int left = DAMAGE_TIME - g_IdleTime[client];
                PrintCenterText(client, "您因持续不移动还有 %d 秒将扣血", left);
            }

            if (g_IdleTime[client] >= DAMAGE_TIME)
            {
                int hp = GetClientHealth(client);
                if (hp > 1) SetEntityHealth(client, hp - 1);
            }
        }
        else
        {
            g_IdleTime[client] = 0;
        }

        CopyVec3(pos, g_LastPos[client]);

        int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
        if (weapon != -1)
        {
            char weaponName[64];
            GetEntityClassname(weapon, weaponName, sizeof(weaponName));
            if (IsRestrictedWeapon(weaponName))
            {
                char displayName[64];
                GetWeaponDisplayName(weaponName, displayName, sizeof(displayName));
                PrintToChat(client, "\x04[限制]\x01 不能使用 %s，已移除", displayName);
                RemovePlayerItem(client, weapon);
                AcceptEntityInput(weapon, "Kill");
            }
        }
    }

    return Plugin_Continue;
}

// ========== weapon_fire 事件：尽早记录“开火事实” ==========
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

    // 作为备份维护窗口计数
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

    LogMessage("OnWeaponFire: client %d weapon %s tick %d (window_count=%d)", client, wpn, tick, g_ShotCountInWindow[client]);
    return Plugin_Continue;
}

// ========== FireBulletsPost 备份（可选） ==========
public void FireBulletsHook(int client, int shots, const char[] weaponname)
{
    if (!IsValidAliveClient(client)) return;
    if (!IsDtWeaponByClass(weaponname)) return;

    int tick = GetGameTickCount();
    if (g_LastShotTick[client] == 0) g_LastShotTick[client] = tick; // 如果 weapon_fire 未触发，作为后备来源

    LogMessage("FireBulletsHook: client %d fired %s (shots=%d) tick=%d", client, weaponname, shots, tick);
}

// ========== OnPlayerRunCmd：按键阶段拦截第二发 ==========
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

    int currentTick = GetGameTickCount();

    // 如果最近一次“开火事实” tick 非 0，且与当前 tick 差 <= allow，则拦截本次（第二发）
    if (g_LastShotTick[client] > 0 && (currentTick - g_LastShotTick[client]) <= allow)
    {
        // 清除按键中的 IN_ATTACK，返回 Plugin_Changed（更稳妥）
        buttons &= ~IN_ATTACK;
        buttons &= ~IN_ATTACK2;

        if (show)
        {
            char disp[64];
            GetWeaponDisplayName(wname, disp, sizeof(disp));
            PrintCenterText(client, "刷枪限制：在 %d tick 内禁止多次注册开火（%s 的第二发已被阻止）", allow, disp);
        }

        LogMessage("AntiDouble: client %d second shot blocked for %s (tick delta %d <= %d)", client, wname, currentTick - g_LastShotTick[client], allow);

        // 更新 last shot tick，避免极端连续短按产生大量提示
        g_LastShotTick[client] = currentTick;

        return Plugin_Changed;
    }

    return Plugin_Continue;
}

// ========== 地图结束/卸载清理 ==========
public void OnMapEnd()
{
    if (g_hIdleTimer != INVALID_HANDLE) { CloseHandle(g_hIdleTimer); g_hIdleTimer = INVALID_HANDLE; }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (g_hUnblockTimer[i] != INVALID_HANDLE) { CloseHandle(g_hUnblockTimer[i]); g_hUnblockTimer[i] = INVALID_HANDLE; }
        if (g_hApplyTimer[i] != INVALID_HANDLE)  { CloseHandle(g_hApplyTimer[i]);  g_hApplyTimer[i] = INVALID_HANDLE; }

        g_LastShotTick[i] = 0;
        g_ShotWindowStartTick[i] = 0;
        g_ShotCountInWindow[i] = 0;
        g_bShotBlocked[i] = false;
        g_LastDamageScaledTick[i] = 0;
    }

    PrintToServer("[ganla] OnMapEnd: 清理完成。");
}
