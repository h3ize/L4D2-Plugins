#pragma newdecls required;

#include <sourcemod>
#include <sdktools_sound>

#define MAX_STR_LEN            30
#define MIN_MIX_START_COUNT    2

#define COND_HAS_ALREADY_VOTED 0
#define COND_NEED_MORE_VOTES   1
#define COND_START_MIX         2
#define COND_START_MIX_ADMIN   3
#define COND_NO_PLAYERS        4

#define STATE_FIRST_CAPT       0
#define STATE_SECOND_CAPT      1
#define STATE_NO_MIX           2
#define STATE_PICK_TEAMS       3

#define L4D_TEAM_SPECTATOR     1
#define L4D_TEAM_SURVIVOR      2
#define L4D_TEAM_INFECTED      3

#define MAX_FAKE_PLAYERS       10

int
    currentState = STATE_NO_MIX,
    mixCallsCount = 0,
    maxVoteCount = 0,
    pickCount = 0,
    iSurvivorLimit = 0,
    survivorsPick = 0,
    fakePlayerCount = 0;

bool
    isDebug = false,
    isMixAllowed = false,
    isPickingCaptain = false;

Menu
    mixMenu;

StringMap
    hVoteResultsTrie,
    hSwapWhitelist,
    hPlayers;

char
    currentMaxVotedCaptAuthId[MAX_STR_LEN],
    survCaptainAuthId[MAX_STR_LEN],
    infCaptainAuthId[MAX_STR_LEN],
    g_FakePlayerAuthIds[MAX_FAKE_PLAYERS][MAX_STR_LEN],
    g_FakePlayerNames[MAX_FAKE_PLAYERS][MAX_STR_LEN];

GlobalForward
    mixStartedForward,
    mixStoppedForward;

Handle captainVoteTimer;
ConVar CvarSurvivorLimit;


public Plugin myinfo =
{
    name = "L4D2 Mix Manager",
    author = "Luckylock, Sir, heize",
    description = "Provides ability to pick captains and teams through menus. Improved to support team mode.",
    version = "6",
    url = "https://github.com/LuckyServ/"
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_mix", Cmd_MixStart, "Mix command");
    RegAdminCmd("sm_mixdebug", Cmd_MixStart, ADMFLAG_CHANGEMAP, "Debug Mix");
    RegAdminCmd("sm_stopmix", Cmd_MixStop, ADMFLAG_CHANGEMAP, "Mix command");

    AddCommandListener(Cmd_OnPlayerJoinTeam, "jointeam");

    hVoteResultsTrie = new StringMap();
    hSwapWhitelist = new StringMap();
    hPlayers = new StringMap();

    mixStartedForward = new GlobalForward("OnMixStarted", ET_Event);
    mixStoppedForward = new GlobalForward("OnMixStopped", ET_Event);

    PrecacheSound("buttons/blip1.wav");

    CvarSurvivorLimit = FindConVar("survivor_limit");
    iSurvivorLimit = CvarSurvivorLimit.IntValue;
    CvarSurvivorLimit.AddChangeHook(SurvLimitChange);
}

void SurvLimitChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
    iSurvivorLimit = CvarSurvivorLimit.IntValue;
}

public void OnMapStart()
{
    isMixAllowed = true;
    StopMix();
}

public void OnRoundIsLive() {
    isMixAllowed = false;
    StopMix();
}

public void OnClientDisconnect(int client)
{
    if (currentState != STATE_NO_MIX && IsClientInPlayers(client))
    {
        PrintToChatAll("\x04Mix Manager: \x01Player \x03%N \x01has left the game, aborting...", client);
        StopMix();
    }
}

public void OnClientPutInServer(int client)
{
    char authId[MAX_STR_LEN];

    if (currentState != STATE_NO_MIX && IsHuman(client))
    {
        GetClientAuthId(client, AuthId_SteamID64, authId, MAX_STR_LEN);
        ChangeClientTeam(client, L4D_TEAM_SPECTATOR);
    }
}

