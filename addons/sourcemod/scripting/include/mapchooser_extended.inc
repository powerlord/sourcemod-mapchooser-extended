#if defined _mapchooser_extended_included_
  #endinput
#endif
#define _mapchooser_extended_included_

/**
 * Called whenever warning timer starts
 * 
 */
forward OnMapVoteWarningStart();

/**
 * Called whenever runoff warning timer starts
 */
forward OnMapVoteRunnoffWarningStart();

/**
 * Called whenever the timer ticks
 */
forward OnMapVoteWarningTick(time);

/**
 * Called whenever vote starts
 * 
 * @deprecated Will be removed in MapChooser 1.8.  Use OnMapVoteStarted instead.
 */
forward OnMapVoteStart();

/**
 * Called whenever vote ends
 */
forward OnMapVoteEnd();

/**
 * Is a map on the current game's official list?
 * This should be treated as informative only.
 * 
 * @param map 	Name of map to check
 * @return 		true if it's on the list of official maps for this game
 */
native bool:IsMapOfficial(const String:map[]);


public SharedPlugin:__pl_mapchooser_extended = 
{
	name = "mapchooser",
	file = "mapchooser_extended.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};
