#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <colors>
#include <left4dhooks>
#include <autoexecconfig>
#include <logic/uservector>

#define PLUGIN_VERSION "3.4.3-2025/1/31"

public Plugin myinfo =
{
	name = "Tank Damage Announce L4D2",
	author = "Griffin and Blade, Sir, Forgetest, heize",
	description = "Announce damage dealt to tanks by survivors",
	version = PLUGIN_VERSION,
	url = "https://github.com/Target5150/MoYu_Server_Stupid_Plugins"
}

#define TRANSLATION_FILE "l4d_tank_damage_announce.phrases"
#define CONFIG_FILE "l4d_tank_damage_announce"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3
#define ZOMBIECLASS_TANK 8

enum struct SurvivorInfo
{
	int userid;
	int damageDone;
	int punch;
	int rock;
	int hittable;
	int damageReceived;
}

enum struct TankInfo
{
	int userid;
	int index;
	int incap;
	int death;
	int totalDamage;
	float aliveSince;
	int lastHealth;
	int maxHealth;
	int lastControlUserid;
	AutoUserVector survivorInfoVector;
	int friendlyDamage;
	int unknownDamage;
}
UserVector g_aTankInfo;

StringMap g_smUserNames;

int g_iTankIndex;

bool g_bIsTankInPlay = false;

ConVar
	g_hCvarEnabled = null,
	g_hCvarDebug = null,
	g_hCvarTopCount = null,
	g_hCvarSuppressTankDamage = null;

enum
{
	Style_Nothing = 0,
	STYLE_FACTS_BEGIN,
	Style_Combined = 1,
	STYLE_SEPARATE_REVERSE_BEGIN,
	Style_Separate_Reverse = 2,
	STYLE_SEPARATE_BEGIN,
	Style_Separate = 3,
	Stype_SeparateDelay = 4,
	NUM_TEXT_STYLE
}
ConVar g_hTextStyle = null;

enum
{
	OTHERSOURCE_FRIENDLY = 1,
	OTHERSOURCE_UNKNOWN = (1 << 1),
};
ConVar g_hCvarOtherSource = null;

