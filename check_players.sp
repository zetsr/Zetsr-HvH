#include <sourcemod>

public Plugin myinfo = 
{
    name = "check_players",
    author = "zetsr",
    description = "显示当前在线的玩家和 Bot 数量",
    version = "1.0",
    url = "https://github.com/zetsr"
};

public void OnPluginStart()
{
    // 注册命令，使其出现在 sm_help 中
    RegConsoleCmd("check_players", Command_Players, "输入!players，显示当前在线的玩家和 Bot 数量");
}

public Action Command_Players(int client, int args)
{
    int players = 0; // 真实玩家的数量
    int bots = 0;    // Bot 的数量
    
    // 遍历所有客户端，统计玩家和 Bot 数量
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            if (IsFakeClient(i))
            {
                bots++;
            }
            else
            {
                players++;
            }
        }
    }
    
    // 输出彩色中文消息
    PrintToChat(client, "当前有 \x03%d 名玩家和 \x07%d 个 Bot 在线。", players, bots);

    return Plugin_Handled;
}