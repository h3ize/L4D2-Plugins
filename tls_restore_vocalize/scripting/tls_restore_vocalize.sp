#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <dhooks>
#include <left4dhooks>
#include <autoexecconfig>

#define PLUGIN_VERSION "3.0"

public Plugin myinfo =
{
    name = "[L4D2] Restore Blocked Vocalize",
    author = "Forgetest, heize",
    description = "Annoyments outside TLS are back. (Admin flags ONLY)",
    version = PLUGIN_VERSION,
    url = "https://github.com/h3ize"
};

#define GAMEDATA_FILE "tls_restore_vocalize"
#define KEY_APPEND "CTerrorPlayer::ModifyOrAppendCriteria"
#define KEY_GAMEMODE "CDirector::GetGameModeBase"

StringMap g_smVocalize;
ConVar g_cAdminFlag = null;

public void OnPluginStart()
{
    AutoExecConfig_SetCreateFile(true);
    AutoExecConfig_SetFile("tls_restore_vocalize.cfg");

    g_cAdminFlag = AutoExecConfig_CreateConVar("tls_restore_vocalizer_flag", "z", "Admin flag required to access vocalize. (Recommend downloading Ion's Vocalizer, Extracting the files, then adding them to your script folder. https://steamcommunity.com/sharedfiles/filedetails/?id=698857882)", FCVAR_NONE);

    AutoExecConfig_ExecuteFile();

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
    g_smVocalize.SetValue("Playerdeath", false);

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
        if (StrEqual(sVocalize, "Playerdeath", false))
            return Plugin_Handled; // Block scream vocalizer since people spam it.

        if (g_smVocalize.ContainsKey(sVocalize))
        {
            bool isRestricted;
            g_smVocalize.GetValue(sVocalize, isRestricted);

            if (isRestricted)
            {
                char adminFlagString[32];
                GetConVarString(g_cAdminFlag, adminFlagString, sizeof(adminFlagString));

                int requiredFlag = ReadFlagString(adminFlagString);
                int clientFlags = GetUserFlagBits(client);

                if ((clientFlags & requiredFlag) != requiredFlag && (clientFlags & ADMFLAG_ROOT) == 0)
                    return Plugin_Handled;

            }

            g_iActor = client;
            RequestFrame(OnNextFrame_ResetActor, GetClientUserId(client));
        }
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
