/**
 * 正確使用round_start
 */

#include <sourcemod>
#include <left4dhooks>
#include <colors>
#undef REQUIRE_PLUGIN
#include <readyup>
#define REQUIRE_PLUGIN

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0.5-2025/1/8"

public Plugin myinfo =
{
    name = "Special Infected Class Announce [Translations Ver]",
    author = "Tabun, Forgetest, PaaNChaN, heize",
    description = "Report what SI classes are up when the round starts AFTER boss percentage on footer.",
    version = PLUGIN_VERSION,
    url = "none"
}

#define ZC_SMOKER               1
#define ZC_BOOMER               2
#define ZC_HUNTER               3
#define ZC_SPITTER              4
#define ZC_JOCKEY               5
#define ZC_CHARGER              6
#define ZC_WITCH                7
#define ZC_TANK                 8

#define TEAM_SPECTATOR			1
#define TEAM_SURVIVOR			2
#define TEAM_INFECTED			3

#define MAXSPAWNS               8

#define CHAT_FLAG        (1 << 0)
#define HINT_FLAG        (1 << 1)

static const char g_csSIClassName[][] =
{
    "",
    "Smoker",
    "Boomer",
    "Hunter",
    "Spitter",
    "Jockey",
    "Charger",
    "",
    ""
};

Handle
	g_hAddFooterTimer;
	
ConVar
	g_hCvarFooter,
	g_hCvarPrint;
	
bool
	g_bRoundStarted,
	g_bAllowFooter,
	g_bMessagePrinted,
	g_bReadyUpFooterAdded;

int 
    g_iRoundStart, 
    g_iPlayerSpawn,
	g_iReadyUpFooterIndex; 

public void OnPluginStart()
{
	g_hCvarFooter	= CreateConVar(	"si_announce_ready_footer",
									"1",
									"Enable si class string be added to readyup panel as footer (if available).",
									FCVAR_NOTIFY, true, 0.0, true, 1.0);
	
	g_hCvarPrint	= CreateConVar(	"si_announce_print",
									"1",
									"Decide where the plugin prints the announce. (0: Disable, 1: Chat, 2: Hint, 3: Chat and Hint)",
									FCVAR_NOTIFY, true, 0.0, true, 3.0);
									
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("player_spawn",           Event_PlayerSpawn);
	HookEvent("round_end",				Event_RoundEnd,		EventHookMode_PostNoCopy); //trigger twice in versus/survival/scavenge mode, one when all survivors wipe out or make it to saferom, one when first round ends (second round_start begins).
	HookEvent("map_transition", 		Event_RoundEnd,		EventHookMode_PostNoCopy); //1. all survivors make it to saferoom in and server is about to change next level in coop mode (does not trigger round_end), 2. all survivors make it to saferoom in versus
	HookEvent("mission_lost", 			Event_RoundEnd,		EventHookMode_PostNoCopy); //all survivors wipe out in coop mode (also triggers round_end)
	HookEvent("finale_vehicle_leaving", Event_RoundEnd,		EventHookMode_PostNoCopy); //final map final rescue vehicle leaving  (does not trigger round_end)

	HookEvent("player_left_start_area", Event_PlayerLeftStartArea, EventHookMode_Post);
	HookEvent("player_team", Event_PlayerTeam);

	LoadTranslations("si_class_announce.phrases");
}

public void OnMapEnd()
{
	ClearDefault();
	delete g_hAddFooterTimer;

	g_bRoundStarted = false;
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if( g_iPlayerSpawn == 1 && g_iRoundStart == 0 )
		CreateTimer(0.5, Timer_PluginStart, _, TIMER_FLAG_NO_MAPCHANGE);
	g_iRoundStart = 1;

	g_bMessagePrinted = false;
	g_bRoundStarted = true;
	g_bAllowFooter = false;

	g_iReadyUpFooterIndex = -1;
	g_bReadyUpFooterAdded = false;
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{ 
	if( g_iPlayerSpawn == 0 && g_iRoundStart == 1 )
		CreateTimer(0.5, Timer_PluginStart, _, TIMER_FLAG_NO_MAPCHANGE);
	g_iPlayerSpawn = 1;	
}

Action Timer_PluginStart(Handle timer)
{
	ClearDefault();

	if (g_hCvarFooter.BoolValue)
	{
		delete g_hAddFooterTimer;
		g_hAddFooterTimer = CreateTimer(7.0, UpdateReadyUpFooter);
		CreateTimer(6.5, g_bAllowFooter_true, _, TIMER_FLAG_NO_MAPCHANGE);
	}

	return Plugin_Continue;
}

Action g_bAllowFooter_true(Handle timer)
{
	g_bAllowFooter = true;

	return Plugin_Continue;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	ClearDefault();

	g_bRoundStarted = false;
}

void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bAllowFooter) return;
	
	if (!g_bRoundStarted) return;
	
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client) return;
	
	if (event.GetInt("team") == TEAM_INFECTED)
	{
		delete g_hAddFooterTimer;
		g_hAddFooterTimer = CreateTimer(1.0, UpdateReadyUpFooter);
	}
}

