#include <sourcemod>
#include <sdktools_client>
#include <colors>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
    name = "Reconnect Command",
    author = "heize",
    description = "Simply as the name says. Ripped this from Caster System plugin, thanks CanadaRox & Forgetest",
    version = "1.3",
    url = "https://github.com/h3ize/L4D2-Plugins"
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_rejoin", Cmd_Rejoin);
    RegConsoleCmd("sm_reconnect", Cmd_Rejoin);
    RegConsoleCmd("sm_rj", Cmd_Rejoin);
}

public Action Cmd_Rejoin(int client, int args)
{
    if (!IsClientInGame(client))
        return Plugin_Handled;

    CPrintToChat(client, "{olive}[SM]{default} Rejoining in {green}3 seconds{default}...");
    CreateTimer(3.0, Timer_Rejoin, client);
    return Plugin_Handled;
}

public Action Timer_Rejoin(Handle timer, int client)
{
    if (IsClientConnected(client))
    {
        ReconnectClient(client);
    }
    return Plugin_Stop;
}
