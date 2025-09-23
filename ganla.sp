#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <cstrike>
#include <colors>
#include <sdktools_tempents_stocks> // 提供 TE_SetupBeamRingPoint 等 stock

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
    name    = "Crouch & Idle Penalty with Weapon Restrictions + Improved Anti-DoubleTap + AFK Ring Pulse",
    author  = "ChatGPT & Optimized by Grok",
    description = "Crouch damage scale, idle punishment, weapon purchase restrictions, robust anti-double-tap (blocks 2nd shot), and AFK ring pulses",
    version = "1.6.2",
    url     = ""
};

// ========== 配置 ==========
#define CHECK_INTERVAL 1.0        // AFK检测间隔（秒）
#define MOVE_THRESHOLD 100.0      // 移动阈值（单位）
#define WARN_TIME 5               // 警告时间（秒）
#define DAMAGE_TIME 10            // 扣血时间（秒）
#define CROUCH_SCALE 0.25         // 下蹲伤害倍率
#define DEFAULT_ALLOW_DT_TICKS 5  // 双击容忍 ticks
#define DT_BLOCK_DELAY 0.2        // 双击拦截后强制延时（秒）
#define MSG_COOLDOWN_TICKS 10
#define CROUCH_MSG_COOLDOWN_TICKS 10

int g_allow_dt_ticks = DEFAULT_ALLOW_DT_TICKS;
bool g_show_msg = true;

// ========== 全局数据 ==========
float g_LastPos[MAXPLAYERS + 1][3];
int   g_IdleTime[MAXPLAYERS + 1];
int   g_TotalDeduct[MAXPLAYERS + 1];
Handle g_hIdleTimer = INVALID_HANDLE;

// Beam ring sprite indices（Model & Halo）
int g_BeamSprite = -1;
int g_HaloSprite = -1;

// 购买受限武器
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

// double-tap 关注武器
char g_DtWeapons[][] = {
    "weapon_scar20",
    "weapon_g3sg1",
    "weapon_deagle"
};

int g_LastShotTick[MAXPLAYERS + 1];
int g_LastDamageScaledTick[MAXPLAYERS + 1];
int g_LastCrouchMsgTick[MAXPLAYERS + 1];

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

static int GetCrouchReductionPercent()
{
    float reduction = (1.0 - CROUCH_SCALE) * 100.0;
    return RoundToNearest(reduction);
}

// ========== 新增：在玩家坐标生成环形脉冲 ==========
/**
 * CreateRingPulse
 * 在玩家位置生成一次 ring pulse（使用 TE_SetupBeamRingPoint）
 * 参数说明（均可调整）：
 *  - isDamage == true: 扣血阶段（更大更醒目）
 *  - isDamage == false: 警告阶段（较小且短）
 */
static void CreateRingPulse(int client, bool isDamage)
{
    if (!IsValidAliveClient(client)) return;
    if (g_BeamSprite <= 0 || g_HaloSprite <= 0) return; // 未预缓存

    float center[3];
    GetClientAbsOrigin(client, center);

    // 可把脉冲放在脚底附近或稍高（此处抬高一点避免被地面遮挡）
    center[2] += 8.0;

    float startRadius;
    float endRadius;
    float life;
    float width;
    float amplitude;
    int color[4];
    int startFrame = 0;
    int frameRate = 15;
    int speed = 0;
    int flags = 0; // 保持默认

    if (isDamage)
    {
        startRadius = 10.0;
        endRadius = 140.0; // 扣血阶段更大
        life = 0.9;
        width = 8.0;
        amplitude = 0.0;
        color[0] = 255; color[1] = 40; color[2] = 40; color[3] = 220; // 红色，alpha稍高
    }
    else
    {
        startRadius = 6.0;
        endRadius = 80.0;  // 警告阶段较小
        life = 0.6;
        width = 6.0;
        amplitude = 0.0;
        color[0] = 255; color[1] = 165; color[2] = 0; color[3] = 200; // 橙色
    }

    // 建立并发送 ring（默认广播给所有人）
    TE_SetupBeamRingPoint(center, startRadius, endRadius, g_BeamSprite, g_HaloSprite, startFrame, frameRate, life, width, amplitude, color, speed, flags);
    TE_SendToAll();

    // 如果你只想让本人看到，把上面 TE_SendToAll() 改为：
    // TE_SendToClient(client);
}

