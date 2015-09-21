/**
 * vim: set ts=4 :
 * =============================================================================
 * MapChooser Extended
 * Creates a map vote at appropriate times, setting sm_nextmap to the winning
 * vote.  Includes extra options not present in the SourceMod MapChooser
 *
 * MapChooser Extended (C)2011-2014 Powerlord (Ross Bemrose)
 * SourceMod (C)2004-2007 AlliedModders LLC.  All rights reserved.
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * As a special exception, AlliedModders LLC gives you permission to link the
 * code of this program (as well as its derivative works) to "Half-Life 2," the
 * "Source Engine," the "SourcePawn JIT," and any Game MODs that run on software
 * by the Valve Corporation.  You must obey the GNU General Public License in
 * all respects for all other code used.  Additionally, AlliedModders LLC grants
 * this exception to all derivative works.  AlliedModders LLC defines further
 * exceptions, found in LICENSE.txt (as of this writing, version JULY-31-2007),
 * or <http://www.sourcemod.net/license.php>.
 *
 * Version: $Id$
 */

#pragma semicolon 1
#include <sourcemod>
#include <mapchooser>
#include <nextmap>
#include <sdktools>
#include <colors>

#pragma newdecls required
#include "include/mapchooser_extended"

#undef REQUIRE_PLUGIN
#include <nativevotes>

#define MCE_VERSION "1.11.0 beta 3"

enum RoundCounting
{
	RoundCounting_Standard = 0,
	RoundCounting_MvM,
	RoundCounting_ArmsRace,
}

// CSGO requires two cvars to get the game type
enum
{
	GameType_Classic	= 0,
	GameType_GunGame	= 1,
	GameType_Training	= 2,
	GameType_Custom		= 3,
}

enum
{
	GunGameMode_ArmsRace	= 0,
	GunGameMode_Demolition	= 1,
	GunGameMode_DeathMatch	= 2,
}

public Plugin myinfo =
{
	name = "MapChooser Extended",
	author = "Powerlord, Zuko, and AlliedModders LLC",
	description = "Automated Map Voting with Extensions",
	version = MCE_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=156974"
};

/* Valve ConVars */
ConVar g_Cvar_Winlimit;
ConVar g_Cvar_Maxrounds;
ConVar g_Cvar_Fraglimit;
ConVar g_Cvar_Bonusroundtime;
ConVar g_Cvar_MatchClinch;
ConVar g_Cvar_VoteNextLevel;
ConVar g_Cvar_GameType;
ConVar g_Cvar_GameMode;

/* Plugin ConVars */
ConVar g_Cvar_StartTime;
ConVar g_Cvar_StartRounds;
ConVar g_Cvar_StartFrags;
ConVar g_Cvar_ExtendTimeStep;
ConVar g_Cvar_ExtendRoundStep;
ConVar g_Cvar_ExtendFragStep;
ConVar g_Cvar_ExcludeMaps;
ConVar g_Cvar_IncludeMaps;
ConVar g_Cvar_NoVoteMode;
ConVar g_Cvar_Extend;
ConVar g_Cvar_DontChange;
ConVar g_Cvar_EndOfMapVote;
ConVar g_Cvar_VoteDuration;

Handle g_VoteTimer;
Handle g_RetryTimer;
Handle g_WarningTimer;

/* Data Handles */
ArrayList g_MapList;
ArrayList g_NominateList;
ArrayList g_NominateOwners;
ArrayList g_OldMapList;
ArrayList g_NextMapList;
Menu g_VoteMenu;
NativeVote g_VoteNative;

int g_Extends;
int g_TotalRounds;
bool g_HasVoteStarted;
bool g_WaitingForVote;
bool g_MapVoteCompleted;
bool g_ChangeMapAtRoundEnd;
bool g_ChangeMapInProgress;
bool g_HasIntermissionStarted = false;
int g_mapFileSerial = -1;

MapChange g_ChangeTime;

Handle g_NominationsResetForward;
Handle g_MapVoteStartedForward;

/* Mapchooser Extended Plugin ConVars */

ConVar g_Cvar_RunOff;
ConVar g_Cvar_RunOffPercent;
ConVar g_Cvar_BlockSlots;
ConVar g_Cvar_MaxRunOffs;
ConVar g_Cvar_StartTimePercent;
ConVar g_Cvar_StartTimePercentEnable;
ConVar g_Cvar_WarningTime;
ConVar g_Cvar_RunOffWarningTime;
ConVar g_Cvar_MenuStyle;
ConVar g_Cvar_TimerLocation;
ConVar g_Cvar_ExtendPosition;
ConVar g_Cvar_MarkCustomMaps;
ConVar g_Cvar_RandomizeNominations;
ConVar g_Cvar_HideTimer;
ConVar g_Cvar_NoVoteOption;
ConVar g_Cvar_NominateAll;

/* Mapchooser Extended Data Handles */
ArrayList g_OfficialList;

/* Mapchooser Extended Forwards */
Handle g_MapVoteWarningStartForward;
Handle g_MapVoteWarningTickForward;
Handle g_MapVoteStartForward;
Handle g_MapVoteEndForward;
Handle g_MapVoteRunoffStartForward;

/* Mapchooser Extended Globals */
int g_RunoffCount = 0;
int g_mapOfficialFileSerial = -1;
bool g_NativeVotes = false;
char g_GameModName[64];
bool g_WarningInProgress = false;
bool g_AddNoVote = false;

RoundCounting g_RoundCounting = RoundCounting_Standard;

/* Upper bound of how many team there could be */
#define MAXTEAMS 10
int g_winCount[MAXTEAMS];

bool g_BlockedSlots = false;
int g_ObjectiveEnt = -1;

enum TimerLocation
{
	TimerLocation_Hint = 0,
	TimerLocation_Center = 1,
	TimerLocation_Chat = 2,
}

enum WarningType
{
	WarningType_Vote,
	WarningType_Revote,
}

#define VOTE_EXTEND "##extend##"
#define VOTE_DONTCHANGE "##dontchange##"

/* Mapchooser Extended Defines */
#define LINE_ONE "##lineone##"
#define LINE_TWO "##linetwo##"
#define LINE_SPACER "##linespacer##"
#define FAILURE_TIMER_LENGTH 5

#define NV "nativevotes"

EngineVersion g_EngineVersion;

