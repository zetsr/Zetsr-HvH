#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <colors>
#include <menus>
#include <dbi>
#include <cstrike>

#define PLUGIN_VERSION "1.0"

#define GUILD_NAME_MAX_LENGTH 10 // 行会名称最大字符长度
#define CONFIRMATION_TIMEOUT 10.0 // 确认操作的超时时间（秒）

// --- 全局变量 --- //
Database g_hDatabase = null;
char g_sChatPrefix[] = "{lime}新曙光 - {default}"; // 统一的聊天消息前缀
bool g_bDatabaseConnected = false; // 数据库是否已连接成功

// 玩家状态追踪
bool g_bIsCreatingGuild[MAXPLAYERS + 1];      // 玩家是否正在输入行会名称
bool g_bIsConfirmingLeave[MAXPLAYERS + 1];    // 玩家是否正在确认退出行会
bool g_bIsConfirmingDisband[MAXPLAYERS + 1];  // 玩家是否正在确认解散行会
bool g_bIsInvitingPlayer[MAXPLAYERS + 1];     // 玩家是否正在邀请其他玩家
Handle g_hConfirmationTimer[MAXPLAYERS + 1];   // 用于超时取消操作的计时器
Handle g_hClanTagTimer[MAXPLAYERS + 1];        // 用于持续设置战队标签的计时器

// 玩家数据缓存 (避免频繁查询数据库)
int g_iPlayerGuildID[MAXPLAYERS + 1];         // 玩家所属行会的ID (0为无)
char g_sPlayerGuildName[MAXPLAYERS + 1][64];  // 玩家所属行会的名称
int g_iPlayerScore[MAXPLAYERS + 1];           // 玩家的个人分数
bool g_bIsPlayerGuildOwner[MAXPLAYERS + 1];   // 玩家是否是行会所有者
bool g_bPlayerDataLoaded[MAXPLAYERS + 1];     // 玩家数据是否已加载完成
bool g_bPlayerHasGuildInDB[MAXPLAYERS + 1];   // 玩家在数据库中是否有行会（安全验证）

// 行会设置缓存
bool g_bGuildAllowMemberInvite[MAXPLAYERS + 1]; // 行会是否允许成员邀请

// --- 自定义函数声明 --- //
stock void SetEntityTribe(int client, const char[] tribeName)
{
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
        return;
    
    if (strlen(tribeName) > 0)
    {
        // 设置玩家战队标签
        CS_SetClientClanTag(client, tribeName);
    }
    else
    {
        // 清除战队标签
        CS_SetClientClanTag(client, "");
    }
}

/**
 * 将单引号转义（' => ''），用来安全地把字符串放进 SQL 字面量中
 */
void EscapeSQL(const char[] src, char[] dest, int destLen)
{
    int j = 0;
    for (int i = 0; src[i] != '\0' && j < destLen - 1; i++)
    {
        if (src[i] == '\'')
        {
            // 需要额外空间插入第二个单引号
            if (j + 2 >= destLen) break;
            dest[j++] = '\'';
            dest[j++] = '\'';
        }
        else
        {
            dest[j++] = src[i];
        }
    }
    dest[j] = '\0';
}

// 持续设置战队标签的计时器函数
public Action Timer_SetClanTag(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client > 0 && IsClientInGame(client) && g_iPlayerGuildID[client] > 0)
    {
        SetEntityTribe(client, g_sPlayerGuildName[client]);
        return Plugin_Continue;
    }
    
    g_hClanTagTimer[client] = null;
    return Plugin_Stop;
}

public Plugin myinfo =
{
    name = "Guild System",
    author = "Gemini",
    description = "A comprehensive guild system with MySQL support.",
    version = PLUGIN_VERSION,
    url = "https://www.google.com"
};

// --- 插件核心函数 --- //

public void OnPluginStart()
{
    // 注册命令
    RegConsoleCmd("sm_g", Command_OpenGuildMenu, "打开行会菜单");
    RegConsoleCmd("sm_guild", Command_OpenGuildMenu, "打开行会菜单");
    RegConsoleCmd("say", Command_Say);
    RegConsoleCmd("say_team", Command_Say);
    RegConsoleCmd("sm_y", Command_ConfirmAction, "确认操作");

    // 挂钩事件
    HookEvent("round_end", Event_RoundEnd, EventHookMode_Post);
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    
    // 连接数据库
    ConnectToDatabase();
}

public void OnPluginEnd()
{
    // 插件关闭时断开数据库连接，虽然通常用不到，但是个好习惯
    if (g_hDatabase != null)
    {
        delete g_hDatabase;
    }
    
    // 清除所有计时器
    for (int i = 1; i <= MaxClients; i++)
    {
        if (g_hConfirmationTimer[i] != null)
        {
            KillTimer(g_hConfirmationTimer[i]);
            g_hConfirmationTimer[i] = null;
        }
        if (g_hClanTagTimer[i] != null)
        {
            KillTimer(g_hClanTagTimer[i]);
            g_hClanTagTimer[i] = null;
        }
    }
}

public void OnClientPutInServer(int client)
{
    // 玩家进入服务器时，加载他们的行会数据
    // 使用计时器延迟执行，确保玩家完全加载
    g_bPlayerDataLoaded[client] = false; // 标记数据未加载
    g_bPlayerHasGuildInDB[client] = false; // 重置数据库验证标记
    
    // 只有在数据库连接成功后才会加载数据
    if (g_bDatabaseConnected)
    {
        CreateTimer(1.0, Timer_LoadPlayerData, GetClientUserId(client));
    }
}

public void OnClientDisconnect(int client)
{
    // 玩家离开时，清除他们的缓存和状态
    ClearPlayerData(client);
}

// --- 数据库相关 --- //

void ConnectToDatabase()
{
    // 从 databases.cfg 读取名为 "guild_system" 的配置
    Database.Connect(OnDatabaseConnected, "guild_system");
}

