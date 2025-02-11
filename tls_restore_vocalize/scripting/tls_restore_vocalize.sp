#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <dhooks>
#include <left4dhooks>
#include <sdktools>
#include <admin>
#include <sdkhooks>

#define PLUGIN_VERSION "2.5"
#define PLUGIN_NAME "RestoreVocalize"

public Plugin myinfo =
{
	name = "[L4D2] Restore Blocked Vocalize (Admin Flag Support)",
	author = "Forgetest, heize",
	description = "Annoyments outside TLS are back.",
	version = PLUGIN_VERSION,
	url = "https://github.com/h3ize"
};

#define GAMEDATA_FILE "tls_restore_vocalize"
#define KEY_APPEND "CTerrorPlayer::ModifyOrAppendCriteria"
#define KEY_GAMEMODE "CDirector::GetGameModeBase"

StringMap g_smVocalize;
ConVar g_hAdminFlag;
ConVar g_hEnableLaugh;
ConVar g_hEnableTaunt;
ConVar g_hEnableDeath;

public void OnPluginStart()
{
	Handle conf = LoadGameConfigFile(GAMEDATA_FILE);
	if (!conf)
		SetFailState("Missing gamedata \""...GAMEDATA_FILE..."\"");

	DynamicDetour hDetour = DynamicDetour.FromConf(conf, KEY_APPEND);
	if (!hDetour)
		SetFailState("Missing detour setup for \""...KEY_APPEND..."\"");

	if (!hDetour.Enable(Hook_Pre, DTR_OnModifyOrAppendCriteria_Pre) || !hDetour.Enable(Hook_Post, DTR_OnModifyOrAppendCriteria_Post))
		SetFailState("Failed to detour \""...KEY_APPEND..."\"");

	hDetour = DynamicDetour.FromConf(conf, KEY_GAMEMODE);
	if (!hDetour)
		SetFailState("Missing detour setup for \""...KEY_GAMEMODE..."\"");

	if (!hDetour.Enable(Hook_Pre, DTR_OnGetGameModeBase_Pre))
		SetFailState("Failed to detour \""...KEY_GAMEMODE..."\"");

	delete conf;

	g_smVocalize = new StringMap();
	g_smVocalize.SetValue("PlayerLaugh", true);
	g_smVocalize.SetValue("PlayerTaunt", true);
	g_smVocalize.SetValue("Playerdeath", true);

	char flagName[64];
	Format(flagName, sizeof(flagName), "%s_flag", PLUGIN_NAME);
	g_hAdminFlag = CreateConVar(flagName, "", "Admin flag required to use restricted vocalizations (leave empty to allow everyone)", FCVAR_ARCHIVE);

	g_hEnableLaugh = CreateConVar(PLUGIN_NAME ... "_enable_laugh", "1", "Enable or disable laugh vocalization", FCVAR_ARCHIVE);
	g_hEnableTaunt = CreateConVar(PLUGIN_NAME ... "_enable_taunt", "1", "Enable or disable taunt vocalization", FCVAR_ARCHIVE);
	g_hEnableDeath = CreateConVar(PLUGIN_NAME ... "_enable_death", "1", "Enable or disable death vocalization", FCVAR_ARCHIVE);

	CreateConVar(PLUGIN_NAME ... "_version", PLUGIN_VERSION, PLUGIN_NAME ... " Plugin Version", FCVAR_ARCHIVE);

	AutoExecConfig(true, PLUGIN_NAME);

	AddCommandListener(CmdLis_OnVocalize, "vocalize");
}

int g_iActor = -1;
Action CmdLis_OnVocalize(int client, const char[] command, int argc)
{
	if (!IsClientInGame(client) || GetClientTeam(client) != 2)
		return Plugin_Continue;

	if (!L4D_IsVersusMode())
		return Plugin_Continue;

	static char sVocalize[64];
	if (GetCmdArg(1, sVocalize, sizeof(sVocalize)))
	{
		if (g_smVocalize.ContainsKey(sVocalize))
		{
			char flag[16];
			g_hAdminFlag.GetString(flag, sizeof(flag));

			if (flag[0] == '\0')
			{
				g_iActor = client;
				RequestFrame(OnNextFrame_ResetActor, GetClientUserId(client));
				return Plugin_Continue;
			}

			AdminFlag eFlag;
			if (FindFlagByChar(flag[0], eFlag))
			{
				int userFlags = GetUserFlagBits(client);
				int flagValue = FlagToBit(eFlag);

				if (!(userFlags & flagValue))
				{
					return Plugin_Handled;
				}
			}
			else
			{
				return Plugin_Handled;
			}

			if ((StrEqual(sVocalize, "PlayerLaugh") && !g_hEnableLaugh.BoolValue) ||
				(StrEqual(sVocalize, "PlayerTaunt") && !g_hEnableTaunt.BoolValue) ||
				(StrEqual(sVocalize, "Playerdeath") && !g_hEnableDeath.BoolValue))
			{
				return Plugin_Handled;
			}
		}

		g_iActor = client;
		RequestFrame(OnNextFrame_ResetActor, GetClientUserId(client));
	}

	return Plugin_Continue;
}

void OnNextFrame_ResetActor(int userid)
{
	int client = GetClientOfUserId(userid);
	if (!client || client == g_iActor)
	{
		g_iActor = -1;
	}
}

bool bShouldOverride = false;
MRESReturn DTR_OnModifyOrAppendCriteria_Pre(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	if (g_iActor != -1)
	{
		bShouldOverride = true;
	}
	return MRES_Ignored;
}

MRESReturn DTR_OnModifyOrAppendCriteria_Post(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	g_iActor = -1;
	bShouldOverride = false;
	return MRES_Ignored;
}

MRESReturn DTR_OnGetGameModeBase_Pre(int pThis, DHookReturn hReturn)
{
	if (bShouldOverride)
	{
		hReturn.SetString("coop");
		return MRES_Supercede;
	}

	return MRES_Ignored;
}
