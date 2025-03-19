#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <multicolors>
#include <autoexecconfig>

#define PLUGIN_VERSION "1.3"

public Plugin myinfo =
{
    name = "AllTalk Toggle",
    author = "heize",
    description = "Toggles sv_alltalk with !alltalk command",
    version = PLUGIN_VERSION,
    url = "http://www.heizemod.us"
};

ConVar g_cAdminFlag = null;

public void OnPluginStart()
{
    AutoExecConfig_SetFile("alltalk_toggle");

    g_cAdminFlag = AutoExecConfig_CreateConVar("sm_alltalk_flag", "z", "Admin flag required to use !alltalk", FCVAR_NONE);

    AutoExecConfig_ExecuteFile();
    AutoExecConfig_CleanFile();

    // Register command after setting the flag
    RegAdminCmd("sm_alltalk", Command_AllTalk, GetFlagFromString(g_cAdminFlag), "Toggles sv_alltalk");
}

public Action Command_AllTalk(int client, int args)
{
    if (!IsClientInGame(client))
    {
        CPrintToChat(client, "{lightblue}[AllTalk] {red}You must be in the game to use this command.");
        return Plugin_Handled;
    }

    // Check for admin flag access
    if (!CheckCommandAccess(client, "sm_alltalk", GetFlagFromString(g_cAdminFlag)))
    {
        CPrintToChat(client, "{lightblue}[AllTalk] {red}You don't have permission to use this command.");
        return Plugin_Handled;
    }

    bool alltalk = GetEngineCvarBool("sv_alltalk");
    alltalk = !alltalk;
    SetEngineCvar("sv_alltalk", alltalk ? "1" : "0");

    if (alltalk)
    {
        CPrintToChatAll("{lightblue}[AllTalk] {lightgreen}Enabled by {yellow}%N", client);
    }
    else
    {
        CPrintToChatAll("{lightblue}[AllTalk] {red}Disabled by {yellow}%N", client);
    }

    return Plugin_Handled;
}

int GetFlagFromString(ConVar flagCvar)
{
    char flag[32];
    flagCvar.GetString(flag, sizeof(flag));

    if (StrEqual(flag, "", false))
        return ADMFLAG_GENERIC; // Default to generic if no flag is set

    int flagBits = ReadFlagString(flag);
    if (flagBits == -1)
        flagBits = ADMFLAG_GENERIC;

    return flagBits;
}

bool GetEngineCvarBool(const char[] cvar)
{
    ConVar hCvar = FindConVar(cvar);
    return hCvar ? hCvar.BoolValue : false;
}

void SetEngineCvar(const char[] cvar, const char[] value)
{
    ServerCommand("%s %s", cvar, value);
}
