#include <sourcemod>
#include <sdktools>
#include <cstrike>

// 插件启动时调用
public void OnPluginStart()
{
    // 监听每一回合开始的事件
    HookEvent("round_start", Event_RoundStart);
}

// 每回合开始时触发
public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    // 设置一个0.1秒的延迟定时器来给予玩家装备
    CreateTimer(0.1, Timer_GiveEquipment, _, TIMER_FLAG_NO_MAPCHANGE);
}

// 定时器回调函数，给所有在游戏中的存活玩家发放装备
public Action Timer_GiveEquipment(Handle timer)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        // 检查玩家是否在游戏中且存活
        if (IsClientInGame(i) && IsPlayerAlive(i))
        {
            // 给玩家发放装备
            GiveEquipment(i);
        }
    }
    return Plugin_Continue;
}

// 给单个玩家发放装备的函数
void GiveEquipment(int client)
{
    // 始终补满护甲并配备头盔
    SetEntProp(client, Prop_Send, "m_ArmorValue", 100);
    SetEntProp(client, Prop_Send, "m_bHasHelmet", 1);
    
    // 如果没有SSG08狙击枪，则给予
    if (!HasWeapon(client, "weapon_ssg08"))
    {
        GivePlayerItem(client, "weapon_ssg08");
    }
    
    // 如果没有电击枪（taser），则给予
    if (!HasWeapon(client, "weapon_taser"))
    {
        GivePlayerItem(client, "weapon_taser");
    }
    
    // 如果没有烟雾弹，则给予
    if (!HasWeapon(client, "weapon_smokegrenade"))
    {
        GivePlayerItem(client, "weapon_smokegrenade");
    }
    
    // 如果没有高爆手雷（HE），则给予
    if (!HasWeapon(client, "weapon_hegrenade"))
    {
        GivePlayerItem(client, "weapon_hegrenade");
    }
    
    // 如果玩家没有燃烧弹（CT）或莫洛托夫（T），根据阵营给予对应物品
    if (!HasWeapon(client, "weapon_incgrenade") && !HasWeapon(client, "weapon_molotov"))
    {
        if (GetClientTeam(client) == CS_TEAM_CT)
        {
            // CT给予燃烧弹
            GivePlayerItem(client, "weapon_incgrenade");
        }
        else if (GetClientTeam(client) == CS_TEAM_T)
        {
            // T给予莫洛托夫
            GivePlayerItem(client, "weapon_molotov");
        }
    }
    
    // 如果是CT且没有拆弹器，则给予拆弹器
    if (GetClientTeam(client) == CS_TEAM_CT && !GetEntProp(client, Prop_Send, "m_bHasDefuser"))
    {
        GivePlayerItem(client, "item_defuser");
    }
}

// 检查玩家是否已经拥有某个武器
bool HasWeapon(int client, const char[] weaponName)
{
    // 获取玩家拥有武器槽的数量
    int maxWeapons = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
    for (int i = 0; i < maxWeapons; i++)
    {
        // 获取第i个武器实体
        int weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
        if (weapon != -1)
        {
            // 获取该武器的类名
            char weaponClass[32];
            GetEntityClassname(weapon, weaponClass, sizeof(weaponClass));
            
            // 如果类名匹配，则表示拥有该武器
            if (StrEqual(weaponClass, weaponName))
            {
                return true;
            }
        }
    }
    return false;
}
