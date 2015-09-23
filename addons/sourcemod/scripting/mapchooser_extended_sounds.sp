/**
 * vim: set ts=4 :
 * =============================================================================
 * MapChooser Extended Sounds
 * Sound support for Mapchooser Extended
 * Inspired by QuakeSounds 2.7
 *
 * MapChooser Extended Sounds (C)2011-2014 Powerlord (Ross Bemrose)
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
#include <sdktools>
#include <emitsoundany>

#pragma semicolon 1
#pragma newdecls required

#define VERSION "1.11.0 beta 5"

#define CONFIG_FILE "configs/mapchooser_extended/sounds.cfg"
#define CONFIG_DIRECTORY "configs/mapchooser_extended/sounds"

#define SET_NAME_MAX_LENGTH 64

// 0-60, even though we don't ever call 0
// Counter-intuitive note: This array has 61 elements, not 60
#define COUNTER_MAX_SIZE 60
// The number of digits in the previous number
#define COUNTER_MAX_SIZE_DIGITS 2

#define NUM_TYPES 5

// CVar Handles
ConVar g_Cvar_EnableSounds;
ConVar g_Cvar_EnableCounterSounds;
ConVar g_Cvar_SoundSet;
ConVar g_Cvar_DownloadAllSounds;

// Data Handles
ArrayList g_TypeNames; // Maps SoundEvent enumeration values to KeyValue section names
ArrayList g_SetNames;
StringMap g_SoundFiles;
StringMap g_CurrentSoundSet; // Lazy "pointer" to the current sound set.  Updated on cvar change or map change.

//Global variables
bool g_DownloadAllSounds;

enum SoundEvent
{
	SoundEvent_Counter = 0,
	SoundEvent_VoteStart = 1,
	SoundEvent_VoteEnd = 2,
	SoundEvent_VoteWarning = 3,
	SoundEvent_RunoffWarning = 4,
}

enum SoundType
{
	SoundType_None,
	SoundType_Sound,
	SoundType_Builtin,
	SoundType_Event
}

enum SoundStore
{
	String:SoundStore_Value[PLATFORM_MAX_PATH],
	SoundType:SoundStore_Type,
	Float:SoundStore_Volume
}

public Plugin myinfo = 
{
	name = "Mapchooser Extended Sounds",
	author = "Powerlord",
	description = "Sound support for Mapchooser Extended",
	version = VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=156974"
}

// Map enum values to their named values
// This is used for searching later.
void PopulateTypeNamesArray()
{
	if (g_TypeNames == null)
	{
		g_TypeNames = new ArrayList(ByteCountToCells(SET_NAME_MAX_LENGTH), NUM_TYPES);
		g_TypeNames.SetString(view_as<int>(SoundEvent_Counter), "counter");
		g_TypeNames.SetString(view_as<int>(SoundEvent_VoteStart), "vote start");
		g_TypeNames.SetString(view_as<int>(SoundEvent_VoteEnd), "vote end");
		g_TypeNames.SetString(view_as<int>(SoundEvent_VoteWarning), "vote warning");
		g_TypeNames.SetString(view_as<int>(SoundEvent_RunoffWarning), "runoff warning");
	}
}

public void OnPluginStart()
{
	g_Cvar_EnableSounds = CreateConVar("mce_sounds_enablesounds", "1", "Enable this plugin.  Sounds will still be downloaded (if applicable) even if the plugin is disabled this way.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_Cvar_EnableCounterSounds = CreateConVar("mce_sounds_enablewarningcountersounds", "1", "Enable sounds to be played during warning counter.  If this is disabled, map vote warning, start, and stop sounds still play.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_Cvar_SoundSet = CreateConVar("mce_sounds_soundset", "tf", "Sound set to use, optimized for TF by default.  Sound sets are defined in addons/sourcemod/configs/mapchooser_extended_sounds.cfg.  Takes effect immediately if sm_mapvote_downloadallsounds is 1, otherwise at map change.", FCVAR_NONE);
	g_Cvar_DownloadAllSounds = CreateConVar("mce_sounds_downloadallsounds", "0", "Force players to download all sound sets, so sets can be dynamically changed during the map. Defaults to off. Takes effect at map change.", FCVAR_NONE, true, 0.0, true, 1.0);
	CreateConVar("mce_sounds_version", VERSION, "Mapchooser Extended Sounds Version", FCVAR_DONTRECORD|FCVAR_SPONLY|FCVAR_REPLICATED);

	AutoExecConfig(true, "mapchooser_extended_sounds");

	RegAdminCmd("mce_sounds_reload", Command_Reload, ADMFLAG_CONVARS, "Reload Mapchooser Sound configuration file.");
	RegAdminCmd("sm_mapvote_reload_sounds", Command_Reload, ADMFLAG_CONVARS, "Deprecated: use mce_sounds_reload");

	RegAdminCmd("mce_sounds_list_soundsets", Command_List_Soundsets, ADMFLAG_CONVARS, "List available Mapchooser Extended sound sets.");
	RegAdminCmd("sm_mapvote_list_soundsets", Command_List_Soundsets, ADMFLAG_CONVARS, "Deprecated: use mce_sounds_list_soundsets");

	PopulateTypeNamesArray();
	// LoadSounds needs to be  executed even if the plugin is "disabled" via the sm_mapvote_enablesounds cvar.

	g_SetNames = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	g_SoundFiles = new StringMap();
	LoadSounds();
	HookConVarChange(g_Cvar_SoundSet, SoundSetChanged);
}

// Not sure this is required, but there were some weird crashes when this plugin was unloaded.  This is an attempt to fix that.
/*
public OnPluginEnd()
{
	CloseSoundArrayHandles();
}
*/