public void OnDatabaseConnected(Database db, const char[] error, any data)
{
    if (db == null)
    {
        LogError("数据库连接失败: %s", error);
        return;
    }
    
    LogMessage("数据库连接成功！");
    g_hDatabase = db;
    g_bDatabaseConnected = true;

    // 设置字符集为 utf8mb4，完美支持中文和表情符号
    g_hDatabase.SetCharset("utf8mb4");

    // 创建数据表 (如果不存在的话)
    // 这种设计可以确保插件在第一次加载时自动完成初始化，非常方便
    char query[1024];

    // 将创建 guilds 表的 SQL 语句合并为一行
    FormatEx(query, sizeof(query), "CREATE TABLE IF NOT EXISTS `guilds` (`id` INT NOT NULL AUTO_INCREMENT, `name` VARCHAR(64) NOT NULL UNIQUE, `owner_steamid` VARCHAR(32) NOT NULL, `creation_date` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, `allow_member_invite` BOOLEAN NOT NULL DEFAULT FALSE, PRIMARY KEY (`id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
    g_hDatabase.Query(OnTableCreated, query);

    // 将创建 players 表的 SQL 语句合并为一行
    FormatEx(query, sizeof(query), "CREATE TABLE IF NOT EXISTS `players` (`steamid` VARCHAR(32) NOT NULL UNIQUE, `name` VARCHAR(64) NOT NULL, `score` INT NOT NULL DEFAULT 0, `guild_id` INT DEFAULT NULL, PRIMARY KEY (`steamid`), FOREIGN KEY (`guild_id`) REFERENCES `guilds`(`id`) ON DELETE SET NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
    g_hDatabase.Query(OnTableCreated, query);
    
    // 为所有已连接的玩家加载数据
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            CreateTimer(0.5, Timer_LoadPlayerData, GetClientUserId(i));
        }
    }
}

public void OnTableCreated(Database owner, DBResultSet results, const char[] error, any data)
{
    if (results == null)
    {
        LogError("创建数据表失败: %s", error);
    }
    else
    {
        // 表创建成功后，尝试添加缺失的列（使用更兼容的语法）
        char query[512];
        FormatEx(query, sizeof(query), "ALTER TABLE `guilds` ADD COLUMN `allow_member_invite` BOOLEAN NOT NULL DEFAULT FALSE");
        g_hDatabase.Query(OnAlterTable, query);
    }
}

public void OnAlterTable(Database owner, DBResultSet results, const char[] error, any data)
{
    if (results == null && error[0] != '\0')
    {
        // 如果列已经存在，可能会报错，这是正常的
        if (StrContains(error, "duplicate") == -1 && StrContains(error, "exists") == -1 && 
            StrContains(error, "1060") == -1) // 1060是MySQL的重复列错误代码
        {
            LogError("修改表结构失败: %s", error);
        }
        else
        {
            LogMessage("列已存在，无需添加");
        }
    }
}

// 加载玩家数据
public Action Timer_LoadPlayerData(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0 || !IsClientInGame(client) || !g_bDatabaseConnected || g_hDatabase == null)
    {
        return Plugin_Stop;
    }
    
    ClearPlayerData(client); // 先清空旧数据

    char steamId[32];
    GetClientAuthId(client, AuthId_SteamID64, steamId, sizeof(steamId));

    // 使用自定义的EscapeSQL函数而不是Database.Escape，避免数据库句柄问题
    char escapedName[MAX_NAME_LENGTH * 2 + 1];
    char playerName[MAX_NAME_LENGTH];
    GetClientName(client, playerName, sizeof(playerName));
    EscapeSQL(playerName, escapedName, sizeof(escapedName));

    // 使用 INSERT ... ON DUPLICATE KEY UPDATE 语句，这是一个非常高效的技巧
    // 如果玩家是第一次来，就插入新记录；如果是老玩家，就更新他的名字
    char query[512];
    FormatEx(query, sizeof(query), "INSERT INTO `players` (steamid, name, score) VALUES ('%s', '%s', 0) ON DUPLICATE KEY UPDATE name = '%s';", steamId, escapedName, escapedName);
    
    g_hDatabase.Query(OnPlayerUpserted, query, GetClientUserId(client));
    return Plugin_Stop;
}

public void OnPlayerUpserted(Database owner, DBResultSet results, const char[] error, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0) return;

    if (results == null) {
        LogError("更新或插入玩家数据失败 for %d: %s", client, error);
        // 如果失败，5秒后重试
        CreateTimer(5.0, Timer_RetryLoadPlayerData, userid);
        return;
    }

    // 现在正式查询玩家的详细数据
    char steamId[32];
    GetClientAuthId(client, AuthId_SteamID64, steamId, sizeof(steamId));

    char query[1024];
    FormatEx(query, sizeof(query), "SELECT p.score, p.guild_id, g.name, g.owner_steamid, g.allow_member_invite FROM `players` p LEFT JOIN `guilds` g ON p.guild_id = g.id WHERE p.steamid = '%s';", steamId);

    g_hDatabase.Query(OnPlayerDataLoaded, query, GetClientUserId(client));
}

// 重试加载玩家数据
public Action Timer_RetryLoadPlayerData(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client > 0 && IsClientInGame(client) && g_bDatabaseConnected)
    {
        CreateTimer(1.0, Timer_LoadPlayerData, userid);
    }
    return Plugin_Stop;
}