void StartMix()
{
    FakeClientCommandAll("sm_hide");
    Call_StartForward(mixStartedForward);
    Call_Finish();
    EmitSoundToAll("buttons/blip1.wav");
}

void StopMix()
{
    currentState = STATE_NO_MIX;
    FakeClientCommandAll("sm_show");
    Call_StartForward(mixStoppedForward);
    Call_Finish();

    if (isPickingCaptain && captainVoteTimer != INVALID_HANDLE)
        KillTimer(captainVoteTimer);
}

void FakeClientCommandAll(char[] command)
{
    for (int client = 1; client <= MaxClients; ++client)
    {
        if (IsClientInGame(client) && !IsFakeClient(client))
            FakeClientCommand(client, command);
    }
}

Action Cmd_OnPlayerJoinTeam(int client, const char[] command, int argc)
{
    char authId[MAX_STR_LEN];
    char cmdArgBuffer[MAX_STR_LEN];
    int allowedTeam;
    int newTeam;

    if (argc >= 1) {

        GetCmdArg(1, cmdArgBuffer, MAX_STR_LEN);
        newTeam = StringToInt(cmdArgBuffer);

        if (currentState != STATE_NO_MIX && newTeam != L4D_TEAM_SPECTATOR && IsHuman(client)) {

            GetClientAuthId(client, AuthId_SteamID64, authId, MAX_STR_LEN);

            if (!hSwapWhitelist.GetValue(authId, allowedTeam) || allowedTeam != newTeam) {
                PrintToChat(client, "\x04Mix Manager: \x01 You can not join a team without being picked.");
                return Plugin_Stop;
            }
        }
    }

    return Plugin_Continue;
}

Action Cmd_MixStop(int client, int args) {
    if (currentState != STATE_NO_MIX) {
        StopMix();
        PrintToChatAll("\x04Mix Manager: \x01Stopped by admin \x03%N\x01.", client);
    } else {
        PrintToChat(client, "\x04Mix Manager: \x01Not currently started.");
    }
    return Plugin_Handled;
}

Action Cmd_MixStart(int client, int args)
{
    char sCmdName[32];
    GetCmdArg(0, sCmdName, 32);

    if (strcmp(sCmdName, "sm_mixdebug") == 0)
        isDebug = true;
    else
        isDebug = false;

    if (currentState != STATE_NO_MIX)
    {
        PrintToChat(client, "\x04Mix Manager: \x01Already started.");
        return Plugin_Handled;
    }
    else if (!isMixAllowed && !isDebug)
    {
        PrintToChat(client, "\x04Mix Manager: \x01Not allowed on live round.");
        return Plugin_Handled;
    }

    int mixConditions = GetMixConditionsAfterVote(client);

    if (mixConditions == COND_START_MIX || mixConditions == COND_START_MIX_ADMIN)
    {
        if (mixConditions == COND_START_MIX_ADMIN)
            PrintToChatAll("\x04Mix Manager: \x01Started by admin \x03%N\x01.%s", client, isDebug ? " (Debug Mode)" : "");

        else
        {
            PrintToChatAll("\x04Mix Manager: \x03%N \x01has voted to start a Mix.", client);
            PrintToChatAll("\x04Mix Manager: \x01Started by vote.");
        }

        currentState = STATE_FIRST_CAPT;
        StartMix();
        SwapAllPlayersToSpec();

        // Initialise values
        mixCallsCount = 0;
        hVoteResultsTrie.Clear();
        hSwapWhitelist.Clear();
        maxVoteCount = 0;
        strcopy(currentMaxVotedCaptAuthId, MAX_STR_LEN, " ");
        pickCount = 0;

        if (Menu_Initialise()) {
            Menu_AddAllSpectators();
            Menu_DisplayToAllSpecs();
        }

        captainVoteTimer = CreateTimer(11.0, Menu_StateHandler, _, TIMER_REPEAT); 
        isPickingCaptain = true;

    } else if (mixConditions == COND_NEED_MORE_VOTES) {
        PrintToChatAll("\x04Mix Manager: \x03%N \x01has voted to start a Mix. (\x05%d \x01more to start)", client, MIN_MIX_START_COUNT - mixCallsCount);

    } else if (mixConditions == COND_HAS_ALREADY_VOTED) {
        PrintToChat(client, "\x04Mix Manager: \x01You already voted to start a Mix.");

    } else if (mixConditions == COND_NO_PLAYERS) {
        PrintToChat(client, "\x04Mix Manager: \x01Join teams to start a mix.");
    }

    return Plugin_Handled;
}