/*
* Moved to OnConfigsExecuted due to cvar requirements
public OnMapStart()
{
	BuildDownloadsTableAll();
}
*/

public void OnConfigsExecuted()
{
	g_DownloadAllSounds = g_Cvar_DownloadAllSounds.BoolValue;

	SetSoundSetFromCVar();
	
	if (g_DownloadAllSounds)
	{
		BuildDownloadsTableAll();
	}
	else
	{
		BuildDownloadsTable(g_CurrentSoundSet);
	}
}

void SetSoundSetFromCVar()
{
	char soundSet[SET_NAME_MAX_LENGTH];
	
	// Store which sound set is in use
	g_Cvar_SoundSet.GetString(soundSet, sizeof(soundSet));
	
	// Unknown sound set from config file, reset to default
	if (g_SetNames.FindString(soundSet) == -1 && !StrEqual(soundSet, "tf", true))
	{
		ResetConVar(g_Cvar_SoundSet);
		g_Cvar_SoundSet.GetString(soundSet, sizeof(soundSet));
	}
	
	SetCurrentSoundSet(soundSet);
}

public void SoundSetChanged(ConVar cvar, char[] oldValue, char[] newValue)
{
	if (g_SetNames.FindString(newValue) == -1)
	{
		LogError("New sound set not found: %s", newValue);
		cvar.SetString(oldValue);
	}
	else if (g_DownloadAllSounds)
	{
		SetCurrentSoundSet(newValue);
	}
}

public void OnMapVoteStarted()
{
	PlaySound(SoundEvent_VoteStart);
}

public void OnMapVoteEnd(const char[] map)
{
	PlaySound(SoundEvent_VoteEnd);
}

public void OnMapVoteWarningStart()
{
	PlaySound(SoundEvent_VoteWarning);
}

public void OnMapVoteRunnoffWarningStart()
{
	PlaySound(SoundEvent_RunoffWarning);
}

