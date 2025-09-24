#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <cstrike>
#include <sdktools_tempents_stocks> // 提供 TE_SetupBeamRingPoint 等 stock

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
    name    = "Anti-AFK with Ring Pulse",
    author  = "ChatGPT & Optimized by Grok",
    description = "Idle punishment and AFK ring pulses",
    version = "1.0.0",
    url     = ""
};

// ========== 配置 ==========
#define CHECK_INTERVAL 1.0        // AFK检测间隔（秒）
#define MOVE_THRESHOLD 100.0      // 移动阈值（单位）
#define WARN_TIME 5               // 警告时间（秒）
#define DAMAGE_TIME 10            // 扣血时间（秒）

// ========== 全局数据 ==========
float g_LastPos[MAXPLAYERS + 1][3];
int   g_IdleTime[MAXPLAYERS + 1];
int   g_TotalDeduct[MAXPLAYERS + 1];
Handle g_hIdleTimer = INVALID_HANDLE;

// Beam ring sprite indices（Model & Halo）
int g_BeamSprite = -1;
int g_HaloSprite = -1;

// ========== 工具函数 ==========
static bool IsValidAliveClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client));
}

static void CopyVec3(const float src[3], float dest[3])
{
    dest[0] = src[0]; dest[1] = src[1]; dest[2] = src[2];
}

// ========== 新增：在玩家坐标生成环形脉冲 ==========
static void CreateRingPulse(int client, bool isDamage)
{
    if (!IsValidAliveClient(client)) return;
    if (g_BeamSprite <= 0 || g_HaloSprite <= 0) return;

    float center[3];
    GetClientAbsOrigin(client, center);
    center[2] += 8.0;

    float startRadius, endRadius, life, width, amplitude;
    int color[4];
    int startFrame = 0;
    int frameRate = 15;
    int speed = 0;
    int flags = 0;

    if (isDamage)
    {
        startRadius = 10.0;
        endRadius = 140.0;
        life = 0.9;
        width = 8.0;
        amplitude = 0.0;
        color[0] = 255; color[1] = 40; color[2] = 40; color[3] = 220;
    }
    else
    {
        startRadius = 6.0;
        endRadius = 80.0;
        life = 0.6;
        width = 6.0;
        amplitude = 0.0;
        color[0] = 255; color[1] = 165; color[2] = 0; color[3] = 200;
    }

    TE_SetupBeamRingPoint(center, startRadius, endRadius, g_BeamSprite, g_HaloSprite, startFrame, frameRate, life, width, amplitude, color, speed, flags);
    TE_SendToAll();
}

// ========== 插件初始化 ==========
public void OnPluginStart()
{
    HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);

    g_BeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt", true);
    g_HaloSprite = PrecacheModel("materials/sprites/glow01.vmt", true);

    if (g_BeamSprite <= 0 || g_HaloSprite <= 0)
    {
        PrintToServer("[anti_afk] 注意：无法预缓存 beam/halo sprite，环形脉冲将不可用");
    }
    else
    {
        PrintToServer("[anti_afk] Beam sprite 预缓存成功 (beam=%d, halo=%d)", g_BeamSprite, g_HaloSprite);
    }

    if (g_hIdleTimer == INVALID_HANDLE)
    {
        g_hIdleTimer = CreateTimer(CHECK_INTERVAL, Timer_CheckIdle, 0, TIMER_REPEAT);
    }

    for (int client = 1; client <= MaxClients; client++)
    {
        g_LastPos[client][0] = g_LastPos[client][1] = g_LastPos[client][2] = 0.0;
        g_IdleTime[client] = 0;
        g_TotalDeduct[client] = 0;

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

    PrintToServer("[anti_afk] 插件加载：AFK ring 脉冲已启用。检测间隔 %.1fs", CHECK_INTERVAL);
}

// ========== OnMapStart ==========
public void OnMapStart()
{
    if (g_hIdleTimer == INVALID_HANDLE)
    {
        g_hIdleTimer = CreateTimer(CHECK_INTERVAL, Timer_CheckIdle, 0, TIMER_REPEAT);
    }

    if (g_BeamSprite <= 0 || g_HaloSprite <= 0)
    {
        g_BeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt", true);
        g_HaloSprite = PrecacheModel("materials/sprites/glow01.vmt", true);
        if (g_BeamSprite > 0 && g_HaloSprite > 0)
            PrintToServer("[anti_afk] OnMapStart: 重新预缓存 beam/halo 成功");
    }

    for (int client = 1; client <= MaxClients; client++)
    {
        g_LastPos[client][0] = g_LastPos[client][1] = g_LastPos[client][2] = 0.0;
        g_IdleTime[client] = 0;
        g_TotalDeduct[client] = 0;

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

    PrintToServer("[anti_afk] OnMapStart: 玩家状态和定时器已重置");
}

// ========== 客户端生命周期钩子 ==========
public void OnClientPutInServer(int client)
{
    float pos[3];
    if (IsClientInGame(client) && IsPlayerAlive(client))
        GetClientAbsOrigin(client, pos);
    else
        pos[0] = pos[1] = pos[2] = 0.0;

    CopyVec3(pos, g_LastPos[client]);
    g_IdleTime[client] = 0;
    g_TotalDeduct[client] = 0;
}

public void OnClientDisconnect(int client)
{
    g_LastPos[client][0] = g_LastPos[client][1] = g_LastPos[client][2] = 0.0;
    g_IdleTime[client] = 0;
    g_TotalDeduct[client] = 0;
}

public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !IsClientInGame(client)) return;

    float pos[3];
    GetClientAbsOrigin(client, pos);
    CopyVec3(pos, g_LastPos[client]);
    g_IdleTime[client] = 0;
    g_TotalDeduct[client] = 0;
}

// ========== 每 CHECK_INTERVAL 秒检测：挂机惩罚 ==========
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
                CreateRingPulse(client, false);
            }

            if (g_IdleTime[client] >= DAMAGE_TIME)
            {
                int hp = GetClientHealth(client);
                bool deducted = false;
                if (hp > 1)
                {
                    SetEntityHealth(client, hp - 1);
                    g_TotalDeduct[client]++;
                    deducted = true;
                    LogMessage("AFK Deduct: client %d HP %d -> %d (total deduct now %d)", client, hp, hp-1, g_TotalDeduct[client]);
                }

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
            if (g_IdleTime[client] > 0)
            {
                g_IdleTime[client] = 0;
                g_TotalDeduct[client] = 0;
                LogMessage("AFK Reset: client %d moved, total deduct reset to 0", client);
            }
        }

        CopyVec3(pos, g_LastPos[client]);
    }

    return Plugin_Continue;
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
        g_LastPos[i][0] = g_LastPos[i][1] = g_LastPos[i][2] = 0.0;
        g_IdleTime[i] = 0;
        g_TotalDeduct[i] = 0;
    }

    PrintToServer("[anti_afk] OnMapEnd: 清理完成。");
}