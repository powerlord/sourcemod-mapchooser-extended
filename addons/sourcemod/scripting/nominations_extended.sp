/**
 * vim: set ts=4 :
 * =============================================================================
 * Nominations Extended
 * Allows players to nominate maps for Mapchooser
 *
 * Nominations Extended (C)2012-2014 Powerlord (Ross Bemrose)
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

#include <sourcemod>
#include <mapchooser>
#include "include/mapchooser_extended"
#include <colors>

#undef REQUIRE_PLUGIN
#include <nativevotes>

#pragma semicolon 1
#pragma newdecls required

#define MCE_VERSION "1.11.0 beta 5"

public Plugin myinfo =
{
	name = "Map Nominations Extended",
	author = "Powerlord and AlliedModders LLC",
	description = "Provides Map Nominations",
	version = MCE_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=156974"
};

ConVar g_Cvar_ExcludeOld;
ConVar g_Cvar_ExcludeCurrent;

ConVar g_Cvar_NVNextLevel;
ConVar g_Cvar_NVChangeLevel;

ArrayList g_MapList;
Menu g_MapMenu;
int g_mapFileSerial = -1;

#define MAPSTATUS_ENABLED (1<<0)
#define MAPSTATUS_DISABLED (1<<1)
#define MAPSTATUS_EXCLUDE_CURRENT (1<<2)
#define MAPSTATUS_EXCLUDE_PREVIOUS (1<<3)
#define MAPSTATUS_EXCLUDE_NOMINATED (1<<4)

StringMap g_mapTrie;

// Nominations Extended Convars
ConVar g_Cvar_MarkCustomMaps;

bool g_NativeVotes = false;
bool g_RegisteredMenusChangeLevel = false;
bool g_RegisteredMenusNextLevel = false;

#define NV "nativevotes"

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("nominations.phrases");
	LoadTranslations("basetriggers.phrases"); // for Next Map phrase
	LoadTranslations("mapchooser_extended.phrases");
	
	g_MapList = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	
	g_Cvar_ExcludeOld = CreateConVar("ne_excludeold", "1", "Specifies if the current map should be excluded from the Nominations list", 0, true, 0.00, true, 1.0);
	g_Cvar_ExcludeCurrent = CreateConVar("ne_excludecurrent", "1", "Specifies if the MapChooser excluded maps should also be excluded from Nominations", 0, true, 0.00, true, 1.0);
	
	RegConsoleCmd("sm_nominate", Command_Nominate);
	
	RegAdminCmd("sm_nominate_addmap", Command_Addmap, ADMFLAG_CHANGEMAP, "sm_nominate_addmap <mapname> - Forces a map to be on the next mapvote.");
	
	// Nominations Extended cvars
	CreateConVar("ne_version", MCE_VERSION, "Nominations Extended Version", FCVAR_SPONLY|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	g_Cvar_NVChangeLevel = CreateConVar("ne_nativevotes_changelevel", "1", "TF2: Add ChangeLevel to NativeVotes 1.0 vote menu.", _, true, 0.0, true, 1.0);
	g_Cvar_NVNextLevel = CreateConVar("ne_nativevotes_nextlevel", "1", "TF2: Add NextLevel to NativeVotes 1.0 vote menu.", _, true, 0.0, true, 1.0);
	
	HookConVarChange(g_Cvar_NVChangeLevel, Cvar_ChangeLevel);
	HookConVarChange(g_Cvar_NVNextLevel, Cvar_NextLevel);
	
	AutoExecConfig(true, "nominations_extended");
	
	g_mapTrie = new StringMap();
}

public void OnAllPluginsLoaded()
{
	if (FindPluginByFile("nominations.smx") != null)
	{
		SetFailState("This plugin replaces nominations.  You cannot run both at once.");
	}
	
	// This is an MCE cvar... this plugin requires MCE to be loaded.  Granted, this plugin SHOULD have an MCE dependency.
	g_Cvar_MarkCustomMaps = FindConVar("mce_markcustommaps");

	g_NativeVotes = LibraryExists(NV) && NativeVotes_IsVoteTypeSupported(NativeVotesType_NextLevelMult) && GetFeatureStatus(FeatureType_Native, "NativeVotes_IsVoteCommandRegistered") == FeatureStatus_Available;
	RegisterVoteHandler();
}

public void OnPluginEnd()
{
	if (g_NativeVotes)
	{
		if (g_RegisteredMenusNextLevel)
		{
			NativeVotes_UnregisterVoteCommand(NativeVotesOverride_NextLevel, Menu_Nominate);
		}
		
		if (g_RegisteredMenusChangeLevel)
		{
			NativeVotes_UnregisterVoteCommand(NativeVotesOverride_ChgLevel, Menu_Nominate);
		}
	}
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, NV) && NativeVotes_IsVoteTypeSupported(NativeVotesType_NextLevelMult) && GetFeatureStatus(FeatureType_Native, "NativeVotes_IsVoteCommandRegistered") == FeatureStatus_Available)
	{
		g_NativeVotes = true;
		RegisterVoteHandler();
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, NV))
	{
		g_NativeVotes = false;
		g_RegisteredMenusNextLevel = false;
		g_RegisteredMenusChangeLevel = false;
	}
}

public void Cvar_ChangeLevel(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (g_Cvar_NVChangeLevel.BoolValue)
	{
		if (!g_RegisteredMenusChangeLevel)
		{
			NativeVotes_RegisterVoteCommand(NativeVotesOverride_ChgLevel, Menu_Nominate);
			g_RegisteredMenusChangeLevel = true;
		}
	}
	else
	{
		if (g_RegisteredMenusChangeLevel)
		{
			NativeVotes_UnregisterVoteCommand(NativeVotesOverride_ChgLevel, Menu_Nominate);		
			g_RegisteredMenusChangeLevel = false;
		}
	}
}

public void Cvar_NextLevel(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (g_Cvar_NVNextLevel.BoolValue)
	{
		if (!g_RegisteredMenusNextLevel)
		{
			NativeVotes_RegisterVoteCommand(NativeVotesOverride_NextLevel, Menu_Nominate);
			g_RegisteredMenusNextLevel = true;
		}
	}
	else
	{
		if (g_RegisteredMenusNextLevel)
		{
			NativeVotes_UnregisterVoteCommand(NativeVotesOverride_NextLevel, Menu_Nominate);		
			g_RegisteredMenusNextLevel = false;
		}
	}
}

void RegisterVoteHandler()
{
	if (!g_NativeVotes)
		return;
		
	if (g_Cvar_NVNextLevel.BoolValue)
	{
		NativeVotes_RegisterVoteCommand(NativeVotesOverride_NextLevel, Menu_Nominate);
		g_RegisteredMenusNextLevel = true;
	}
	
	if (g_Cvar_NVChangeLevel.BoolValue)
	{
		NativeVotes_RegisterVoteCommand(NativeVotesOverride_ChgLevel, Menu_Nominate);
		g_RegisteredMenusChangeLevel = true;
	}
}

public void OnConfigsExecuted()
{
	if (ReadMapList(g_MapList,
					g_mapFileSerial,
					"nominations",
					MAPLIST_FLAG_CLEARARRAY|MAPLIST_FLAG_MAPSFOLDER)
		== INVALID_HANDLE)
	{
		if (g_mapFileSerial == -1)
		{
			SetFailState("Unable to create a valid map list.");
		}
	}
	
	BuildMapMenu();
}

public void OnNominationRemoved(const char[] map, int owner)
{
	int status;
	
	char resolvedMap[PLATFORM_MAX_PATH];
	FindMap(map, resolvedMap, sizeof(resolvedMap));
	
	/* Is the map in our list? */
	if (!g_mapTrie.GetValue(resolvedMap, status))
	{
		return;
	}
	
	/* Was the map disabled due to being nominated */
	if ((status & MAPSTATUS_EXCLUDE_NOMINATED) != MAPSTATUS_EXCLUDE_NOMINATED)
	{
		return;
	}
	
	g_mapTrie.SetValue(resolvedMap, MAPSTATUS_ENABLED);
}