public void OnMapVoteWarningTick(int time)
{
	if (g_Cvar_EnableSounds.BoolValue && g_Cvar_EnableCounterSounds.BoolValue) {
		char currentType[SET_NAME_MAX_LENGTH];
		StringMap counterTrie;
		
		if (g_CurrentSoundSet != null)
		{
			if (g_TypeNames.GetString(view_as<int>(SoundEvent_Counter), currentType, sizeof(currentType)) > 0 && g_CurrentSoundSet.GetValue(currentType, counterTrie))
			{
				char key[5];
				IntToString(time, key, sizeof(key));
				
				int soundData[SoundStore];
				if (!GetTrieArray(counterTrie, key, soundData[0], sizeof(soundData)))
				{
					return;
				}
				
				if (soundData[SoundStore_Type] == SoundType_Event)
				{
					BroadcastAudio(soundData[SoundStore_Value]);
				}
				else
				{
					EmitSoundToAllAny(soundData[SoundStore_Value], .volume=soundData[SoundStore_Volume]);
				}
			}
		}
	}
}

public Action Command_Reload(int client, int args)
{
	LoadSounds();
	SetSoundSetFromCVar();
	ReplyToCommand(client, "[MCES] Reloaded sound configuration.");
	return Plugin_Handled;
}

public Action Command_List_Soundsets(int client, int args)
{
	int setCount = g_SetNames.Length;
	ReplyToCommand(client, "[SM] The following %d sound sets are installed:", setCount);
	for (int i = 0; i < setCount; i++)
	{
		char setName[SET_NAME_MAX_LENGTH];
		g_SetNames.GetString(i, setName, sizeof(setName));
		ReplyToCommand(client, "[SM] %s", setName);
	}
}

void PlaySound(SoundEvent event)
{
	if (g_Cvar_EnableSounds.BoolValue)
	{
		if (g_CurrentSoundSet != null)
		{
			char currentType[SET_NAME_MAX_LENGTH];
			
			if (g_TypeNames.GetString(view_as<int>(event), currentType, sizeof(currentType)) > 0)
			{
				int soundData[SoundStore];
				g_CurrentSoundSet.GetArray(currentType, soundData[0], sizeof(soundData));
				if (soundData[SoundStore_Type] == SoundType_Event)
				{
					BroadcastAudio(soundData[SoundStore_Value]);
				}
				else
				{
					EmitSoundToAllAny(soundData[SoundStore_Value], .volume=soundData[SoundStore_Volume]);
				}
			}
		}
	}

}

void SetCurrentSoundSet(char[] soundSet)
{
	// Save a reference to the Trie for the current sound set, for use in the forwards below.
	// Also do error checking to make sure the set exists.
	if (!g_SoundFiles.GetValue(soundSet, g_CurrentSoundSet))
	{
		SetFailState("Could not load sound set");
	}
	
}

