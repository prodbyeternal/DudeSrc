// consider this what bunnymod xt does to half life.
class GoldSrcInjector extends Info
	config(GoldSrc);

var config bool bEnabled;


var config bool bVerbose;

var bool bApplied;


function PreBeginPlay()
{
	Super.PreBeginPlay();
	Apply();
}

function PostBeginPlay()
{
	Super.PostBeginPlay();
	Apply();

	// Keep checking briefly.
	
	if (!bApplied)
		SetTimer(0.1, true);
}

function Timer()
{
	Apply();

	if (bApplied)
		SetTimer(0.0, false);
}

// point the gameinfo to us.
function Apply()
{
	if (!bEnabled || Level == None || Level.Game == None)
		return;

	// SP ONLY, leave multi outta this. the gameinfo is a global so changing it in multi would break everyone else.

	if (Level.NetMode != NM_Standalone)
		return;

	if (Level.Game.PlayerControllerClass != class'GoldSrcPlayer')
	{
		Level.Game.PlayerControllerClass = class'GoldSrcPlayer';
		Level.Game.PlayerControllerClassName = "GoldSrcMovement.GoldSrcPlayer";

		if (bVerbose)
			Log("GoldSrcInjector: PlayerControllerClass -> GoldSrcPlayer on"
				@ Level.Game.Class, 'GoldSrc');
	}

	if (Level.Game.HUDType != "GoldSrcMovement.GoldSrcHUD")
	{
		Level.Game.HUDType = "GoldSrcMovement.GoldSrcHUD";

		if (bVerbose)
			Log("GoldSrcInjector: HUDType -> GoldSrcHUD", 'GoldSrc');
	}

	bApplied = true;
}

defaultproperties
{
	bEnabled=true
	bVerbose=true

	bHidden=true
	bAlwaysRelevant=false
	RemoteRole=ROLE_None
	bOnlyDirtyReplication=true
}
