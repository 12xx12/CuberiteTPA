g_PluginInfo =
{
	Name = "TPA Plugin",
	Date = "2021-04-24",
	Description = "This Plugin emulates the TPA plugin functionality for Cuberite. You can send teleport requests to other players and they can accept or deny it.",

	-- The following members will be documented in greater detail later:
	AdditionalInfo = {},
	Commands =
	{
		["/tpa"] =
		{
			HelpString = "Sends a teleport request",
			Permission = "tpa.request",
			Handler = SendRequest,
			ParameterCombinations =
			{
				{
					Params = "x",
					Help = "Internal use. Accepts/Denies a specific teleport request.",
				},
				{
					Params = "-p",
					Help = "Accepts the the last request sent from this player.",
				}
			},
		},
		["/tpaccept"] =
		{
			HelpString = "Accepts a pending teleport request",
			Permission = "tpa.accept",
			Handler = AcceptRequest,
			Params = "-p",
		},
		["/tpdeny"] =
		{
			HelpString = "Denys any teleport requests",
			Permission = "tpa.tpa.deny",
			Handler = DenyRequest,
			Params = "-p",
		}
	},
	ConsoleCommands = {},
	Permissions = 
	{
		["tpa.request"] =
		{
			Description = "",
			RecommendedGroups = "players",
		},
		["tpa.accept"] =
		{
			Description = "",
			RecommendedGroups = "players",
		},
		["tpa.hide"] =
		{
			Description = "Any player with this permission can't be targeted by a teleport request.",
			RecommendedGroups = "admin",
		},
		["tpa.override"] =
		{
			Description = "Any player with this permission doesn't need a confirmation by their destination.",
			RecommendedGroups = "admin",
		},
		["tpa.overrideCoolDown"] =
		{
			Description = "Any player with this permission ignores the teleport cooldown.",
			RecommendedGroups = "admin",
		}
	},
	Categories = {},
}
