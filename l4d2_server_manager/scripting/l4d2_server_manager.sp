#include <sourcemod>
#include <sdktools>

#define MAX_STR_LEN 128

new bool:isFirstMapStart = true;
new bool:isSwitchingMaps = true;
new bool:startedTimer = false;
new Handle:switchMapTimer = INVALID_HANDLE;
new float:lastDisconnectTime = 0.0;

public Plugin myinfo =
{
    name = "L4D2 Server Manager",
    author = "heize",
    description = "Restarts server automatically.",
    version = "1.5",
    url = "https://github.com/h3ize/"
};

public void OnPluginStart()
{
    new ConVar:cvarHibernateWhenEmpty = FindConVar("sv_hibernate_when_empty");
    SetConVarInt(cvarHibernateWhenEmpty, 0, false, false);

    RegAdminCmd("sm_rs", KickClientsAndRestartServer, ADMFLAG_ROOT, "Kicks all clients and restarts server");
    RegAdminCmd("sm_restart", KickClientsAndRestartServer, ADMFLAG_ROOT, "Kicks all clients and restarts server");
    HookEvent("player_disconnect", Event_PlayerDisconnect);
}

public void OnPluginEnd()
{
    CrashIfNoHumans(INVALID_HANDLE);
}

public Action KickClientsAndRestartServer(int client, int args)
{
    char kickMessage[MAX_STR_LEN];

    if (GetCmdArgs() >= 1) {
        GetCmdArgString(kickMessage, MAX_STR_LEN);
    } else {
        strcopy(kickMessage, MAX_STR_LEN, "Server is restarting");
    }

    for (new i = 1; i <= MaxClients; ++i) {
        if (IsHuman(i)) {
            KickClient(i, kickMessage);
        }
    }

    CrashServer();
    return Plugin_Stop;
}

public void OnMapStart()
{
    if (!isFirstMapStart && !startedTimer) {
        CreateTimer(30.0, CrashIfNoHumans, _, TIMER_REPEAT);
        startedTimer = true;
    }

    if (switchMapTimer != INVALID_HANDLE) {
        KillTimer(switchMapTimer);
    }

    switchMapTimer = CreateTimer(15.0, SwitchedMap);
    isFirstMapStart = false;
}

public void OnMapEnd()
{
    isSwitchingMaps = true;
}

public Action SwitchedMap(Handle timer)
{
    isSwitchingMaps = false;
    switchMapTimer = INVALID_HANDLE;
    return Plugin_Stop;
}

public Action CrashIfNoHumans(Handle timer)
{
    if (!isSwitchingMaps && !HumanFound()) {
        CrashServer();
    }
    return Plugin_Continue;
}

public bool HumanFound()
{
    for (new i = 1; i <= MaxClients; i++) {
        if (IsHuman(i)) {
            return true;
        }
    }
    return false;
}

public bool IsHuman(int client)
{
    return IsClientInGame(client) && !IsFakeClient(client);
}

public void CrashServer()
{
    PrintToServer("Crashing the server for a restart..");
    SetCommandFlags("crash", GetCommandFlags("crash") & ~FCVAR_CHEAT);
    ServerCommand("crash");
}

public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0) {
        return;
    }

    if (!IsClientConnected(client)) {
        return;
    }

    if (IsFakeClient(client)) {
        return;
    }

    float disconnectTime = GetGameTime();

    if (lastDisconnectTime == disconnectTime) {
        return;
    }

    lastDisconnectTime = disconnectTime;
    CreateTimer(1.0, Timer_PlayerDisconnect, Float:disconnectTime);
}

public Action Timer_PlayerDisconnect(Handle timer, any data)
{
    float disconnectTime = view_as<float>(data);

    if (disconnectTime != -1.0 && disconnectTime != lastDisconnectTime) {
        return Plugin_Stop;
    }

    if (!ServerIsEmpty()) {
        return Plugin_Stop;
    }

    CrashServer();
    return Plugin_Stop;
}

public bool ServerIsEmpty()
{
    for (new i = 1; i <= MaxClients; i++) {
        if (IsClientConnected(i) && !IsFakeClient(i)) {
            return false;
        }
    }
    return true;
}

public int GetSeriousClientCount()
{
    new count = 0;
    for (new i = 1; i <= MaxClients; i++) {
        if (IsClientConnected(i) && !IsFakeClient(i)) {
            count++;
        }
    }
    return count;
}