GlobalForward g_TankDanageAnnounceForward;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("TFA_Punches", Native_Punches);
	CreateNative("TFA_Rocks", Native_Rocks);
	CreateNative("TFA_Hittables", Native_Hittables);
	CreateNative("TFA_TotalDmg", Native_TotalDamage);
	CreateNative("TFA_UpTime", Native_UpTime);

	g_TankDanageAnnounceForward = new GlobalForward("OnTankDamageAnnounce", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Array, Param_Array, Param_Cell);

	RegPluginLibrary("l4d_tank_damage_announce");

	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadPluginTranslations(TRANSLATION_FILE);

	AutoExecConfig_SetFile(CONFIG_FILE);

	g_hCvarEnabled = AutoExecConfig_CreateConVar("l4d_tankdamage_enabled", "1", "Announce damage done to tanks when enabled", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hCvarDebug = AutoExecConfig_CreateConVar("l4d_tankdamage_debug", "0", "Debug toggler.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hCvarTopCount = AutoExecConfig_CreateConVar("l4d_tankdamage_top_count", "0", "Print only top-numbered survivor damages. 0 = print all survivor damages", FCVAR_NONE, true, 0.0, false, 0.0);
	g_hCvarOtherSource = AutoExecConfig_CreateConVar("l4d_tankdamage_other_source", "3", "Announce damages from other source than survivors.\n1 = Infected friendly damage\n2 = Unknown source damage\n3 = All.", FCVAR_NONE, true, 0.0, false, 0.0);
	g_hTextStyle = AutoExecConfig_CreateConVar("l4d_tankdamage_text_style", "2", "Text style for how tank facts are printed.\n0 = Nothing\n1 = Combine with damage print\n2 = Separate lines before damage print\n3 = Separate lines after damage print\n4 = Individually print with a delay.", FCVAR_NONE, true, 0.0, true, 4.0);
	g_hCvarSuppressTankDamage = AutoExecConfig_CreateConVar("l4d_tankdamage_suppress_tank_damage", "0", "Suppress tank damage messages in chat.", FCVAR_NONE, true, 0.0, true, 1.0);

	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();

	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("map_transition", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("mission_lost", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("finale_vehicle_leaving", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("player_bot_replace", Event_PlayerBotReplace);
	HookEvent("bot_player_replace", Event_BotPlayerReplace);
	HookEvent("tank_spawn", Event_TankSpawn);
	HookEvent("player_incapacitated_start", Event_PlayerIncapStart);
	HookEvent("player_incapacitated", Event_PlayerIncap);
	HookEvent("player_hurt", Event_PlayerHurt);
	HookEvent("player_death", Event_PlayerKilled);

	g_aTankInfo = new UserVector(sizeof(TankInfo));
	g_smUserNames = new StringMap();
}

public void OnClientDisconnect(int client)
{
	int userid = GetClientUserId(client);

	char key[16], name[MAX_NAME_LENGTH];
	IntToString(userid, key, sizeof(key));
	GetClientName(client, name, sizeof(name));
	g_smUserNames.SetString(key, name);

	if (IsFakeClient(client))
	{
		Timer_CheckTank(null, userid);
	}
}

bool g_bRoundEnd;
void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_bRoundEnd = false;
	g_iTankIndex = 0;
	g_smUserNames.Clear();
	ClearTankInfo();
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if(g_bRoundEnd) return;
	g_bRoundEnd = true;

	PrintTankInfo();
}

void Event_PlayerBotReplace(Event event, const char[] name, bool dontBroadcast)
{
	HandlePlayerReplace(event.GetInt("bot"), event.GetInt("player"));
}

void Event_BotPlayerReplace(Event event, const char[] name, bool dontBroadcast)
{
	HandlePlayerReplace(event.GetInt("player"), event.GetInt("bot"));
}

public void L4D_OnReplaceTank(int tank, int newtank)
{
	if (!tank || !newtank || tank == newtank)
		return;

	DataPack dp = new DataPack();
	dp.WriteCell(GetClientUserId(tank));
	dp.WriteCell(GetClientUserId(newtank));

	RequestFrame(OnFrame_HandlePlayerReplace, dp);
}

void OnFrame_HandlePlayerReplace(DataPack dp)
{
	int tank, newtank;

	dp.Reset();
	tank = dp.ReadCell();
	newtank = dp.ReadCell();

	delete dp;

	HandlePlayerReplace(newtank, tank);
}

void HandlePlayerReplace(int replacer, int replacee)
{
	int client = GetClientOfUserId(replacer);
	if (!client || !IsClientInGame(client))
		return;

	if (!IsTank(client))
		return;

	if (g_aTankInfo.FindOrCreate(replacer) != -1)
	{
		--g_iTankIndex;
		ClearTankInfo(replacer);
	}

	g_aTankInfo.Set(replacee, replacer, TankInfo::userid);

	client = GetClientOfUserId(replacee);
	if (!client || !IsClientInGame(client) || !IsFakeClient(client))
		g_aTankInfo.Set(replacer, replacee, TankInfo::lastControlUserid);
}

void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	if (!client || !IsClientInGame(client))
		return;

	++g_iTankIndex;

	g_bIsTankInPlay = true;
	g_aTankInfo.FindOrCreate(userid, true);

	AutoUserVector survivorVector = new AutoUserVector(sizeof(SurvivorInfo));
	g_aTankInfo.Set(userid, survivorVector, TankInfo::survivorInfoVector);
	g_aTankInfo.Set(userid, GetGameTime(), TankInfo::aliveSince);
	g_aTankInfo.Set(userid, g_iTankIndex, TankInfo::index);

	UpdateTankHealth(client);
}

void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bIsTankInPlay)
		return;

	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (!victim || !IsClientInGame(victim))
		return;

	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (!attacker || !IsClientInGame(attacker))
		attacker = event.GetInt("attackerentid");

	int damage = event.GetInt("dmg_health");
	if (damage <= 0)
		return;

	PrintDebug("%s : %N", name, victim);

	if (IsTank(victim))
	{
		if (IsIncapacitated(victim))
			return;

		OnTankTakeDamage(victim, attacker, damage);
	}
	else if (GetClientTeam(victim) == TEAM_SURVIVOR)
	{
		if (IsIncapacitated(victim))
			return;

		if (attacker <= 0 || attacker > MaxClients || !IsTank(attacker))
			return;

		int health = GetClientHealth(victim);
		if (health < 0)
			damage += health + L4D_GetPlayerTempHealth(victim);

		char weapon[64];
		event.GetString("weapon", weapon, sizeof(weapon));
		OnTankAttackDamage(attacker, victim, damage, weapon);
	}
}