int GetMixConditionsAfterVote(int client)
{
    bool dummy = false;
    char clientAuthId[MAX_STR_LEN];
    GetClientAuthId(client, AuthId_SteamID64, clientAuthId, MAX_STR_LEN);
    bool hasVoted = GetTrieValue(hVoteResultsTrie, clientAuthId, dummy)

    if (!SavePlayers())
        return COND_NO_PLAYERS;

    if (CheckCommandAccess(client, "sm_changemap", ADMFLAG_CHANGEMAP, true))
        return COND_START_MIX_ADMIN;

    else if (hasVoted)
        return COND_HAS_ALREADY_VOTED;

    else if (++mixCallsCount >= MIN_MIX_START_COUNT)
        return COND_START_MIX;

    SetTrieValue(hVoteResultsTrie, clientAuthId, true);
    return COND_NEED_MORE_VOTES;
}

bool SavePlayers()
{
    char clientAuthId[MAX_STR_LEN];

    ClearTrie(hPlayers);

    // First count and add real players
    int realPlayerCount = 0;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsSurvivor(client) || IsInfected(client))
        {
            GetClientAuthId(client, AuthId_SteamID64, clientAuthId, MAX_STR_LEN);
            SetTrieValue(hPlayers, clientAuthId, true);
            realPlayerCount++;
        }
    }

    // In debug mode, auto-fill with fake players to reach required count
    if (isDebug)
    {
        if (realPlayerCount < iSurvivorLimit * 2)
            AutoFillFakePlayers(realPlayerCount);

        for (int i = 0; i < fakePlayerCount; i++)
            SetTrieValue(hPlayers, g_FakePlayerAuthIds[i], true);
    }

    return GetTrieSize(hPlayers) == iSurvivorLimit * 2;
}

bool Menu_Initialise()
{
    if (currentState == STATE_NO_MIX) return false;

    mixMenu = new Menu(Menu_MixHandler, MENU_ACTIONS_ALL);
    mixMenu.ExitButton = false;

    switch(currentState) {
        case STATE_FIRST_CAPT: {
            mixMenu.SetTitle("Mix Manager - Pick first captain");
            return true;
        }

        case STATE_SECOND_CAPT: {
            mixMenu.SetTitle("Mix Manager - Pick second captain");
            return true;
        }

        case STATE_PICK_TEAMS: {
            mixMenu.SetTitle("Mix Manager - Pick team member(s)");
            return true;
        }
    }

    CloseHandle(mixMenu);
    return false;
}

void Menu_AddAllSpectators()
{
    char clientName[MAX_STR_LEN];
    char clientId[MAX_STR_LEN];

    mixMenu.RemoveAllItems();

    for (int client = 1; client <= MaxClients; ++client)
    {
        if (IsClientSpec(client) && IsClientInPlayers(client))
        {
            GetClientAuthId(client, AuthId_SteamID64, clientId, MAX_STR_LEN);
            GetClientName(client, clientName, MAX_STR_LEN);
            mixMenu.AddItem(clientId, clientName);
        }
    }

    if (isDebug)
    {
        for (int i = 0; i < fakePlayerCount; i++)
        {
            int team;
            if (!hSwapWhitelist.GetValue(g_FakePlayerAuthIds[i], team))
            {
                mixMenu.AddItem(g_FakePlayerAuthIds[i], g_FakePlayerNames[i]);
            }
        }
    }
}

