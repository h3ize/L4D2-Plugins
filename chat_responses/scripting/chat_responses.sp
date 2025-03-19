#pragma semicolon 1
#pragma newdecls required

#include <sdktools>
#include <sdkhooks>
#include <basecomm>
#include <multicolors>

#define DATA_FILE "chat_responses.txt"

public Plugin myinfo =
{
    name = "Autoresponder",
    description = "Displays chat advertisements when specified text is said in player chat.",
    author = "Russianeer, HarryPotter, heize",
    version = "1.1",
    url = "http://github.com/h3ize"
};

public void OnPluginStart()
{
    AddCommandListener(Command_Say, "say");
    AddCommandListener(Command_Say, "say_team");
}

public Action Command_Say(int client, const char[] command, int argc)
{
    if (client == 0) return Plugin_Continue;

    if (BaseComm_IsClientGagged(client) == true)
        return Plugin_Continue;

    char text[256];
    GetCmdArg(1, text, sizeof(text));

    char output[256];
    if (LoadAds(text, output, sizeof(output)))
    {
        CPrintToChat(client, "%s", output);
    }

    return Plugin_Continue;
}

bool LoadAds(char[] command, char[] output, int maxlength)
{
    KeyValues kv = CreateKeyValues("ChatResponses");
    char path[256];
    BuildPath(Path_SM, path, sizeof(path), "configs/%s", DATA_FILE);

    if (!FileToKeyValues(kv, path))
    {
        LogError("[MI] Couldn't load %s config!", DATA_FILE);
        CloseHandle(kv);
        return false;
    }

    if (!KvJumpToKey(kv, command, false))
    {
        CloseHandle(kv);
        return false;
    }

    KvGetString(kv, "text", output, maxlength, "");
    CloseHandle(kv);
    return true;
}
