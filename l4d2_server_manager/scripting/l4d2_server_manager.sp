#include <sourcemod>

#define MAX_STR_LEN 128

new ConVar:g_cvHibernateWhenEmpty;
new Float:g_fLastDisconnectTime;
new bool:g_bHibernateDisabled;
new bool:g_bFirstMapStart = true;
new bool:g_bSwitchingMaps = true;
new bool:g_bStartedTimer;
new Handle:g_hSwitchMapTimer;

public Plugin:myinfo =
{
    name = "L4D2 Server Manager",
    description = "Restarts server automatically when empty.",
    author = "heize",
    version = "1.0",
    url = "https://github.com/h3ize/"
};

void ConVarChanged_HibernateWhenEmpty(ConVar:_arg0, String:_arg1[], String:_arg2[])
{
    g_cvHibernateWhenEmpty.SetBool(false, false, false);
}

Action SwitchedMap(Handle:_arg0)
{
    g_bSwitchingMaps = false;
    g_hSwitchMapTimer = INVALID_HANDLE;
    return Plugin_Stop;
}

Action CrashIfNoHumans(Handle:_arg0)
{
    if (!g_bSwitchingMaps)
    {
        if (!HumanFound())
        {
            CrashServer();
        }
    }
    return Plugin_Continue;
}

bool HumanFound()
{
    new var1 = 1;
    while (var1 <= MaxClients)
    {
        if (IsHuman(var1))
        {
            return true;
        }
        var1++;
    }
    return false;
}

bool IsHuman(_arg0)
{
    return IsClientInGame(_arg0) && !IsFakeClient(_arg0);
}

void CrashServer()
{
    PrintToServer("Server Restarter Plugin: Crashing the server...");
    SetCommandFlags("crash", GetCommandFlags("crash") & ~FCVAR_CHEAT);
    ServerCommand("crash");
}

void Event_PlayerDisconnect(Event:_arg0, String:_arg1[], bool:_arg2)
{
    new var1 = GetClientOfUserId(_arg0.GetInt("userid", 0));
    if (var1 <= 0)
    {
        return;
    }
    if (IsClientConnected(var1))
    {
        if (IsFakeClient(var1))
        {
            return;
        }
        new Float:var2 = GetGameTime();
        if (g_fLastDisconnectTime == var2)
        {
            return;
        }
        g_fLastDisconnectTime = var2;
        CreateTimer(0.5, Timer_PlayerDisconnect, var2);
    }
}

Action Timer_PlayerDisconnect(Handle:_arg0, any:_arg1)
{
    if (_arg1 != -1082130432)
    {
        if (g_fLastDisconnectTime != _arg1)
        {
            return Plugin_Continue;
        }
    }
    if (ServerIsEmpty())
    {
        CrashServer();
        return Plugin_Stop;
    }
    return Plugin_Continue;
}

bool ServerIsEmpty()
{
    new var1 = 1;
    while (var1 <= MaxClients)
    {
        if (IsClientConnected(var1))
        {
            if (!IsFakeClient(var1))
            {
                return false;
            }
        }
        var1++;
    }
    return true;
}

public void OnClientPutInServer(_arg0)
{
    if (!IsFakeClient(_arg0))
    {
        if (!g_bHibernateDisabled)
        {
            g_cvHibernateWhenEmpty.SetBool(false, false, false);
            g_cvHibernateWhenEmpty.AddChangeHook(ConVarChanged_HibernateWhenEmpty);
        }
    }
}

public void OnMapEnd()
{
    g_bSwitchingMaps = true;
}

public void OnMapStart()
{
    if (!g_bFirstMapStart)
    {
        if (!g_bStartedTimer)
        {
            CreateTimer(30.0, CrashIfNoHumans, _, TIMER_REPEAT);
            g_bStartedTimer = true;
        }
    }
    if (g_hSwitchMapTimer != INVALID_HANDLE)
    {
        KillTimer(g_hSwitchMapTimer);
    }
    g_hSwitchMapTimer = CreateTimer(15.0, SwitchedMap);
    g_bFirstMapStart = false;
}

public void OnPluginStart()
{
    g_cvHibernateWhenEmpty = FindConVar("sv_hibernate_when_empty");
    g_cvHibernateWhenEmpty.SetBool(false, false, false);
    HookEvent("player_disconnect", Event_PlayerDisconnect);
    RegAdminCmd("sm_restart", AdminRestartServer, ADMFLAG_ROOT, "Kicks all clients and restarts server");
    RegAdminCmd("sm_rs", AdminRestartServer, ADMFLAG_ROOT, "Kicks all clients and restarts server");
}

public Action AdminRestartServer(client, args)
{
    char kickMessage[MAX_STR_LEN];

    if (GetCmdArgs() >= 1)
    {
        GetCmdArgString(kickMessage, MAX_STR_LEN);
    }
    else
    {
        strcopy(kickMessage, MAX_STR_LEN, "Server is now restarting..");
    }

    for (new i = 1; i <= MaxClients; ++i)
    {
        if (IsHuman(i))
        {
            KickClient(i, kickMessage);
        }
    }

    CrashServer();
    return Plugin_Stop;
}