// Load the list of sounds sounds from the configuration file
// This should be done on plugin load.
// This looks really complicated, but it really isn't.
void LoadSounds()
{
	CloseSoundArrayHandles();
	
	char directoryPath[PLATFORM_MAX_PATH];
	char modName[SET_NAME_MAX_LENGTH];
	
	GetGameFolderName(modName, sizeof(modName));
	
	BuildPath(Path_SM, directoryPath, sizeof(directoryPath), CONFIG_DIRECTORY);

	DirectoryListing directory = OpenDirectory(directoryPath, true);
	if (directory != null)
	{
		char dirEntry[PLATFORM_MAX_PATH];
		FileType type;
		while (directory.GetNext(dirEntry, sizeof(dirEntry), type))
		{
			KeyValues soundsKV = CreateKeyValues("MapchooserSoundsList");
			char filePath[PLATFORM_MAX_PATH];
			
			Format(filePath, sizeof(filePath), "%s/%s", directoryPath, dirEntry);
			
			if (type != FileType_Directory)
			{
				soundsKV.ImportFromFile(filePath);
				
				if (soundsKV.GotoFirstSubKey())
				{
					// Iterate through the sets
					do
					{
						StringMap setTrie = CreateTrie();
						char currentSet[SET_NAME_MAX_LENGTH];
						bool builtinSet = false;
						
						soundsKV.GetSectionName(currentSet, sizeof(currentSet));
						
						if (g_SetNames.FindString(currentSet) == -1)
						{
							// Add to the list of sound sets
							g_SetNames.PushString(currentSet);
						}
						else
						{
							SetFailState("Duplicate sound set: %s", currentSet);
						}
						
						if (StrEqual(currentSet, modName, false))
						{
							builtinSet = true;
						}
						
						if (soundsKV.GotoFirstSubKey()) {
							// Iterate through each sound in the set
							do
							{
								char currentType[SET_NAME_MAX_LENGTH];
								soundsKV.GetSectionName(currentType, sizeof(currentType));
								// Type to enum mapping
								SoundEvent typeKey = view_as<SoundEvent>(g_TypeNames.FindString(currentType));
								
								switch(typeKey)
								{
									case SoundEvent_Counter:
									{
										// Counter is special, as it has multiple values
										StringMap counterTrie = CreateTrie();
										
										if (soundsKV.GotoFirstSubKey())
										{
											do
											{
												// Get the current key
												char time[COUNTER_MAX_SIZE_DIGITS + 1];
												
												soundsKV.GetSectionName(time, sizeof(time));
												
												int soundData[SoundStore];
												
												// new key = StringToInt(time);
												
												soundData[SoundStore_Type] =  RetrieveSound(soundsKV, builtinSet, soundData[SoundStore_Value], PLATFORM_MAX_PATH, soundData[SoundStore_Volume]);
												if (soundData[SoundStore_Type] == SoundType_None)
												{
													continue;
												}
												
												// This seems wrong, but this is documented on the forums here: https://forums.alliedmods.net/showthread.php?t=151942
												counterTrie.SetArray(time, soundData[0], sizeof(soundData));
												
												//SetArrayString(counterArray, key, soundFile);
											} while (soundsKV.GotoNextKey());
											soundsKV.GoBack();
										}
										
										setTrie.SetValue(currentType, view_as<int>(counterTrie));
										
									}
									
									// Set the sounds directly for other types
									default:
									{
										int soundData[SoundStore];
										
										soundData[SoundStore_Type] = RetrieveSound(soundsKV, builtinSet, soundData[SoundStore_Value], PLATFORM_MAX_PATH, soundData[SoundStore_Volume]);
										
										if (soundData[SoundStore_Type] == SoundType_None)
										{
											continue;
										}
										
										setTrie.SetArray(currentType, soundData[0], sizeof(soundData));
									}
								}
							} while (soundsKV.GotoNextKey());
							soundsKV.GoBack();
						}
						g_SoundFiles.SetValue(currentSet, setTrie);
					} while (soundsKV.GotoNextKey());
				}
			}
			delete soundsKV;
		}
		delete directory;
	}
	
	if (g_SetNames.Length == 0)
	{
		SetFailState("Could not locate any sound sets.");
	}
}

// Internal LoadSounds function to get sound and type 
SoundType RetrieveSound(KeyValues soundsKV, bool isBuiltin, char[] soundFile, int soundFileSize, float &volume=SNDVOL_NORMAL)
{
	volume = soundsKV.GetFloat("volume", SNDVOL_NORMAL);
	
	if (isBuiltin)
	{
		// event is considered before builtin, as it has related game data and should always be used in preference to builtin
		soundsKV.GetString("event", soundFile, soundFileSize);
		
		if (!StrEqual(soundFile, ""))
		{
			return SoundType_Event;
		}
		
		soundsKV.GetString("builtin", soundFile, soundFileSize);
		if (!StrEqual(soundFile, ""))
		{
			return SoundType_Builtin;
		}
	}
	
	soundsKV.GetString("sound", soundFile, soundFileSize);

	if (!StrEqual(soundFile, ""))
	{
		return SoundType_Sound;
	}
	
	// Whoops, didn't find this sound
	return SoundType_None;
}