public Action Command_Addmap(int client, int args)
{
	if (args < 1)
	{
		CReplyToCommand(client, "[NE] Usage: sm_nominate_addmap <mapname>");
		return Plugin_Handled;
	}
	
	char mapname[PLATFORM_MAX_PATH];
	char resolvedMap[PLATFORM_MAX_PATH];
	GetCmdArg(1, mapname, sizeof(mapname));

	if (FindMap(mapname, resolvedMap, sizeof(resolvedMap)) == FindMap_NotFound)
	{
		// We couldn't resolve the map entry to a filename, so...
		CReplyToCommand(client, "%t", "Map was not found", mapname);
		return Plugin_Handled;
	}
	
	char displayName[PLATFORM_MAX_PATH];
	GetMapDisplayName(resolvedMap, displayName, sizeof(displayName));
	
	int status;
	if (!g_mapTrie.GetValue(resolvedMap, status))
	{
		CReplyToCommand(client, "%t", "Map was not found", displayName);
		return Plugin_Handled;
	}
	
	NominateResult result = NominateMap(resolvedMap, true, 0);
	
	if (result > Nominate_Replaced)
	{
		/* We assume already in vote is the casue because the maplist does a Map Validity check and we forced, so it can't be full */
		CReplyToCommand(client, "%t", "Map Already In Vote", displayName);
		
		return Plugin_Handled;
	}
	
	g_mapTrie.SetValue(resolvedMap, MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_NOMINATED);
	
	CReplyToCommand(client, "%t", "Map Inserted", displayName);
	LogAction(client, -1, "\"%L\" inserted map \"%s\".", client, mapname);

	return Plugin_Handled;		
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	if (!client)
	{
		return;
	}
	
	if (strcmp(sArgs, "nominate", false) == 0)
	{
		ReplySource old = SetCmdReplySource(SM_REPLY_TO_CHAT);
		
		AttemptNominate(client);
		
		SetCmdReplySource(old);
	}
}

