#include <sourcemod>
#include <sdktools>
#include <cstrike>

// CT 探员模型
new const String:g_CTAgentModels[][] = {
    "models/player/custom_player/legacy/ctm_fbi_variantb.mdl",         // Special Agent Ava | FBI
    "models/player/custom_player/legacy/ctm_sas_variantf.mdl",         // B Squadron Officer | SAS
    "models/player/custom_player/legacy/ctm_st6_variante.mdl",         // Seal Team 6 Soldier | NSWC SEAL
    "models/player/custom_player/legacy/ctm_st6_variantg.mdl",         // Buckshot | NSWC SEAL
    "models/player/custom_player/legacy/ctm_st6_varianti.mdl",         // Lt. Commander Ricksaw | NSWC SEAL
    "models/player/custom_player/legacy/ctm_fbi_variantg.mdl",         // Markus Delrow | FBI HRT
    "models/player/custom_player/legacy/ctm_fbi_varianth.mdl",         // Michael Syfers | FBI Sniper
    "models/player/custom_player/legacy/ctm_swat_variante.mdl"         // Cmdr. Mae | SWAT
};

// CT 探员双语名称
new const String:g_CTAgentNames[][] = {
    "Special Agent Ava | 特别探员艾娃·艾尔帕克",
    "B Squadron Officer | B中队军官",
    "Seal Team 6 Soldier | 海豹六队士兵",
    "Buckshot | 巴克肖特",
    "Lt. Commander Ricksaw | 瑞克索中校",
    "Markus Delrow | 马库斯·德尔罗",
    "Michael Syfers | 迈克尔·赛弗斯",
    "Cmdr. Mae | 梅指挥官"
};

// T 探员模型
new const String:g_TAgentModels[][] = {
    "models/player/custom_player/legacy/tm_professional_varf.mdl",     // Miami | Sir Bloody Darryl
    "models/player/custom_player/legacy/tm_professional_varf1.mdl",    // Silent | Sir Bloody Darryl
    "models/player/custom_player/legacy/tm_professional_varf2.mdl",    // Skullhead | Sir Bloody Darryl
    "models/player/custom_player/legacy/tm_professional_varf3.mdl",    // Royale | Sir Bloody Darryl
    "models/player/custom_player/legacy/tm_professional_varf4.mdl",    // Loudmouth | Sir Bloody Darryl
    "models/player/custom_player/legacy/tm_professional_varf5.mdl",    // Bloody Darryl The Strapped | The Professionals
    "models/player/custom_player/legacy/tm_professional_varg.mdl",     // Safecracker Voltzmann | Professional
    "models/player/custom_player/legacy/tm_professional_varh.mdl",     // Little Kev | Professional
    "models/player/custom_player/legacy/tm_professional_varj.mdl",     // Getaway Sally | Professional
    "models/player/custom_player/legacy/tm_professional_vari.mdl",     // AGENT Gandon | Professional
    "models/player/custom_player/legacy/tm_jungle_raider_varianta.mdl",// Elite Trapper Solman | Guerrilla Warfare
    "models/player/custom_player/legacy/tm_jungle_raider_variantb.mdl",// Crasswater The Forgotten | Guerrilla Warfare
    "models/player/custom_player/legacy/tm_jungle_raider_variantb2.mdl",// 'Medium Rare' Crasswater | Guerrilla Warfare
    "models/player/custom_player/legacy/tm_jungle_raider_variantc.mdl",// Arno The Overgrown | Guerrilla Warfare
    "models/player/custom_player/legacy/tm_jungle_raider_variantd.mdl",// Col. Mangos Dabisi | Guerrilla Warfare
    "models/player/custom_player/legacy/tm_jungle_raider_variante.mdl",// Vypa Sista of the Revolution | Guerrilla Warfare
    "models/player/custom_player/legacy/tm_jungle_raider_variantf.mdl",// Trapper Aggressor | Guerrilla Warfare
    "models/player/custom_player/legacy/tm_jungle_raider_variantf2.mdl",// Trapper | Guerrilla Warfare
    "models/player/custom_player/legacy/tm_balkan_variantf.mdl",       // Dragomir | Sabre
    "models/player/custom_player/legacy/tm_balkan_variantg.mdl",       // Rezan The Ready | Sabre
    "models/player/custom_player/legacy/tm_balkan_varianth.mdl",       // 'The Doctor' Romanov | Sabre
    "models/player/custom_player/legacy/tm_balkan_varianti.mdl",       // Maximus | Sabre
    "models/player/custom_player/legacy/tm_balkan_variantj.mdl",       // Blackwolf | Sabre
    "models/player/custom_player/legacy/tm_balkan_variantk.mdl",       // Rezan the Redshirt | Sabre
    "models/player/custom_player/legacy/tm_balkan_variantl.mdl",       // Dragomir | Sabre Footsoldier
    "models/player/custom_player/legacy/tm_phoenix_variantf.mdl",      // Enforcer | Phoenix
    "models/player/custom_player/legacy/tm_phoenix_variantg.mdl",      // Slingshot | Phoenix
    "models/player/custom_player/legacy/tm_phoenix_varianth.mdl",      // Soldier | Phoenix
    "models/player/custom_player/legacy/tm_phoenix_varianti.mdl",      // Street Soldier | Phoenix
    "models/player/custom_player/legacy/tm_leet_variantf.mdl",         // The Elite Mr. Muhlik | Elite Crew
    "models/player/custom_player/legacy/tm_leet_variantg.mdl",         // Ground Rebel | Elite Crew
    "models/player/custom_player/legacy/tm_leet_varianth.mdl",         // Osiris | Elite Crew
    "models/player/custom_player/legacy/tm_leet_varianti.mdl"          // Prof. Shahmat | Elite Crew
};