public void OnPlayerDataLoaded(Database owner, DBResultSet results, const char[] error, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0) return;
    
    if (results == null || !results.FetchRow())
    {
        if (error[0] != '\0') 
        {
            // 检查是否是缺少列的错误
            if (StrContains(error, "allow_member_invite") != -1)
            {
                // 如果是缺少列的错误，使用备用查询（不包含新列）
                char steamId[32];
                GetClientAuthId(client, AuthId_SteamID64, steamId, sizeof(steamId));
                
                char query[1024];
                FormatEx(query, sizeof(query), "SELECT p.score, p.guild_id, g.name, g.owner_steamid FROM `players` p LEFT JOIN `guilds` g ON p.guild_id = g.id WHERE p.steamid = '%s';", steamId);
                
                g_hDatabase.Query(OnPlayerDataLoadedFallback, query, GetClientUserId(client));
                return;
            }
            
            LogError("加载玩家数据失败 for %d: %s", client, error);
            // 如果失败，5秒后重试
            CreateTimer(5.0, Timer_RetryLoadPlayerData, userid);
        }
        return;
    }
    
    g_iPlayerScore[client] = results.FetchInt(0);
    g_iPlayerGuildID[client] = results.FetchInt(1);

    if (g_iPlayerGuildID[client] > 0)
    {
        results.FetchString(2, g_sPlayerGuildName[client], sizeof(g_sPlayerGuildName[]));
        
        char ownerSteamId[32];
        results.FetchString(3, ownerSteamId, sizeof(ownerSteamId));
        
        char playerSteamId[32];
        GetClientAuthId(client, AuthId_SteamID64, playerSteamId, sizeof(playerSteamId));

        g_bIsPlayerGuildOwner[client] = (StrEqual(ownerSteamId, playerSteamId));
        
        // 尝试获取新列，如果不存在则使用默认值
        if (results.FieldCount > 4)
        {
            g_bGuildAllowMemberInvite[client] = view_as<bool>(results.FetchInt(4));
        }
        else
        {
            g_bGuildAllowMemberInvite[client] = false;
        }
        
        g_bPlayerHasGuildInDB[client] = true; // 标记玩家在数据库中有行会

        // 设置玩家的战队标签
        SetEntityTribe(client, g_sPlayerGuildName[client]);
        
        // 启动持续设置战队标签的计时器
        if (g_hClanTagTimer[client] == null)
        {
            g_hClanTagTimer[client] = CreateTimer(1.0, Timer_SetClanTag, GetClientUserId(client), TIMER_REPEAT);
        }
    }
    else
    {
        // 玩家没有行会，清除战队标签
        SetEntityTribe(client, "");
        g_bPlayerHasGuildInDB[client] = false;
    }
    
    // 标记数据已加载完成
    g_bPlayerDataLoaded[client] = true;
}

// 备用数据加载回调（用于处理缺少新列的情况）
public void OnPlayerDataLoadedFallback(Database owner, DBResultSet results, const char[] error, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0) return;
    
    if (results == null || !results.FetchRow())
    {
        if (error[0] != '\0') 
        {
            LogError("备用加载玩家数据失败 for %d: %s", client, error);
        }
        return;
    }
    
    g_iPlayerScore[client] = results.FetchInt(0);
    g_iPlayerGuildID[client] = results.FetchInt(1);

    if (g_iPlayerGuildID[client] > 0)
    {
        results.FetchString(2, g_sPlayerGuildName[client], sizeof(g_sPlayerGuildName[]));
        
        char ownerSteamId[32];
        results.FetchString(3, ownerSteamId, sizeof(ownerSteamId));
        
        char playerSteamId[32];
        GetClientAuthId(client, AuthId_SteamID64, playerSteamId, sizeof(playerSteamId));

        g_bIsPlayerGuildOwner[client] = (StrEqual(ownerSteamId, playerSteamId));
        g_bGuildAllowMemberInvite[client] = false; // 使用默认值
        g_bPlayerHasGuildInDB[client] = true;

        // 设置玩家的战队标签
        SetEntityTribe(client, g_sPlayerGuildName[client]);
        
        // 启动持续设置战队标签的计时器
        if (g_hClanTagTimer[client] == null)
        {
            g_hClanTagTimer[client] = CreateTimer(1.0, Timer_SetClanTag, GetClientUserId(client), TIMER_REPEAT);
        }
    }
    else
    {
        // 玩家没有行会，清除战队标签
        SetEntityTribe(client, "");
        g_bPlayerHasGuildInDB[client] = false;
    }
    
    // 标记数据已加载完成
    g_bPlayerDataLoaded[client] = true;
}

// --- 事件处理 --- //

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && IsClientInGame(client) && g_iPlayerGuildID[client] > 0)
    {
        // 玩家重生时重新设置战队标签
        SetEntityTribe(client, g_sPlayerGuildName[client]);
    }
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    int winner = event.GetInt("winner"); // 2 for T, 3 for CT
    // 只要不是平局，就给所有玩家加分
    if (winner == 2 || winner == 3)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && !IsFakeClient(i))
            {
                g_iPlayerScore[i]++; // 先更新缓存
                
                // 然后更新数据库
                char steamId[32];
                GetClientAuthId(i, AuthId_SteamID64, steamId, sizeof(steamId));
                
                char query[256];
                // 使用 `score = score + 1` 来避免多服务器同时操作时的数据覆盖问题
                FormatEx(query, sizeof(query), "UPDATE `players` SET `score` = `score` + 1 WHERE `steamid` = '%s';", steamId);
                
                // 使用空回调函数而不是 null
                if (g_bDatabaseConnected && g_hDatabase != null)
                {
                    g_hDatabase.Query(SQL_CheckForErrors, query);
                }
            }
        }
    }
}

// 空回调函数用于处理不需要特殊处理的查询
public void SQL_CheckForErrors(Database db, DBResultSet results, const char[] error, any data)
{
    if (results == null && error[0] != '\0')
    {
        LogError("SQL查询错误: %s", error);
    }
}

// --- 命令处理 --- //

public Action Command_OpenGuildMenu(int client, int args)
{
    if (!g_bPlayerDataLoaded[client])
    {
        CPrintToChat(client, "%s {red}数据正在加载中，请稍候...", g_sChatPrefix);
        return Plugin_Handled;
    }
    
    DisplayMainMenu(client);
    return Plugin_Handled;
}

public Action Command_Say(int client, int args)
{
    // 获取玩家发送的完整消息
    char text[192];
    GetCmdArgString(text, sizeof(text));
    // 去掉消息两边的引号
    StripQuotes(text);

    // 检查是否是正在创建行会的状态
    if (g_bIsCreatingGuild[client])
    {
        // 取消计时器，因为玩家已经输入了
        if (g_hConfirmationTimer[client] != null)
        {
            KillTimer(g_hConfirmationTimer[client]);
            g_hConfirmationTimer[client] = null;
        }

        g_bIsCreatingGuild[client] = false; // 重置状态
        HandleGuildCreation(client, text);
        return Plugin_Handled; // 阻止消息发送到公屏
    }

    return Plugin_Continue;
}