bool IsClientInPlayers(int client)
{
    bool dummy;
    char clientAuthId[MAX_STR_LEN];
    GetClientAuthId(client, AuthId_SteamID64, clientAuthId, MAX_STR_LEN);
    return GetTrieValue(hPlayers, clientAuthId, dummy);
}

void Menu_DisplayToAllSpecs()
{
    for (int client = 1; client <= MaxClients; ++client)
    {
        if (IsClientSpec(client) && IsClientInPlayers(client))
            mixMenu.Display(client, 10);
    }
}

int Menu_MixHandler(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        if (currentState == STATE_FIRST_CAPT || currentState == STATE_SECOND_CAPT)
        {
            char authId[MAX_STR_LEN];
            menu.GetItem(param2, authId, MAX_STR_LEN);

            int voteCount;

            if (!GetTrieValue(hVoteResultsTrie, authId, voteCount))
                voteCount = 0;

            SetTrieValue(hVoteResultsTrie, authId, ++voteCount, true);

            if (voteCount > maxVoteCount)
            {
                strcopy(currentMaxVotedCaptAuthId, MAX_STR_LEN, authId);
                maxVoteCount = voteCount;
            }
        }
        else if (currentState == STATE_PICK_TEAMS)
        {
            char authId[MAX_STR_LEN];
            menu.GetItem(param2, authId, MAX_STR_LEN);
            int team = GetClientTeam(param1);

            if (team == L4D_TEAM_SPECTATOR || (team == L4D_TEAM_INFECTED && survivorsPick == 1) || (team == L4D_TEAM_SURVIVOR && survivorsPick == 0)) 
            {
                PrintToChatAll("\x04Mix Manager: \x01Captain \x03%N \x01found in the wrong team, aborting...", param1);
                StopMix();
            }
            else
            {
                if (SwapPlayerToTeam(authId, team, 0))
                {
                    pickCount++;
                    if (pickCount == iSurvivorLimit && !IsTeamFull(team))
                    {
                        // Do not switch picks
                    }
                    else if (IsTeamFull(L4D_TEAM_SURVIVOR) && IsTeamFull(L4D_TEAM_INFECTED)) 
                    {
                        PrintToChatAll("\x04Mix Manager: \x01 Teams are picked.");
                        StopMix();
                    }
                    else
                    {
                        survivorsPick = survivorsPick == 1 ? 0 : 1;

                        // Flip it again if the team is actually full. (5v5)
                        if (IsTeamFull(survivorsPick == 0 ? L4D_TEAM_INFECTED : L4D_TEAM_SURVIVOR))
                            survivorsPick = survivorsPick == 1 ? 0 : 1;
                    }
                }
                else
                {
                    PrintToChatAll("\x04Mix Manager: \x01The team member who was picked was not found, aborting...", param1);
                    StopMix();
                }
            }
        }
    }

    return 0;
}

