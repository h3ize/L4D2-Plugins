#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <regex>

#define PLUGIN_VERSION "3.3-2025/7/29"
#define DEBUG 0

public Plugin myinfo =
{
    name = "[L4D1/L4D2/Any] auto restart",
    author = "Harry Potter, HatsuneImagin, heize",
    description = "Make server restart (Force crash) when the last player disconnects from the server or when the match ends",
    version = PLUGIN_VERSION,
    url = "https://steamcommunity.com/profiles/76561198026784913"
};

bool g_bGameL4D;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    EngineVersion test = GetEngineVersion();
    if (test == Engine_Left4Dead || test == Engine_Left4Dead2)
    {
        g_bGameL4D = true;
    }
    return APLRes_Success;
}

ConVar g_hConVarHibernate;
ConVar g_hHeizepugsMatchId;

Handle COLD_DOWN_Timer;

bool
    g_bNoOneInServer = false,
    g_bFirstMap = true,
    g_bCmdMap = false,
    g_bAnyoneConnectedBefore = false,
    g_bFinaleWaitingForDisconnect = false;

char g_sPath[256];

public void OnPluginStart()
{
    if (g_bGameL4D)
    {
        g_hConVarHibernate = FindConVar("sv_hibernate_when_empty");
        g_hConVarHibernate.AddChangeHook(ConVarChanged_Hibernate);
    }

    g_hHeizepugsMatchId = FindConVar("heizepugs_matchid");

    HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
    HookEvent("versus_match_finished", Event_MatchEnd);
    HookEvent("finale_vehicle_leaving", Event_MatchEnd);

    RegAdminCmd("sm_crash", Cmd_RestartServer, ADMFLAG_ROOT);
    RegAdminCmd("sm_rs", Cmd_ImmediateRestartServer, ADMFLAG_ROOT);

    AddCommandListener(ServerCmd_map, "map");
    BuildPath(Path_SM, g_sPath, sizeof(g_sPath), "logs/linux_auto_restart.log");
}

public void OnPluginEnd()
{
    delete COLD_DOWN_Timer;
}

void ConVarChanged_Hibernate(ConVar cvar, const char[] oldVal, const char[] newVal)
{
    g_hConVarHibernate.SetBool(false);
}

public void OnMapEnd()
{
    delete COLD_DOWN_Timer;
}

public void OnConfigsExecuted()
{
    if (g_bNoOneInServer || (!g_bFirstMap && g_bAnyoneConnectedBefore) || g_bCmdMap)
    {
        delete COLD_DOWN_Timer;
        COLD_DOWN_Timer = CreateTimer(20.0, Timer_COLD_DOWN);
    }
    g_bFirstMap = false;
}

public void OnClientConnected(int client)
{
    if (IsFakeClient(client))
        return;

    if (!g_bAnyoneConnectedBefore && g_bGameL4D)
        g_hConVarHibernate.SetBool(false);

    g_bAnyoneConnectedBefore = true;
}

Action Cmd_RestartServer(int client, int args)
{
    CreateTimer(5.0, Timer_Cmd_RestartServer);
    return Plugin_Continue;
}

Action Cmd_ImmediateRestartServer(int client, int args)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
            KickClient(i, "Server is restarting");
    }

    UnloadAccelerator();
    CreateTimer(0.1, Timer_RestartServer);
    return Plugin_Handled;
}

public void Event_MatchEnd(Event event, const char[] name, bool dontBroadcast)
{
    g_bFinaleWaitingForDisconnect = true;

    // If match ends while server is already empty, re-arm restart
    if (!CheckPlayerInGame(0))
    {
        delete COLD_DOWN_Timer;
        COLD_DOWN_Timer = CreateTimer(10.0, Timer_COLD_DOWN);
    }
}

void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
    if (event.GetBool("bot"))
        return;

    static char networkid[32];
    event.GetString("networkid", networkid, sizeof(networkid));
    if (strcmp(networkid, "BOT", false) == 0)
        return;

    int client = GetClientOfUserId(event.GetInt("userid"));

    if (!CheckPlayerInGame(client))
    {
        g_bNoOneInServer = true;
        delete COLD_DOWN_Timer;
        COLD_DOWN_Timer = CreateTimer(15.0, Timer_COLD_DOWN);
    }
}

Action Timer_COLD_DOWN(Handle timer, any data)
{
    COLD_DOWN_Timer = null;

    // Defer restart while Heizepugs match is active
    if (IsHeizepugsMatchActive())
    {
        LogToFileEx(g_sPath, "Heizepugs match active — deferring auto restart.");
        COLD_DOWN_Timer = CreateTimer(30.0, Timer_COLD_DOWN);
        return Plugin_Continue;
    }

    if (CheckPlayerInGame(0))
    {
        g_bNoOneInServer = false;
        return Plugin_Continue;
    }

    if (g_bFinaleWaitingForDisconnect)
        LogToFileEx(g_sPath, "Match/finale ended and all players left. Restarting.");
    else
        LogToFileEx(g_sPath, "Server became empty during play. Restarting.");

    PrintToServer("AutoRestart: Server is restarting.");
    UnloadAccelerator();
    CreateTimer(0.1, Timer_RestartServer);

    g_bNoOneInServer = false;
    g_bFinaleWaitingForDisconnect = false;

    return Plugin_Continue;
}

Action Timer_RestartServer(Handle timer)
{
    SetCommandFlags("crash", GetCommandFlags("crash") & ~FCVAR_CHEAT);
    ServerCommand("crash");

    if (!g_bGameL4D)
    {
        SetCommandFlags("sv_crash", GetCommandFlags("sv_crash") & ~FCVAR_CHEAT);
        ServerCommand("sv_crash");
        ServerCommand("_restart");
    }
    return Plugin_Continue;
}

Action Timer_Cmd_RestartServer(Handle timer)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
            KickClient(i, "Server is restarting..");
    }

    UnloadAccelerator();
    CreateTimer(0.2, Timer_RestartServer);
    return Plugin_Continue;
}

void UnloadAccelerator()
{
    char buffer[4096];
    ServerCommandEx(buffer, sizeof(buffer), "sm exts list");

    Regex regex = new Regex("\\[([0-9]+)\\] Accelerator");
    if (regex.Match(buffer) > 0)
    {
        char num[4];
        regex.GetSubString(1, num, sizeof(num));
        ServerCommand("sm exts unload %s 0", num);
        ServerExecute();
    }
    delete regex;
}

bool CheckPlayerInGame(int skip)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (i != skip && IsClientConnected(i) && !IsFakeClient(i))
            return true;
    }
    return false;
}

Action ServerCmd_map(int client, const char[] command, int argc)
{
    if (!g_bGameL4D)
        return Plugin_Continue;

    g_bCmdMap = true;
    g_hConVarHibernate.SetBool(false);
    delete COLD_DOWN_Timer;
    return Plugin_Continue;
}

bool IsHeizepugsMatchActive()
{
    if (g_hHeizepugsMatchId == null)
        return false;

    char matchId[64];
    g_hHeizepugsMatchId.GetString(matchId, sizeof(matchId));

    return !(matchId[0] == '\0' || StrEqual(matchId, "64.0000"));
}