int g_iPlayerLastHealth;
void Event_PlayerIncapStart(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (!victim || !IsClientInGame(victim))
		return;

	g_iPlayerLastHealth = GetClientHealth(victim) + L4D_GetPlayerTempHealth(victim);
}

void Event_PlayerIncap(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bIsTankInPlay)
		return;

	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (!victim || !IsClientInGame(victim))
		return;

	PrintDebug("%s : %N", name, victim);

	if (GetClientTeam(victim) == TEAM_SURVIVOR)
	{
		int attacker = GetClientOfUserId(event.GetInt("attacker"));
		if (!attacker || !IsClientInGame(attacker))
			return;

		if (!IsTank(attacker))
			return;

		char weapon[64];
		event.GetString("weapon", weapon, sizeof(weapon));
		OnTankAttackDamage(attacker, victim, g_iPlayerLastHealth, weapon);

		OnSurvivorIncap(victim);
	}
}

void Event_PlayerKilled(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bIsTankInPlay)
		return;

	if (event.GetBool("abort"))
		return;

	int victimid = event.GetInt("userid");
	int victim = GetClientOfUserId(victimid);
	if (!victim || !IsClientInGame(victim))
		return;

	PrintDebug("%s : %N", name, victim);

	if (IsTank(victim))
	{
		int iTankLastHealth;
		g_aTankInfo.Get(victimid, iTankLastHealth, TankInfo::lastHealth);

		int attacker = GetClientOfUserId(event.GetInt("attacker"));
		if (!attacker || !IsClientInGame(attacker))
			attacker = event.GetInt("attackerentid");

		OnTankTakeDamage(victim, attacker, iTankLastHealth);

		CreateTimer(0.1, Timer_CheckTank, victimid);
	}
	else if (GetClientTeam(victim) == TEAM_SURVIVOR)
	{
		OnSurvivorDeath(victim);
	}
}

void UpdateTankHealth(int tank)
{
	int tankid = GetClientUserId(tank);

	g_aTankInfo.Set(tankid, GetEntProp(tank, Prop_Data, "m_iMaxHealth"), TankInfo::maxHealth);
	g_aTankInfo.Set(tankid, GetClientHealth(tank), TankInfo::lastHealth);

	PrintDebug("UpdateTankHealth : %N  %d / %d", tank, GetClientHealth(tank), GetEntProp(tank, Prop_Data, "m_iMaxHealth"));
}