// T 探员双语名称
new const String:g_TAgentNames[][] = {
    "Miami | Sir Bloody Darryl | 迈阿密 | 血腥达里尔爵士",
    "Silent | Sir Bloody Darryl | 无声 | 血腥达里尔爵士",
    "Skullhead | Sir Bloody Darryl | 骷髅头 | 血腥达里尔爵士",
    "Royale | Sir Bloody Darryl | 皇家 | 血腥达里尔爵士",
    "Loudmouth | Sir Bloody Darryl | 大嗓门 | 血腥达里尔爵士",
    "Bloody Darryl The Strapped | 捆绑血腥达里尔",
    "Safecracker Voltzmann | 保险箱破解者沃尔兹曼",
    "Little Kev | 小凯文",
    "Getaway Sally | 逃亡萨莉",
    "AGENT Gandon | 探员冈东",
    "Elite Trapper Solman | 精锐陷阱手索尔曼",
    "Crasswater The Forgotten | 被遗忘的克拉斯沃特",
    "'Medium Rare' Crasswater | “半熟”克拉斯沃特",
    "Arno The Overgrown | 过度生长的阿尔诺",
    "Col. Mangos Dabisi | 芒果·达比西上校",
    "Vypa Sista of the Revolution | 革命薇帕姐妹",
    "Trapper Aggressor | 侵略陷阱手",
    "Trapper | 陷阱手",
    "Dragomir | Sabre | 德拉戈米尔 | 军刀",
    "Rezan The Ready | Sabre | 准备好的雷赞 | 军刀",
    "'The Doctor' Romanov | Sabre | “医生”罗曼诺夫 | 军刀",
    "Maximus | Sabre | 马克西姆斯 | 军刀",
    "Blackwolf | Sabre | 黑狼 | 军刀",
    "Rezan the Redshirt | Sabre | 红衫雷赞 | 军刀",
    "Dragomir | Sabre Footsoldier | 德拉戈米尔 | 军刀步兵",
    "Enforcer | Phoenix | 执行者 | 凤凰",
    "Slingshot | Phoenix | 弹弓 | 凤凰",
    "Soldier | Phoenix | 士兵 | 凤凰",
    "Street Soldier | Phoenix | 街头士兵 | 凤凰",
    "The Elite Mr. Muhlik | 精锐穆赫利克先生",
    "Ground Rebel | 地面叛军",
    "Osiris | 奥西里斯",
    "Prof. Shahmat | 沙赫马特教授"
};

// 定义模型数量常量
#define CT_AGENT_COUNT sizeof(g_CTAgentModels)
#define T_AGENT_COUNT sizeof(g_TAgentModels)

#define PLUGIN_VERSION "1.0"
#define CONFIG_PATH "configs/player_agents.cfg"

public Plugin:myinfo = {
    name = "Agent Selector",
    author = "zetsr",
    description = "Allows players to select faction-specific paid agent models",
    version = PLUGIN_VERSION,
    url = "https://github.com/zetsr"
};

public OnPluginStart() {
    RegConsoleCmd("sm_agent", Command_Agent, "Opens agent selection menu");
    HookEvent("player_spawn", Event_PlayerSpawn); // 添加玩家生成事件钩子
    LoadTranslations("common.phrases");
    
    // 预加载 CT 模型
    for (new i = 0; i < CT_AGENT_COUNT; i++) {
        if (FileExists(g_CTAgentModels[i], true)) {
            PrecacheModel(g_CTAgentModels[i], true);
            PrintToServer("Precached CT model: %s", g_CTAgentModels[i]);
        } else {
            LogError("CT model file not found: %s", g_CTAgentModels[i]);
        }
    }
    
    // 预加载 T 模型
    for (new i = 0; i < T_AGENT_COUNT; i++) {
        if (FileExists(g_TAgentModels[i], true)) {
            PrecacheModel(g_TAgentModels[i], true);
            PrintToServer("Precached T model: %s", g_TAgentModels[i]);
        } else {
            LogError("T model file not found: %s", g_TAgentModels[i]);
        }
    }
}

