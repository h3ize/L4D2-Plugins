#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#define L4D2UTIL_STOCKS_ONLY 1
#include <l4d2util> //IsTank

//L4D2_OnEndVersusModeRound
#include <left4dhooks> //#include <left4downtown>

#define DEBUG_MODE 0

Handle
	g_hForwardRequestUpdate = null; // request final update before round ends

ConVar
	g_hCvarEnabled = null,
	g_hCvarBonusTank = null,
	g_hCvarBonusWitch = null,
	g_hCvarDefibPenalty = null;

bool
	g_bSecondHalf = false,
	g_bFirstMapStartDone = false,		// so we can set the config-set defib penalty
	g_bRoundOver[2] = {false, false};	// tank/witch deaths don't count after this true

int
	g_iOriginalPenalty = 25,			// original defib penalty
	g_iDefibsUsed[2] = {0, 0},			// defibs used this round
	g_iBonus[2] = {0, 0};				// bonus to be added when this round ends

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int sErrMax)
{
	g_hForwardRequestUpdate = CreateGlobalForward("PBONUS_RequestFinalUpdate", ET_Single, Param_CellByRef);

	CreateNative("PBONUS_GetRoundBonus", Native_GetRoundBonus);
	CreateNative("PBONUS_ResetRoundBonus", Native_ResetRoundBonus);
	CreateNative("PBONUS_SetRoundBonus", Native_SetRoundBonus);
	CreateNative("PBONUS_AddRoundBonus", Native_AddRoundBonus);
	CreateNative("PBONUS_GetDefibsUsed", Native_GetDefibsUsed);
	CreateNative("PBONUS_SetDefibPenalty", Native_SetDefibPenalty);

	RegPluginLibrary("penaltybonus");
	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "Kill the Boss.",
	author = "heize",
	description = "Killing a boss gives additional score. Ripped from penalty.",
	version = "3",
	url = "https://github.com/h3ize"
};

// Init and round handling
// -----------------------
public void OnPluginStart()
{
	// store original penalty
	g_hCvarDefibPenalty = FindConVar("vs_defib_penalty");

	// cvars
	g_hCvarEnabled = CreateConVar("sm_pbonus_enable", "1", "Whether the penalty-bonus system is enabled.", _, true, 0.0, true, 1.0);
	g_hCvarBonusTank = CreateConVar("sm_bonus_tank", "25", "Give this much bonus when a tank is killed (0 to disable entirely).", _, true, 0.0);
	g_hCvarBonusWitch = CreateConVar("sm_bonus_witch", "25", "Give this much bonus when a witch is killed (0 to disable entirely).", _, true, 0.0);

	// hook events
	HookEvent("defibrillator_used", Event_DefibUsed, EventHookMode_PostNoCopy);
	HookEvent("witch_killed", Event_WitchKilled, EventHookMode_PostNoCopy);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
}

public void OnPluginEnd()
{
	g_hCvarDefibPenalty.SetInt(g_iOriginalPenalty);
}

public void OnMapStart()
{
	if (!g_bFirstMapStartDone) {
		g_iOriginalPenalty = g_hCvarDefibPenalty.IntValue;
		g_bFirstMapStartDone = true;
	}

	g_hCvarDefibPenalty.SetInt(g_iOriginalPenalty);

	g_bSecondHalf = false;

	for (int i = 0; i < 2; i++) {
		g_bRoundOver[i] = false;
		g_iDefibsUsed[i] = 0;
	}
}

public void OnMapEnd()
{
	g_bSecondHalf = false;
}

void Event_RoundStart(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	// reset
	g_hCvarDefibPenalty.SetInt(g_iOriginalPenalty);

	g_iBonus[RoundNum()] = 0;
}

void Event_RoundEnd(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	// Fix double event call
	float fRoundEndTime = GameRules_GetPropFloat("m_flRoundEndTime");
	if (fRoundEndTime != GetGameTime()) {
		return;
	}

	g_bRoundOver[RoundNum()] = true;
	g_bSecondHalf = true;

	if (g_hCvarEnabled.BoolValue) {
		DisplayBonus();
	}
}

// Tank and Witch tracking
// -----------------------
void Event_PlayerDeath(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	if (!g_hCvarEnabled.BoolValue) {
		return;
	}

	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));

	if (iClient && IsTank(iClient)) {
		TankKilled();
	}
}

void TankKilled()
{
	int iTankBonus = g_hCvarBonusTank.IntValue;

	if (iTankBonus == 0 || g_bRoundOver[RoundNum()]) {
		return;
	}

	g_iBonus[RoundNum()] += iTankBonus;
	ReportChange(iTankBonus);
}

void Event_WitchKilled(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	if (!g_hCvarEnabled.BoolValue) {
		return;
	}

	int iWitchBonus = g_hCvarBonusWitch.IntValue;
	if (iWitchBonus == 0 || g_bRoundOver[RoundNum()]) {
		return;
	}

	g_iBonus[RoundNum()] += iWitchBonus;
	ReportChange(iWitchBonus);
}

