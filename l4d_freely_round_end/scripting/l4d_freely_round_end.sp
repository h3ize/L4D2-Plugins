#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <autoexecconfig>

#define PLUGIN_VERSION "3"
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

public Plugin myinfo =
{
    name = "[L4D & 2] Freely Round End",
    author = "Forgetest, heize",
    description = "Free movement after round ends for admins only.",
    version = PLUGIN_VERSION,
    url = "https://github.com/h3ize"
};

ConVar g_cPluginEnabled = null;
ConVar g_cAdminFlag = null;

public void OnPluginStart()
{
    AutoExecConfig_SetFile("freely_round_end");

    g_cPluginEnabled = AutoExecConfig_CreateConVar("sm_freely_round_end_enable", "1", "Enables/disables the plugin", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cAdminFlag = AutoExecConfig_CreateConVar("sm_freely_move_flag", "", "Admin flag required to move freely after round end. Leave empty to allow all players to move.", FCVAR_NONE);

    AutoExecConfig_ExecuteFile();
    AutoExecConfig_CleanFile();

    HookEvent("round_end", Event_RoundEnd);
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (event.GetInt("reason") == 5)
    {
        RequestFrame(OnFrame_RoundEnd);
    }
}

void OnFrame_RoundEnd()
{
    if (!g_cPluginEnabled.BoolValue)
    {
        return;
    }

    char adminFlagString[32];
    GetConVarString(g_cAdminFlag, adminFlagString, sizeof(adminFlagString));

    bool allowAllPlayers = StrEqual(adminFlagString, "", false);
    int requiredFlag = ReadFlagString(adminFlagString);

    for (int i = 1; i <= MaxClients; ++i)
    {
        if (!IsClientInGame(i))
            continue;

        int team = GetClientTeam(i);
        int clientFlags = GetUserFlagBits(i);

        SetEntityFlags(i, GetEntityFlags(i) & ~FL_GODMODE);

        if (team == TEAM_INFECTED || 
            (team == TEAM_SURVIVOR && (allowAllPlayers || (clientFlags & requiredFlag) == requiredFlag)))
        {
            SetEntityFlags(i, GetEntityFlags(i) & ~FL_FROZEN);
        }
    }
}
