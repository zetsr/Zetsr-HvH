#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
    name = "Remove Landing Inaccuracy",
    author = "zetsr",
    description = "Removes weapon inaccuracy penalty on landing",
    version = "1.0",
    url = "https://github.com/zetsr/"
};

public void OnPluginStart() {
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i)) {
            SDKHook(i, SDKHook_PreThinkPost, OnPlayerThink);
        }
    }
}

public void OnClientPutInServer(int client) {
    SDKHook(client, SDKHook_PreThinkPost, OnPlayerThink);
}

public void OnPlayerThink(int client) {
    if (!IsPlayerAlive(client)) {
        return;
    }

    static int lastFlags[MAXPLAYERS + 1];
    int currentFlags = GetEntityFlags(client);

    // 检测玩家落地瞬间
    if (!(lastFlags[client] & FL_ONGROUND) && (currentFlags & FL_ONGROUND)) {
        int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
        if (weapon != -1) {
            // 重置武器的不精准度
            SetEntPropFloat(weapon, Prop_Send, "m_fAccuracyPenalty", 0.0);
        }
    }

    lastFlags[client] = currentFlags;
}