// ========== 插件初始化 ==========
public void OnPluginStart()
{
    HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);
    HookEvent("item_purchase", OnItemPurchase, EventHookMode_Post);
    HookEvent("weapon_fire", OnWeaponFire, EventHookMode_Post);

    // 预缓存 beam/halo sprite（常见路径，CS:GO 环境广泛可用）
    g_BeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt", true);
    g_HaloSprite = PrecacheModel("materials/sprites/glow01.vmt", true);

    if (g_BeamSprite <= 0 || g_HaloSprite <= 0)
    {
        PrintToServer("[ganla] 注意：无法预缓存 beam/halo sprite，环形脉冲将不可用（检查服务器是否有这些文件）");
    }
    else
    {
        PrintToServer("[ganla] Beam sprite 预缓存成功 (beam=%d, halo=%d)", g_BeamSprite, g_HaloSprite);
    }

    // 初始化定时器
    if (g_hIdleTimer == INVALID_HANDLE)
    {
        g_hIdleTimer = CreateTimer(CHECK_INTERVAL, Timer_CheckIdle, 0, TIMER_REPEAT);
    }

    // 初始化玩家数据
    for (int client = 1; client <= MaxClients; client++)
    {
        g_LastPos[client][0] = g_LastPos[client][1] = g_LastPos[client][2] = 0.0;
        g_IdleTime[client] = 0;
        g_TotalDeduct[client] = 0;
        g_LastShotTick[client] = 0;
        g_LastDamageScaledTick[client] = 0;
        g_LastCrouchMsgTick[client] = 0;
        g_ShotWindowStartTick[client] = 0;
        g_ShotCountInWindow[client] = 0;
        g_bShotBlocked[client] = false;
        g_hUnblockTimer[client] = INVALID_HANDLE;
        g_hApplyTimer[client] = INVALID_HANDLE;
        g_LastMsgTick[client] = 0;

        if (IsClientInGame(client))
        {
            SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
            SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquipPost);
            SDKHook(client, SDKHook_FireBulletsPost, FireBulletsHook);
        }
    }

    int reduction = GetCrouchReductionPercent();
    PrintToServer("[ganla] 插件加载：AFK ring 脉冲已启用。下蹲减伤 %d%%。AFK检测间隔 %.1fs。默认允许间隔 ticks = %d", reduction, CHECK_INTERVAL, g_allow_dt_ticks);
}

// ========== OnMapStart ==========
public void OnMapStart()
{
    if (g_hIdleTimer == INVALID_HANDLE)
    {
        g_hIdleTimer = CreateTimer(CHECK_INTERVAL, Timer_CheckIdle, 0, TIMER_REPEAT);
    }

    // 重新尝试预缓存（mapchange 后有时需要）
    if (g_BeamSprite <= 0 || g_HaloSprite <= 0)
    {
        g_BeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt", true);
        g_HaloSprite = PrecacheModel("materials/sprites/glow01.vmt", true);
        if (g_BeamSprite > 0 && g_HaloSprite > 0)
            PrintToServer("[ganla] OnMapStart: 重新预缓存 beam/halo 成功 (beam=%d, halo=%d)", g_BeamSprite, g_HaloSprite);
    }

    for (int client = 1; client <= MaxClients; client++)
    {
        g_LastPos[client][0] = g_LastPos[client][1] = g_LastPos[client][2] = 0.0;
        g_IdleTime[client] = 0;
        g_TotalDeduct[client] = 0;
        g_LastShotTick[client] = 0;
        g_LastDamageScaledTick[client] = 0;
        g_LastCrouchMsgTick[client] = 0;
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

        if (IsClientInGame(client))
        {
            float pos[3];
            if (IsPlayerAlive(client))
                GetClientAbsOrigin(client, pos);
            else
                pos[0] = pos[1] = pos[2] = 0.0;
            CopyVec3(pos, g_LastPos[client]);
        }
    }

    PrintToServer("[ganla] OnMapStart: 玩家状态和定时器已重置");
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
    g_TotalDeduct[client] = 0;
    g_LastShotTick[client] = 0;
    g_LastDamageScaledTick[client] = 0;
    g_LastCrouchMsgTick[client] = 0;
    g_ShotWindowStartTick[client] = 0;
    g_ShotCountInWindow[client] = 0;
    g_bShotBlocked[client] = false;
    g_hUnblockTimer[client] = INVALID_HANDLE;
    g_hApplyTimer[client] = INVALID_HANDLE;
    g_LastMsgTick[client] = 0;
}