public Action Command_ConfirmAction(int client, int args)
{
    if (g_bIsConfirmingLeave[client])
    {
        // 取消计时器
        if (g_hConfirmationTimer[client] != null)
        {
            KillTimer(g_hConfirmationTimer[client]);
            g_hConfirmationTimer[client] = null;
        }
        g_bIsConfirmingLeave[client] = false; // 重置状态
        HandleLeaveGuild(client);
    }
    else if (g_bIsConfirmingDisband[client])
    {
        // 取消计时器
        if (g_hConfirmationTimer[client] != null)
        {
            KillTimer(g_hConfirmationTimer[client]);
            g_hConfirmationTimer[client] = null;
        }
        g_bIsConfirmingDisband[client] = false; // 重置状态
        HandleDisbandGuild(client);
    }
    else
    {
        CPrintToChat(client, "%s {default}当前没有需要您确认的操作。", g_sChatPrefix);
    }
    
    return Plugin_Handled;
}

// --- 菜单系统 --- //

void DisplayMainMenu(int client)
{
    if (!g_bPlayerDataLoaded[client])
    {
        CPrintToChat(client, "%s {red}数据正在加载中，请稍候...", g_sChatPrefix);
        return;
    }
    
    char title[128];
    char playerName[MAX_NAME_LENGTH];
    GetClientName(client, playerName, sizeof(playerName));

    if (g_iPlayerGuildID[client] > 0)
    {
        FormatEx(title, sizeof(title), "%s [%s]", playerName, g_sPlayerGuildName[client]);
    }
    else
    {
        FormatEx(title, sizeof(title), "%s [无行会]", playerName);
    }

    Menu menu = new Menu(MainMenuHandler);
    menu.SetTitle(title);
    
    // 如果不在行会里，"我的行会"选项是禁用的，这很酷
    menu.AddItem("my_guild", "我的行会", g_iPlayerGuildID[client] > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    menu.AddItem("create_guild", "创建行会", (g_iPlayerGuildID[client] > 0 || !g_bPlayerDataLoaded[client]) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
    menu.AddItem("all_guilds", "所有行会");
    
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MainMenuHandler(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(item, info, sizeof(info));
        
        if (StrEqual(info, "my_guild"))
        {
            DisplayMyGuildMenu(client);
        }
        else if (StrEqual(info, "create_guild"))
        {
            if (g_iPlayerGuildID[client] > 0 || !g_bPlayerDataLoaded[client])
            {
                CPrintToChat(client, "%s {default}您已经在一个行会里了，不能创建新的。", g_sChatPrefix);
                return 0;
            }
            
            // 双重安全检查：验证数据库中的实际状态
            VerifyPlayerGuildStatus(client);
        }
        else if (StrEqual(info, "all_guilds"))
        {
            DisplayAllGuildsMenu(client, 0); // 从第一页开始显示
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    return 0;
}

// 双重安全验证：检查玩家在数据库中的实际行会状态
void VerifyPlayerGuildStatus(int client)
{
    char steamId[32];
    GetClientAuthId(client, AuthId_SteamID64, steamId, sizeof(steamId));
    
    char query[256];
    FormatEx(query, sizeof(query), "SELECT guild_id FROM players WHERE steamid = '%s';", steamId);
    
    g_hDatabase.Query(OnGuildStatusVerified, query, GetClientUserId(client));
}

public void OnGuildStatusVerified(Database owner, DBResultSet results, const char[] error, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0) return;

    if (results == null)
    {
        LogError("验证玩家行会状态失败: %s", error);
        CPrintToChat(client, "%s {red}验证失败，请稍后再试。", g_sChatPrefix);
        return;
    }
    
    if (results.FetchRow())
    {
        int dbGuildId = results.FetchInt(0);
        
        if (dbGuildId > 0)
        {
            // 数据库显示玩家有行会，但本地缓存没有 - 重新加载数据
            CPrintToChat(client, "%s {red}检测到数据不一致，正在重新加载...", g_sChatPrefix);
            CreateTimer(1.0, Timer_LoadPlayerData, userid);
            return;
        }
    }
    
    // 数据库确认玩家没有行会，允许创建
    g_bIsCreatingGuild[client] = true;
    g_hConfirmationTimer[client] = CreateTimer(CONFIRMATION_TIMEOUT, Timer_CancelGuildCreation, GetClientUserId(client));
    CPrintToChat(client, "%s {default}请在聊天框输入您想要的行会名称 (10秒内)", g_sChatPrefix);
}

void DisplayMyGuildMenu(int client)
{
    if (!g_bPlayerDataLoaded[client])
    {
        CPrintToChat(client, "%s {red}数据正在加载中，请稍候...", g_sChatPrefix);
        return;
    }
    
    // 这个菜单的标题信息量巨大，需要进行多次数据库查询
    // 为了不让代码阻塞，我们采用回调地狱...啊不，是异步查询的方式
    // 1. 获取行会成员数
    char query[256];
    FormatEx(query, sizeof(query), "SELECT COUNT(*) FROM `players` WHERE `guild_id` = %d;", g_iPlayerGuildID[client]);
    g_hDatabase.Query(OnMemberCountReady, query, GetClientUserId(client));
}

// 异步回调链，一步一步获取数据来构建菜单标题
public void OnMemberCountReady(Database owner, DBResultSet results, const char[] error, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0) return;

    if (results == null || !results.FetchRow())
    {
        CPrintToChat(client, "%s {red}错误：无法获取行会成员信息。", g_sChatPrefix);
        return;
    }
    
    int memberCount = results.FetchInt(0);
    
    // 2. 获取玩家在行会内的排名
    char query[256];
    FormatEx(query, sizeof(query), "SELECT COUNT(*) + 1 FROM `players` WHERE `guild_id` = %d AND `score` > %d;", g_iPlayerGuildID[client], g_iPlayerScore[client]);
    
    // 把上一步的结果(成员数)传给下一步
    DataPack pack = new DataPack();
    pack.WriteCell(userid);
    pack.WriteCell(memberCount);
    
    g_hDatabase.Query(OnPlayerRankReady, query, pack);
}

public void OnPlayerRankReady(Database owner, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userid = pack.ReadCell();
    int memberCount = pack.ReadCell();
    delete pack;
    
    int client = GetClientOfUserId(userid);
    if (client == 0) return;

    if (results == null || !results.FetchRow())
    {
        CPrintToChat(client, "%s {red}错误：无法获取玩家排名信息。", g_sChatPrefix);
        return;
    }

    int playerRank = results.FetchInt(0);
    
    // 3. 获取行会总分，为计算全服排名做准备
    char query[256];
    FormatEx(query, sizeof(query), "SELECT SUM(score) FROM `players` WHERE `guild_id` = %d;", g_iPlayerGuildID[client]);
    
    // 把之前的结果都传给下一步
    DataPack newPack = new DataPack();
    newPack.WriteCell(userid);
    newPack.WriteCell(playerRank);
    newPack.WriteCell(memberCount);
    
    g_hDatabase.Query(OnGuildScoreReady, query, newPack);
}

public void OnGuildScoreReady(Database owner, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userid = pack.ReadCell();
    int playerRank = pack.ReadCell();
    int memberCount = pack.ReadCell();
    delete pack;
    
    int client = GetClientOfUserId(userid);
    if (client == 0) return;

    if (results == null || !results.FetchRow())
    {
        CPrintToChat(client, "%s {red}错误：无法获取行会分数信息。", g_sChatPrefix);
        return;
    }

    // 这里我们不再使用 guildScore 变量，直接使用结果
    int guildScore = results.FetchInt(0);

    // 4. 计算行会全服排名
    char query[512];
    FormatEx(query, sizeof(query), "SELECT COUNT(*) + 1 FROM (SELECT SUM(score) AS total_score FROM `players` WHERE `guild_id` IS NOT NULL GROUP BY `guild_id`) AS guild_scores WHERE total_score > %d;", guildScore);

    DataPack newPack = new DataPack();
    newPack.WriteCell(userid);
    newPack.WriteCell(playerRank);
    newPack.WriteCell(memberCount);
    
    g_hDatabase.Query(OnGuildRankReady, query, newPack);
}

public void OnGuildRankReady(Database owner, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userid = pack.ReadCell();
    int playerRank = pack.ReadCell();
    int memberCount = pack.ReadCell();
    delete pack;
    
    int client = GetClientOfUserId(userid);
    if (client == 0) return;
    
    if (results == null || !results.FetchRow())
    {
        CPrintToChat(client, "%s {red}错误：无法获取行会排名信息。", g_sChatPrefix);
        return;
    }

    int guildRank = results.FetchInt(0);

    // 所有数据都到齐了！开始构建菜单
    char title[256];
    FormatEx(title, sizeof(title), "个人排名: %d | 行会排名: %d (%d人)", playerRank, guildRank, memberCount);

    Menu menu = new Menu(MyGuildMenuHandler);
    menu.SetTitle(title);

    menu.AddItem("members", "行会成员");
    menu.AddItem("invite", "邀请玩家");
    
    // 行会所有者不能退出，只能解散
    menu.AddItem("leave", "退出行会", g_bIsPlayerGuildOwner[client] ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
    
    // 只有行会所有者能解散和设置
    menu.AddItem("settings", "行会设置", g_bIsPlayerGuildOwner[client] ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    menu.AddItem("disband", "解散行会", g_bIsPlayerGuildOwner[client] ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MyGuildMenuHandler(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(item, info, sizeof(info));
        
        if (StrEqual(info, "members"))
        {
            DisplayGuildMembersMenu(client, 0);
        }
        else if (StrEqual(info, "invite"))
        {
            // 检查权限
            if (!g_bIsPlayerGuildOwner[client] && !g_bGuildAllowMemberInvite[client])
            {
                CPrintToChat(client, "%s {red}您没有权限邀请玩家加入行会。", g_sChatPrefix);
                DisplayMyGuildMenu(client);
                return 0;
            }
            DisplayInviteMenu(client);
        }
        else if (StrEqual(info, "leave"))
        {
            g_bIsConfirmingLeave[client] = true;
            g_hConfirmationTimer[client] = CreateTimer(CONFIRMATION_TIMEOUT, Timer_CancelLeaveConfirmation, GetClientUserId(client));
            CPrintToChat(client, "%s {default}您确定要退出当前行会吗？请在聊天框发送 {lime}!y {default}确认 (10秒内)", g_sChatPrefix);
        }
        else if (StrEqual(info, "settings"))
        {
            DisplayGuildSettingsMenu(client);
        }
        else if (StrEqual(info, "disband"))
        {
            g_bIsConfirmingDisband[client] = true;
            g_hConfirmationTimer[client] = CreateTimer(CONFIRMATION_TIMEOUT, Timer_CancelDisbandConfirmation, GetClientUserId(client));
            CPrintToChat(client, "%s {red}警告！{default}解散行会是不可逆的！所有成员数据将被清除！请在聊天框发送 {lime}!y {default}确认 (10秒内)", g_sChatPrefix);
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack) // 返回上一级菜单
    {
        DisplayMainMenu(client);
    }
    return 0;
}

void DisplayGuildSettingsMenu(int client)
{
    Menu menu = new Menu(GuildSettingsMenuHandler);
    menu.SetTitle("行会设置");
    
    char buffer[128];
    FormatEx(buffer, sizeof(buffer), "允许成员邀请: %s", g_bGuildAllowMemberInvite[client] ? "是" : "否");
    menu.AddItem("toggle_invite", buffer);
    
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int GuildSettingsMenuHandler(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(item, info, sizeof(info));
        
        if (StrEqual(info, "toggle_invite"))
        {
            ToggleMemberInvitePermission(client);
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
    {
        DisplayMyGuildMenu(client);
    }
    return 0;
}

void DisplayInviteMenu(int client)
{
    Menu menu = new Menu(InviteMenuHandler);
    menu.SetTitle("邀请玩家加入行会");
    
    char buffer[128], itemName[32];
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && i != client && g_iPlayerGuildID[i] == 0)
        {
            char name[MAX_NAME_LENGTH];
            GetClientName(i, name, sizeof(name));
            FormatEx(buffer, sizeof(buffer), "%s", name);
            FormatEx(itemName, sizeof(itemName), "%d", GetClientUserId(i));
            menu.AddItem(itemName, buffer);
        }
    }
    
    if (menu.ItemCount == 0)
    {
        menu.AddItem("", "没有可邀请的玩家", ITEMDRAW_DISABLED);
    }
    
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int InviteMenuHandler(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(item, info, sizeof(info));
        
        int targetUserid = StringToInt(info);
        int target = GetClientOfUserId(targetUserid);
        
        if (target > 0 && IsClientInGame(target) && g_iPlayerGuildID[target] == 0)
        {
            InvitePlayerToGuild(client, target);
        }
        else
        {
            CPrintToChat(client, "%s {red}无法邀请该玩家，可能该玩家已加入其他行会或已离线。", g_sChatPrefix);
            DisplayInviteMenu(client);
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
    {
        DisplayMyGuildMenu(client);
    }
    return 0;
}

void DisplayGuildMembersMenu(int client, int page)
{
    char query[256];
    FormatEx(query, sizeof(query), "SELECT name, score FROM players WHERE guild_id = %d ORDER BY score DESC;", g_iPlayerGuildID[client]);
    
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(page);
    
    g_hDatabase.Query(OnGuildMembersLoaded, query, pack);
}

public void OnGuildMembersLoaded(Database owner, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userid = pack.ReadCell();
    int page = pack.ReadCell();
    delete pack;
    
    int client = GetClientOfUserId(userid);
    if (client == 0) return;
    
    if (results == null)
    {
        CPrintToChat(client, "%s {red}无法获取成员列表。", g_sChatPrefix);
        return;
    }
    
    Menu menu = new Menu(GuildMembersMenuHandler);
    char title[128];
    FormatEx(title, sizeof(title), "%s - 成员列表 (第%d页)", g_sPlayerGuildName[client], page + 1);
    menu.SetTitle(title);
    
    int totalMembers = results.RowCount;
    int itemsPerPage = 6;
    int startIndex = page * itemsPerPage;

    char buffer[128], itemName[32];
    for (int i = startIndex; i < totalMembers && i < startIndex + itemsPerPage; i++)
    {
        results.FetchRow();
        char name[MAX_NAME_LENGTH];
        int score = results.FetchInt(1);
        results.FetchString(0, name, sizeof(name));
        
        FormatEx(buffer, sizeof(buffer), "%s (分数: %d)", name, score);
        FormatEx(itemName, sizeof(itemName), "member_%d", i); // 唯一的item名字，虽然在这里没用
        menu.AddItem(itemName, buffer, ITEMDRAW_DISABLED);
    }
    
    // 分页逻辑
    if (startIndex > 0)
    {
        menu.AddItem("prev_page", "上一页");
    }
    if (startIndex + itemsPerPage < totalMembers)
    {
        menu.AddItem("next_page", "下一页");
    }

    menu.ExitBackButton = true;
    menu.DisplayAt(client, page * itemsPerPage, MENU_TIME_FOREVER);
}

public int GuildMembersMenuHandler(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(item, info, sizeof(info));
        
        int currentPage = 0; // 简化处理
        if (StrEqual(info, "prev_page"))
        {
            DisplayGuildMembersMenu(client, currentPage - 1);
        }
        else if (StrEqual(info, "next_page"))
        {
            DisplayGuildMembersMenu(client, currentPage + 1);
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
    {
        DisplayMyGuildMenu(client);
    }
    return 0;
}

void DisplayAllGuildsMenu(int client, int page)
{
    // 这个实现和成员列表很像
    char query[512] = "SELECT g.name, SUM(p.score) AS total_score, COUNT(p.steamid) AS member_count FROM guilds g JOIN players p ON g.id = p.guild_id GROUP BY g.id ORDER BY total_score DESC;";
    
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(page);
    
    g_hDatabase.Query(OnAllGuildsLoaded, query, pack);
}

public void OnAllGuildsLoaded(Database owner, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userid = pack.ReadCell();
    int page = pack.ReadCell();
    delete pack;
    
    int client = GetClientOfUserId(userid);
    if (client == 0) return;

    if (results == null)
    {
        CPrintToChat(client, "%s {red}无法获取全服行会列表。", g_sChatPrefix);
        return;
    }
    
    Menu menu = new Menu(AllGuildsMenuHandler);
    
    int totalGuilds = results.RowCount;
    
    if (totalGuilds == 0)
    {
        menu.SetTitle("所有行会 - 暂无行会");
        menu.AddItem("", "当前服务器暂无任何行会", ITEMDRAW_DISABLED);
    }
    else
    {
        char title[128];
        FormatEx(title, sizeof(title), "所有行会 (按总分排名) - 第%d页", page + 1);
        menu.SetTitle(title);
        
        int itemsPerPage = 7;
        int startIndex = page * itemsPerPage;

        char buffer[128], itemName[32];
        for (int i = startIndex; i < totalGuilds && i < startIndex + itemsPerPage; i++)
        {
            results.FetchRow();
            char name[64];
            int score = results.FetchInt(1);
            int members = results.FetchInt(2);
            results.FetchString(0, name, sizeof(name));
            
            FormatEx(buffer, sizeof(buffer), "第%d名: %s (%d人, 总分: %d)", i+1, name, members, score);
            FormatEx(itemName, sizeof(itemName), "guild_%d", i);
            menu.AddItem(itemName, buffer, ITEMDRAW_DISABLED);
        }
        
        if (startIndex > 0) menu.AddItem("prev_page", "上一页");
        if (startIndex + itemsPerPage < totalGuilds) menu.AddItem("next_page", "下一页");
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int AllGuildsMenuHandler(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(item, info, sizeof(info));
        
        int currentPage = 0; // 简化处理
        if (StrEqual(info, "prev_page"))
        {
            DisplayAllGuildsMenu(client, currentPage - 1);
        }
        else if (StrEqual(info, "next_page"))
        {
            DisplayAllGuildsMenu(client, currentPage + 1);
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
    {
        DisplayMainMenu(client);
    }
    return 0;
}

// --- 逻辑处理函数 --- //

void HandleGuildCreation(int client, const char[] name)
{
    // 1. 验证行会名称
    if (!IsValidGuildName(name))
    {
        CPrintToChat(client, "%s {red}行会名称不合法！{default}长度限制10个字符，且只能包含中文、字母和数字。", g_sChatPrefix);
        return;
    }

    // 2. 将名称转义，防止SQL注入
    char escapedName[sizeof(g_sPlayerGuildName[]) * 2 + 1];
    strcopy(escapedName, sizeof(escapedName), name);
    g_hDatabase.Escape(escapedName, escapedName, sizeof(escapedName));

    char steamId[32];
    GetClientAuthId(client, AuthId_SteamID64, steamId, sizeof(steamId));

    // 3. 插入新行会到数据库
    char query[512];
    FormatEx(query, sizeof(query), "INSERT INTO `guilds` (name, owner_steamid) VALUES ('%s', '%s');", escapedName, steamId);
    
    // 使用简单的查询而不是事务
    g_hDatabase.Query(OnGuildInserted, query, GetClientUserId(client));
}

public void OnGuildInserted(Database owner, DBResultSet results, const char[] error, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0) return;

    if (results == null)
    {
        // 检查是否是重复名称错误
        if (StrContains(error, "Duplicate entry") != -1)
        {
            CPrintToChat(client, "%s {red}这个行会名称已经被占用了，换一个吧！", g_sChatPrefix);
        }
        else
        {
            LogError("插入行会失败: %s", error);
            CPrintToChat(client, "%s {red}创建行会时发生未知错误，请联系管理员。", g_sChatPrefix);
        }
        return;
    }

    // 获取插入的行会ID - 修复编译错误
    int guildId = results.InsertId;
    
    if (guildId <= 0)
    {
        CPrintToChat(client, "%s {red}创建行会失败，无法获取行会ID。", g_sChatPrefix);
        return;
    }

    // 行会创建成功，现在更新玩家的行会ID
    char steamId[32];
    GetClientAuthId(client, AuthId_SteamID64, steamId, sizeof(steamId));
    
    char query[256];
    FormatEx(query, sizeof(query), "UPDATE `players` SET `guild_id` = %d WHERE `steamid` = '%s';", guildId, steamId);
    
    g_hDatabase.Query(OnPlayerGuildUpdated, query, GetClientUserId(client));
}

public void OnPlayerGuildUpdated(Database owner, DBResultSet results, const char[] error, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0) return;

    if (results == null)
    {
        LogError("更新玩家行会ID失败: %s", error);
        CPrintToChat(client, "%s {red}创建行会时发生错误，请联系管理员。", g_sChatPrefix);
        return;
    }

    CPrintToChat(client, "%s {lime}恭喜！{default}您的行会已成功创建！", g_sChatPrefix);
    
    // 创建成功后，必须重新加载玩家数据以更新缓存和战队标签
    CreateTimer(1.0, Timer_LoadPlayerData, userid);
}

/**
 * 邀请玩家加入行会 —— 修复后的版本
 */
void InvitePlayerToGuild(int inviter, int target)
{
    // 目标已经有行会
    if (g_iPlayerGuildID[target] > 0)
    {
        CPrintToChat(inviter, "%s {red}该玩家已经加入其他行会了。", g_sChatPrefix);
        return;
    }

    // 先拿 steamid
    char steamId[64];
    if (!GetClientAuthId(target, AuthId_SteamID64, steamId, sizeof(steamId)))
    {
        CPrintToChat(inviter, "%s {red}无法获取目标玩家的 SteamID（可能玩家未连接或 ID 不可用）。", g_sChatPrefix);
        return;
    }

    // 转义 steamid（防注入），然后拼 SQL
    char escSteam[128];
    EscapeSQL(steamId, escSteam, sizeof(escSteam));

    char query[256];
    FormatEx(query, sizeof(query),
        "UPDATE `players` SET `guild_id` = %d WHERE `steamid` = '%s';",
        g_iPlayerGuildID[inviter], escSteam);

    // 打包调用信息（原样保留）
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(inviter));
    pack.WriteCell(GetClientUserId(target));

    // 发起数据库查询
    g_hDatabase.Query(OnPlayerInvited, query, pack);
}

public void OnPlayerInvited(Database owner, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int inviterUserid = pack.ReadCell();
    int targetUserid = pack.ReadCell();
    delete pack;
    
    int inviter = GetClientOfUserId(inviterUserid);
    int target = GetClientOfUserId(targetUserid);
    
    if (inviter == 0) return;

    if (results == null)
    {
        LogError("邀请玩家失败: %s", error);
        CPrintToChat(inviter, "%s {red}邀请玩家时发生错误。", g_sChatPrefix);
        return;
    }

    if (target > 0 && IsClientInGame(target))
    {
        CPrintToChat(target, "%s {lime}%N {default}邀请您加入了行会【%s】！", g_sChatPrefix, inviter, g_sPlayerGuildName[inviter]);
        SetEntityTribe(target, g_sPlayerGuildName[inviter]);
        CreateTimer(1.0, Timer_LoadPlayerData, targetUserid);
    }
    
    CPrintToChat(inviter, "%s {default}成功邀请玩家加入行会！", g_sChatPrefix);
}

void ToggleMemberInvitePermission(int client)
{
    bool newSetting = !g_bGuildAllowMemberInvite[client];
    
    char query[256];
    FormatEx(query, sizeof(query), "UPDATE `guilds` SET `allow_member_invite` = %d WHERE `id` = %d;", 
             newSetting ? 1 : 0, g_iPlayerGuildID[client]);
    
    g_hDatabase.Query(OnInvitePermissionUpdated, query, GetClientUserId(client));
}

public void OnInvitePermissionUpdated(Database owner, DBResultSet results, const char[] error, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0) return;

    if (results == null)
    {
        LogError("更新邀请权限失败: %s", error);
        CPrintToChat(client, "%s {red}更新行会设置时发生错误。", g_sChatPrefix);
        return;
    }

    g_bGuildAllowMemberInvite[client] = !g_bGuildAllowMemberInvite[client];
    CPrintToChat(client, "%s {default}行会设置已更新：{lime}%s {default}成员邀请权限。", 
                 g_sChatPrefix, g_bGuildAllowMemberInvite[client] ? "开启" : "关闭");
    
    DisplayGuildSettingsMenu(client);
}

void HandleLeaveGuild(int client)
{
    if (g_bIsPlayerGuildOwner[client]) return; // 再次确认，虽然菜单里已经禁用了

    char steamId[32];
    GetClientAuthId(client, AuthId_SteamID64, steamId, sizeof(steamId));
    
    char query[256];
    FormatEx(query, sizeof(query), "UPDATE `players` SET `guild_id` = NULL WHERE `steamid` = '%s';", steamId);

    g_hDatabase.Query(OnGuildLeft, query, GetClientUserId(client));
}

public void OnGuildLeft(Database owner, DBResultSet results, const char[] error, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0) return;

    if (results == null)
    {
        LogError("退出行会失败: %s", error);
        CPrintToChat(client, "%s {red}退出行会时发生错误。", g_sChatPrefix);
        return;
    }

    CPrintToChat(client, "%s {default}您已成功退出行会。", g_sChatPrefix);
    SetEntityTribe(client, ""); // 清除战队标签
    CreateTimer(1.0, Timer_LoadPlayerData, userid); // 重新加载数据
}

void HandleDisbandGuild(int client)
{
    if (!g_bIsPlayerGuildOwner[client]) return; // 再次确认

    // 解散行会是个大操作，直接删除guilds表里的对应行
    // 由于我们设置了外键 `ON DELETE SET NULL`，players表里所有该行会的成员的 guild_id 会自动变为 NULL
    // 这就是关系型数据库的魅力！
    char query[256];
    FormatEx(query, sizeof(query), "DELETE FROM `guilds` WHERE `id` = %d;", g_iPlayerGuildID[client]);
    
    g_hDatabase.Query(OnGuildDisbanded, query, GetClientUserId(client));
}

public void OnGuildDisbanded(Database owner, DBResultSet results, const char[] error, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0) return;

    if (results == null)
    {
        LogError("解散行会失败: %s", error);
        CPrintToChat(client, "%s {red}解散行会时发生错误。", g_sChatPrefix);
        return;
    }

    CPrintToChatAll("%s {orange}江湖快报：{default}由 %N 创建的行会【%s】已宣告解散！", g_sChatPrefix, client, g_sPlayerGuildName[client]);
    SetEntityTribe(client, ""); // 清除自己的标签
    
    // 重新加载所有在线玩家的数据，以清除那些被解散行会的成员的标签
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            CreateTimer(1.0, Timer_LoadPlayerData, GetClientUserId(i));
        }
    }
}

bool IsValidGuildName(const char[] name)
{
    int len = strlen(name);
    if (len == 0 || len > GUILD_NAME_MAX_LENGTH)
    {
        return false;
    }

    for (int i = 0; i < len; i++)
    {
        // 检查是否是字母、数字或中文字符
        // 这是一个简化的检查，但能过滤掉大部分符号
        if ((name[i] >= 'a' && name[i] <= 'z') ||
            (name[i] >= 'A' && name[i] <= 'Z') ||
            (name[i] >= '0' && name[i] <= '9') ||
            (name[i] & 0x80) != 0) // 简单判断是否为多字节字符（可能是中文）
        {
            continue;
        }
        return false;
    }
    return true;
}

// --- 计时器回调 (用于取消操作) --- //

public Action Timer_CancelGuildCreation(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client > 0 && g_bIsCreatingGuild[client])
    {
        g_bIsCreatingGuild[client] = false;
        CPrintToChat(client, "%s {default}行会创建已取消，因为您超时未输入名称。", g_sChatPrefix);
    }
    g_hConfirmationTimer[client] = null;
    return Plugin_Stop;
}

public Action Timer_CancelLeaveConfirmation(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client > 0 && g_bIsConfirmingLeave[client])
    {
        g_bIsConfirmingLeave[client] = false;
        CPrintToChat(client, "%s {default}退出行会请求已取消，因为您超时未确认。", g_sChatPrefix);
    }
    g_hConfirmationTimer[client] = null;
    return Plugin_Stop;
}

public Action Timer_CancelDisbandConfirmation(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client > 0 && g_bIsConfirmingDisband[client])
    {
        g_bIsConfirmingDisband[client] = false;
        CPrintToChat(client, "%s {default}解散行会请求已取消，因为您超时未确认。", g_sChatPrefix);
    }
    g_hConfirmationTimer[client] = null;
    return Plugin_Stop;
}

// --- 辅助函数 --- //

void ClearPlayerData(int client)
{
    g_bIsCreatingGuild[client] = false;
    g_bIsConfirmingLeave[client] = false;
    g_bIsConfirmingDisband[client] = false;
    g_bIsInvitingPlayer[client] = false;
    g_bPlayerDataLoaded[client] = false;
    g_bPlayerHasGuildInDB[client] = false;
    
    if (g_hConfirmationTimer[client] != null)
    {
        KillTimer(g_hConfirmationTimer[client]);
        g_hConfirmationTimer[client] = null;
    }
    
    if (g_hClanTagTimer[client] != null)
    {
        KillTimer(g_hClanTagTimer[client]);
        g_hClanTagTimer[client] = null;
    }
    
    g_iPlayerGuildID[client] = 0;
    g_sPlayerGuildName[client][0] = '\0';
    g_iPlayerScore[client] = 0;
    g_bIsPlayerGuildOwner[client] = false;
    g_bGuildAllowMemberInvite[client] = false;
}