// Preload all sounds in a set
void BuildDownloadsTable(StringMap currentSoundSet)
{
	if (currentSoundSet != null)
	{
		for (int i = 0; i < g_TypeNames.Length; i++)
		{
			char currentType[SET_NAME_MAX_LENGTH];
			g_TypeNames.GetString(i, currentType, sizeof(currentType));

			switch(view_as<SoundEvent>(i))
			{
				case SoundEvent_Counter:
				{
					StringMap counterTrie;
					if (currentSoundSet.GetValue(currentType, counterTrie))
					{
						// Skip value 0
						for (int j = 1; j <= COUNTER_MAX_SIZE; ++j)
						{
							char key[5];
							IntToString(j, key, sizeof(key));
							
							int soundData[SoundStore];
							counterTrie.GetArray(key, soundData[0], sizeof(soundData));
							if (soundData[SoundStore_Type] != SoundType_Event)
							{
								CacheSound(soundData);
							}
						}
					}
				}
				
				default:
				{
					int soundData[SoundStore];
					currentSoundSet.GetArray(currentType, soundData[0], sizeof(soundData));
					
					if (soundData[SoundStore_Type] != SoundType_Event)
					{
						CacheSound(soundData);
					}
				}
			}
		}
	}
}

// Load each set and build its download table
stock void BuildDownloadsTableAll()
{
	for (int i = 0; i < g_SetNames.Length; i++)
	{
		char currentSet[SET_NAME_MAX_LENGTH];
		StringMap currentSoundSet;
		g_SetNames.GetString(i, currentSet, sizeof(currentSet));
		
		if (g_SoundFiles.GetValue(currentSet, currentSoundSet))
		{
			BuildDownloadsTable(currentSoundSet);
		}
	}
}

// Found myself repeating this code, so I pulled it into a separate function
void CacheSound(int soundData[SoundStore])
{
	if (soundData[SoundStore_Type] == SoundType_Builtin)
	{
		PrecacheSoundAny(soundData[SoundStore_Value]);
	}
	else if (soundData[SoundStore_Type] == SoundType_Sound)
	{
		if (PrecacheSoundAny(soundData[SoundStore_Value]))
		{
			char downloadLocation[PLATFORM_MAX_PATH];
			Format(downloadLocation, sizeof(downloadLocation), "sound/%s", soundData[SoundStore_Value]);
			AddFileToDownloadsTable(downloadLocation);
		} else {
			LogMessage("Failed to load sound: %s", soundData[SoundStore_Value]);
		}
	}
}

// Close all the handles that are children and grandchildren of the g_SoundFiles trie.
stock void CloseSoundArrayHandles()
{
	// Close all open handles in the sound set
	for (int i = 0; i < g_SetNames.Length; i++)
	{
		char currentSet[SET_NAME_MAX_LENGTH];
		StringMap trieHandle;
		ArrayList arrayHandle;
		
		g_SetNames.GetString(i, currentSet, sizeof(currentSet));
		g_SoundFiles.GetValue(currentSet, trieHandle);
		// "counter" is an adt_trie, close that too
		trieHandle.GetValue("counter", arrayHandle);
		delete arrayHandle;
		delete trieHandle;
	}
	g_SoundFiles.Clear();
	g_SetNames.Clear();
	
	delete g_CurrentSoundSet;
}

bool BroadcastAudio(const char[] sound)
{
	Event broadcastEvent = CreateEvent("teamplay_broadcast_audio");
	if (broadcastEvent == null)
	{
		#if defined DEBUG
		LogError("Could not create teamplay_broadcast_event. This may be because there are no players connected.");
		#endif
		return false;
	}
	broadcastEvent.SetInt("team", -1);
	broadcastEvent.SetString("sound", sound);
	broadcastEvent.Fire();
	
	return true;
}