// Special Check (test)
// --------------------
public Action L4D2_OnEndVersusModeRound(bool bCountSurvivors)
{
	int iUpdateScore = 0, iUpdateResult = 0;

	// get update before setting the bonus
	Call_StartForward(g_hForwardRequestUpdate);
	Call_PushCellRef(iUpdateScore);
	Call_Finish(iUpdateResult);

	// add the update to the round's bonus
	g_iBonus[RoundNum()] += iUpdateResult;

	SetBonus();

	return Plugin_Continue;
}

// Bonus
// -----
void SetBonus()
{
	// only change anything if there's a bonus to set at all
	if (g_iBonus[RoundNum()] == 0) {
		g_hCvarDefibPenalty.SetInt(g_iOriginalPenalty );
		return;
	}

	// set the bonus as though only 1 defib was used: so 1 * CalculateBonus
	int iBonus = CalculateBonus();

	// set bonus(penalty) cvar
	g_hCvarDefibPenalty.SetInt(iBonus);

	// only set the amount of defibs used to 1 if there is a bonus to set
	GameRules_SetProp("m_iVersusDefibsUsed", (iBonus != 0) ? 1 : 0, 4, GameRules_GetProp("m_bAreTeamsFlipped", 4, 0));
}

int CalculateBonus()
{
	// negative = actual bonus, otherwise it is a penalty
	return (g_iOriginalPenalty * g_iDefibsUsed[RoundNum()]) - g_iBonus[RoundNum()];
}

void DisplayBonus(int iClient = -1)
{
	char sMsgPartHdr[48], sMsgPartBon[48];

	int iRoundNum = RoundNum();

	for (int iRound = 0; iRound <= iRoundNum; iRound++) {
		if (g_bRoundOver[iRound]) {
			Format(sMsgPartHdr, sizeof(sMsgPartHdr), "Round \x05%i\x01 extra bonus", iRound + 1);
		} else {
			Format(sMsgPartHdr, sizeof(sMsgPartHdr), "Current extra bonus");
		}

		Format(sMsgPartBon, sizeof(sMsgPartBon), "\x04%4d\x01", g_iBonus[iRound]);

		if (g_iDefibsUsed[iRound]) {
			Format(sMsgPartBon, sizeof(sMsgPartBon), "%s (- \x04%d\x01 defib penalty)", sMsgPartBon, g_iOriginalPenalty * g_iDefibsUsed[iRound]);
		}

		// Display the bonus to the specific client or to all clients
		if (iClient == -1) {
			PrintToChatAll("\x01%s: %s", sMsgPartHdr, sMsgPartBon);
		} else if (iClient) {
			PrintToChat(iClient, "\x01%s: %s", sMsgPartHdr, sMsgPartBon);
		}
	}
}

void ReportChange(int iBonusChange, int iClient = -1, bool bAbsoluteSet = false)
{
	if (iBonusChange == 0 && !bAbsoluteSet) {
		return;
	}

	// report bonus to all
	char sMsgPartBon[48];
	if (bAbsoluteSet) { // set to a specific value
		Format(sMsgPartBon, sizeof(sMsgPartBon), "Boss death bonus set to: \x04%i\x01", g_iBonus[RoundNum()]);
	} else {
		Format(sMsgPartBon, sizeof(sMsgPartBon), "Boss death bonus change: %s\x04%i\x01", (iBonusChange > 0) ? "\x04+\x01" : "\x03-\x01", RoundFloat(FloatAbs(float(iBonusChange))));
	}

	if (iClient == -1) {
		PrintToChatAll("\x01%s", sMsgPartBon);
	} else if (iClient) {
		PrintToChat(iClient, "\x01%s", sMsgPartBon);
	}
}

// Defib tracking
// --------------
void Event_DefibUsed(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	g_iDefibsUsed[RoundNum()]++;
}

// Support functions
// -----------------
int RoundNum()
{
	return (g_bSecondHalf) ? 1 : 0;
	//return GameRules_GetProp("m_bInSecondHalfOfRound");
}

// Natives
// -------
int Native_GetRoundBonus(Handle hPlugin, int iNumParams)
{
	return g_iBonus[RoundNum()];
}

int Native_ResetRoundBonus(Handle hPlugin, int iNumParams)
{
	g_iBonus[RoundNum()] = 0;
	return 1;
}

int Native_SetRoundBonus(Handle hPlugin, int iNumParams)
{
	int iBonus = GetNativeCell(1);
	g_iBonus[RoundNum()] = iBonus;

	return 1;
}

int Native_AddRoundBonus(Handle hPlugin, int iNumParams)
{
	bool bNoReport = false;
	int iBonus = GetNativeCell(1);

	g_iBonus[RoundNum()] += iBonus;

	if (iNumParams > 1) {
		bNoReport = view_as<bool>(GetNativeCell(2));
	}

	if (!bNoReport) {
		ReportChange(iBonus);
	}

	return 1;
}

int Native_GetDefibsUsed(Handle hPlugin, int iNumParams)
{
	return g_iDefibsUsed[RoundNum()];
}

int Native_SetDefibPenalty(Handle hPlugin, int iNumParams)
{
	int iPenalty = GetNativeCell(1);
	g_iOriginalPenalty = iPenalty;
	return 1;
}
