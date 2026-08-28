/// persist & duck/ducktap fix


class GoldSrcConsole extends FPSConsoleExt
	config(GoldSrc);

var config bool bEnabled;
var config bool bPatchGameDefaults;   // job 1
var config bool bWheelDuckFix;        // job 2
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
			GP.DuckTapHoldEnd();
	}

	// The console eats keys while it is open, so a hold that survives into typing
	// would never see its release. End it as soon as typing starts.
	if (bTyping)
	{
		GP = GoldSrcPlayer(PC);
		if (GP != None && GP.DuckTapHoldKey != 0)
			GP.DuckTapHoldEnd();
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

	if (bVerbose)
		Log("GoldSrcConsole: patched game type defaults -> GoldSrcPlayer / GoldSrcHUD", 'GoldSrc');
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
	bVerbose=false

	bRequiresTick=True
}