public void OnPluginStart()
{
	LoadTranslations("mapchooser_extended.phrases");
	LoadTranslations("basevotes.phrases");
	LoadTranslations("common.phrases");
	
	int arraySize = ByteCountToCells(PLATFORM_MAX_PATH);
	g_MapList = new ArrayList(arraySize);
	g_NominateList = new ArrayList(arraySize);
	g_NominateOwners = new ArrayList();
	g_OldMapList = new ArrayList(arraySize);
	g_NextMapList = new ArrayList(arraySize);
	g_OfficialList = new ArrayList(arraySize);
	
	GetGameFolderName(g_GameModName, sizeof(g_GameModName));
	
	g_Cvar_EndOfMapVote = CreateConVar("mce_endvote", "1", "Specifies if MapChooser should run an end of map vote", _, true, 0.0, true, 1.0);

	g_Cvar_StartTime = CreateConVar("mce_starttime", "10.0", "Specifies when to start the vote based on time remaining.", _, true, 1.0);
	g_Cvar_StartRounds = CreateConVar("mce_startround", "2.0", "Specifies when to start the vote based on rounds remaining. Use 0 on DoD:S, CS:S, and TF2 to start vote during bonus round time", _, true, 0.0);
	g_Cvar_StartFrags = CreateConVar("mce_startfrags", "5.0", "Specifies when to start the vote base on frags remaining.", _, true, 1.0);
	g_Cvar_ExtendTimeStep = CreateConVar("mce_extend_timestep", "15", "Specifies how much many more minutes each extension makes", _, true, 5.0);
	g_Cvar_ExtendRoundStep = CreateConVar("mce_extend_roundstep", "5", "Specifies how many more rounds each extension makes", _, true, 1.0);
	g_Cvar_ExtendFragStep = CreateConVar("mce_extend_fragstep", "10", "Specifies how many more frags are allowed when map is extended.", _, true, 5.0);	
	g_Cvar_ExcludeMaps = CreateConVar("mce_exclude", "5", "Specifies how many past maps to exclude from the vote.", _, true, 0.0);
	g_Cvar_IncludeMaps = CreateConVar("mce_include", "5", "Specifies how many maps to include in the vote.", _, true, 2.0, true, 6.0);
	g_Cvar_NoVoteMode = CreateConVar("mce_novote", "1", "Specifies whether or not MapChooser should pick a map if no votes are received.", _, true, 0.0, true, 1.0);
	g_Cvar_Extend = CreateConVar("mce_extend", "0", "Number of extensions allowed each map.", _, true, 0.0);
	g_Cvar_DontChange = CreateConVar("mce_dontchange", "1", "Specifies if a 'Don't Change' option should be added to early votes", _, true, 0.0);
	g_Cvar_VoteDuration = CreateConVar("mce_voteduration", "20", "Specifies how long the mapvote should be available for.", _, true, 5.0);
	g_Cvar_RunOff = CreateConVar("mce_runoff", "1", "Hold run off votes if winning choice has less than a certain percentage of votes", _, true, 0.0, true, 1.0);
	g_Cvar_RunOffPercent = CreateConVar("mce_runoffpercent", "50", "If winning choice has less than this percent of votes, hold a runoff", _, true, 0.0, true, 100.0);
	
	// MapChooser Extended cvars
	CreateConVar("mce_version", MCE_VERSION, "MapChooser Extended Version", FCVAR_SPONLY|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	g_Cvar_BlockSlots = CreateConVar("mce_blockslots", "1", "Block slots to prevent accidental votes.  Only applies when Voice Command style menus are in use.", _, true, 0.0, true, 1.0);
	//g_Cvar_BlockSlotsCount = CreateConVar("mce_blockslots_count", "2", "Number of slots to block.", _, true, 1.0, true, 3.0);
	g_Cvar_MaxRunOffs = CreateConVar("mce_maxrunoffs", "1", "Number of run off votes allowed each map.", _, true, 0.0);
	g_Cvar_StartTimePercent = CreateConVar("mce_start_percent", "35.0", "Specifies when to start the vote based on percents.", _, true, 0.0, true, 100.0);
	g_Cvar_StartTimePercentEnable = CreateConVar("mce_start_percent_enable", "0", "Enable or Disable percentage calculations when to start vote.", _, true, 0.0, true, 1.0);
	g_Cvar_WarningTime = CreateConVar("mce_warningtime", "15.0", "Warning time in seconds.", _, true, 0.0, true, 60.0);
	g_Cvar_RunOffWarningTime = CreateConVar("mce_runoffvotewarningtime", "5.0", "Warning time for runoff vote in seconds.", _, true, 0.0, true, 30.0);
	g_Cvar_MenuStyle = CreateConVar("mce_menustyle", "0", "Menu Style.  0 is the game's default, 1 is the older Valve style that requires you to press Escape to see the menu, 2 is the newer 1-9 button Voice Command style, unavailable in some games. Ignored on TF2 if NativeVotes Plugin is loaded.", _, true, 0.0, true, 2.0);
	g_Cvar_TimerLocation = CreateConVar("mce_warningtimerlocation", "0", "Location for the warning timer text. 0 is HintBox, 1 is Center text, 2 is Chat.  Defaults to HintBox.", _, true, 0.0, true, 2.0);
	g_Cvar_MarkCustomMaps = CreateConVar("mce_markcustommaps", "1", "Mark custom maps in the vote list. 0 = Disabled, 1 = Mark with *, 2 = Mark with phrase.", _, true, 0.0, true, 2.0);
	g_Cvar_ExtendPosition = CreateConVar("mce_extendposition", "0", "Position of Extend/Don't Change options. 0 = at end, 1 = at start.", _, true, 0.0, true, 1.0);
	g_Cvar_RandomizeNominations = CreateConVar("mce_randomizeorder", "1", "Randomize map order?", _, true, 0.0, true, 1.0);
	g_Cvar_HideTimer = CreateConVar("mce_hidetimer", "0", "Hide the MapChooser Extended warning timer", _, true, 0.0, true, 1.0);
	g_Cvar_NoVoteOption = CreateConVar("mce_addnovote", "1", "Add \"No Vote\" to vote menu? Doesn't apply for NativeVotes.", _, true, 0.0, true, 1.0);
	g_Cvar_NominateAll = CreateConVar("mce_nominateall", "0", "Allow all nominations, ignoring nominations limit. Requires mce_randomizeorder 1 and will be ignored otherwise.", _, true, 0.0, true, 1.0);

	RegAdminCmd("sm_mapvote", Command_Mapvote, ADMFLAG_CHANGEMAP, "sm_mapvote - Forces MapChooser to attempt to run a map vote now.");
	RegAdminCmd("sm_setnextmap", Command_SetNextmap, ADMFLAG_CHANGEMAP, "sm_setnextmap <map>");
	
	// Mapchooser Extended Commands
	RegAdminCmd("mce_reload_maplist", Command_ReloadMaps, ADMFLAG_CHANGEMAP, "mce_reload_maplist - Reload the Official Maplist file.");

	g_Cvar_Winlimit = FindConVar("mp_winlimit");
	g_Cvar_Maxrounds = FindConVar("mp_maxrounds");
	g_Cvar_Fraglimit = FindConVar("mp_fraglimit");
	
	g_EngineVersion = GetEngineVersion();
	
	char mapListPath[PLATFORM_MAX_PATH];
	
	BuildPath(Path_SM, mapListPath, PLATFORM_MAX_PATH, "configs/mapchooser_extended/maps/%s.txt", g_GameModName);
	SetMapListCompatBind("official", mapListPath);

	switch (g_EngineVersion)
	{
		case Engine_TF2:
		{
			g_Cvar_VoteNextLevel = FindConVar("sv_vote_issue_nextlevel_allowed");
			g_Cvar_Bonusroundtime = FindConVar("mp_bonusroundtime");			
		}
		
		case Engine_CSGO:
		{
			g_Cvar_VoteNextLevel = FindConVar("mp_endmatch_votenextmap");
			g_Cvar_GameType = FindConVar("game_type");
			g_Cvar_GameMode = FindConVar("game_mode");
			g_Cvar_Bonusroundtime = FindConVar("mp_round_restart_delay");
		}
		
		case Engine_DODS:
		{
			g_Cvar_Bonusroundtime = FindConVar("dod_bonusroundtime");
		}
		
		case Engine_CSS:
		{
			g_Cvar_Bonusroundtime = FindConVar("mp_round_restart_delay");
		}
		
		default:
		{
			g_Cvar_Bonusroundtime = FindConVar("mp_bonusroundtime");			
		}
	}

	if (g_Cvar_Winlimit != null || g_Cvar_Maxrounds != null)
	{
		switch (g_EngineVersion)
		{
			case Engine_TF2:
			{
				HookEvent("teamplay_win_panel", Event_TeamPlayWinPanel);
				HookEvent("teamplay_restart_round", Event_TFRestartRound);
				HookEvent("arena_win_panel", Event_TeamPlayWinPanel);
				HookEvent("pve_win_panel", Event_MvMWinPanel);
			}
			
			case Engine_NuclearDawn:
			{
				HookEvent("round_win", Event_RoundEnd);
			}
			
			case Engine_CSGO:
			{
				HookEvent("round_end", Event_RoundEnd);
				HookEvent("cs_intermission", Event_Intermission);
				HookEvent("announce_phase_end", Event_PhaseEnd);
				g_Cvar_MatchClinch = FindConVar("mp_match_can_clinch");
			}
			
			case Engine_DODS:
			{
				HookEvent("dod_round_win", Event_RoundEnd);
			}
			
			default:
			{
				HookEvent("round_end", Event_RoundEnd);
			}
		}
	}
	
	if (g_Cvar_Fraglimit != null)
	{
		HookEvent("player_death", Event_PlayerDeath);		
	}
	
	AutoExecConfig(true, "mapchooser_extended");
	
	//Change the mp_bonusroundtime max so that we have time to display the vote
	//If you display a vote during bonus time good defaults are 17 vote duration and 19 mp_bonustime
	if (g_Cvar_Bonusroundtime != null)
	{
		g_Cvar_Bonusroundtime.SetBounds(ConVarBound_Upper, true, 30.0);		
	}
	
	g_NominationsResetForward = CreateGlobalForward("OnNominationRemoved", ET_Ignore, Param_String, Param_Cell);
	g_MapVoteStartedForward = CreateGlobalForward("OnMapVoteStarted", ET_Ignore);

	//MapChooser Extended Forwards
	g_MapVoteStartForward = CreateGlobalForward("OnMapVoteStart", ET_Ignore); // Deprecated
	g_MapVoteEndForward = CreateGlobalForward("OnMapVoteEnd", ET_Ignore, Param_String);
	g_MapVoteWarningStartForward = CreateGlobalForward("OnMapVoteWarningStart", ET_Ignore);
	g_MapVoteWarningTickForward = CreateGlobalForward("OnMapVoteWarningTick", ET_Ignore, Param_Cell);
	g_MapVoteRunoffStartForward = CreateGlobalForward("OnMapVoteRunnoffWarningStart", ET_Ignore);

}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("mapchooser");	
	
	CreateNative("NominateMap", Native_NominateMap);
	CreateNative("RemoveNominationByMap", Native_RemoveNominationByMap);
	CreateNative("RemoveNominationByOwner", Native_RemoveNominationByOwner);
	CreateNative("InitiateMapChooserVote", Native_InitiateVote);
	CreateNative("CanMapChooserStartVote", Native_CanVoteStart);
	CreateNative("HasEndOfMapVoteFinished", Native_CheckVoteDone);
	CreateNative("GetExcludeMapList", Native_GetExcludeMapList);
	CreateNative("GetNominatedMapList", Native_GetNominatedMapList);
	CreateNative("EndOfMapVoteEnabled", Native_EndOfMapVoteEnabled);
	
	// MapChooser Extended natives
	CreateNative("IsMapOfficial", Native_IsMapOfficial);
	CreateNative("CanNominate", Native_CanNominate);
	
	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	if (FindPluginByFile("mapchooser.smx") != null)
	{
		SetFailState("This plugin replaces mapchooser.  You cannot run both at once.");
	}
	
	g_NativeVotes = LibraryExists(NV) && NativeVotes_IsVoteTypeSupported(NativeVotesType_NextLevelMult);
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, NV) && NativeVotes_IsVoteTypeSupported(NativeVotesType_NextLevelMult))
	{
		g_NativeVotes = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, NV))
	{
		g_NativeVotes = false;
	}
}