public Action:Command_Agent(client, args) {
    if (!IsClientInGame(client) || !IsPlayerAlive(client)) {
        PrintToChat(client, "\x04[Agent] \x01你必须活着才能选择探员！");
        return Plugin_Handled;
    }
    
    ShowAgentMenu(client);
    return Plugin_Handled;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client && IsClientInGame(client)) {
        LoadPlayerAgent(client);
    }
}

void ShowAgentMenu(client) {
    new Handle:menu = CreateMenu(AgentMenuHandler);
    new team = GetClientTeam(client);
    SetMenuTitle(menu, team == CS_TEAM_CT ? "选择CT探员" : "选择T探员");
    
    if (team == CS_TEAM_CT) {
        for (new i = 0; i < CT_AGENT_COUNT; i++) {
            char info[8];
            IntToString(i, info, sizeof(info));
            AddMenuItem(menu, info, g_CTAgentNames[i]);
        }
    } else if (team == CS_TEAM_T) {
        for (new i = 0; i < T_AGENT_COUNT; i++) {
            char info[8];
            IntToString(i, info, sizeof(info));
            AddMenuItem(menu, info, g_TAgentNames[i]);
        }
    }
    
    SetMenuExitButton(menu, true);
    DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public AgentMenuHandler(Handle:menu, MenuAction:action, client, param2) {
    if (action == MenuAction_Select) {
        char info[8];
        GetMenuItem(menu, param2, info, sizeof(info));
        new modelIndex = StringToInt(info);
        new team = GetClientTeam(client);
        char model[PLATFORM_MAX_PATH];
        
        if (team == CS_TEAM_CT && modelIndex < CT_AGENT_COUNT) {
            strcopy(model, sizeof(model), g_CTAgentModels[modelIndex]);
            PrintToChat(client, "\x04[Agent] \x01已选择: %s", g_CTAgentNames[modelIndex]);
        } else if (team == CS_TEAM_T && modelIndex < T_AGENT_COUNT) {
            strcopy(model, sizeof(model), g_TAgentModels[modelIndex]);
            PrintToChat(client, "\x04[Agent] \x01已选择: %s", g_TAgentNames[modelIndex]);
        } else {
            PrintToChat(client, "\x04[Agent] \x01无效的选择！");
            return;
        }
        
        if (IsModelPrecached(model)) {
            SetEntityModel(client, model);
            SavePlayerAgent(client, model);
        } else {
            PrintToChat(client, "\x04[Agent] \x01模型未加载，请联系管理员！");
            LogError("Failed to apply model %s for client %N: not precached", model, client);
        }
    }
    else if (action == MenuAction_End) {
        CloseHandle(menu);
    }
}

void SavePlayerAgent(client, const String:model[]) {
    char steamid[32];
    GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
    
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), CONFIG_PATH);
    
    Handle kv = CreateKeyValues("PlayerAgents");
    FileToKeyValues(kv, path);
    
    if (!KvJumpToKey(kv, steamid, true)) {
        LogError("Failed to create/jump to key for SteamID: %s", steamid);
        CloseHandle(kv);
        return;
    }
    
    new team = GetClientTeam(client);
    if (team == CS_TEAM_CT) {
        KvSetString(kv, "CT", model);
    } else if (team == CS_TEAM_T) {
        KvSetString(kv, "T", model);
    }
    
    KvRewind(kv);
    KeyValuesToFile(kv, path);
    CloseHandle(kv);
    
    LogMessage("Saved agent for %N (SteamID: %s, Team: %d): %s", client, steamid, team, model);
}

void LoadPlayerAgent(client) {
    if (!IsClientInGame(client) || !IsPlayerAlive(client)) {
        return;
    }
    
    char steamid[32];
    GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
    
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), CONFIG_PATH);
    
    if (!FileExists(path)) {
        LogMessage("Config file not found for %N: %s", client, path);
        return;
    }
    
    Handle kv = CreateKeyValues("PlayerAgents");
    FileToKeyValues(kv, path);
    
    if (!KvJumpToKey(kv, steamid)) {
        LogMessage("No agent config found for %N (SteamID: %s)", client, steamid);
        CloseHandle(kv);
        return;
    }
    
    char model[PLATFORM_MAX_PATH];
    new team = GetClientTeam(client);
    
    if (team == CS_TEAM_CT) {
        KvGetString(kv, "CT", model, sizeof(model));
    } else if (team == CS_TEAM_T) {
        KvGetString(kv, "T", model, sizeof(model));
    } else {
        LogMessage("Invalid team for %N: %d", client, team);
        CloseHandle(kv);
        return;
    }
    
    if (strlen(model) > 0) {
        if (IsModelPrecached(model)) {
            SetEntityModel(client, model);
            LogMessage("Applied saved agent for %N (SteamID: %s, Team: %d): %s", client, steamid, team, model);
        } else {
            LogError("Failed to apply saved model for %N (SteamID: %s): %s not precached", client, steamid, model);
        }
    } else {
        LogMessage("No saved model found for %N (SteamID: %s, Team: %d)", client, steamid, team);
    }
    
    CloseHandle(kv);
}