void OnTankTakeDamage(int tank, int attacker, int damage)
{
	int tankid = GetClientUserId(tank);

	if (attacker != tank && attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
	{
		PrintDebug("OnTankTakeDamage : %N <- %N @ %d", tank, attacker, damage);

		int attackerid = GetClientUserId(attacker);
		int team = GetClientTeam(attacker);
		if (team == TEAM_SURVIVOR)
		{
			AutoUserVector survivorVector;
			if(g_aTankInfo.Get(tankid, survivorVector, TankInfo::survivorInfoVector) == false) return;

			survivorVector.Add(attackerid, damage, SurvivorInfo::damageDone);
		}
		else if (team == TEAM_INFECTED)
		{
			g_aTankInfo.Add(tankid, damage, TankInfo::friendlyDamage);
		}
	}
	else if (IsValidEntity(attacker))
	{
		if (GetEntProp(attacker, Prop_Data, "m_iTeamNum") == TEAM_INFECTED)
		{
			char cls[64];
			GetEdictClassname(attacker, cls, sizeof(cls));
			PrintDebug("OnTankTakeDamage : %N <- %s @ %d", tank, cls, damage);
			g_aTankInfo.Add(tankid, damage, TankInfo::friendlyDamage);
		}
		else
		{
			char cls[64];
			GetEdictClassname(attacker, cls, sizeof(cls));
			PrintDebug("OnTankTakeDamage : %N <- %s @ %d", tank, cls, damage);
			g_aTankInfo.Add(tankid, damage, TankInfo::unknownDamage);
		}
	}

	UpdateTankHealth(tank);
}

void OnTankAttackDamage(int tank, int victim, int damage, const char[] weapon)
{
	int attackerid = GetClientUserId(tank);
	int victimid = GetClientUserId(victim);

	AutoUserVector survivorVector;
	if(g_aTankInfo.Get(attackerid, survivorVector, TankInfo::survivorInfoVector) == false) return;

	if (StrContains(weapon, "tank_claw") != -1)
		survivorVector.Add(victimid, 1, SurvivorInfo::punch);
	else if (strcmp(weapon, "tank_rock") == 0)
		survivorVector.Add(victimid, 1, SurvivorInfo::rock);
	else if (strcmp(weapon, "prop_physics") == 0 || strcmp(weapon, "prop_car_alarm") == 0)
		survivorVector.Add(victimid, 1, SurvivorInfo::hittable);
	else if (strcmp(weapon, "insect_swarm", false) == 0){
		return;
	}

	survivorVector.Add(victimid, damage, SurvivorInfo::damageReceived);
	g_aTankInfo.Add(attackerid, damage, TankInfo::totalDamage);

	PrintDebug("OnTankAttackDamage : %N <- %N @ %d [%s]", victim, tank, damage, weapon);
}

void OnSurvivorIncap(int survivor)
{
	g_aTankInfo.ForEach( OnSurvivorIncapInternal, survivor );
}

bool OnSurvivorIncapInternal(int userid)
{
	g_aTankInfo.Add(userid, 1, TankInfo::incap);
	return true;
}

void OnSurvivorDeath(int survivor)
{
	g_aTankInfo.ForEach( OnSurvivorDeathInternal, survivor );
}

bool OnSurvivorDeathInternal(int userid)
{
	g_aTankInfo.Add(userid, 1, TankInfo::death);
	return true;
}

void CheckTank(int userid)
{
	if (g_aTankInfo.FindOrCreate(userid) != -1)
	{
		PrintTankInfo(userid);
	}
}

bool FindTankControlName(int userid, char[] name, int maxlen)
{
	int client = GetClientOfUserId(userid);

	if (!IsFakeClient(client))
	{
		return GetClientName(client, name, maxlen);
	}

	int lastControlUserid;
	if (g_aTankInfo.Get(userid, lastControlUserid, TankInfo::lastControlUserid) && lastControlUserid)
	{
		return GetClientNameFromUserId(lastControlUserid, name, maxlen);
	}

	GetClientName(client, name, maxlen);
	return false;
}

void PrintTankDamageTitle(const TankInfo info)
{
	int client = GetClientOfUserId(info.userid);

	char name[MAX_NAME_LENGTH];
	bool bHumanControlled = FindTankControlName(info.userid, name, sizeof(name));

	Format(name, sizeof(name), "%t", IsFakeClient(client) ? (bHumanControlled ? "Frustrated" : "AI") : "HumanControlled", name);

	if (IsPlayerAlive(client))
		CPrintToChatAll("%t", g_hCvarTopCount.IntValue ? "RemainingHealth_TopNumbered" : "RemainingHealth", name, info.lastHealth, info.index, g_hCvarTopCount.IntValue);
	else
		CPrintToChatAll("%t", g_hCvarTopCount.IntValue ? "DamageDealt_TopNumbered" : "DamageDealt", name, info.index, g_hCvarTopCount.IntValue);
}

void PrintTankFactsTitle(const TankInfo info)
{
	int client = GetClientOfUserId(info.userid);

	char name[MAX_NAME_LENGTH];
	bool bHumanControlled = FindTankControlName(info.userid, name, sizeof(name));

	Format(name, sizeof(name), "%t", IsFakeClient(client) ? (bHumanControlled ? "Frustrated" : "AI") : "HumanControlled", name);

	CPrintToChatAll("%t", "FactsTitle", name, info.index);
}

void PrintTankInfo(int userid = 0)
{
	if (userid > 0)
	{
		PrintTankInfoInternal(userid);
	}
	else
	{
		g_aTankInfo.ForEach( PrintTankInfoInternal );
	}
}

bool PrintTankInfoInternal(int userid)
{
	if (!g_hCvarEnabled.BoolValue)
		return false;

	int style = g_hTextStyle.IntValue;

	if (style == Style_Separate_Reverse)
	{
		PrintTankFacts(userid);
	}

	PrintTankDamage(userid);

	if (style >= STYLE_SEPARATE_BEGIN)
	{
		float delay = 0.0;
		if (style == Stype_SeparateDelay)
			delay = 3.0;

		PrintTankFacts(userid, delay);
	}

	ForwardTankInfo(userid);

	return true;
}

void ForwardTankInfo(int userid)
{
	if (!g_TankDanageAnnounceForward.FunctionCount)
		return;

	int client = GetClientOfUserId(userid);
	if (!client || !IsClientInGame(client))
		return;

	TankInfo tank;
	g_aTankInfo.GetArray(userid, tank);

	int size = tank.survivorInfoVector.Super.Length;
	int count = 0;

	int[] survivors = new int[size];
	int[] damages = new int[size];

	SurvivorInfo survivor;
	for (int i = 0; i < size; ++i)
	{
		tank.survivorInfoVector.Super.GetArray(i, survivor);

		int temp = GetClientOfUserId(survivor.userid);
		if (!temp || !IsClientInGame(temp))
			continue;

		survivors[count] = temp;
		damages[count] = survivor.damageDone;
		count++;
	}

	Call_StartForward(g_TankDanageAnnounceForward);
	Call_PushCell(client);
	Call_PushCell(tank.lastHealth);
	Call_PushCell(tank.maxHealth);
	Call_PushArray(survivors, count);
	Call_PushArray(damages, count);
	Call_PushCell(count);
	Call_Finish();
}

void ClearTankInfo(int userid = 0)
{
	if (userid > 0)
	{
		ClearTankInfoInternal(userid);
		g_aTankInfo.Erase(userid);
	}
	else
	{
		g_aTankInfo.ForEach( ClearTankInfoInternal );
		g_aTankInfo.Clear();
	}

	g_bIsTankInPlay = g_aTankInfo.Length > 0;
}

bool ClearTankInfoInternal(int userid)
{
	AutoUserVector survivorVector;
	if (g_aTankInfo.Get(userid, survivorVector, TankInfo::survivorInfoVector))
		delete survivorVector;

	return true;
}

int g_iAnnounceCount = 0;
void PrintTankDamage(int userid)
{
	if (g_hCvarSuppressTankDamage.BoolValue)
		return;

	TankInfo info;
	g_aTankInfo.GetArray(userid, info);

	PrintTankDamageTitle(info);

	AutoUserVector survivorVector = info.survivorInfoVector;
	survivorVector.SortCustom( SortADT_DamageDesc );

	g_iAnnounceCount = 0;
	survivorVector.ForEach( PrintTankDamageInternal, userid );

	if (info.friendlyDamage && g_hCvarOtherSource.IntValue & OTHERSOURCE_FRIENDLY)
	{
		int percent = RoundToNearest(float(info.friendlyDamage) / info.maxHealth * 100.0);
		CPrintToChatAll("%t", "DamageToTank_Friendly", info.friendlyDamage, percent);
	}

	if (info.unknownDamage && g_hCvarOtherSource.IntValue & OTHERSOURCE_UNKNOWN)
	{
		int percent = RoundToNearest(float(info.unknownDamage) / info.maxHealth * 100.0);
		CPrintToChatAll("%t", "DamageToTank_Unknown", info.unknownDamage, percent);
	}
}

bool PrintTankDamageInternal(int userid, any tankid)
{
	int style = g_hTextStyle.IntValue;

	AutoUserVector survivorVector;
	if(g_aTankInfo.Get(tankid, survivorVector, TankInfo::survivorInfoVector) == false) return false;

	SurvivorInfo info;
	survivorVector.GetArray(userid, info);

	char name[MAX_NAME_LENGTH];
	GetClientNameFromUserId(info.userid, name, sizeof(name));

	int maxHealth;
	g_aTankInfo.Get(tankid, maxHealth, TankInfo::maxHealth);

	int percent = RoundToNearest(float(info.damageDone) / maxHealth * 100.0);

	if (info.damageDone > 0 || (style == Style_Combined && info.damageReceived))
	{
		if (style == Style_Combined)
			CPrintToChatAll("%t", "DamageToTank_Combined", info.damageDone, percent, name, info.punch, info.rock, info.hittable, info.damageReceived);
		else
			CPrintToChatAll("%t", "DamageToTank", info.damageDone, percent, name);
	}

	g_iAnnounceCount++;
	return !g_hCvarTopCount.IntValue || g_iAnnounceCount < g_hCvarTopCount.IntValue;
}

void PrintTankFacts(int userid, float delay = 0.0)
{
	if (g_hCvarSuppressTankDamage.BoolValue)
		return;

	TankInfo info;
	g_aTankInfo.GetArray(userid, info);

	if (delay > 0.0)
	{
		info.survivorInfoVector = view_as<AutoUserVector>(info.survivorInfoVector.Clone());

		DataPack dp;
		CreateDataTimer(delay, Timer_PrintTankFacts, dp, TIMER_FLAG_NO_MAPCHANGE);
		static char controlName[MAX_NAME_LENGTH];
		bool bHumanControlled = FindTankControlName(userid, controlName, sizeof(controlName));
		int client = GetClientOfUserId(userid);

		dp.WriteCellArray(info, sizeof(info));

		dp.WriteString(controlName);
		dp.WriteCell(IsFakeClient(client));
		dp.WriteCell(bHumanControlled);
		dp.WriteCell(info.index);
		dp.WriteFloat(delay);

		return;
	}
	else
	{
		PrintTankFactsTitle(info);
		PrintTankFactsInternal(info, 0.0);
	}
}

Action Timer_PrintTankFacts(Handle timer, DataPack dp)
{
	if (g_hCvarSuppressTankDamage.BoolValue)
		return Plugin_Stop;

	dp.Reset();

	TankInfo info;
	dp.ReadCellArray(info, sizeof(info));

	char name[MAX_NAME_LENGTH];
	dp.ReadString(name, sizeof(name));
	bool bAI = dp.ReadCell();
	bool bHumanControlled = dp.ReadCell();
	int tankindex = dp.ReadCell();
	float delay  = dp.ReadFloat();
	delete dp;

	Format(name, sizeof(name), "%t", bAI ? (bHumanControlled ? "Frustrated" : "AI") : "HumanControlled", name);

	CPrintToChatAll("%t", "FactsTitle", name, tankindex);

	PrintTankFactsInternal(info, delay);

	delete info.survivorInfoVector;

	return Plugin_Stop;
}

void PrintTankFactsInternal(const TankInfo info, float delay)
{
	if (g_hCvarSuppressTankDamage.BoolValue)
		return;

	AutoUserVector survivorVector = info.survivorInfoVector;

	int total_punch = survivorVector.Sum(SurvivorInfo::punch);
	int total_rock = survivorVector.Sum(SurvivorInfo::rock);
	int total_hittable = survivorVector.Sum(SurvivorInfo::hittable);
	int total_incap = info.incap;
	int total_death = info.death;
	int total_damage = info.totalDamage;

	int iAliveDuration = RoundToFloor(GetGameTime() - info.aliveSince - delay - 0.1);

	CPrintToChatAll("%t", "Announce_TankAttack", total_punch, total_rock, total_hittable);
	CPrintToChatAll("%t", "Announce_AttackResult", total_incap, total_death);
	if (iAliveDuration > 60)
		CPrintToChatAll("%t", "Announce_Summary_WithMinute", iAliveDuration / 60, iAliveDuration % 60, total_damage);
	else
		CPrintToChatAll("%t", "Announce_Summary_WithoutMinute", iAliveDuration, total_damage);
}


bool GetClientNameFromUserId(int userid, char[] name, int maxlen)
{
	int client = GetClientOfUserId(userid);

	if (client && IsClientInGame(client))
	{
		return GetClientName(client, name, maxlen);
	}

	char key[16];
	IntToString(userid, key, sizeof(key));
	return g_smUserNames.GetString(key, name, maxlen);
}

bool IsTank(int client)
{
	return GetClientTeam(client) == 3 && GetEntProp(client, Prop_Send, "m_zombieClass") == ZOMBIECLASS_TANK;
}

bool IsIncapacitated(int client)
{
	return GetEntProp(client, Prop_Send, "m_isIncapacitated", 1) != 0;
}

int SortADT_DamageDesc(int index1, int index2, Handle array, Handle hndl)
{
	AutoUserVector survivorVector = view_as<AutoUserVector>(array);

	int damage1 = survivorVector.Super.Get(index1, SurvivorInfo::damageDone);
	int damage2 = survivorVector.Super.Get(index2, SurvivorInfo::damageDone);

	if (damage1 > damage2)
		return -1;
	else if (damage1 < damage2)
		return 1;

	return 0;
}

any Native_Punches(Handle hPlugin, int iNumParams) {
	int client = GetNativeCell(1);
	if (client <= 0 || client > MaxClients)
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);

	int userid = GetClientUserId(client);

	AutoUserVector survivorVector;
	if (!g_aTankInfo.Get(userid, survivorVector, TankInfo::survivorInfoVector))
		return -1;

	return survivorVector.Sum(SurvivorInfo::punch);
}