public void OnMapStart()
{
	g_RoundCounting = RoundCounting_Standard;
	g_ObjectiveEnt = -1;
	
	if (g_EngineVersion == Engine_TF2 && GameRules_GetProp("m_bPlayingMannVsMachine"))
	{
		g_RoundCounting = RoundCounting_MvM;
		g_ObjectiveEnt = EntIndexToEntRef(FindEntityByClassname(-1, "tf_objective_resource"));
	}
	else if (g_EngineVersion == Engine_CSGO && g_Cvar_GameType.IntValue == GameType_GunGame &&
		g_Cvar_GameMode.IntValue == GunGameMode_ArmsRace)
	{
		g_RoundCounting = RoundCounting_ArmsRace;
	}
}

public void OnConfigsExecuted()
{
	if (ReadMapList(g_MapList,
					 g_mapFileSerial, 
					 "mapchooser",
					 MAPLIST_FLAG_CLEARARRAY|MAPLIST_FLAG_MAPSFOLDER)
		!= null)
		
	{
		if (g_mapFileSerial == -1)
		{
			LogError("Unable to create a valid map list.");
		}
	}
	
	// Disable the next level vote in TF2 and CS:GO
	// In TF2, this has two effects: 1. Stop the next level vote (which overlaps rtv functionality).
	// 2. Stop the built-in end level vote.  This is the only thing that happens in CS:GO
	if (g_Cvar_VoteNextLevel != null)
	{
		g_Cvar_VoteNextLevel.BoolValue = false;
	}
	
	CreateNextVote();
	SetupTimeleftTimer();
	
	g_TotalRounds = 0;
	
	g_Extends = 0;
	
	g_MapVoteCompleted = false;
	
	g_NominateList.Clear();
	g_NominateOwners.Clear();
	
	for (int i=0; i<MAXTEAMS; i++)
	{
		g_winCount[i] = 0;	
	}

	/* Check if mapchooser will attempt to start mapvote during bonus round time */
	if ((g_Cvar_Bonusroundtime != null) && !g_Cvar_StartRounds.IntValue)
	{
		if (!g_Cvar_StartTime.IntValue && g_Cvar_Bonusroundtime.FloatValue <= g_Cvar_VoteDuration.FloatValue)
		{
			LogError("Warning - Bonus Round Time shorter than Vote Time. Votes during bonus round may not have time to complete");
		}
	}
	
	InitializeOfficialMapList();
}

public void OnMapEnd()
{
	g_HasVoteStarted = false;
	g_WaitingForVote = false;
	g_ChangeMapAtRoundEnd = false;
	g_ChangeMapInProgress = false;
	g_HasIntermissionStarted = false;
	
	g_VoteTimer = null;
	g_RetryTimer = null;
	g_WarningTimer = null;
	g_RunoffCount = 0;
	
	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, PLATFORM_MAX_PATH);
	g_OldMapList.PushString(map);
				
	if (g_OldMapList.Length > g_Cvar_ExcludeMaps.IntValue)
	{
		g_OldMapList.Erase(0);
	}	
}

public void OnClientDisconnect(int client)
{
	int index = g_NominateOwners.FindValue(client);
	
	if (index == -1)
	{
		return;
	}
	
	char oldmap[PLATFORM_MAX_PATH];
	g_NominateList.GetString(index, oldmap, PLATFORM_MAX_PATH);
	Call_StartForward(g_NominationsResetForward);
	Call_PushString(oldmap);
	Call_PushCell(GetArrayCell(g_NominateOwners, index));
	Call_Finish();
	
	g_NominateOwners.Erase(index);
	g_NominateList.Erase(index);
}

public Action Command_SetNextmap(int client, int args)
{
	if (args < 1)
	{
		CReplyToCommand(client, "[MCE] Usage: sm_setnextmap <map>");
		return Plugin_Handled;
	}

	char map[PLATFORM_MAX_PATH];
	char displayName[PLATFORM_MAX_PATH];
	GetCmdArg(1, map, PLATFORM_MAX_PATH);

	if (FindMap(map, displayName, sizeof(displayName)) == FindMap_NotFound)
	{
		CReplyToCommand(client, "[MCE] %t", "Map was not found", map);
		return Plugin_Handled;
	}

	GetMapDisplayName(displayName, displayName, sizeof(displayName));
	
	ShowActivity(client, "%t", "Changed Next Map", map);
	LogAction(client, -1, "\"%L\" changed nextmap to \"%s\"", client, map);

	SetNextMap(map);
	g_MapVoteCompleted = true;

	return Plugin_Handled;
}

public Action Command_ReloadMaps(int client, int args)
{
	InitializeOfficialMapList();
}

public void OnMapTimeLeftChanged()
{
	if (g_MapList.Length)
	{
		SetupTimeleftTimer();
	}
}

void SetupTimeleftTimer()
{
	int time;
	if (GetMapTimeLeft(time) && time > 0)
	{
		int startTime;
		if (g_Cvar_StartTimePercentEnable.BoolValue)
		{
			int timeLimit;
			if (GetMapTimeLimit(timeLimit) && timeLimit > 0)
			{
				startTime = GetConVarInt(g_Cvar_StartTimePercent) * (timeLimit * 60) / 100;
			}
		}
		else
		{
			startTime = GetConVarInt(g_Cvar_StartTime) * 60;
		}
		
		if (time - startTime < 0 && GetConVarBool(g_Cvar_EndOfMapVote) && !g_MapVoteCompleted && !g_HasVoteStarted)
		{
			SetupWarningTimer(WarningType_Vote);
		}
		else
		{
			if (g_WarningTimer == null)
			{
				if (g_VoteTimer != null)
				{
					delete g_VoteTimer;
				}	
				
				//g_VoteTimer = CreateTimer(float(time - startTime), Timer_StartMapVoteTimer_StartMapVote, _, TIMER_FLAG_NO_MAPCHANGE);
				g_VoteTimer = CreateTimer(float(time - startTime), Timer_StartWarningTimer, _, TIMER_FLAG_NO_MAPCHANGE);
			}
		}		
	}
}

public Action Timer_StartWarningTimer(Handle timer)
{
	g_VoteTimer = null;
	
	if (!g_WarningInProgress || g_WarningTimer == null)
	{
		SetupWarningTimer(WarningType_Vote);
	}
}

