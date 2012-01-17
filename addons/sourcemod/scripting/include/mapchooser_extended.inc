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