public Action Menu_Nominate(int client, NativeVotesOverride overrideType, const char[] voteArgument)
{
	if (!client || NativeVotes_IsVoteInProgress() || !IsNominateAllowed(client, true))
	{
		return Plugin_Handled;
	}
	
	if (strlen(voteArgument) == 0)
	{
		NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_SpecifyMap);
		return Plugin_Handled;
	}
	
	ReplySource old = SetCmdReplySource(SM_REPLY_TO_CHAT);
	
	Action myReturn = Internal_NominateCommand(client, voteArgument, true);
	
	SetCmdReplySource(old);
	
	return myReturn;
}

public Action Command_Nominate(int client, int args)
{
	if (!client || !IsNominateAllowed(client))
	{
		return Plugin_Handled;
	}
	
	if (args == 0)
	{
		AttemptNominate(client);
		return Plugin_Handled;
	}
	
	char mapname[PLATFORM_MAX_PATH];
	GetCmdArg(1, mapname, sizeof(mapname));
	
	return Internal_NominateCommand(client, mapname, false);
}

Action Internal_NominateCommand(int client, const char[] mapname, bool isVoteMenu)
{
	char resolvedMap[PLATFORM_MAX_PATH];
	if (FindMap(mapname, resolvedMap, sizeof(resolvedMap)) == FindMap_NotFound)
	{
		// We couldn't resolve the map entry to a filename, so...
		CReplyToCommand(client, "%t", "Map was not found", mapname);
		return Plugin_Handled;		
	}
	
	char displayName[PLATFORM_MAX_PATH];
	GetMapDisplayName(resolvedMap, displayName, sizeof(displayName));
	
	int status;
	if (!g_mapTrie.GetValue(resolvedMap, status))
	{
		if (isVoteMenu && g_NativeVotes)
		{
			NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_MapNotValid);
		}
		CReplyToCommand(client, "[NE] %t", "Map was not found", displayName);
		return Plugin_Handled;		
	}
	
	if ((status & MAPSTATUS_DISABLED) == MAPSTATUS_DISABLED)
	{
		if ((status & MAPSTATUS_EXCLUDE_CURRENT) == MAPSTATUS_EXCLUDE_CURRENT)
		{
			if (isVoteMenu && g_NativeVotes)
			{
				NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_MapNotValid);
			}
			CReplyToCommand(client, "[NE] %t", "Can't Nominate Current Map");
		}
		
		if ((status & MAPSTATUS_EXCLUDE_PREVIOUS) == MAPSTATUS_EXCLUDE_PREVIOUS)
		{
			if (isVoteMenu && g_NativeVotes)
			{
				NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_MapNotValid);
			}
			CReplyToCommand(client, "[NE] %t", "Map in Exclude List");
		}
		
		if ((status & MAPSTATUS_EXCLUDE_NOMINATED) == MAPSTATUS_EXCLUDE_NOMINATED)
		{
			if (isVoteMenu && g_NativeVotes)
			{
				NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_MapNotValid);
			}
			CReplyToCommand(client, "[NE] %t", "Map Already Nominated");
		}
		
		return Plugin_Handled;
	}
	
	NominateResult result = NominateMap(resolvedMap, false, client);
	
	if (result > Nominate_Replaced)
	{
		if (result == Nominate_AlreadyInVote)
		{
			if (isVoteMenu && g_NativeVotes)
			{
				NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_MapNotValid);
			}
			CReplyToCommand(client, "[NE] %t", "Map Already In Vote", displayName);
		}
		else
		{
			if (isVoteMenu && g_NativeVotes)
			{
				NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_MapNotValid);
			}
			CReplyToCommand(client, "[NE] %t", "Map Already Nominated");
		}
		
		return Plugin_Handled;	
	}
	
	/* Map was nominated! - Disable the menu item and update the trie */
	
	g_mapTrie.SetValue(resolvedMap, MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_NOMINATED);
	
	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	CPrintToChatAll("[NE] %t", "Map Nominated", name, displayName);
	
	return Plugin_Handled;
}