public Action Timer_StartMapVote(Handle timer, DataPack data)
{
	static int timePassed;

	// This is still necessary because InitiateVote still calls this directly via the retry timer
	if (!GetArraySize(g_MapList) || !GetConVarBool(g_Cvar_EndOfMapVote) || g_MapVoteCompleted || g_HasVoteStarted)
	{
		g_WarningTimer = null;
		return Plugin_Stop;
	}

	data.Reset();
	int warningMaxTime = data.ReadCell();
	int warningTimeRemaining = warningMaxTime - timePassed;

	char warningPhrase[32];
	data.ReadString(warningPhrase, sizeof(warningPhrase));
	
	// Tick timer for external plugins
	Call_StartForward(g_MapVoteWarningTickForward);
	Call_PushCell(warningTimeRemaining);
	Call_Finish();

	if (timePassed == 0 || !g_Cvar_HideTimer.BoolValue)
	{
		TimerLocation timerLocation = view_as<TimerLocation>(g_Cvar_TimerLocation.IntValue);
		
		switch(timerLocation)
		{
			case TimerLocation_Center:
			{
				PrintCenterTextAll("%t", warningPhrase, warningTimeRemaining);
			}
			
			case TimerLocation_Chat:
			{
				PrintToChatAll("%t", warningPhrase, warningTimeRemaining);
			}
			
			default:
			{
				PrintHintTextToAll("%t", warningPhrase, warningTimeRemaining);
			}
		}
	}

	if (timePassed++ >= warningMaxTime)
	{
		if (timer == g_RetryTimer)
		{
			g_WaitingForVote = false;
			g_RetryTimer = null;
		}
		else
		{
			g_WarningTimer = null;
		}
	
		timePassed = 0;
		MapChange mapChange = view_as<MapChange>(data.ReadCell());
		ArrayList hndl = view_as<ArrayList>(data.ReadCell());
		
		InitiateVote(mapChange, hndl);
		
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

public void Event_TFRestartRound(Event event, const char[] name, bool dontBroadcast)
{
	/* Game got restarted - reset our round count tracking */
	g_TotalRounds = 0;	
}

public void Event_TeamPlayWinPanel(Event event, const char[] name, bool dontBroadcast)
{
	if (g_ChangeMapAtRoundEnd)
	{
		g_ChangeMapAtRoundEnd = false;
		CreateTimer(2.0, Timer_ChangeMap, _, TIMER_FLAG_NO_MAPCHANGE);
		g_ChangeMapInProgress = true;
	}
	
	int bluescore = GetEventInt(event, "blue_score");
	int redscore = GetEventInt(event, "red_score");
		
	if(event.GetInt("round_complete") == 1 || StrEqual(name, "arena_win_panel"))
	{
		g_TotalRounds++;
		
		if (!g_MapList.Length || g_HasVoteStarted || g_MapVoteCompleted || !g_Cvar_EndOfMapVote.BoolValue)
		{
			return;
		}
		
		CheckMaxRounds(g_TotalRounds);
		
		switch(event.GetInt("winning_team"))
		{
			case 3:
			{
				CheckWinLimit(bluescore);
			}
			case 2:
			{
				CheckWinLimit(redscore);				
			}			
			//We need to do nothing on winning_team == 0 this indicates stalemate.
			default:
			{
				return;
			}			
		}
	}
}

public void Event_MvMWinPanel(Event event, const char[] name, bool dontBroadcast)
{
	if (event.GetInt("winning_team") == 2)
	{
		int objectiveEnt = EntRefToEntIndex(g_ObjectiveEnt);
		if (objectiveEnt != INVALID_ENT_REFERENCE)
		{
			g_TotalRounds = GetEntProp(g_ObjectiveEnt, Prop_Send, "m_nMannVsMachineWaveCount");
			CheckMaxRounds(g_TotalRounds);
		}
	}
}

public void Event_Intermission(Event event, const char[] name, bool dontBroadcast)
{
	g_HasIntermissionStarted = true;
}

public void Event_PhaseEnd(Event event, const char[] name, bool dontBroadcast)
{
	/* announce_phase_end fires for both half time and the end of the map, but intermission fires first for end of the map. */
	if (g_HasIntermissionStarted)
	{
		return;
	}

	/* No intermission yet, so this must be half time. Swap the score counters. */
	int t_score = g_winCount[2];
	g_winCount[2] =  g_winCount[3];
	g_winCount[3] = t_score;
}
 
public void Event_WeaponRank(Event event, const char[] name, bool dontBroadcast)
{
	int rank = event.GetInt("weaponrank");
	if (rank > g_TotalRounds)
	{
		g_TotalRounds = rank;
		CheckMaxRounds(g_TotalRounds);
	}
}

/* You ask, why don't you just use team_score event? And I answer... Because CSS doesn't. */
public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (g_RoundCounting == RoundCounting_ArmsRace)
	{
		return;
	}
	
	if (g_ChangeMapAtRoundEnd)
	{
		g_ChangeMapAtRoundEnd = false;
		CreateTimer(2.0, Timer_ChangeMap, _, TIMER_FLAG_NO_MAPCHANGE);
		g_ChangeMapInProgress = true;
	}
	
	int winner;
	if (strcmp(name, "round_win") == 0 || strcmp(name, "dod_round_win") == 0)
	{
		// Nuclear Dawn & DoD:S
		winner = event.GetInt("team");
	}
	else
	{
		winner = event.GetInt("winner");
	}
	
	if (winner == 0 || winner == 1 || !g_Cvar_EndOfMapVote.BoolValue)
	{
		return;
	}
	
	if (winner >= MAXTEAMS)
	{
		SetFailState("Mod exceed maximum team count - Please file a bug report.");	
	}

	g_TotalRounds++;
	
	g_winCount[winner]++;
	
	if (!g_MapList.Length || g_HasVoteStarted || g_MapVoteCompleted)
	{
		return;
	}
	
	CheckWinLimit(g_winCount[winner]);
	CheckMaxRounds(g_TotalRounds);
}

public void CheckWinLimit(int winner_score)
{	
	if (g_Cvar_Winlimit != null)
	{
		int winlimit = g_Cvar_Winlimit.IntValue;
		if (winlimit)
		{			
			if (winner_score >= (winlimit - g_Cvar_StartRounds.IntValue))
			{
				if (!g_WarningInProgress || g_WarningTimer == null)
				{
					SetupWarningTimer(WarningType_Vote, MapChange_MapEnd);
				}
			}
		}
	}
	
	if (g_Cvar_MatchClinch != null && g_Cvar_Maxrounds != null)
	{
		bool clinch = g_Cvar_MatchClinch.BoolValue;
		
		if (clinch)
		{
			int maxrounds = g_Cvar_Maxrounds.IntValue;
			int winlimit = RoundFloat(maxrounds / 2.0);
			
			if(winner_score == winlimit - 1)
			{
				if (!g_WarningInProgress || g_WarningTimer == null)
				{
					SetupWarningTimer(WarningType_Vote, MapChange_MapEnd);
				}
			}
		}
	}
}

public void CheckMaxRounds(int roundcount)
{
	int maxrounds = 0;
	
	if (g_RoundCounting == RoundCounting_ArmsRace)
	{
		maxrounds = GameRules_GetProp("m_iNumGunGameProgressiveWeaponsCT");
	}
	else if (g_RoundCounting == RoundCounting_MvM)
	{
		maxrounds = GetEntProp(g_ObjectiveEnt, Prop_Send, "m_nMannVsMachineMaxWaveCount");
	}
	else if (g_Cvar_Maxrounds != INVALID_HANDLE)
	{
		maxrounds = GetConVarInt(g_Cvar_Maxrounds);
	}
	else
	{
		return;
	}
	
	if (maxrounds)
	{
		if (roundcount >= (maxrounds - g_Cvar_StartRounds.IntValue))
		{
			if (!g_WarningInProgress || g_WarningTimer == null)
			{
				SetupWarningTimer(WarningType_Vote, MapChange_MapEnd);
			}
		}
	}
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_MapList.Length || g_Cvar_Fraglimit == null || g_HasVoteStarted)
	{
		return;
	}
	
	if (!g_Cvar_Fraglimit.IntValue || !g_Cvar_EndOfMapVote.BoolValue)
	{
		return;
	}

	if (g_MapVoteCompleted)
	{
		return;
	}

	int fragger = GetClientOfUserId(GetEventInt(event, "attacker"));

	if (!fragger)
	{
		return;
	}

	if (GetClientFrags(fragger) >= (g_Cvar_Fraglimit.IntValue - g_Cvar_StartFrags.IntValue))
	{
		if (!g_WarningInProgress || g_WarningTimer == null)
		{
			SetupWarningTimer(WarningType_Vote, MapChange_MapEnd);
		}
	}
}

public Action Command_Mapvote(int client, int args)
{
	ShowActivity2(client, "[MCE] ", "%t", "Initiated Vote Map");

	SetupWarningTimer(WarningType_Vote, MapChange_MapEnd, _, true);

	return Plugin_Handled;	
}

/**
 * Starts a new map vote
 *
 * @param when			When the resulting map change should occur.
 * @param inputlist		Optional list of maps to use for the vote, otherwise an internal list of nominations + random maps will be used.
 */
