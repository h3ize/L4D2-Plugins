#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <discord_webhook>
#include "finalemaps"

#define DEBUG 1

#define CONBUFSIZELARGE         (1 << 12)       // 4k
#define ROUNDEND_DELAY          3.0
#define IS_VALID_CLIENT(%1)     (%1 > 0 && %1 <= MaxClients)
#define IS_SURVIVOR(%1)         (GetClientTeam(%1) == TEAM_SURVIVOR)
#define IS_INFECTED(%1)         (GetClientTeam(%1) == TEAM_INFECTED)
#define IS_VALID_INGAME(%1)     (IS_VALID_CLIENT(%1) && IsClientInGame(%1))
#define IS_VALID_SURVIVOR(%1)   (IS_VALID_INGAME(%1) && IS_SURVIVOR(%1))
#define IS_VALID_INFECTED(%1)   (IS_VALID_INGAME(%1) && IS_INFECTED(%1))

#define TEAM_SPECTATOR          1
#define TEAM_SURVIVOR           2
#define TEAM_INFECTED           3

#define MAXMAP                  32

bool g_bInRound = false;
int iTankPercent = 0;
int scoreTotals[2];
char sPlayers[2][512];
char titles[2][64];
char sEmbedRequest[CONBUFSIZELARGE];
int iEmbedCount = 0;
Handle  g_hCvarWebhookConfig = INVALID_HANDLE;
char g_sWebhookName[64];

public Plugin myinfo =
{
    name = "Discord Scoreboard 2.0",
    author = "devilesk, heize",
    description = "Reports round end stats to discord",
    version = "2.0",
    url = "https://github.com/devilesk/rl4d2l-plugins"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    RegPluginLibrary("discord_scoreboard");
    
    CreateNative("AddEmbed", Native_AddEmbed);
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_hCvarWebhookConfig = CreateConVar("discord_scoreboard_webhook_cfg", "discord_scoreboard", "Name of webhook keyvalue entry to use in discord_webhook.cfg", FCVAR_NONE);
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
}

public void OnMapStart()
{
    sEmbedRequest[0] = '\0';
    iEmbedCount = 0;
}