void AttemptNominate(int client)
{
	g_MapMenu.SetTitle("%T", "Nominate Title", client);
	g_MapMenu.Display(client, MENU_TIME_FOREVER);
}

void BuildMapMenu()
{
	if (g_MapMenu != null)
	{
		delete g_MapMenu;
	}
	
	g_mapTrie.Clear();
	
	g_MapMenu = new Menu(Handler_MapSelectMenu, MENU_ACTIONS_DEFAULT|MenuAction_DrawItem|MenuAction_DisplayItem);

	char map[PLATFORM_MAX_PATH];
	
	ArrayList excludeMaps;
	char currentMap[PLATFORM_MAX_PATH];
	
	if (g_Cvar_ExcludeOld.BoolValue)
	{	
		excludeMaps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
		GetExcludeMapList(excludeMaps);
	}
	
	if (g_Cvar_ExcludeCurrent.BoolValue)
	{
		GetCurrentMap(currentMap, sizeof(currentMap));
	}
	
	for (int i = 0; i < g_MapList.Length; i++)
	{
		int status = MAPSTATUS_ENABLED;
		
		g_MapList.GetString(i, map, sizeof(map));
		
		FindMap(map, map, sizeof(map));
		
		char displayName[PLATFORM_MAX_PATH];
		GetMapDisplayName(map, displayName, sizeof(displayName));
		
		if (g_Cvar_ExcludeCurrent.BoolValue)
		{
			if (StrEqual(map, currentMap))
			{
				status = MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_CURRENT;
			}
		}
		
		/* Dont bother with this check if the current map check passed */
		if (g_Cvar_ExcludeOld.BoolValue && status == MAPSTATUS_ENABLED)
		{
			if (excludeMaps.FindString(map))
			{
				status = MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_PREVIOUS;
			}
		}
		
		// Don't modify how it appears in the list.
		g_MapMenu.AddItem(map, displayName);
		g_mapTrie.SetValue(map, status);
	}
	
	g_MapMenu.ExitButton = true;

	if (excludeMaps != null)
	{
		delete excludeMaps;
	}
}