void InitiateVote(MapChange when, ArrayList inputlist=null)
{
	g_WaitingForVote = true;
	g_WarningInProgress = false;
 
	// Check if a nativevotes vote is in progress first
	// NativeVotes running at the same time as a regular vote can cause hintbox problems,
	// so always check for a standard vote
	if (IsVoteInProgress() || (g_NativeVotes && NativeVotes_IsVoteInProgress()))
	{
		// Can't start a vote, try again in 5 seconds.
		//g_RetryTimer = CreateTimer(5.0, Timer_StartMapVote, _, TIMER_FLAG_NO_MAPCHANGE);
		
		CPrintToChatAll("[MCE] %t", "Cannot Start Vote", FAILURE_TIMER_LENGTH);
		DataPack data;
		g_RetryTimer = CreateDataTimer(1.0, Timer_StartMapVote, data, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
		
		/* Mapchooser Extended */
		data.WriteCell(FAILURE_TIMER_LENGTH);

		if (g_Cvar_RunOff.BoolValue && g_RunoffCount > 0)
		{
			data.WriteString("Revote Warning");
		} else {
			data.WriteString("Vote Warning");
		}
		/* End Mapchooser Extended */

		data.WriteCell(when);
		data.WriteCell(inputlist);
		data.Reset();
		return;
	}
	
	/* If the main map vote has completed (and chosen result) and its currently changing (not a delayed change) we block further attempts */
	if (g_MapVoteCompleted && g_ChangeMapInProgress)
	{
		return;
	}
	
	g_ChangeTime = when;
	
	g_WaitingForVote = false;
		
	g_HasVoteStarted = true;
	
	if (g_NativeVotes)
	{
		g_VoteNative = new NativeVote(Handler_NV_MapVoteMenu, NativeVotesType_NextLevelMult, MenuAction_End | MenuAction_VoteCancel | MenuAction_DisplayItem);
		g_VoteNative.VoteResultCallback = Handler_NV_MapVoteFinished;
	}
	else
	{
		g_VoteMenu = CreateStyledMenu();

		g_AddNoVote = g_Cvar_NoVoteOption.BoolValue;
		
		// Block Vote Slots
		if (g_Cvar_BlockSlots.BoolValue)
		{
			Handle radioStyle = GetMenuStyleHandle(MenuStyle_Radio);
			
			if (GetMenuStyle(g_VoteMenu) == radioStyle)
			{
				g_BlockedSlots = true;
				g_VoteMenu.AddItem(LINE_ONE, "Choose something...", ITEMDRAW_DISABLED);
				g_VoteMenu.AddItem(LINE_TWO, "...will ya?", ITEMDRAW_DISABLED);
				if (!g_AddNoVote)
				{
					g_VoteMenu.AddItem(LINE_SPACER, "", ITEMDRAW_SPACER);
				}
			} else {
				g_BlockedSlots = false;
			}
		}
		
		if (g_AddNoVote)
		{
			g_VoteMenu.NoVoteButton  = true;
		}
		
		g_VoteMenu.SetTitle("Vote Nextmap");
		g_VoteMenu.VoteResultCallback = Handler_MapVoteFinished;
	}

	/* Call OnMapVoteStarted() Forward */
//	Call_StartForward(g_MapVoteStartedForward);
//	Call_Finish();

	/**
	 * TODO: Make a proper decision on when to clear the nominations list.
	 * Currently it clears when used, and stays if an external list is provided.
	 * Is this the right thing to do? External lists will probably come from places
	 * like sm_mapvote from the adminmenu in the future.
	 */
	 
	char map[PLATFORM_MAX_PATH];
	
	/* No input given - User our internal nominations and maplist */
	if (inputlist == null)
	{
		ArrayList randomizeList;
		if (g_Cvar_RandomizeNominations.BoolValue)
		{
			randomizeList = g_NominateList.Clone();
		}
		
		int nominateCount = g_NominateList.Length;
		
		int voteSize = GetVoteSize();
		
		// The if and else if could be combined, but it looks extremely messy
		// This is a hack to lower the vote menu size by 1 when Don't Change or Extend Map should appear
		if (g_NativeVotes)
		{
			if ((when == MapChange_Instant || when == MapChange_RoundEnd) && g_Cvar_DontChange.BoolValue)
			{
				voteSize--;
			}
			else if (g_Cvar_Extend.IntValue && g_Extends < g_Cvar_Extend.IntValue)
			{
				voteSize--;
			}
		}
		
		/* Smaller of the two - It should be impossible for nominations to exceed the size though (cvar changed mid-map?) */
		int nominationsToAdd = nominateCount >= voteSize ? voteSize : nominateCount;
		
		bool extendFirst = g_Cvar_ExtendPosition.BoolValue;
		
		if (extendFirst)
		{
			AddExtendToMenu(g_VoteMenu, when);
		}
		
		for (int i=0; i<nominationsToAdd; i++)
		{
			g_NominateList.GetString(i, map, PLATFORM_MAX_PATH);
			
			if (randomizeList == INVALID_HANDLE)
			{
				AddMapItem(map);
				RemoveStringFromArray(g_NextMapList, map);
			}
			
			/* Notify Nominations that this map is now free */
			Call_StartForward(g_NominationsResetForward);
			Call_PushString(map);
			Call_PushCell(g_NominateOwners.Get(i));
			Call_Finish();
		}
		
		/* Clear out the rest of the nominations array */
		for (int i=nominationsToAdd; i<nominateCount; i++)
		{
			g_NominateList.GetString(i, map, PLATFORM_MAX_PATH);
			/* These maps shouldn't be excluded from the vote as they weren't really nominated at all */
			
			/* Notify Nominations that this map is now free */
			Call_StartForward(g_NominationsResetForward);
			Call_PushString(map);
			Call_PushCell(GetArrayCell(g_NominateOwners, i));
			Call_Finish();
		}
		
		/* There should currently be 'nominationsToAdd' unique maps in the vote */
		
		int i = nominationsToAdd;
		int count = 0;
		
		if (randomizeList != null && i < voteSize)
		{
			for (int j = 0; j < randomizeList.Length; j++)
			{
				randomizeList.GetString(j, map, sizeof(map));
				RemoveStringFromArray(g_NextMapList, map);
			}
		}
		
		int availableMaps = g_NextMapList.Length;

		if (i < voteSize && availableMaps == 0)
		{
			if (i == 0)
			{
				LogError("No maps available for vote.");
				return;
			}
			else
			{
				LogMessage("Not enough maps to fill map list, reducing map count. Adjust mce_include and mce_exclude to avoid this warning.");
				voteSize = i;
			}
		}
		
		while (i < voteSize)
		{
			g_NextMapList.GetString(count, map, PLATFORM_MAX_PATH);
			count++;
			
			if (randomizeList == null)
			{
				/* Insert the map and increment our count */
				AddMapItem(map);
			}
			else
			{
				randomizeList.PushString(map);
			}
			i++;
			
			if (count >= availableMaps)
			{
				//Run out of maps, this will have to do.
				break;
			}
		}
		
		if (randomizeList != null)
		{
			// Fisher-Yates Shuffle
			for (int j = randomizeList.Length - 1; j >= 1; j--)
			{
				int k = GetRandomInt(0, j);
				SwapArrayItems(randomizeList, j, k);
			}
			
			for (int j = 0; j < voteSize; j++)
			{
				randomizeList.GetString(j, map, sizeof(map));
				AddMapItem(map);
			}
			
			delete randomizeList;
		}
		
		/* Wipe out our nominations list - Nominations have already been informed of this */
		g_NominateOwners.Clear();
		g_NominateList.Clear();
		
		if (!extendFirst)
		{
			AddExtendToMenu(g_VoteMenu, when);
		}
	}
	else //We were given a list of maps to start the vote with
	{
		int size = inputlist.Length;
		
		for (int i=0; i<size; i++)
		{
			inputlist.GetString(i, map, PLATFORM_MAX_PATH);
			
			if (IsMapValid(map))
			{
				AddMapItem(map);
			}
			// New in Mapchooser Extended
			else if (StrEqual(map, VOTE_DONTCHANGE))
			{
				if (g_NativeVotes)
				{
					g_VoteNative.AddItem(VOTE_DONTCHANGE, "Don't Change");
				}
				else
				{
					g_VoteMenu.AddItem(VOTE_DONTCHANGE, "Don't Change");
				}
			}
			else if (StrEqual(map, VOTE_EXTEND))
			{
				if (g_NativeVotes)
				{
					g_VoteNative.AddItem(VOTE_EXTEND, "Extend Map");
				}
				else
				{
					g_VoteMenu.AddItem(VOTE_EXTEND, "Extend Map");
				}
			}
		}
		delete inputlist;
	}
	
	int voteDuration = g_Cvar_VoteDuration.IntValue;

	if (g_NativeVotes)
	{
		g_VoteNative.DisplayVoteToAll(voteDuration);
	}
	else
	{
		//SetMenuExitButton(g_VoteMenu, false);
		
		if (GetVoteSize() <= GetMaxPageItems(GetMenuStyle(g_VoteMenu)))
		{
			//This is necessary to get items 9 and 0 as usable voting items
			g_VoteMenu.Pagination = MENU_NO_PAGINATION;
		}
		
		g_VoteMenu.DisplayVoteToAll(voteDuration);
	}

	/* Call OnMapVoteStarted() Forward */
	Call_StartForward(g_MapVoteStartForward); // Deprecated
	Call_Finish();

	Call_StartForward(g_MapVoteStartedForward);
	Call_Finish();

	LogAction(-1, -1, "Voting for next map has started.");
	CPrintToChatAll("[MCE] %t", "Nextmap Voting Started");
}

public void Handler_NV_VoteFinishedGeneric(NativeVote menu,
						   int num_votes, 
						   int num_clients,
						   const int[] client_indexes,
						   const int[] client_votes,
						   int num_items,
						   const int[] item_indexes,
						   const int[] item_votes)
{
	int[][] client_info = new int[num_clients][2];
	int[][] item_info = new int[num_items][2];
	
	NativeVotes_FixResults(num_clients, client_indexes, client_votes, num_items, item_indexes, item_votes, client_info, item_info);
	
	char map[PLATFORM_MAX_PATH];
	char displayName[PLATFORM_MAX_PATH];
	menu.GetItem(item_indexes[0], map, sizeof(map), displayName, sizeof(displayName));
	
	Handler_VoteFinishedGenericShared(map, displayName, num_votes, num_clients, client_info, num_items, item_info, true);
}

public void Handler_VoteFinishedGeneric(Menu menu,
						   int num_votes,
						   int num_clients,
						   const int[][] client_info,
						   int num_items,
						   const int[][] item_info)
{
	char map[PLATFORM_MAX_PATH];
	char displayName[PLATFORM_MAX_PATH];
	menu.GetItem(item_info[0][VOTEINFO_ITEM_INDEX], map, sizeof(map), _, displayName, sizeof(displayName));
	
	Handler_VoteFinishedGenericShared(map, displayName, num_votes, num_clients, client_info, num_items, item_info, false);
}

public void Handler_VoteFinishedGenericShared(const char[] map,
						   const char[] displayName,
						   int num_votes,
						   int num_clients,
						   const int[][] client_info,
						   int num_items,
						   const int[][] item_info,
						   bool isNativeVotes)
{
	Call_StartForward(g_MapVoteEndForward);
	Call_PushString(map);
	Call_Finish();
	
	if (strcmp(map, VOTE_EXTEND, false) == 0)
	{
		g_Extends++;
		
		int time;
		if (GetMapTimeLimit(time))
		{
			if (time > 0)
			{
				ExtendMapTimeLimit(g_Cvar_ExtendTimeStep.IntValue * 60);						
			}
		}
		
		if (g_Cvar_Winlimit)
		{
			int winlimit = g_Cvar_Winlimit.IntValue;
			if (winlimit)
			{
				g_Cvar_Winlimit.IntValue = winlimit + g_Cvar_ExtendRoundStep.IntValue;
			}					
		}
		
		if (g_Cvar_Maxrounds)
		{
			int maxrounds = g_Cvar_Maxrounds.IntValue;
			if (maxrounds)
			{
				g_Cvar_Maxrounds.IntValue = maxrounds + g_Cvar_ExtendRoundStep.IntValue;
			}
		}
		
		if (g_Cvar_Fraglimit)
		{
			int fraglimit = g_Cvar_Fraglimit.IntValue;
			if (fraglimit)
			{
				g_Cvar_Fraglimit.IntValue = fraglimit + g_Cvar_ExtendFragStep.IntValue;
			}
		}

		PrintToChatAll("[MCE] %t", "Current Map Extended", RoundToFloor(float(item_info[0][VOTEINFO_ITEM_VOTES])/float(num_votes)*100), num_votes);
		LogAction(-1, -1, "Voting for next map has finished. The current map has been extended.");
		
		if (isNativeVotes)
		{
			g_VoteNative.DisplayPassEx(NativeVotesPass_Extend);
		}
		
		// We extended, so we'll have to vote again.
		g_HasVoteStarted = false;
		CreateNextVote();
		SetupTimeleftTimer();
		
	}
	else if (strcmp(map, VOTE_DONTCHANGE, false) == 0)
	{
		PrintToChatAll("[MCE] %t", "Current Map Stays", RoundToFloor(float(item_info[0][VOTEINFO_ITEM_VOTES])/float(num_votes)*100), num_votes);
		LogAction(-1, -1, "Voting for next map has finished. 'No Change' was the winner");
		
		if (isNativeVotes)
		{
			g_VoteNative.DisplayPassEx(NativeVotesPass_Extend);
		}
		
		g_HasVoteStarted = false;
		CreateNextVote();
		SetupTimeleftTimer();
	}
	else
	{
		if (g_ChangeTime == MapChange_MapEnd)
		{
			SetNextMap(map);
		}
		else if (g_ChangeTime == MapChange_Instant)
		{
			DataPack data;
			CreateDataTimer(5.0, Timer_ChangeMap, data);
			data.WriteString(map);
			g_ChangeMapInProgress = false;
		}
		else // MapChange_RoundEnd
		{
			SetNextMap(map);
			g_ChangeMapAtRoundEnd = true;
		}
		
		g_HasVoteStarted = false;
		g_MapVoteCompleted = true;
		
		if (isNativeVotes)
		{
			g_VoteNative.DisplayPass(displayName);
		}
		
		PrintToChatAll("[MCE] %t", "Nextmap Voting Finished", displayName, RoundToFloor(float(item_info[0][VOTEINFO_ITEM_VOTES])/float(num_votes)*100), num_votes);
		LogAction(-1, -1, "Voting for next map has finished. Nextmap: %s.", map);
	}	
}

public void Handler_NV_MapVoteFinished(NativeVote menu,
							int num_votes,
							int num_clients,
							const int[] client_indexes,
							const int[] client_votes,
							int num_items,
							const int[] item_indexes,
							const int[] item_votes)
{
	// Implement revote logic - Only run this` block if revotes are enabled and this isn't the last revote
	if (g_Cvar_RunOff.BoolValue && num_items > 1 && g_RunoffCount < g_Cvar_MaxRunOffs.IntValue)
	{
		float winningvotes = float(item_votes[0]);
		float required = num_votes * (g_Cvar_RunOffPercent.FloatValue / 100.0);
	
		if (winningvotes < required || item_votes[0] == item_votes[1])
		{
			/* Insufficient Winning margin - Lets do a runoff */
			
			g_RunoffCount++;
			g_HasVoteStarted = false;
			
			ArrayList mapList = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
			
			char map1[PLATFORM_MAX_PATH];
			menu.GetItem(item_indexes[0], map1, PLATFORM_MAX_PATH);
			
			mapList.PushString(map1);
			
			// We allow more than two maps for a revote if they are tied
			for (int i = 1; i < num_items; i++)
			{
				if (mapList.Length < 2 || item_votes[i] == item_votes[i - 1])
				{
					char map[PLATFORM_MAX_PATH];
					menu.GetItem(item_indexes[i], map, PLATFORM_MAX_PATH);
					mapList.PushString(map);
				}
				else
				{
					break;
				}
			}
			
			menu.DisplayFail(NativeVotesFail_NotEnoughVotes);
			
			if (item_votes[0] == item_votes[1])
			{
				CPrintToChatAll("[MCE] %t", "Tie Vote", mapList.Length);
			}
			else
			{
				CPrintToChatAll("[MCE] %t", "Revote Is Needed", RoundToCeil(required));
			}
			
			SetupWarningTimer(WarningType_Revote, g_ChangeTime, mapList);
			LogMessage("Voting for next map was indecisive, beginning runoff vote");
			
			return;
		}
	}
	
	// No revote needed, continue as normal.
	Handler_NV_VoteFinishedGeneric(menu, num_votes, num_clients, client_indexes, client_votes, num_items, item_indexes, item_votes);
}

public void Handler_MapVoteFinished(Menu menu,
						   int num_votes,
						   int num_clients,
						   const int[][] client_info,
						   int num_items,
						   const int[][] item_info)
{
	// Implement revote logic - Only run this` block if revotes are enabled and this isn't the last revote
	if (g_Cvar_RunOff.BoolValue && num_items > 1 && g_RunoffCount < g_Cvar_MaxRunOffs.IntValue)
	{
		float winningvotes = float(item_info[0][VOTEINFO_ITEM_VOTES]);
		float required = num_votes * (g_Cvar_RunOffPercent.FloatValue / 100.0);
		
		if (winningvotes < required || item_info[0][VOTEINFO_ITEM_VOTES] == item_info[1][VOTEINFO_ITEM_VOTES])
		{
			/* Insufficient Winning margin - Lets do a runoff */
			
			g_RunoffCount++;
			g_HasVoteStarted = false;
			
			ArrayList mapList = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

			char map1[PLATFORM_MAX_PATH];
			menu.GetItem(item_info[0][VOTEINFO_ITEM_INDEX], map1, PLATFORM_MAX_PATH);

			mapList.PushString(map1);

			// We allow more than two maps for a revote if they are tied
			for (int i = 1; i < num_items; i++)
			{
				if (mapList.Length < 2 || item_info[i][VOTEINFO_ITEM_VOTES] == item_info[i - 1][VOTEINFO_ITEM_VOTES])
				{
					char map[PLATFORM_MAX_PATH];
					menu.GetItem(item_info[i][VOTEINFO_ITEM_INDEX], map, PLATFORM_MAX_PATH);
					mapList.PushString(map);
				}
				else
				{
					break;
				}
			}
			
			if (g_NativeVotes)
			{
				NativeVotes_DisplayFail(menu, NativeVotesFail_NotEnoughVotes);
			}
			
			if (item_info[0][VOTEINFO_ITEM_VOTES] == item_info[1][VOTEINFO_ITEM_VOTES])
			{
				CPrintToChatAll("[MCE] %t", "Tie Vote", mapList.Length);
			}
			else
			{
				CPrintToChatAll("[MCE] %t", "Revote Is Needed", RoundToCeil(required));
			}
			
			SetupWarningTimer(WarningType_Revote, g_ChangeTime, mapList);
			LogMessage("Voting for next map was indecisive, beginning runoff vote");
			
			return;
		}
	}
	
	// No revote needed, continue as normal.
	Handler_VoteFinishedGeneric(menu, num_votes, num_clients, client_info, num_items, item_info);
}

// This is shared by NativeVotes now, but NV doesn't support Display or DisplayItem
public int Handler_MapVoteMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete g_VoteMenu;
		}
		
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "%T", "Vote Nextmap", param1);
			Panel panel = view_as<Panel>(param2);
			panel.SetTitle(buffer);
		}
		
		case MenuAction_DisplayItem:
		{
			char map[PLATFORM_MAX_PATH];
			char buffer[255];
			int mark = g_Cvar_MarkCustomMaps.IntValue;
			
			menu.GetItem(param2, map, PLATFORM_MAX_PATH);
			
			if (StrEqual(map, VOTE_EXTEND, false))
			{
				Format(buffer, sizeof(buffer), "%T", "Extend Map", param1);
			}
			else if (StrEqual(map, VOTE_DONTCHANGE, false))
			{
				Format(buffer, sizeof(buffer), "%T", "Dont Change", param1);
			}
			// Mapchooser Extended
			else if (StrEqual(map, LINE_ONE, false))
			{
				Format(buffer, sizeof(buffer),"%T", "Line One", param1);
			}
			else if (StrEqual(map, LINE_TWO, false))
			{
				Format(buffer, sizeof(buffer),"%T", "Line Two", param1);
			}
			// Note that the first part is to discard the spacer line
			else if (!StrEqual(map, LINE_SPACER, false))
			{
				if (mark == 1 && !InternalIsMapOfficial(map))
				{
					Format(buffer, sizeof(buffer), "%T", "Custom Marked", param1, map);
				}
				else if (mark == 2 && !InternalIsMapOfficial(map))
				{
					Format(buffer, sizeof(buffer), "%T", "Custom", param1, map);
				}
			}
			
			if (buffer[0] != '\0')
			{
				return RedrawMenuItem(buffer);
			}
			// End Mapchooser Extended
		}		
	
		case MenuAction_VoteCancel:
		{
			// If we receive 0 votes, pick at random.
			if (param1 == VoteCancel_NoVotes && g_Cvar_NoVoteMode.BoolValue)
			{
				int count = menu.ItemCount;
				
				int item;
				char map[PLATFORM_MAX_PATH];
				
				int startInt = 0;
				if (g_BlockedSlots)
				{
					if (g_AddNoVote)
					{
						startInt = 2;
					}
					else
					{
						startInt = 3;
					}
				}
				
				// Make sure it's not one of the special items.
				do
				{
					item = GetRandomInt(startInt, count - 1);
					menu.GetItem(item, map, sizeof(map));
				}
				while (strcmp(map, VOTE_EXTEND, false) == 0 || strcmp(map, VOTE_DONTCHANGE, false) == 0);
				
				SetNextMap(map);
				g_MapVoteCompleted = true;
			}
			else
			{
				// We were actually cancelled. I guess we do nothing.
			}
			
			g_HasVoteStarted = false;
		}
	}
	
	return 0;
}