Action Menu_StateHandler(Handle timer, Handle hndl)
{
    switch(currentState) {
        case STATE_FIRST_CAPT: {
            int numVotes = 0;
            GetTrieValue(hVoteResultsTrie, currentMaxVotedCaptAuthId, numVotes);
            ClearTrie(hVoteResultsTrie);
           
            if (SwapPlayerToTeam(currentMaxVotedCaptAuthId, L4D_TEAM_SURVIVOR, numVotes)) {
                strcopy(survCaptainAuthId, MAX_STR_LEN, currentMaxVotedCaptAuthId);
                currentState = STATE_SECOND_CAPT;
                maxVoteCount = 0;

                if (Menu_Initialise()) {
                    Menu_AddAllSpectators();
                    Menu_DisplayToAllSpecs();
                }
            } else {
                PrintToChatAll("\x04Mix Manager: \x01Failed to find first captain with at least 1 vote from spectators, aborting...");
                StopMix();
            }

            strcopy(currentMaxVotedCaptAuthId, MAX_STR_LEN, " ");
        }

        case STATE_SECOND_CAPT: {
            int numVotes = 0;
            GetTrieValue(hVoteResultsTrie, currentMaxVotedCaptAuthId, numVotes);
            ClearTrie(hVoteResultsTrie);

            if (SwapPlayerToTeam(currentMaxVotedCaptAuthId, L4D_TEAM_INFECTED, numVotes)) {
                strcopy(infCaptainAuthId, MAX_STR_LEN, currentMaxVotedCaptAuthId);
                currentState = STATE_PICK_TEAMS;
                CreateTimer(0.5, Menu_StateHandler);

            } else {
                PrintToChatAll("\x04Mix Manager: \x01Failed to find second captain with at least 1 vote from spectators, aborting...");
                StopMix();
            }

            strcopy(currentMaxVotedCaptAuthId, MAX_STR_LEN, " ");
        }

        case STATE_PICK_TEAMS: {
            isPickingCaptain = false;
            survivorsPick = GetURandomInt() & 1;
            CreateTimer(1.0, Menu_TeamPickHandler, _, TIMER_REPEAT);
        }
    }

    if (currentState == STATE_NO_MIX || currentState == STATE_PICK_TEAMS)
        return Plugin_Stop; 
    else
        return Plugin_Handled;
}

Action Menu_TeamPickHandler(Handle timer)
{
    if (currentState == STATE_PICK_TEAMS)
    {
        if (Menu_Initialise())
        {
            Menu_AddAllSpectators();
            int captain = GetClientFromAuthId(survivorsPick == 1 ? survCaptainAuthId : infCaptainAuthId);

            if (captain > 0)
            {
                if (GetSpectatorsCount() > 0)
                    mixMenu.Display(captain, 1);
                else
                {
                    PrintToChatAll("\x04Mix Manager: \x01No more spectators to choose from, aborting...");
                    StopMix();
                    return Plugin_Stop;
                }
            }
            else
            {
                PrintToChatAll("\x04Mix Manager: \x01Failed to find the captain, aborting...");
                StopMix();
                return Plugin_Stop;
            }

            return Plugin_Continue;
        }
    }
    return Plugin_Stop;
}

void SwapAllPlayersToSpec()
{
    for (int client = 1; client <= MaxClients; ++client)
    {
        if (IsClientInGame(client) && !IsFakeClient(client))
            ChangeClientTeam(client, L4D_TEAM_SPECTATOR);
    }
}

bool SwapPlayerToTeam(const char[] authId, int team, int numVotes)
{
    if (isDebug && strncmp(authId, "FAKE_", 5) == 0)
    {
        hSwapWhitelist.SetValue(authId, team);

        // Find the fake player name
        char fakeName[MAX_STR_LEN] = "FAKE_PLAYER";
        for (int i = 0; i < fakePlayerCount; i++)
        {
            if (strcmp(authId, g_FakePlayerAuthIds[i]) == 0)
            {
                strcopy(fakeName, sizeof(fakeName), g_FakePlayerNames[i]);
                break;
            }
        }

        if (currentState == STATE_PICK_TEAMS)
        {
            if (survivorsPick == 1)
                PrintToChatAll("\x04Mix Manager: \x03%s \x01was picked (survivors).", fakeName);
            else
                PrintToChatAll("\x04Mix Manager: \x03%s \x01was picked (infected).", fakeName);
        }

        return true;
    }

    int client = GetClientFromAuthId(authId);
    bool foundClient = client > 0;

    if (foundClient)
    {
        hSwapWhitelist.SetValue(authId, team);

        if (team == L4D_TEAM_SURVIVOR)
            FakeClientCommand(client, "jointeam 2");
        else
            FakeClientCommand(client, "jointeam 3");

        switch(currentState) {
            case STATE_FIRST_CAPT: {
                PrintToChatAll("\x04Mix Manager: \x01First captain is \x03%N\x01. (\x05%d \x01votes)", client, numVotes);
            }

            case STATE_SECOND_CAPT: {
                PrintToChatAll("\x04Mix Manager: \x01Second captain is \x03%N\x01. (\x05%d \x01votes)", client, numVotes);
            }

            case STATE_PICK_TEAMS: {
                if (survivorsPick == 1) {
                    PrintToChatAll("\x04Mix Manager: \x03%N \x01was picked (survivors).", client)
                } else {
                    PrintToChatAll("\x04Mix Manager: \x03%N \x01was picked (infected).", client)
                }
            }
        }
    }

    return foundClient;
}

