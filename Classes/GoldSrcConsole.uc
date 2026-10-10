/// persist & duck/ducktap fix


class GoldSrcConsole extends FPSConsoleExt
	config(GoldSrc);

var config bool bEnabled;
var config bool bPatchGameDefaults;   // job 1
var config bool bWheelDuckFix;        // job 2
var config bool bInstantLauncher;     // hand out GoldSrcRocketLauncher, not LauncherWeapon
var config bool bVerbose;


var int  DuckKeys[4];
var int  NumDuckKeys;
var bool bDuckKeysValid;

var LevelInfo LastLevel;

// init
event Initialized()
{
	Super.Initialized();

	// Runs before the first map is loaded, so the very first Login already
	// sees the patched defaults.
	PatchGameDefaults();
}

// init on every level change
function Tick(float DeltaTime)
{
	local PlayerController PC;
	local GoldSrcPlayer    GP;

	Super.Tick(DeltaTime);

	if (!bEnabled)
		return;

	PC = GetPC();
	if (PC == None)
		return;

	if (PC.Level != LastLevel)
	{
		LastLevel      = PC.Level;
		bDuckKeysValid = false;
		PatchGameDefaults();

		// A key held across a level change never delivers its release to the new
		// level's controller, so end the hold rather than leave it stuck on.
		GP = GoldSrcPlayer(PC);
		if (GP != None)
		{
			GP.DuckTapHoldEnd();
			GP.EdgebugHoldEnd();
		}
	}

	// The console eats keys while it is open, so a hold that survives into typing
	// would never see its release. End it as soon as typing starts.
	if (bTyping)
	{
		GP = GoldSrcPlayer(PC);
		if (GP != None)
		{
			if (GP.DuckTapHoldKey != 0)
				GP.DuckTapHoldEnd();
			if (GP.EdgebugHoldKey != 0)
				GP.EdgebugHoldEnd();
		}
	}

	if (!bDuckKeysValid)
		CacheBindKeys(PC);
}

final function PlayerController GetPC()
{
	if (ViewportOwner == None)
		return None;

	return ViewportOwner.Actor;
}

// patch class defaults
final function PatchGameDefaults()
{
	if (!bEnabled || !bPatchGameDefaults)
		return;

	// retail game DefaultPlayer
	class'AWPGameInfo'.default.PlayerControllerClassName = "GoldSrcMovement.GoldSrcPlayer";
	class'AWPGameInfo'.default.HUDType                   = "GoldSrcMovement.GoldSrcHUD";

	// what the shell launches for single-player
	class'GameSinglePlayer'.default.PlayerControllerClassName = "GoldSrcMovement.GoldSrcPlayer";
	class'GameSinglePlayer'.default.HUDType                   = "GoldSrcMovement.GoldSrcHUD";

	// apocalypse weekend final, which is what the shell launches for single-player if the
	class'AWGameSPFinal'.default.PlayerControllerClassName = "GoldSrcMovement.GoldSrcPlayer";
	class'AWGameSPFinal'.default.HUDType                   = "GoldSrcMovement.GoldSrcHUD";

	// Paradise Lost ships its own game info class, whose default controller is
	// PLGame.PLDudePlayer. It is not part of the SDK this mod compiles against,
	// so it can only be named as a string here -- and if the package is absent
	// (plain Postal 2) the load simply returns None and we move on. CreditsGameInfo
	// is a separate subclass with its own defaults, so it has to be named too.
	PatchGameInfoByName("PLGame.PLGameInfo");
	PatchGameInfoByName("PLGame.TWPGameInfo");
	PatchGameInfoByName("PLGame.CreditsGameInfo");

	// Every launcher pickup in every map -- and Paradise Lost's weapon vending
	// machine, which stocks the same pickup -- hands out this class, so the world
	// launchers become the fast Quake one without touching a single map. Launchers
	// a loadout or a cheat grants outright are caught by the sweep in GoldSrcPlayer.
	if (bInstantLauncher)
		class'LauncherPickup'.default.InventoryType = class'GoldSrcRocketLauncher';

	if (bVerbose)
		Log("GoldSrcConsole: patched game type defaults -> GoldSrcPlayer / GoldSrcHUD", 'GoldSrc');
}