public int Handler_NV_MapVoteMenu(NativeVote menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			NativeVotes_Close(menu);
			delete g_VoteNative;
		}
		
		case MenuAction_DisplayItem:
		{
			char map[PLATFORM_MAX_PATH];
			char buffer[255];
			int mark = g_Cvar_MarkCustomMaps.IntValue;
			
			menu.GetItem(param2, map, PLATFORM_MAX_PATH);
			
			if (StrEqual(map, VOTE_EXTEND, false))
			{
				Format(buffer, sizeof(buffer), "%T", "Extend Map", param1);
			}
			else if (StrEqual(map, VOTE_DONTCHANGE, false))
			{
				Format(buffer, sizeof(buffer), "%T", "Dont Change", param1);
			}
			// Mapchooser Extended
			else if (StrEqual(map, LINE_ONE, false))
			{
				Format(buffer, sizeof(buffer),"%T", "Line One", param1);
			}
			else if (StrEqual(map, LINE_TWO, false))
			{
				Format(buffer, sizeof(buffer),"%T", "Line Two", param1);
			}
			// Note that the first part is to discard the spacer line
			else if (!StrEqual(map, LINE_SPACER, false))
			{
				if (mark == 1 && !InternalIsMapOfficial(map))
				{
					Format(buffer, sizeof(buffer), "%T", "Custom Marked", param1, map);
				}
				else if (mark == 2 && !InternalIsMapOfficial(map))
				{
					Format(buffer, sizeof(buffer), "%T", "Custom", param1, map);
				}
			}
			
			if (buffer[0] != '\0')
			{
				NativeVotes_RedrawVoteItem(buffer);
				return view_as<int>(Plugin_Continue);
			}
			// End Mapchooser Extended
		}		
	
		case MenuAction_VoteCancel:
		{
			// If we receive 0 votes, pick at random.
			if (param1 == VoteCancel_NoVotes && g_Cvar_NoVoteMode.BoolValue)
			{
				int count = menu.ItemCount;
				
				int item;
				char map[PLATFORM_MAX_PATH];
				
				do
				{
					item = GetRandomInt(0, count - 1);
					menu.GetItem(item, map, sizeof(map));
				}
				while (strcmp(map, VOTE_EXTEND, false) == 0 || strcmp(map, VOTE_DONTCHANGE, false) == 0);
				
				SetNextMap(map);
				g_MapVoteCompleted = true;
				
				menu.DisplayPass(map);
			}
			else
			{
				// We were actually cancelled, but NativeVotes does stuff on cancel
				NativeVotesFailType reason = NativeVotesFail_Generic;
				if (param1 == VoteCancel_NoVotes)
				{
					reason = NativeVotesFail_NotEnoughVotes;
				}
				
				menu.DisplayFail(reason);
			}
			
			g_HasVoteStarted = false;
		}
	}
	
	return 0;
}