int GetClientFromAuthId(const char[] authId)
{
    char clientAuthId[MAX_STR_LEN];

    if (isDebug && strncmp(authId, "FAKE_", 5) == 0)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && !IsFakeClient(i) && CheckCommandAccess(i, "sm_changemap", ADMFLAG_CHANGEMAP, true))
            {
                return i;
            }
        }
        return 1;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            GetClientAuthId(i, AuthId_SteamID64, clientAuthId, MAX_STR_LEN);

            if (strcmp(authId, clientAuthId) == 0)
                return i;
        }
    }

    return 0;
}

bool IsClientSpec(int client)
{
    return IsClientInGame(client) && !IsFakeClient(client) && GetClientTeam(client) == 1;
}

int GetSpectatorsCount()
{
    int count = 0;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientSpec(client))
            ++count;
    }

    if (isDebug)
    {
        for (int i = 0; i < fakePlayerCount; i++)
        {
            int team;
            if (!hSwapWhitelist.GetValue(g_FakePlayerAuthIds[i], team))
            {
                count++;
            }
        }
    }

    return count;
}

bool IsSurvivor(int client)
{
    return IsHuman(client) && GetClientTeam(client) == L4D_TEAM_SURVIVOR;
}

bool IsInfected(int client)
{
    return IsHuman(client) && GetClientTeam(client) == L4D_TEAM_INFECTED;
}

bool IsHuman(int client)
{
    return IsClientInGame(client) && !IsFakeClient(client);
}

stock bool IsTeamFull(int teamToCount)
{
    int count, team;
    StringMapSnapshot snapshot = hSwapWhitelist.Snapshot();
    int size = snapshot.Length;
    char authId[64];

    for (int i = 0; i < size; i++)
    {
        snapshot.GetKey(i, authId, sizeof(authId))

        if (hSwapWhitelist.GetValue(authId, team) && team == teamToCount)
        {
            count++;
        }
    }

    delete snapshot;
    return count >= iSurvivorLimit;
}

void AutoFillFakePlayers(int realPlayerCount)
{
    // Calculate how many fake players we need
    int requiredPlayers = iSurvivorLimit * 2;
    int neededFakePlayers = requiredPlayers - realPlayerCount;

    // Clear existing fake players first
    for (int i = 0; i < fakePlayerCount; i++)
    {
        hPlayers.Remove(g_FakePlayerAuthIds[i]);
        hSwapWhitelist.Remove(g_FakePlayerAuthIds[i]);
    }
    fakePlayerCount = 0;

    // Add the needed fake players
    if (neededFakePlayers > 0)
    {
        int actualCount = neededFakePlayers < MAX_FAKE_PLAYERS ? neededFakePlayers : MAX_FAKE_PLAYERS;

        for (int i = 0; i < actualCount; i++)
        {
            // Create name with your preferred format
            char name[MAX_STR_LEN];
            Format(name, sizeof(name), "FAKE_PLAYER_%d", i+1);

            // Generate a unique fake SteamID
            char authId[MAX_STR_LEN];
            Format(authId, sizeof(authId), "FAKE_%d", GetRandomInt(10000, 99999));

            // Store the fake player info
            strcopy(g_FakePlayerAuthIds[fakePlayerCount], MAX_STR_LEN, authId);
            strcopy(g_FakePlayerNames[fakePlayerCount], MAX_STR_LEN, name);

            // Add to players trie for mix eligibility
            SetTrieValue(hPlayers, authId, true);

            fakePlayerCount++;
        }
    }
}