public void Event_RoundStart(Handle hEvent, const char[] name, bool dontBroadcast)
{
    g_bInRound = true;
    int indexSurvivor = GameRules_GetProp("m_bAreTeamsFlipped");
    int indexInfected = 1 - indexSurvivor;
    scoreTotals[indexSurvivor] = GameRules_GetProp("m_iCampaignScore", 2, indexSurvivor);
    scoreTotals[indexInfected] = GameRules_GetProp("m_iCampaignScore", 2, indexInfected);
    CreateTimer(6.0, SaveBossFlows, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action SaveBossFlows(Handle timer)
{
    if (!InSecondHalfOfRound())
    {
        iTankPercent = 0;

        if (L4D2Direct_GetVSTankToSpawnThisRound(0))
        {
            iTankPercent = RoundToNearest(GetTankFlow(0)*100.0);
        }
    }
    else
    {
        if (iTankPercent != 0)
        {
            iTankPercent = RoundToNearest(GetTankFlow(1)*100.0);
        }
    }
    return Plugin_Stop;
}

public void Event_RoundEnd(Handle hEvent, const char[] name, bool dontBroadcast)
{
    if (!g_bInRound) { return; }
    g_bInRound = false;
    CreateTimer(ROUNDEND_DELAY, Timer_RoundEnd, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RoundEnd(Handle timer)
{
    char sHostname[128];
    char sMap[64];
    char description[512];
    
    // Reset sPlayers array
    sPlayers[0][0] = '\0';
    sPlayers[1][0] = '\0';
    
    GetConVarString(FindConVar("hostname"), sHostname, sizeof(sHostname));
    GetCurrentMapLower(sMap, sizeof(sMap));
    GetMapName(sMap, sMap, sizeof(sMap));
    
    int indexSurvivor = GameRules_GetProp("m_bAreTeamsFlipped");
    int indexInfected = 1 - indexSurvivor;
    int totalSurvivor = GameRules_GetProp("m_iCampaignScore", 2, indexSurvivor);
    int totalInfected = GameRules_GetProp("m_iCampaignScore", 2, indexInfected);
    int roundSurvivor = totalSurvivor - scoreTotals[indexSurvivor];
    int roundInfected = totalInfected - scoreTotals[indexInfected];
    scoreTotals[indexSurvivor] = totalSurvivor;
    scoreTotals[indexInfected] = totalInfected;
    
    // Determine winning and losing teams
    int winningTeamIndex = (totalSurvivor > totalInfected) ? indexSurvivor : indexInfected;
    int losingTeamIndex = (totalSurvivor > totalInfected) ? indexInfected : indexSurvivor;
    
    Format(titles[winningTeamIndex], 64, "Winning Team: [%d]", (totalSurvivor > totalInfected) ? totalSurvivor : totalInfected);
    Format(titles[losingTeamIndex], 64, "Losing Team: [%d]", (totalSurvivor > totalInfected) ? totalInfected : totalSurvivor);
    
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IS_VALID_SURVIVOR(client))
        {
            if (indexSurvivor == winningTeamIndex)
            {
                Format(sPlayers[winningTeamIndex], 512, "%s%N\\n", sPlayers[winningTeamIndex], client);
            }
            else
            {
                Format(sPlayers[losingTeamIndex], 512, "%s%N\\n", sPlayers[losingTeamIndex], client);
            }
        }
        else if (IS_VALID_INFECTED(client))
        {
            if (indexInfected == winningTeamIndex)
            {
                Format(sPlayers[winningTeamIndex], 512, "%s%N\\n", sPlayers[winningTeamIndex], client);
            }
            else
            {
                Format(sPlayers[losingTeamIndex], 512, "%s%N\\n", sPlayers[losingTeamIndex], client);
            }
        }
    }
    
    if (!sPlayers[winningTeamIndex][0])
    {
        strcopy(sPlayers[winningTeamIndex], 512, "None");
    }
    if (!sPlayers[losingTeamIndex][0])
    {
       strcopy(sPlayers[losingTeamIndex], 512, "None");
    }
    
    if (InSecondHalfOfRound())
    {
        char fields[CONBUFSIZELARGE];
        Format(fields, CONBUFSIZELARGE, "{\"name\":\"%s\",\"value\":\"%s\",\"inline\":%d},{\"name\":\"%s\",\"value\":\"%s\",\"inline\":%d}", titles[winningTeamIndex], sPlayers[winningTeamIndex], 1, titles[losingTeamIndex], sPlayers[losingTeamIndex], 1);
        InternalAddEmbed(sHostname, sMap, "", 2829617, fields);
        FormatEmbedRequest(sEmbedRequest, sizeof(sEmbedRequest), sEmbedRequest);
        GetConVarString(g_hCvarWebhookConfig, g_sWebhookName, sizeof(g_sWebhookName));
        SendToDiscord(g_sWebhookName, sEmbedRequest);
        
        if (IsMissionFinalMap())
        {
            scoreTotals[0] = 0;
            scoreTotals[1] = 0;
        }
    }
    return Plugin_Stop;
}


bool GetMapName(const char[] mapId, char[] mapName, int iLength)
{
    KeyValues kv = new KeyValues("DiscordScoreboard");

    char sFile[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sFile, sizeof(sFile), "configs/discord_scoreboard.cfg");

    if (!FileExists(sFile))
    {
        SetFailState("[GetMapName] \"%s\" not found!", sFile);
        return false;
    }

    kv.ImportFromFile(sFile);

    if (!kv.JumpToKey(mapId, false))
    {
        SetFailState("[GetMapName] Can't find map \"%s\" in \"%s\"!", mapId, sFile);
        delete kv;
        return false;
    }
    kv.GetString(NULL_STRING, mapName, iLength);
    delete kv;
    return true;
}

stock float GetTankFlow(int round)
{
    return L4D2Direct_GetVSTankFlowPercent(round);
}

public int Native_AddEmbed(Handle plugin, int numParams)
{
    int len;

    GetNativeStringLength(1, len);
    char[] title = new char[len+1];
    GetNativeString(1, title, len+1);

    GetNativeStringLength(2, len);
    char[] description = new char[len+1];
    GetNativeString(2, description, len+1);

    GetNativeStringLength(3, len);
    char[] url = new char[len+1];
    GetNativeString(3, url, len+1);
    
    int color = GetNativeCell(4);
    
    char fields[CONBUFSIZELARGE];
    char name[256];
    char value[256];
    int inline;
    
        for (int i = 5; i <= numParams; i+=3)
    {
        // field name
        GetNativeStringLength(i, len);
        if (len <= 0) { return 0; }
        GetNativeString(i, name, len+1);
        
        // field value
        GetNativeStringLength(i+1, len);
        if (len <= 0) { return 0; }
        GetNativeString(i+1, value, len+1);
        
        inline = GetNativeCellRef(i+2);
        
        if (i == 5)
        {
            Format(fields, CONBUFSIZELARGE, "{\"name\":\"%s\",\"value\":\"%s\",\"inline\":%d}", name, value, inline);
        }
        else
        {
            Format(fields, CONBUFSIZELARGE, "%s,{\"name\":\"%s\",\"value\":\"%s\",\"inline\":%d}", fields, name, value, inline);
        }
    }
    
    InternalAddEmbed(title, description, url, color, fields);
    return 1;
}

void InternalAddEmbed(const char[] title, const char[] description, const char[] url, int color, const char[] fields)
{
    char sEmbed[CONBUFSIZELARGE];
    FormatEmbed2(sEmbed, sizeof(sEmbed), title, description, url, color, fields);
    if (iEmbedCount == 0) {
        strcopy(sEmbedRequest, sizeof(sEmbedRequest), sEmbed);
    }
    else {
        Format(sEmbedRequest, sizeof(sEmbedRequest), "%s,%s", sEmbedRequest, sEmbed);
		}
    iEmbedCount++;
}

int InSecondHalfOfRound()
{
    return GameRules_GetProp("m_bInSecondHalfOfRound");
}