Action UpdateReadyUpFooter(Handle timer)
{
	g_hAddFooterTimer = null;
	
	if (!IsInfectedTeamFullAlive() || !g_bAllowFooter)
		return Plugin_Stop;
	
	// get currently active SI classes
	int iSpawns;
	int iSpawnClass[MAXSPAWNS];

	GetSpawnClass(iSpawns, iSpawnClass);

	char msg[65];
	if (ProcessSIString(msg, sizeof(msg), true))
	{	
		// Check to see if the Ready Up footer has already been added 
		if (g_bReadyUpFooterAdded) 
		{
			// Ready Up footer already exists, so we can just edit it.
			EditFooterStringAtIndex(g_iReadyUpFooterIndex, msg);
		}
		else
		{
			// Ready Up footer hasn't been added yet. Must be the start of a new round! Lets add it.
			g_iReadyUpFooterIndex = AddStringToReadyFooter(msg);
			g_bReadyUpFooterAdded = true;
		}
	}

	return Plugin_Stop;
}

public void OnRoundIsLive()
{
	if (g_hCvarPrint.IntValue == 0)
		return;
	
	// get currently active SI classes
	int iSpawns;
	int iSpawnClass[MAXSPAWNS];

	GetSpawnClass(iSpawns, iSpawnClass);

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientShowAnnounceSI(client))
		{
			// announce SI classes up now
			char msg[256];

			if (ProcessSIString(msg, sizeof(msg)))
			{
				AnnounceSIClasses(msg, client);
			}
		}
	}

	g_bMessagePrinted = true;
}

void Event_PlayerLeftStartArea(Event event, const char[] name, bool dontBroadcast)
{
	if( L4D_GetGameModeType() == GAMEMODE_VERSUS )
	{
		// if no readyup, use this as the starting event
		if (!g_bMessagePrinted) {

			// get currently active SI classes
			int iSpawns;
			int iSpawnClass[MAXSPAWNS];

			GetSpawnClass(iSpawns, iSpawnClass);

			for (int client = 1; client <= MaxClients; client++)
			{			
				if (IsClientShowAnnounceSI(client))
				{
					// announce SI classes up now
					char msg[256];

					if (ProcessSIString(msg, sizeof(msg)) && g_hCvarPrint.IntValue != 0)
					{
						AnnounceSIClasses(msg, client);
					}
				}
			}
				
			// no matter printed or not, we won't bother the game since survivor leaves saferoom.
			g_bMessagePrinted = true;
		}
	}
}

#define COLOR_PARAM "%s{red}%s{default}"
#define NORMA_PARAM "%s%s"

bool ProcessSIString(char[] msg, int maxlength, bool footer = false)
{
	// get currently active SI classes
	int iSpawns;
	int iSpawnClass[MAXSPAWNS];
	
	for (int i = 1; i <= MaxClients && iSpawns < MAXSPAWNS; i++) {
		if (!IsClientInGame(i) || GetClientTeam(i) != TEAM_INFECTED || !IsPlayerAlive(i)) { continue; }
		
		iSpawnClass[iSpawns] = GetEntProp(i, Prop_Send, "m_zombieClass");
		
		if (iSpawnClass[iSpawns] != ZC_WITCH && iSpawnClass[iSpawns] != ZC_TANK)
			iSpawns++;
	}
	
	// found nothing :/
	if (!iSpawns) {
		return false;
	}

	char translate[32];

	if(footer)
	{
		Format(translate, sizeof(translate), "%T", "SI", LANG_SERVER);
		strcopy(msg, maxlength, translate);
	}
	else
	{
		Format(translate, sizeof(translate), "%T", "SpecialInfected", LANG_SERVER);
		strcopy(msg, maxlength, translate);
	}
	
	int printFlags = g_hCvarPrint.IntValue;
	bool useColor = !footer && (printFlags & CHAT_FLAG);
	
	// format classes, according to amount of spawns found
	for (int i = 0; i < iSpawns; i++) {
		if (i) StrCat(msg, maxlength, ", ");
		
		Format(	msg,
				maxlength,
				(useColor ? COLOR_PARAM : NORMA_PARAM),
				msg,
				g_csSIClassName[iSpawnClass[i]]
		);
	}
	
	return true;
}

void AnnounceSIClasses(const char[] Message, int client)
{
	char temp[256];
	
	int printFlags = g_hCvarPrint.IntValue;
	if (printFlags & HINT_FLAG)
	{
		strcopy(temp, sizeof temp, Message);
		CRemoveTags(temp, sizeof temp);
	}
	
	if (printFlags & CHAT_FLAG) CPrintToChat(client, Message);
	if (printFlags & HINT_FLAG) PrintHintText(client, temp);
}

stock bool IsInfectedTeamFullAlive()
{
	static ConVar cMaxZombies;
	if (!cMaxZombies) cMaxZombies = FindConVar("z_max_player_zombies");
	
	int players = 0;
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && GetClientTeam(i) == TEAM_INFECTED && IsPlayerAlive(i)) players++;
	}
	return players == cMaxZombies.IntValue;
}

void GetSpawnClass(int &iSpawns, int[] iSpawnClass)
{	
	for (int i = 1; i <= MaxClients && iSpawns < MAXSPAWNS; i++)
	{
		if (!IsClientInGame(i) || GetClientTeam(i) != TEAM_INFECTED || !IsPlayerAlive(i)) { continue; }
		
		iSpawnClass[iSpawns] = GetEntProp(i, Prop_Send, "m_zombieClass");
		
		if (iSpawnClass[iSpawns] != ZC_WITCH && iSpawnClass[iSpawns] != ZC_TANK)
			iSpawns++;
	}
}

stock bool IsClientShowAnnounceSI(int client)
{
	return IsClientInGame(client) && GetClientTeam(client) != TEAM_INFECTED && (!IsFakeClient(client) || IsClientSourceTV(client));
}

void ClearDefault()
{
	g_iRoundStart = 0;
	g_iPlayerSpawn = 0;
}