public int Handler_MapSelectMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char map[PLATFORM_MAX_PATH], name[MAX_NAME_LENGTH], displayName[PLATFORM_MAX_PATH];
			menu.GetItem(param2, map, sizeof(map), _, displayName, sizeof(displayName));
			
			GetClientName(param1, name, MAX_NAME_LENGTH);
	
			NominateResult result = NominateMap(map, false, param1);
			
			/* Don't need to check for InvalidMap because the menu did that already */
			if (result == Nominate_AlreadyInVote)
			{
				CPrintToChat(param1, "[NE] %t", "Map Already Nominated");
				return 0;
			}
			else if (result == Nominate_VoteFull)
			{
				CPrintToChat(param1, "[NE] %t", "Max Nominations");
				return 0;
			}
			
			g_mapTrie.SetValue(map, MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_NOMINATED);

			if (result == Nominate_Replaced)
			{
				CPrintToChatAll("[NE] %t", "Map Nomination Changed", name, displayName);
				return 0;	
			}
			
			CPrintToChatAll("[NE] %t", "Map Nominated", name, displayName);
			LogMessage("%s nominated %s", name, map);
		}
		
		case MenuAction_DrawItem:
		{
			char map[PLATFORM_MAX_PATH];
			menu.GetItem(param2, map, sizeof(map));
			
			int status;
			
			if (!g_mapTrie.GetValue(map, status))
			{
				LogError("Menu selection of item not in trie. Major logic problem somewhere.");
				return ITEMDRAW_DEFAULT;
			}
			
			if ((status & MAPSTATUS_DISABLED) == MAPSTATUS_DISABLED)
			{
				return ITEMDRAW_DISABLED;	
			}
			
			return ITEMDRAW_DEFAULT;
			
		}
		
		case MenuAction_DisplayItem:
		{
			char map[PLATFORM_MAX_PATH];
			menu.GetItem(param2, map, sizeof(map));
			
			int mark = g_Cvar_MarkCustomMaps.IntValue;
			bool official;

			int status;
			
			if (!g_mapTrie.GetValue(map, status))
			{
				LogError("Menu selection of item not in trie. Major logic problem somewhere.");
				return 0;
			}
			
			char buffer[100];
			char display[150];
			
			if (mark)
			{
				official = IsMapOfficial(map);
			}
			
			if (mark && !official)
			{
				switch (mark)
				{
					case 1:
					{
						Format(buffer, sizeof(buffer), "%T", "Custom Marked", param1, map);
					}
					
					case 2:
					{
						Format(buffer, sizeof(buffer), "%T", "Custom", param1, map);
					}
				}
			}
			else
			{
				strcopy(buffer, sizeof(buffer), map);
			}
			
			if ((status & MAPSTATUS_DISABLED) == MAPSTATUS_DISABLED)
			{
				if ((status & MAPSTATUS_EXCLUDE_CURRENT) == MAPSTATUS_EXCLUDE_CURRENT)
				{
					Format(display, sizeof(display), "%s (%T)", buffer, "Current Map", param1);
					return RedrawMenuItem(display);
				}
				
				if ((status & MAPSTATUS_EXCLUDE_PREVIOUS) == MAPSTATUS_EXCLUDE_PREVIOUS)
				{
					Format(display, sizeof(display), "%s (%T)", buffer, "Recently Played", param1);
					return RedrawMenuItem(display);
				}
				
				if ((status & MAPSTATUS_EXCLUDE_NOMINATED) == MAPSTATUS_EXCLUDE_NOMINATED)
				{
					Format(display, sizeof(display), "%s (%T)", buffer, "Nominated", param1);
					return RedrawMenuItem(display);
				}
			}
			
			if (mark && !official)
				return RedrawMenuItem(buffer);
			
			return 0;
		}
	}
	
	return 0;
}

stock bool IsNominateAllowed(int client, bool isVoteMenu=false)
{
	CanNominateResult result = CanNominate();
	
	switch(result)
	{
		case CanNominate_No_VoteInProgress:
		{
			CReplyToCommand(client, "[NE] %t", "Nextmap Voting Started");
			return false;
		}
		
		case CanNominate_No_VoteComplete:
		{
			char map[PLATFORM_MAX_PATH];
			GetNextMap(map, sizeof(map));
			if (isVoteMenu && g_NativeVotes)
			{
				NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_LevelSet);
			}
			CReplyToCommand(client, "[NE] %t", "Next Map", map);
			return false;
		}
		
		case CanNominate_No_VoteFull:
		{
			if (isVoteMenu && g_NativeVotes)
			{
				NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_Generic);				
			}
			CReplyToCommand(client, "[NE] %t", "Max Nominations");
			return false;
		}
	}
	
	return true;
}