any Native_Rocks(Handle hPlugin, int iNumParams) {
	int client = GetNativeCell(1);
	if (client <= 0 || client > MaxClients)
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);

	int userid = GetClientUserId(client);

	AutoUserVector survivorVector;
	if (!g_aTankInfo.Get(userid, survivorVector, TankInfo::survivorInfoVector))
		return -1;

	return survivorVector.Sum(SurvivorInfo::rock);
}

any Native_Hittables(Handle hPlugin, int iNumParams) {
	int client = GetNativeCell(1);
	if (client <= 0 || client > MaxClients)
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);

	int userid = GetClientUserId(client);

	AutoUserVector survivorVector;
	if (!g_aTankInfo.Get(userid, survivorVector, TankInfo::survivorInfoVector))
		return -1;

	return survivorVector.Sum(SurvivorInfo::hittable);
}

any Native_TotalDamage(Handle hPlugin, int iNumParams) {
	int client = GetNativeCell(1);
	if (client <= 0 || client > MaxClients)
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);

	int userid = GetClientUserId(client);

	int value = -1;
	g_aTankInfo.Get(userid, value, TankInfo::totalDamage);
	return value;
}

any Native_UpTime(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	if (client <= 0 || client > MaxClients)
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);

	int userid = GetClientUserId(client);

	float value = -1.0;
	if (g_aTankInfo.Get(userid, value, TankInfo::aliveSince))
		value = GetGameTime() - value;

	return RoundToFloor(value);
}

stock void LoadPluginTranslations(const char[] file)
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "translations/%s.txt", file);
	if (!FileExists(sPath))
	{
		SetFailState("Missing translations \"%s\"", file);
	}
	LoadTranslations(file);
}

Action Timer_CheckTank(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if(!client || !IsClientInGame(client)) return Plugin_Continue;

	CheckTank(userid);
	ClearTankInfo(userid);

	return Plugin_Continue;
}

stock void PrintDebug(const char[] format, any ...)
{
	if (g_hCvarDebug.BoolValue)
	{
		char msg[512];
		VFormat(msg, sizeof(msg), format, 2);
		PrintToChatAll("%s", msg);
	}
}

// l4d_tank_pass API---
// when tank pass control to another player by menu
/*
public void TP_OnTankPass(int tank, int newtank)
{
	if (!tank || !newtank || tank == newtank)
		return;

	PrintToChatAll("TP_OnTankPass %N %N", tank, newtank);

	// This is a pre-hook so make sure the replace actually happens via a delayed check.
	DataPack dp = new DataPack();
	dp.WriteCell(GetClientUserId(tank));
	dp.WriteCell(GetClientUserId(newtank));

	RequestFrame(OnFrame_HandlePlayerReplace, dp);
}*/