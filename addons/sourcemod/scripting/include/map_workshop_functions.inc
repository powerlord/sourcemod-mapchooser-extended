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
 * @param start		position to start at, 0 numbered. Negative means to start that many characters from the end.
 * @param len			number of characters to copy.  Negative means to not copy that many characters from the end.
 * @param destination	String to copy to
 * @param maxlen		Length of destination string.  Must be 1 or greater.
 * 
 * @return			True if success, false if number of characters copied would be negative.
 * NOTE:				There is no mechanism to get the remaining characters of a string.
 * 					Instead, use strcopy with source[start] for that.
 */
stock bool:SubString(const String:source[], start, len, String:destination[], maxlen)
{
	if (maxlen < 1)
	{
		ThrowError("Destination size must be positive, was %d", maxlen);
	}
	
	// optimization
	if (len == 0)
	{
		strcopy(destination, maxlen, "");
		return true;
	}
	
	if (start < 0)
	{
		// strlen doesn't count the null terminator, so don't -1 on it.
		start = strlen(source) + start;
		if (start < 0)
			start = 0;
	}
	
	if (len < 0)
	{
		len = strlen(source) + len - start;
		// If length is still less than 0, that'd be an error.
		if (len < 0)
			return false;
	}
	
	// Check to make sure destination is large enough to hold the len, or truncate it.
	// len + 1 because second arg to strcopy counts 1 for the null terminator
	new realLength = len + 1 < maxlen ? len + 1 : maxlen;
	
	strcopy(destination, realLength, source[start]);
	return true;
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
stock bool:RemoveMapPath(const String:map[], String:destination[], maxlen)
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
	
	SubString(map, pos + 1, len, destination, maxlen);
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