public Action Timer_ChangeMap(Handle hTimer, DataPack dp)
{
	g_ChangeMapInProgress = false;
	
	char map[PLATFORM_MAX_PATH];
	
	if (dp == null)
	{
		if (!GetNextMap(map, sizeof(map)))
		{
			//No passed map and no set nextmap. fail!
			return Plugin_Stop;
		}
	}
	else
	{
		dp.Reset();
		dp.ReadString(map, sizeof(map));
	}
	
	ForceChangeLevel(map, "Map Vote");
	
	return Plugin_Stop;
}

stock bool RemoveStringFromArray(ArrayList array, char[] str)
{
	int index = array.FindString(str);
	if (index != -1)
	{
		array.Erase(index);
		return true;
	}
	
	return false;
}

void CreateNextVote()
{
	g_NextMapList.Clear();
	
	char map[PLATFORM_MAX_PATH];
	// tempMaps is a resolved map list
	ArrayList tempMaps  = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	
	for (int i = 0; i < g_MapList.Length; i++)
	{
		g_MapList.GetString(i, map, sizeof(map));
		if (FindMap(map, map, sizeof(map)) != FindMap_NotFound)
		{
			tempMaps.PushString(map);
		}
	}
	
	if (g_Cvar_ExcludeMaps.IntValue > 0)
	{
		//GetCurrentMap always returns a resolved map
		GetCurrentMap(map, sizeof(map));
		RemoveStringFromArray(tempMaps, map);
	}
	
	if (g_Cvar_ExcludeMaps.IntValue && tempMaps.Length > g_Cvar_ExcludeMaps.IntValue)
	{
		for (int i = 0; i < g_OldMapList.Length; i++)
		{
			g_OldMapList.GetString(i, map, sizeof(map));
			RemoveStringFromArray(tempMaps, map);
		}	
	}

	int voteSize = GetVoteSize();
	int limit = (voteSize < tempMaps.Length ? voteSize : tempMaps.Length);
	for (int i = 0; i < limit; i++)
	{
		int b = GetRandomInt(0, tempMaps.Length - 1);
		tempMaps.GetString(b, map, sizeof(map));
		g_NextMapList.PushString(map);
		tempMaps.Erase(b);
	}
	
	delete tempMaps;
}

bool CanVoteStart()
{
	if (g_WaitingForVote || g_HasVoteStarted)
	{
		return false;	
	}
	
	return true;
}

NominateResult InternalNominateMap(char[] map, bool force, int owner)
{
	if (!IsMapValid(map))
	{
		return Nominate_InvalidMap;
	}
	
	/* Map already in the vote */
	if (g_NominateList.FindString(map) != -1)
	{
		return Nominate_AlreadyInVote;	
	}
	
	int index;

	/* Look to replace an existing nomination by this client - Nominations made with owner = 0 aren't replaced */
	if (owner && ((index = g_NominateOwners.FindValue(owner)) != -1))
	{
		char oldmap[PLATFORM_MAX_PATH];
		g_NominateList.GetString(index, oldmap, PLATFORM_MAX_PATH);
		Call_StartForward(g_NominationsResetForward);
		Call_PushString(oldmap);
		Call_PushCell(owner);
		Call_Finish();
		
		g_NominateList.SetString(index, map);
		return Nominate_Replaced;
	}
	
	/* Too many nominated maps. */
	if (!g_Cvar_NominateAll.BoolValue && g_NominateList.Length >= GetVoteSize() && !force)
	{
		return Nominate_VoteFull;
	}
	
	g_NominateList.PushString(map);
	g_NominateOwners.Push(owner);
	
	while (!g_Cvar_NominateAll.BoolValue && g_NominateList.Length > GetVoteSize())
	{
		char oldmap[PLATFORM_MAX_PATH];
		g_NominateList.GetString(0, oldmap, PLATFORM_MAX_PATH);
		Call_StartForward(g_NominationsResetForward);
		Call_PushString(oldmap);
		Call_PushCell(GetArrayCell(g_NominateOwners, 0));
		Call_Finish();
		
		g_NominateList.Erase(0);
		g_NominateOwners.Erase(0);
	}
	
	return Nominate_Added;
}

/* Add natives to allow nominate and initiate vote to be call */

/* native  bool:NominateMap(const String:map[], bool:force, &NominateError:error); */
public int Native_NominateMap(Handle plugin, int numParams)
{
	int len;
	GetNativeStringLength(1, len);
	
	if (len <= 0)
	{
	  return false;
	}
	
	char[] map = new char[len+1];
	GetNativeString(1, map, len+1);
	
	return view_as<int>(InternalNominateMap(map, GetNativeCell(2), GetNativeCell(3)));
}

bool InternalRemoveNominationByMap(char[] map)
{	
	for (int i = 0; i < g_NominateList.Length; i++)
	{
		char oldmap[PLATFORM_MAX_PATH];
		g_NominateList.GetString(i, oldmap, PLATFORM_MAX_PATH);

		if(strcmp(map, oldmap, false) == 0)
		{
			Call_StartForward(g_NominationsResetForward);
			Call_PushString(oldmap);
			Call_PushCell(GetArrayCell(g_NominateOwners, i));
			Call_Finish();

			g_NominateList.Erase(i);
			g_NominateOwners.Erase(i);

			return true;
		}
	}
	
	return false;
}

/* native  bool:RemoveNominationByMap(const String:map[]); */
public int Native_RemoveNominationByMap(Handle plugin, int numParams)
{
	int len;
	GetNativeStringLength(1, len);
	
	if (len <= 0)
	{
	  return false;
	}
	
	char[] map = new char[len+1];
	GetNativeString(1, map, len+1);
	
	return view_as<int>(InternalRemoveNominationByMap(map));
}

bool InternalRemoveNominationByOwner(int owner)
{	
	int index;

	if (owner && ((index = g_NominateOwners.FindValue(owner)) != -1))
	{
		char oldmap[PLATFORM_MAX_PATH];
		g_NominateList.GetString(index, oldmap, PLATFORM_MAX_PATH);

		Call_StartForward(g_NominationsResetForward);
		Call_PushString(oldmap);
		Call_PushCell(owner);
		Call_Finish();

		g_NominateList.Erase(index);
		g_NominateOwners.Erase(index);

		return true;
	}
	
	return false;
}

/* native  bool:RemoveNominationByOwner(owner); */
public int Native_RemoveNominationByOwner(Handle plugin, int numParams)
{	
	return view_as<int>(InternalRemoveNominationByOwner(GetNativeCell(1)));
}