// Point one game info class -- named by string, so it need not exist in the SDK --
// at the mod's controller and HUD. These are class defaults, and the engine reads
// them (GameInfo.uc:754) at Login, once per level, before any level script runs,
// which is exactly why patching them here reaches a game info we cannot subclass.
final function PatchGameInfoByName(string ClassName)
{
	local class<GameInfo> GIC;

	GIC = class<GameInfo>(DynamicLoadObject(ClassName, class'Class', true));
	if (GIC == None)
		return;

	GIC.default.PlayerControllerClassName = "GoldSrcMovement.GoldSrcPlayer";
	GIC.default.HUDType                   = "GoldSrcMovement.GoldSrcHUD";

	if (bVerbose)
		Log("GoldSrcConsole: patched" @ ClassName @ "-> GoldSrcPlayer / GoldSrcHUD", 'GoldSrc');
}

// ask input system which keys are bound to duck and cache them for later use
final function CacheBindKeys(PlayerController PC)
{
	local int i, k;

	NumDuckKeys = 0;

	for (i = 0; i < 4; i++)
	{
		k = int(PC.ConsoleCommand("BINDING2KEYVAL \"Duck\"" @ i));

		if (k > 0)
		{
			DuckKeys[NumDuckKeys] = k;
			NumDuckKeys++;
		}
	}

	bDuckKeysValid = true;

	if (bVerbose)
		Log("GoldSrcConsole: cached" @ NumDuckKeys @ "duck key(s)", 'GoldSrc');
}

// raw key hook for wheel duck and ducktap hold
//
// The ducktap half deliberately does NOT look the binding up by name. It used to,
// with BINDING2KEYVAL "ducktap", and that is a string compare against whatever is
// literally written in the ini: `Mouse4=DuckTap` does not match "ducktap", so the
// cache came back empty, no key was ever watched, no release was ever reported,
// and holding the bind produced exactly one tap -- the reported bug.
//
// Instead the key identifies itself. We publish the key whose press we are
// processing and GoldSrcPlayer.DuckTap claims it; if the engine happens to run
// bindings BEFORE its interactions, the exec has already left a timestamp and we
// adopt the key for it here instead. Either order works, so no assumption about
// the dispatch order is baked in -- and any key, any spelling, any compound bind
// containing ducktap, with no ini reading at all.

function bool KeyEvent(EInputKey Key, EInputAction Action, FLOAT Delta)
{
	local GoldSrcPlayer GP;
	local int i;

	if (bEnabled)
	{
		GP = GoldSrcPlayer(GetPC());

		if (GP != None && GP.bGoldSrcMovement)
		{
			if (bWheelDuckFix && Action == IST_Press && !bTyping)
			{
				for (i = 0; i < NumDuckKeys; i++)
				{
					if (int(Key) == DuckKeys[i])
					{
						// guarantee that the duck pulse is sent even if the key is already down,
						// which is what a wheel does, and even if the key is released
						GP.GoldSrcDuckPulse();
						break;
					}
				}
			}

			// End of the hold. Not gated on bTyping: a release has to be honoured
			// wherever it arrives, or opening the console mid-hold strands it on.
			if (Action == IST_Release && GP.DuckTapHoldKey != 0
				&& GP.DuckTapHoldKey == int(Key))
			{
				GP.DuckTapHoldEnd();
			}

			// Same arrangement for the edgebug hold.
			if (Action == IST_Release && GP.EdgebugHoldKey != 0
				&& GP.EdgebugHoldKey == int(Key))
			{
				GP.EdgebugHoldEnd();
			}

			if (Action == IST_Press && !bTyping)
			{
				GP.DuckTapKeyInFlight     = int(Key);
				GP.DuckTapKeyInFlightTime = GP.Level.TimeSeconds;

				// The exec already ran this frame and found no key published, so it
				// was dispatched ahead of us: this press is its key.
				if (GP.DuckTapHoldKey == 0
					&& GP.DuckTapExecTime == GP.Level.TimeSeconds)
				{
					GP.DuckTapHoldKey = int(Key);
					GP.bDuckTapHeld   = true;
				}

				GP.EdgebugKeyInFlight     = int(Key);
				GP.EdgebugKeyInFlightTime = GP.Level.TimeSeconds;

				// The exec already ran this frame and found no key published, so it
				// was dispatched ahead of us: this press is its key.
				if (GP.EdgebugHoldKey == 0
					&& GP.EdgebugExecTime == GP.Level.TimeSeconds)
				{
					GP.EdgebugHoldKey = int(Key);
					GP.bEdgebugHeld   = true;
				}
			}
		}
	}

	return Super.KeyEvent(Key, Action, Delta);
}

defaultproperties
{
	bEnabled=true
	bPatchGameDefaults=true
	bWheelDuckFix=true
	bInstantLauncher=true
	bVerbose=false

	bRequiresTick=True
}
