#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <colors>

#define PLUGIN_VERSION "1.5"

ConVar g_cAdminFlag = null;

int  g_iRequiredFlags = 0;
bool g_bFlagEmpty = false;

public Plugin myinfo =
{
    name        = "L4D2 Flag VoteKick Protection",
    author      = "heize",
    description = "Blocks votekick attempts against protected admin flags",
    version     = PLUGIN_VERSION,
    url         = ""
};

public void OnPluginStart()
{
    g_cAdminFlag = CreateConVar(
        "sm_votekick_protect_flag",
        "t",
        "Admin flag(s) required to be protected from votekick",
        FCVAR_NONE
    );
    AutoExecConfig(true, "antivotekick");
    HookConVarChange(g_cAdminFlag, OnCvarChanged_AdminFlag);
    RefreshFlagCache();
    LoadTranslations("votekick_phrases");
    AddCommandListener(VoteListener, "callvote");
}

public void OnCvarChanged_AdminFlag(ConVar convar, const char[] oldValue, const char[] newValue)
{
    RefreshFlagCache();
}

void RefreshFlagCache()
{
    char s[32];
    g_cAdminFlag.GetString(s, sizeof(s));

    g_bFlagEmpty = (s[0] == '\0');
    g_iRequiredFlags = ReadFlagString(s);
}

bool IsProtectedClient(int client)
{
    if (client <= 0 || client > MaxClients) return false;
    if (!IsClientInGame(client)) return false;

    int bits = GetUserFlagBits(client);

    if (bits & ADMFLAG_ROOT)
        return true;

    if (g_bFlagEmpty || g_iRequiredFlags == 0)
        return false;

    return (bits & g_iRequiredFlags) == g_iRequiredFlags;
}

public Action VoteListener(int client, const char[] command, int argc)
{
    if (!client || !IsClientInGame(client))
    {
        ReplyToCommand(client, "%t", "NotConsoleVote");
        return Plugin_Handled;
    }

    if (argc < 2)
        return Plugin_Continue;

    char issue[32];
    GetCmdArg(1, issue, sizeof(issue));

    if (!StrEqual(issue, "Kick", false))
        return Plugin_Continue;

    char option[32];
    GetCmdArg(2, option, sizeof(option));

    int target = GetClientOfUserId(StringToInt(option));
    if (target <= 0 || target > MaxClients || !IsClientInGame(target))
        return Plugin_Continue;

    if (IsProtectedClient(target))
    {
        CPrintToChat(client, "%t", "KickBlocked", target);
        CPrintToChat(target, "%t", "KickAttempted", client);
        return Plugin_Handled;
    }

    return Plugin_Continue;
}