/* native InitiateMapChooserVote(); */
public int Native_InitiateVote(Handle plugin, int numParams)
{
	MapChange when = view_as<MapChange>(GetNativeCell(1));
	ArrayList inputarray = view_as<ArrayList>(GetNativeCell(2));
	
	LogAction(-1, -1, "Starting map vote because outside request");

	SetupWarningTimer(WarningType_Vote, when, inputarray);
	//InitiateVote(when, inputarray);
}

public int Native_CanVoteStart(Handle plugin, int numParams)
{
	return CanVoteStart();	
}

public int Native_CheckVoteDone(Handle plugin, int numParams)
{
	return g_MapVoteCompleted;
}

public int Native_EndOfMapVoteEnabled(Handle plugin, int numParams)
{
	return g_Cvar_EndOfMapVote.BoolValue;
}

public int Native_GetExcludeMapList(Handle plugin, int numParams)
{
	ArrayList array = view_as<ArrayList>(GetNativeCell(1));
	
	if (array == null)
	{
		return;	
	}
	int size = g_OldMapList.Length;
	char map[PLATFORM_MAX_PATH];
	
	for (int i=0; i<size; i++)
	{
		g_OldMapList.GetString(i, map, PLATFORM_MAX_PATH);
		array.PushString(map);	
	}
	
	return;
}

public int Native_GetNominatedMapList(Handle plugin, int numParams)
{
	ArrayList maparray = view_as<ArrayList>(GetNativeCell(1));
	ArrayList ownerarray = view_as<ArrayList>(GetNativeCell(2));
	
	if (maparray == null)
		return;

	char map[PLATFORM_MAX_PATH];

	for (int i = 0; i < g_NominateList.Length; i++)
	{
		g_NominateList.GetString(i, map, PLATFORM_MAX_PATH);
		maparray.PushString(map);

		// If the optional parameter for an owner list was passed, then we need to fill that out as well
		if(ownerarray != null)
		{
			int index = g_NominateOwners.Get(i);
			ownerarray.Push(index);
		}
	}

	return;
}

// Functions new to Mapchooser Extended

/*
SetupWarningTimer(MapChange:when=MapChange_MapEnd, Handle:mapList=INVALID_HANDLE)
{
	if (!IsMapEndVoteAllowed())
	{
		return;
	}

	Call_StartForward(g_MapVoteWarningStartForward);
	Call_Finish();

	new Handle:data;
	g_WarningTimer = CreateDataTimer(1.0, Timer_StartMapVote, data, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
	WritePackCell(data, GetConVarInt(g_Cvar_WarningTime));
	WritePackString(data, "Vote Warning");
	WritePackCell(data, _:when);
	WritePackCell(data, _:mapList);
}

SetupRunoffTimer(MapChange:when, Handle:mapList)
{
	if (!IsMapEndVoteAllowed())
	{
		return;
	}

	Call_StartForward(g_MapVoteRunoffStartForward);
	Call_Finish();

	new Handle:data;
	g_WarningTimer = CreateDataTimer(1.0, Timer_StartMapVote, data, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
	WritePackCell(data, GetConVarInt(g_Cvar_RunOffWarningTime));
	WritePackString(data, "Revote Warning");
	WritePackCell(data, _:when);
	WritePackCell(data, _:mapList);
}
*/

stock void SetupWarningTimer(WarningType type, MapChange when=MapChange_MapEnd, ArrayList mapList=null, bool force=false)
{
	if (!g_MapList.Length || g_ChangeMapInProgress || g_HasVoteStarted || (!force && ((when == MapChange_MapEnd && !g_Cvar_EndOfMapVote.BoolValue) || g_MapVoteCompleted)))
	{
		return;
	}
	
	bool interrupted = false;
	if (g_WarningInProgress && g_WarningTimer != null)
	{
		interrupted = true;
		delete g_WarningTimer;
	}
	
	g_WarningInProgress = true;
	
	Handle forwardVote;
	ConVar cvarTime;
	char translationKey[64];
	
	switch (type)
	{
		case WarningType_Vote:
		{
			forwardVote = g_MapVoteWarningStartForward;
			cvarTime = g_Cvar_WarningTime;
			strcopy(translationKey, sizeof(translationKey), "Vote Warning");
		}
		
		case WarningType_Revote:
		{
			forwardVote = g_MapVoteRunoffStartForward;
			cvarTime = g_Cvar_RunOffWarningTime;
			strcopy(translationKey, sizeof(translationKey), "Revote Warning");
		}
	}

	if (cvarTime.IntValue == 0)
	{
		InitiateVote(when, mapList);
	}
	else
	{
		if (!interrupted)
		{
			Call_StartForward(forwardVote);
			Call_Finish();
		}
		
		DataPack data;
		g_WarningTimer = CreateDataTimer(1.0, Timer_StartMapVote, data, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
		data.WriteCell(cvarTime.IntValue);
		data.WriteString(translationKey);
		data.WriteCell(view_as<int>(when));
		data.WriteCell(view_as<int>(mapList));
		data.Reset();
	}
}

stock void InitializeOfficialMapList()
{
	// If this fails, we want it to have an empty adt_array
	if (ReadMapList(g_OfficialList,
		g_mapOfficialFileSerial,
		"official",
		MAPLIST_FLAG_CLEARARRAY|MAPLIST_FLAG_NO_DEFAULT)
		!= INVALID_HANDLE)
	{
		LogMessage("Loaded map list for %s.", g_GameModName);
	}
	// Check if the map list was ever loaded
	else if (g_mapOfficialFileSerial == -1)
	{
		LogMessage("No official map list found for %s. Consider submitting one!", g_GameModName);
	}
}

stock bool IsMapEndVoteAllowed()
{
	if (!g_Cvar_EndOfMapVote.BoolValue || g_MapVoteCompleted || g_HasVoteStarted)
	{
		return false;
	}
	else
	{
		return true;
	}
}

public int Native_IsMapOfficial(Handle plugin, int numParams)
{
	int len;
	GetNativeStringLength(1, len);
	
	if (len <= 0)
	{
	  return false;
	}
	
	char[] map = new char[len+1];
	GetNativeString(1, map, len+1);
	
	return InternalIsMapOfficial(map);
}

bool InternalIsMapOfficial(const char[] mapname)
{
	int officialMapIndex = g_OfficialList.FindString(mapname);
	return (officialMapIndex > -1);
}

public int Native_IsWarningTimer(Handle plugin, int numParams)
{
	return g_WarningInProgress;
}

public int Native_CanNominate(Handle plugin, int numParams)
{
	if (g_HasVoteStarted)
	{
		return view_as<int>(CanNominate_No_VoteInProgress);
	}
	
	if (g_MapVoteCompleted)
	{
		return view_as<int>(CanNominate_No_VoteComplete);
	}
	
	if (!g_Cvar_NominateAll.BoolValue && g_NominateList.Length >= GetVoteSize())
	{
		return view_as<int>(CanNominate_No_VoteFull);
	}
	
	return view_as<int>(CanNominate_Yes);
}


stock void AddMapItem(const char[] map)
{
	char displayName[PLATFORM_MAX_PATH];
	GetMapDisplayName(map, displayName, sizeof(displayName));
	
	if (g_NativeVotes)
	{
		g_VoteNative.AddItem(map, displayName);
	}
	else
	{
		g_VoteMenu.AddItem(map, displayName);
	}
}

stock void AddExtendToMenu(Menu menu, MapChange when)
{
	/* Do we add any special items? */
	// Moved for Mapchooser Extended

	if ((when == MapChange_Instant || when == MapChange_RoundEnd) && g_Cvar_DontChange.BoolValue)
	{
		if (g_NativeVotes)
		{
			menu.AddItem(VOTE_DONTCHANGE, "Don't Change");
		}
	}
	else if (g_Cvar_Extend.BoolValue && g_Extends < g_Cvar_Extend.IntValue)
	{
		if (g_NativeVotes)
		{
			menu.AddItem(VOTE_EXTEND, "Extend Map");
		}
	}
}

stock void AddExtendToMenu_NV(NativeVote menu, MapChange when)
{
	/* Do we add any special items? */
	// Moved for Mapchooser Extended

	if ((when == MapChange_Instant || when == MapChange_RoundEnd) && g_Cvar_DontChange.BoolValue)
	{
		if (g_NativeVotes)
		{
			menu.AddItem(VOTE_DONTCHANGE, "Don't Change");
		}
	}
	else if (g_Cvar_Extend.BoolValue && g_Extends < g_Cvar_Extend.IntValue)
	{
		if (g_NativeVotes)
		{
			menu.AddItem(VOTE_EXTEND, "Extend Map");
		}
	}
}

int GetVoteSize()
{
	int voteSize = g_Cvar_IncludeMaps.IntValue;
	
	// New in 1.9.5 to let us bump up the included maps count
	if (g_NativeVotes)
	{
		int max = NativeVotes_GetMaxItems();
		
		if (max < voteSize)
		{
			voteSize = max;
		}
	}
	
	return voteSize;
}

Menu CreateStyledMenu()
{
	Menu menu;
	Handle menuStyle = GetMenuStyleHandle(view_as<MenuStyle>(g_Cvar_MenuStyle.IntValue));
	
	if (menuStyle != null)
	{
		menu = CreateMenuEx(menuStyle, Handler_MapVoteMenu, MenuAction_End | MenuAction_Display | MenuAction_DisplayItem | MenuAction_VoteCancel);
	}
	else
	{
		// You chose... poorly
		menu = new Menu(Handler_MapVoteMenu, MenuAction_End | MenuAction_Display | MenuAction_DisplayItem | MenuAction_VoteCancel);
	}
	
	return menu;
}