public void OnClientDisconnect(int client)
{
    SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    SDKUnhook(client, SDKHook_WeaponEquipPost, OnWeaponEquipPost);
    SDKUnhook(client, SDKHook_FireBulletsPost, FireBulletsHook);

    g_LastPos[client][0] = g_LastPos[client][1] = g_LastPos[client][2] = 0.0;
    g_IdleTime[client] = 0;
    g_TotalDeduct[client] = 0;
    g_LastShotTick[client] = 0;
    g_LastDamageScaledTick[client] = 0;
    g_LastCrouchMsgTick[client] = 0;
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
        g_TotalDeduct[client] = 0;
        g_LastShotTick[client] = 0;
        g_LastDamageScaledTick[client] = 0;
        g_LastCrouchMsgTick[client] = 0;
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

// ========== RunCmd：即时下蹲提示 + 双击检测 ==========
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if (!IsValidAliveClient(client)) return Plugin_Continue;

    int currentTick = GetGameTickCount();

    if (GetClientButtons(client) & IN_DUCK)
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

    // 双击拦截逻辑（保持原样）
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

// ========== 每 CHECK_INTERVAL 秒检测：挂机惩罚 & 武器移除（下蹲提示移到RunCmd） ==========
public Action Timer_CheckIdle(Handle timer, any data)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidAliveClient(client)) continue;

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

                // 警告阶段：每秒产生一个较弱的发光脉冲 / 环形脉冲
                CreateRingPulse(client, false);
            }

            if (g_IdleTime[client] >= DAMAGE_TIME)
            {
                int hp = GetClientHealth(client);
                bool deducted = false;
                if (hp > 1)
                {
                    SetEntityHealth(client, hp - 1);
                    g_TotalDeduct[client]++;  // 仅实际扣血时增加
                    deducted = true;
                    LogMessage("AFK Deduct: client %d HP %d -> %d (total deduct now %d)", client, hp, hp-1, g_TotalDeduct[client]);
                }

                // 扣血阶段：使用更明显的脉冲
                CreateRingPulse(client, true);

                if (hp > 1 || !deducted)
                {
                    if (hp <= 1)
                    {
                        PrintCenterText(client, "您已被扣除 %d 血，血量已最低，继续不动将死亡！", g_TotalDeduct[client]);
                    }
                    else
                    {
                        PrintCenterText(client, "您已被扣除 %d 血，继续不动将持续扣血！", g_TotalDeduct[client]);
                    }
                }
            }
        }
        else
        {
            // 移动时重置
            if (g_IdleTime[client] > 0)
            {
                g_IdleTime[client] = 0;
                g_TotalDeduct[client] = 0;
                // 修复：确保格式字符串的占位符与实际参数一致（之前少传 client 导致异常）
                LogMessage("AFK Reset: client %d moved, total deduct reset to 0", client);
            }
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
    if (g_hIdleTimer != INVALID_HANDLE)
    {
        CloseHandle(g_hIdleTimer);
        g_hIdleTimer = INVALID_HANDLE;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
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

        g_LastPos[i][0] = g_LastPos[i][1] = g_LastPos[i][2] = 0.0;
        g_IdleTime[i] = 0;
        g_TotalDeduct[i] = 0;
        g_LastShotTick[i] = 0;
        g_LastDamageScaledTick[i] = 0;
        g_LastCrouchMsgTick[i] = 0;
        g_ShotWindowStartTick[i] = 0;
        g_ShotCountInWindow[i] = 0;
        g_bShotBlocked[i] = false;
        g_LastMsgTick[i] = 0;
    }

    PrintToServer("[ganla] OnMapEnd: 清理完成。");
}
