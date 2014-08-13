/**
 * vim: set ts=4 :
 * =============================================================================
 * Map Workshop Functions
 * A few stocks for dealing with workshop map paths and such
 *
 * Map Workshop Functions (C)2014 Powerlord (Ross Bemrose). All rights reserved.
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

#if defined _map_workshop_functions_included_
  #endinput
#endif
#define _map_workshop_functions_included_

/**
 * Copy a substring from source to destination
 * 
 * @param source		String to copy from
 * @param start		position to start at, 0 numbered
 * @param len			number of characters to copy
 * @param destination	String to copy to
 * @param maxlen		Length of destination string
 * 
 * @return			number of characters copied
 */
static stock SubString(const String:source[], start, len, String:destination[], maxlen)
{
	if (start < 0)
	{
		ThrowError("start must be positive.");
	}
	
	if (maxlen < 1)
	{
		ThrowError("Destination size must be positive: %d", maxlen);
	}
	
	// maxlen - 1 to account for null terminator
	new realLength = len < maxlen - 1 ? len : maxlen - 1;
	
	return strcopy(destination, realLength, source[start]);
}

/**
 * Can't be called directly, see MapEqual and FindMapStringInMapArray below
 * Remove the path from the map name
 * This was added to remove workshop paths.
 * 
 * @param map			Map name
 * @param destination	String to copy map name to
 * @param maxlen		Length of destination string
 * 
 * @return		true if path was removed, false if map and destination are the same
 */
stock static bool:RemoveMapPath(const String:map[], String:destination[], maxlen)
{
	if (strlen(map) < 1)
	{
		ThrowError("Bad map name: %s", map);
	}
	
	// UNIX paths
	new pos = FindCharInString(map, '/', true);
	if (pos == -1)
	{
		// Windows paths
		pos = FindCharInString(map, '\\', true);
		if (pos == -1)
		{
			destination[0] = '\0';
			//strcopy(destination, maxlen, map);
			return false;
		}
	}

	// strlen is last + 1
	new len = strlen(map) - 1 - pos;
	
	SubString(map, pos, len, destination, maxlen);
	return true;
}

/**
 * Check if two maps are the same map.
 * Takes workshop paths into account.
 * 
 * @param map		First map
 * @param map2	Second map
 * 
 * @return		true if they're the same map, false if not.
 */
stock bool:MapEqual(const String:map[], const String:map2[])
{
	new bPathless;
	new bPathless2;
	new String:pathlessMap[PLATFORM_MAX_PATH];
	new String:pathlessMap2[PLATFORM_MAX_PATH];
	
	bPathless = RemoveMapPath(map, pathlessMap, sizeof(pathlessMap));
	bPathless2 = RemoveMapPath(map2, pathlessMap2, sizeof(pathlessMap2));
	
	if (StrEqual(map, map2) ||
		(bPathless && !bPathless2 && StrEqual(pathlessMap, map2)) ||
		(!bPathless && bPathless2 && StrEqual(map, pathlessMap2)) ||
		(bPathless && bPathless2 && StrEqual(pathlessMap, pathlessMap2)))
	{
		return true;
	}
	
	return false;
	
}

/**
 * Returns the index for the first occurance of the provided map. If the map cannot be located, -1 will be returned.
 * Takes workshop maps into account.
 * 
 * @param array		Array Handle.
 * @param map			Map to search for
 *
 * @return 			Array index, or -1 on failure
 */
stock FindMapStringInMapArray(Handle:array, const String:map[])
{
	new arrayLen = GetArraySize(array);
	for (new i = 0; i < arrayLen; i++)
	{
		new String:arrayMap[PLATFORM_MAX_PATH];
		GetArrayString(array, i, arrayMap, sizeof(arrayMap));
		if (MapEqual(arrayMap, map))
		{
			return i;
		}
	}
	
	return -1;
}
