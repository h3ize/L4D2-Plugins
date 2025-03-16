#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "2.1.3"

#define TEAM_SPEC 1
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

ConVar hAllTalk;

public Plugin myinfo =
{
    name = "Spectator-AllTalk",
    author = "heize",
    description = "Allows spectators to hear players.",
    version = PLUGIN_VERSION,
    url = "http://github.com/h3ize"
}

public void OnPluginStart()
{
    HookEvent("player_team", Event_PlayerChangeTeam);
    hAllTalk = FindConVar("sv_alltalk");
    hAllTalk.AddChangeHook(OnAlltalkChange);
}

void OnAlltalkChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (StringToInt(newValue) == 0)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsValidClient(i) && GetClientTeam(i) == TEAM_SPEC)
            {
                SetClientListeningFlags(i, VOICE_LISTENALL);
            }
        }
    }
}

void Event_PlayerChangeTeam(Event event, const char[] name, bool dontBroadcast)
{
    int userID = GetClientOfUserId(GetEventInt(event, "userid"));
    if (IsValidClient(userID))
    {
        if (event.GetInt("team") == TEAM_SPEC)
        {
            SetClientListeningFlags(userID, VOICE_LISTENALL);
        }
        else
        {
            SetClientListeningFlags(userID, VOICE_NORMAL);
        }
    }
}

public void OnClientDisconnect(int client)
{
    if (client > 0 && !IsFakeClient(client) && GetClientTeam(client) != TEAM_SPEC)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsValidClient(i) && GetClientTeam(i) == TEAM_SPEC)
            {
                ClientCommand(i, "chooseteam");
            }
        }
    }
}

stock int IsValidClient(int client)
{
    return client > 0 && IsClientConnected(client) && !IsFakeClient(client) && IsClientInGame(client);
}
