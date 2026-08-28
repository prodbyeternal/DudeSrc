// GoldSrcPlayer
// Extends AWDudePlayer, which is the controller the retail game actually spawns.
// Working from the most derived class means every stock system -- weapons,
// inventory, interactions, missions, achievements -- is inherited untouched.
class GoldSrcPlayer extends AWDudePlayer
	config(GoldSrc);

var GoldSrcMovement Move;           // The movement simulation

var config bool bGoldSrcMovement;   // Master enable
var config bool bShowSpeedometer;
var config bool bShowMoveDebug;
var config bool bShowNetGraph;       // net_graph 1  (GoldSrcHUD.DrawNetGraph)
var config bool bShowPos;            // cl_showpos 1 (GoldSrcHUD.DrawShowPos)

// Source viewmodel bob. The port itself lives on the HUD, because that is where
// the weapon gets drawn (GoldSrcHUD.PostRender); these are just the dials, kept
// here with the rest of the player's config so they land in the same ini block.
var config bool  bViewModelBob;      // cl_viewmodelbob 1
var config float ViewModelBobScale;  // cl_bobscale -- 1.0 is Valve's amount

// Source viewmodel lag ("sway"): the gun trailing behind the camera when you turn
// and drooping when you look up or down. Same arrangement as the bob -- the port
// is GoldSrcHUD.CalcViewModelLag, these are the dials.
var config bool  bViewModelSway;      // cl_viewmodelsway 1
var config float ViewModelSwayScale;  // cl_swayscale -- 1.0 is Valve's amount
var config bool  bViewModelSwayPitch; // cl_swaypitch -- sv_viewmodel_lag_do_angles

// The crackola's second gun, permanently, with no bottle to drink.
var config bool bForceDualWield;      // cl_forcedualwield 1

// Strafe roll: the camera banking into a sideways move. The angle is degrees at
// full lean and the speed is how fast (HL units) you have to be sliding sideways
// to get there. The port is V_CalcRoll; Deathmatch Classic ships 0.65 / 300,
// Quake used 2.0 / 200 if you want it seasick.
var config float ViewRollAngle;       // cl_viewroll
var config float ViewRollSpeed;       // cl_rollspeed

// GoldSrc's footstep cadence instead of POSTAL 2's. The rhythm is the
// simulation's (PM_UpdateStepSound); this picks which one UpdateFootSteps plays.
var config bool bGoldSrcFootSteps;    // cl_footsteps 1

// Half-Life's four-way damage direction indicator. Drawn by GoldSrcHUD.DrawPain,
// fed from NotifyTakeHit.
var config bool bDamageIndicator;     // cl_damageindicator 1

var bool  bMoveInitialized;

// The ladder volume we are currently climbing, resolved by SyncLadderState. Not
// Pawn.OnLadder: setting that is Pawn.ClimbLadder's job, and ClimbLadder is the
// one function we have to keep from running.
var LadderVolume HeldLadder;

// Latched crouch state, used when P2Player.bCrouchToggle is on.
var bool  bGoldSrcDuckToggled;

// Mean of P2Pawn's own bullet momentum damp (P2Pawn.uc:309-310, the middle of
// 0.10..0.20). DamageKnockback uses it to reconstruct the push the pawn got.
const BULLET_DAMP_MEAN = 0.15;

// Vertical state pinned across a frame that something else owned -- a damage
// stomp, or the idle handoff that lets the cops see us standing still. Latched
// before control leaves us, re-applied by every reclaim. See ApplyZPin.
var bool  bZPinned;
var float PinZ;                 // origin.Z as it was before we let go
var float PinVelZ;              // velocity.Z as it was before we let go

// Largest vertical correction the pin will make (P2 units). Big enough to undo
// anything native physics can do to us in a frame (a crouch moves the pawn 38, a
// floor snap 36) and small enough to leave a lift or a teleporter alone.
const Z_PIN_LIMIT = 96.0;

// How far the pawn must be from where the simulation left it before we believe
// something OUTSIDE the movement code moved it -- a teleporter, a lift, a
// cutscene, a mission script -- and re-seed our velocity from the pawn's.
const EXTERNAL_MOVE_DIST = 96.0;

// How long after a physics stomp the simulation keeps refusing to adopt small
// displacements it did not author. See RestorePawnPosition.
const STOMP_WINDOW = 0.2;

// How much short of the asked-for distance a salvaged move still counts as
// having arrived. See SalvageRefusedMove.
const PM_REFUSE_SLACK = 0.6;

// Damage-push budget, one frame wide. Damage does not arrive one hit at a time --
// a shotgun is eight TakeDamage calls in the same frame -- so the frame's hits are
// accumulated here and clamped as a whole. See BudgetDamagePush.
var float  DamagePushFrame;     // Level.TimeSeconds the current budget belongs to
var vector DamagePushAccum;     // what this frame has spent of it so far

// Diagnostics for the movedebug readout.
var int  SetLocFails;           // SetLocation calls the engine refused
var int  SetLocSalvaged;        // ...of those, how many the sweep recovered
var int  SetLocClipped;         // ...and how many actually cost velocity
var bool bLastMoveEmbedded;     // was the pawn inside something at the last one
var int  PhysHolds;             // times HoldPhysNone had to put PHYS_None back

// What refused the last move, asked of the ENGINE rather than of BlocksPlayer.
var Actor  RefuseActor;         // first thing on the swept path, filter ignored
var string RefuseName;          // kept as text: the actor may be gone by readout
var string RefuseClass;
var vector RefuseNormal;
var float  RefuseWanted;        // how far the move asked to go
var float  RefuseMoved;         // how far the sweep salvaged
var float  RefuseTime;

// Ground actually covered, in HL units per second, measured from the pawn's own
// position rather than from the simulation's velocity.
var float   MeasuredSpeedHL;    // EMA of |travel| / dt / WorldScale
var vector  LastMeasureLoc;     // pawn location at the previous sample
var bool    bMeasureValid;      // LastMeasureLoc is seeded

// The raw input axes as the movement frame saw them, plus the largest horizontal
// magnitude so far. Diagnostic only, but the peak is the number MoveAxisMax has to
// match: hold a movement key for a moment and read the "axis" row in movedebug.
var vector  DebugRawAxes;       // (aForward, aStrafe, aUp), this frame
var float   DebugAxisPeak;      // max |aForward|, |aStrafe| since level start

// Physics stomps: every damage event takes the pawn off PHYS_None, because
// P2Pawn.TakeDamage (P2Pawn.uc:2327) puts it back on a walking mode.
var float LastStompTime;        // Level.TimeSeconds a stomp was last seen
var name  LastStompPhysics;     // which mode it stomped us to, for the readout
var int   StompsPerSec;         // stomps counted in the second just finished
var int   StompCount;           // stomps counted in the second in progress
var float StompCountTime;       // when the second in progress began

// Level.TimeSeconds of the last animation re-pick, so several reclaims inside one
// frame (a shotgun is eight TakeDamage calls) do not re-pick eight times. See
// SyncPawnAnimation.
var float LastAnimSyncTime;

// Displacement the simulation did not author, split by what we did with it, in HL
// units per second. The Pending pair accumulates raw P2 units within a frame --
// one per hit -- and UpdateDriftReadout folds them.
var float DriftAdoptedHL;       // banked: the pawn's position became ours
var float DriftRefusedHL;       // put back: the pawn returned to our origin
var float PendingAdopted;
var float PendingRefused;

// Standing-still timers for the police (see DriveArrestAI).
var float IdleStillTime;        // how long we have been stopped, seconds
var float IdleArrestTime;       // countdown to the next nudge of the arrest AI

// The pawn's own BaseEyeHeight, saved before we start pinning ours over it.
var Pawn  StockEyePawn;         // which pawn StockBaseEyeHeight came from
var float StockBaseEyeHeight;

// Stair-step view smoothing state, Valve's two view.cpp statics (:697).
// StepSmoothOldZ trails the origin's Z while it climbs; StepSmoothLastTime is
// what the catch-up rate is measured against.
var float StepSmoothOldZ;
var float StepSmoothLastTime;

// The shift CalcFirstPersonView put on the camera this frame (oldz - simorg[2],
// so zero or negative), published for the view model.
var float StepSmoothShift;

// Valve's numbers from that block, in HL units: the camera climbs at 150 units a
// second and is never allowed to trail the origin by more than 18 -- one stair.
const STEP_SMOOTH_SPEED = 150.0;
const STEP_SMOOTH_MAX   = 18.0;

// Slack (P2 units, one sv_stepsize) allowed past each end of the span the Ladder
// nav points describe. They sit at pawn centre height rather than on the ladder's
// ends, and a step of give at the foot and at the lip covers that.
const LADDER_END_SLACK = 36.0;

// How far off the climb axis the pawn may be and still be holding the ladder, on
// top of its own hull radius (P2 units, 16 HL).
const LADDER_AXIS_REACH = 32.0;

// Input latches.
var bool  bJumpLatched;         // exec Jump fired since the last movement frame
var bool  bDuckLatched;         // duck press seen since the last movement frame

// Magnitude of the aUp contribution of the Jump/Duck binds, from
// Aliases[8]/Aliases[9]. Only change this if you retune those aliases.
var config float JumpDuckAxisSpeed;

// Full-deflection magnitude of the movement axes, i.e. what aForward and aStrafe
// read with a key held down. It comes straight off the shipped binds -- Aliases
// [2]/[3] and [6]/[7] are all "Speed=+-1200.0" -- and PlayerInput folds aBaseY
// into aForward, so the alias Speed IS the value we see.
var config float MoveAxisMax;

// A duck press that begins AND ends inside a single frame (mouse wheel) must
// still produce a real duck, or wheel-bound duckrolling does nothing at all.
// DuckPulseTime holds duck down for a short real-time window instead.
var float DuckPulseTime;            // seconds of synthetic duck remaining
var config float DuckPulseSeconds;  // how long one pulse lasts

// Ducktap bind (Bunnymod XT's +bxt_ducktap). Hold-only: while the key is down the
// sim taps duck on every touchdown, so you keep hopping off the floor without ever
// jumping. See PM_DuckTap for what the tap actually exploits.
var input byte bDuckTap;
var bool bDuckTapHeld;      // ducktap key held, reported by GoldSrcConsole
var int  DuckTapHoldKey;    // the raw key whose release ends that hold
var int  DuckTapKeyInFlight;// key whose press is being processed (console sets)
var float DuckTapKeyInFlightTime;   // when, so only this frame's key counts
var float DuckTapExecTime;  // when the exec last ran with no key published

// Footsteps.
var float FootStepAccum;    // mirrors AWDude.LastFootstepTime
var bool  bWasOnGround;     // landing edge detection

// Jump is bound as an exec, so this fires even when the aUp axis is being
// cancelled out by the duck bind. Latch it for the next movement frame.
exec function Jump(optional float F)
{
	bJumpLatched = true;
	Super.Jump(F);
}

// Explicit duck pulse, bindable to the mouse wheel:
//     bind MouseWheelDown GoldSrcDuckPulse
// The wheel sends a press and a release in the same frame, so the hold-to-crouch
// path never sees it. GoldSrcConsole calls this for a raw press of any Duck bind.
exec function GoldSrcDuckPulse()
{
	DuckPulseTime = DuckPulseSeconds;
	bDuckLatched  = true;
}

// Ducktap, bound as a plain exec:
//     set input V ducktap
exec function DuckTap()
{
	if (DuckTapKeyInFlight != 0 && DuckTapKeyInFlightTime == Level.TimeSeconds)
	{
		DuckTapHoldKey = DuckTapKeyInFlight;

		// Assignment, not a toggle: UE2 auto-repeats IST_Press for a held keyboard
		// key, and a toggle would flicker the hold off on the first repeat.
		bDuckTapHeld = true;
		return;
	}

	DuckTapExecTime = Level.TimeSeconds;

	if (bDuckTapHeld)
		return;

	if (Move != None)
		Move.ducktapOnce = true;
}

// Called by GoldSrcConsole on the release of the key that claimed the hold, and
// wherever a held key can no longer be trusted to deliver one (typing, level
// change, a new pawn).
final function DuckTapHoldEnd()
{
	bDuckTapHeld   = false;
	DuckTapHoldKey = 0;
}

// Setup
function PostBeginPlay()
{
	Super.PostBeginPlay();

	if (Move == None)
		Move = new(Self) class'GoldSrcMovement';
}

function Possess(Pawn aPawn)
{
	Super.Possess(aPawn);

	if (Move == None)
		Move = new(Self) class'GoldSrcMovement';

	// Whatever the input state was before this pawn (level travel, respawn), the
	// ducktap key is not being held right now.
	DuckTapHoldEnd();

	DuckTapKeyInFlight = 0;

	bMoveInitialized = false;

	// bCheatDualWield is not travel tagged, so a level change drops it while the
	// config flag survives. Only reassert it when we are forcing, so a level begun
	// with this off leaves the game's own DoubleTheGun cheat alone.
	if (bForceDualWield)
		ApplyForceDualWield();

	if (bGoldSrcMovement)
		GotoState('PlayerGoldSrcWalking');
}

// Sync the simulation state from the pawn. Called when we take over, or
// after anything external moves the player (teleport, cutscene, etc).
final function InitMoveState(optional bool bKeepDuck, optional bool bKeepVelocity)
{
	local bool bWantDuck;

	if (Pawn == None || Move == None)
		return;

	Move.PM         = Pawn;
	Move.TraceOwner = Pawn;

	// Once per pawn, and before ApplyMoveState has ever run for it, so what we save is
	// the pawn's value and not our own. If the pawn is crouched this reads the crouched
	// eye height, which stock code overwrites on standing up anyway.
	if (StockEyePawn != Pawn)
	{
		StockEyePawn       = Pawn;
		StockBaseEyeHeight = Pawn.BaseEyeHeight;
	}

	// Resolve P2's own body dimensions off the pawn class. Must happen before
	// any hull query below, since sv_usep2hull reads these.
	Move.SyncP2HullDims();

	Move.origin     = Pawn.Location;

	// Velocity seed. On a genuine state ENTRY we adopt the pawn's velocity. On a
	// mid-flight RECLAIM -- damage is the usual culprit -- the pawn has already run a
	// frame of native friction, and re-seeding from that dead value is what laundered
	// a 500 ups bhop into a crawl on every hit, so keep ours instead. Knockback is
	// folded in separately by NotifyTakeHit.
	if (bKeepVelocity && bMoveInitialized)
	{
		// Move.velocity already holds the authoritative pre-stomp value.
	}
	else
	{
		Move.velocity = Pawn.Velocity;
	}

	Move.basevelocity = vect(0,0,0);
	Move.dead       = (Pawn.Health <= 0);
	Move.friction   = 1.0;
	Move.gravityScale = 1.0;
	Move.maxspeed   = Move.sv_maxspeed;

	// A genuine first ENTRY knows nothing about where we stand, so start from "not on
	// ground" and let PM_CategorizePosition work it out, landing-frame floor drop
	// included.
	if (!bMoveInitialized)
		Move.onground = false;

	// Decide which hull we can legally occupy at this position.
	bWantDuck = bKeepDuck && Move.bDucking;

	// If we want to stand but the standing hull does not fit here, stay ducked rather
	// than teleport ourselves into the world. Both tests are against the position the
	// hull change will LEAVE us in (see HullFitsAfterSync); when neither hull fits we
	// keep the standing one and let PM_CheckStuck nudge us free.
	if (!bWantDuck && !HullFitsAfterSync(0) && HullFitsAfterSync(1))
	{
		bWantDuck = true;
	}

	if (bWantDuck)
	{
		Move.usehull    = 1;
		Move.bDucking   = true;
		Move.bInDuck    = false;
		Move.flDuckTime = 0;
		Move.view_ofs   = Move.DuckViewOfs();
	}
	else
	{
		Move.usehull    = 0;
		Move.bDucking   = false;
		Move.bInDuck    = false;
		Move.flDuckTime = 0;
		Move.view_ofs   = Move.ViewOfs();
	}

	// Resize the Unreal cylinder BEFORE categorizing, so the traces that
	// decide "am I on the ground" use the hull we just chose.
	if (!SyncHull(true) && !Move.bDucking && HullFitsAfterSync(1))
	{
		// The standing hull would not fit after all, and the ducked one will.
		// Take it rather than leaving the pawn at P2's size, which the
		// simulation does not know how to trace against.
		Move.usehull    = 1;
		Move.bDucking   = true;
		Move.bInDuck    = false;
		Move.flDuckTime = 0;
		Move.view_ofs   = Move.DuckViewOfs();

		SyncHull(true);
	}

	// The hull is authoritative now, so make sure the simulation's origin
	// agrees with where the pawn actually ended up.
	Move.origin = Pawn.Location;

	// Undo anything the damage path did to our height before categorizing, so
	// the ground test below runs where the player actually was.
	ApplyZPin();

	Move.PM_CategorizePosition();

	bMoveInitialized = true;
}

// Hold the pawn on PHYS_None -- for the whole frame, not just the top of it.
final function HoldPhysNone()
{
	if (Pawn == None)
		return;

	if (Pawn.Physics == PHYS_None
		|| Pawn.Physics == PHYS_Karma
		|| Pawn.Physics == PHYS_KarmaRagDoll)
		return;

	Pawn.SetPhysics(PHYS_None);

	PhysHolds++;
}

// Move the pawn.
final function bool MovePawnTo(vector NewLoc, optional bool bIgnoreEncroachment)
{
	local bool bMoved;

	if (Pawn == None)
		return false;

	bMoved = Pawn.SetLocation(NewLoc, bIgnoreEncroachment);

	HoldPhysNone();

	return bMoved;
}

// Record what refused a move.
final function NoteRefusal(Actor A, vector N, float Wanted, float Moved)
{
	RefuseActor  = A;
	RefuseNormal = N;
	RefuseWanted = Wanted;
	RefuseMoved  = Moved;
	RefuseTime   = Level.TimeSeconds;

	if (A != None)
	{
		RefuseName  = string(A.Name);
		RefuseClass = string(A.Class.Name);
	}
	else
	{
		// Nothing on the swept path, so the engine's objection was to the DESTINATION:
		// FarMoveActor fit-tests where you asked to end up, and a box a hundredth of a
		// unit inside a stair face fails that with nothing at all in the way.
		RefuseName  = "<destination>";
		RefuseClass = "no swept hit";
	}
}

// Recover from a SetLocation the engine refused.
final function SalvageRefusedMove()
{
	local vector Delta, Before, N, HitLoc, HitNorm, Extent, NewVel;
	local Actor  A;
	local float  Wanted, Moved;
	local bool   bEmbedded;

	Before = Pawn.Location;
	Delta  = Move.origin - Before;
	Wanted = VSize(Delta);

	// The pawn's OWN dimensions, not the simulation hull -- the question is what the
	// engine sees when it moves this body -- and bTraceActors with no BlocksPlayer
	// filter, so the things our filter calls passable still show up.
	Extent.X = Pawn.CollisionRadius;
	Extent.Y = Pawn.CollisionRadius;
	Extent.Z = Pawn.CollisionHeight;

	A = Pawn.Trace(HitLoc, HitNorm, Move.origin, Before, true, Extent);

	if (A != None)
		N = HitNorm;

	bEmbedded = !Move.PM_TestPlayerPosition(Before);

	SetLocFails++;
	bLastMoveEmbedded = bEmbedded;

	if (bEmbedded && MovePawnTo(Move.origin, true))
	{
		NoteRefusal(A, N, Wanted, Wanted);
		return;
	}

	Pawn.Move(Delta);
	HoldPhysNone();

	Moved       = VSize(Pawn.Location - Before);
	Move.origin = Pawn.Location;

	NoteRefusal(A, N, Wanted, Moved);

	if (Moved > 0.0)
		SetLocSalvaged++;

	// Got there bar the trace epsilon: we are where we asked to be and there is
	// nothing to clip.
	if (Moved >= Wanted - PM_REFUSE_SLACK)
		return;

	// Stopped short, but that alone is NOT permission to touch the velocity.
	if (N == vect(0,0,0))
		return;

	// A surface, but we are already travelling AWAY from it: the jump frame off a
	// floor we just touched. GoldSrc does not clip here either, because PM_FlyMove
	// only clips a plane it ran into, and clipping anyway subtracts the jump.
	if ((Move.velocity dot N) >= 0.0)
		return;

	// Driving into it for real. Lose that component and keep the rest, which is
	// PM_FlyMove's own rule and the difference between sliding along a wall and
	// sticking to it.
	SetLocClipped++;

	Move.PM_ClipVelocity(Move.velocity, N, NewVel, 1.0);
	Move.velocity = NewVel;
}

// Put the vertical axis back where it was before we let go of the pawn.
final function ApplyZPin()
{
	local vector Fixed;

	if (!bZPinned || Pawn == None || Move == None)
		return;

	// Vertical momentum first: it needs no clearance and it is what carries a
	// jump or a fall through the hit instead of letting native friction eat it.
	Move.velocity.Z = PinVelZ;

	if (Move.origin.Z == PinZ)
		return;

	if (Abs(Move.origin.Z - PinZ) > Z_PIN_LIMIT)
		return;

	// Small differences are the engine's own resting height, not a stomp: native
	// walking rests a pawn a couple of units above the floor where GoldSrc rests it
	// flush. Correcting those would fight the engine on every frame of sustained fire.
	if (Abs(Move.origin.Z - PinZ) <= Move.GroundSlack())
		return;

	Fixed   = Move.origin;
	Fixed.Z = PinZ;

	if (!Move.PM_TestPlayerPosition(Fixed))
		return;

	if (MovePawnTo(Fixed))
		Move.origin = Fixed;
}

// Latch the pin. Call this immediately before letting anything else own the
// pawn, while the simulation's own numbers are still the truth.
final function PinVertical()
{
	if (Move == None || !bMoveInitialized)
		return;

	bZPinned = true;
	PinZ     = Move.origin.Z;
	PinVelZ  = Move.velocity.Z;
}

// Take the pawn back off whatever physics mode stole it -- as cheaply as the
// situation actually allows.
final function bool ReclaimPawn(optional bool bForceResync)
{
	if (Pawn == None || Move == None)
		return false;

	// Legitimate takeovers, ceded entirely: karma and the ragdoll are the engine
	// physically owning the body, and there is nothing there for us to reclaim.
	if (Pawn.Physics == PHYS_Karma || Pawn.Physics == PHYS_KarmaRagDoll)
		return false;

	if (Pawn.Physics != PHYS_None)
	{
		// Remember it before undoing it. RestorePawnPosition needs to know a stomp
		// happened, and it is the only evidence that the displacement about to show
		// up in PlayerMove was native physics rather than the world moving us.
		NoteStomp();

		Pawn.SetPhysics(PHYS_None);

		// Whatever ran while the mode was stolen may have left the pawn in a
		// looping run animation, and on PHYS_None nothing would ever pick another
		// one. See SyncPawnAnimation -- this is the footstep spam after damage.
		SyncPawnAnimation();
	}

	if (bForceResync || !bMoveInitialized || PawnHasDiverged())
	{
		// Before resyncing ONTO the displacement, try to refuse it. A native tick that ran
		// on a stomped mode is the common reason we are here, and adopting what it did is
		// what paid the player for ground they never covered; see RestorePawnPosition.
		if (!bForceResync && bMoveInitialized && RestorePawnPosition()
			&& !PawnHasDiverged())
		{
			Move.PM         = Pawn;
			Move.TraceOwner = Pawn;
			Move.dead       = (Pawn.Health <= 0);

			ApplyZPin();

			return false;
		}

		// bKeepDuck: whatever stole the physics does not know we are crouched, and
		// standing up blindly can wedge us in a ceiling. bKeepVelocity: the pawn may have
		// run a frame of native friction, so ours is the last correct velocity.
		InitMoveState(true, true);
		return true;
	}

	// Cheap path. Refresh only what costs nothing and would be wrong if stale,
	// then put the vertical state back the way the simulation had it.
	Move.PM         = Pawn;
	Move.TraceOwner = Pawn;
	Move.dead       = (Pawn.Health <= 0);

	ApplyZPin();

	return false;
}

// Has anything actually moved or resized the pawn out from under the simulation?
final function bool PawnHasDiverged()
{
	local vector D;

	if (Pawn == None || Move == None)
		return true;

	// Hull mismatch. SyncHull compares these exactly; a tenth of a unit of slack
	// here only keeps float noise from forcing a pointless resync.
	if (Abs(Pawn.CollisionRadius - Move.HullRadius()) > 0.1)
		return true;

	if (Abs(Pawn.CollisionHeight - Move.HullHalfHeight()) > 0.1)
		return true;

	D = Pawn.Location - Move.origin;

	if (VSize(vect(1,1,0) * D) > 1.0)
		return true;

	return Abs(D.Z) > Move.GroundSlack();
}

// Record that something took the pawn off PHYS_None.
final function NoteStomp()
{
	if (Pawn == None)
		return;

	LastStompTime    = Level.TimeSeconds;
	LastStompPhysics = GetEnum(enum'EPhysics', Pawn.Physics);

	if (Level.TimeSeconds - StompCountTime >= 1.0)
	{
		StompsPerSec   = StompCount;
		StompCount     = 0;
		StompCountTime = Level.TimeSeconds;
	}

	StompCount++;
}

// Re-pick the pawn's body animation now that PHYS_None is back in effect.
final function SyncPawnAnimation(optional bool bForce)
{
	if (Pawn == None)
		return;

	// Only meaningful once the mode we want the animation chosen for is the mode
	// the pawn is actually in.
	if (Pawn.Physics != PHYS_None)
		return;

	if (!bForce && LastAnimSyncTime == Level.TimeSeconds)
		return;

	LastAnimSyncTime = Level.TimeSeconds;

	Pawn.ChangeAnimation();
}

// Put the pawn back where the simulation left it, and say whether that worked.
final function bool RestorePawnPosition()
{
	local float D;

	if (Pawn == None || Move == None)
		return false;

	if (Level.TimeSeconds - LastStompTime > STOMP_WINDOW)
		return false;

	// Based on something that can move: it is entitled to carry us.
	if (Pawn.Base != None && !Pawn.Base.bWorldGeometry && !Pawn.Base.bStatic)
		return false;

	D = VSize(Pawn.Location - Move.origin);

	if (D <= 1.0 || D > EXTERNAL_MOVE_DIST)
		return false;

	if (!Move.PM_TestPlayerPosition(Move.origin))
		return false;

	if (!MovePawnTo(Move.origin))
	{
		SetLocFails++;
		return false;
	}

	PendingRefused += D;

	return true;
}

// Fold the frame's refused and adopted displacement into the readout.
final function UpdateDriftReadout(float DeltaTime)
{
	local float Scale;

	Scale = 1.0 / FMax(DeltaTime, 0.0001);

	if (Move != None)
		Scale /= FMax(Move.WorldScale, 0.0001);

	DriftAdoptedHL += (PendingAdopted * Scale - DriftAdoptedHL) * 0.25;
	DriftRefusedHL += (PendingRefused * Scale - DriftRefusedHL) * 0.25;

	PendingAdopted = 0.0;
	PendingRefused = 0.0;
}

// How fast the player is REALLY travelling, from the pawn's own footprints.
final function SampleMeasuredSpeed(float DeltaTime)
{
	local vector Travel;
	local float  Raw;

	if (Pawn == None || Move == None)
		return;

	// A teleport is not a speed. Seed on the first frame, and re-seed after
	// anything that breaks continuity, rather than reporting a five-figure spike.
	if (!bMeasureValid || DeltaTime <= 0.0
		|| VSize(Pawn.Location - LastMeasureLoc) > EXTERNAL_MOVE_DIST)
	{
		LastMeasureLoc  = Pawn.Location;
		bMeasureValid   = true;
		MeasuredSpeedHL = 0.0;
		return;
	}

	Travel = vect(1,1,0) * (Pawn.Location - LastMeasureLoc);

	Raw = VSize(Travel) / DeltaTime;

	if (Move.WorldScale > 0.0)
		Raw /= Move.WorldScale;

	// Same weight the accel readout uses, for the same reason.
	MeasuredSpeedHL += (Raw - MeasuredSpeedHL) * 0.25;

	LastMeasureLoc = Pawn.Location;
}

// Would hull TestHull be clear once SyncHull has finished moving us into it?
final function bool HullFitsAfterSync(int TestHull)
{
	local vector Landed;

	if (Pawn == None || Move == None)
		return false;

	Landed    = Move.origin;
	Landed.Z += Move.HullHalfHeightFor(TestHull) - Pawn.CollisionHeight;

	return Move.PM_TestHullPosition(Landed, TestHull);
}

// Apply the simulation result back onto the pawn.
final function ApplyMoveState()
{
	if (Pawn == None || Move == None)
		return;

	// SetLocation is a teleport AND it can FAIL: it returns false and moves nothing
	// when the destination encroaches geometry. Ignoring that return is what wedges
	// the player -- the sim keeps integrating from an origin the pawn never reached.
	if (Move.origin != Pawn.Location && !MovePawnTo(Move.origin))
		SalvageRefusedMove();

	Pawn.Velocity     = Move.velocity;
	Pawn.Acceleration = Move.DebugWishDir * Move.DebugWishSpeed;

	// Keep the pawn's own crouch flag in sync so animation / weapon code
	// that reads bWantsToCrouch still behaves.
	Pawn.bWantsToCrouch = Move.bDucking;

	// Drive eye height from the GoldSrc view offset, and pin BaseEyeHeight too: the
	// pawn's own code lerps EyeHeight toward it every frame, and the scaled-HL default
	// (56) would drag the camera below where P2's art expects it, which reads in game
	// as the player being shorter than the NPCs.
	Pawn.EyeHeight     = Move.view_ofs;
	Pawn.BaseEyeHeight = Move.view_ofs;

	// Last word on the physics mode for this frame. The move above is the usual
	// way it gets taken (see HoldPhysNone), but a hull resize can lose the base
	// too, and this runs after both.
	HoldPhysNone();
}

// Tell the police we have stopped, without ever leaving PHYS_None.
const IDLE_ARREST_SPEED  = 2.0;     // P2 units/s -- 1 HL unit/s, i.e. stopped
const IDLE_ARREST_DWELL  = 0.75;    // seconds stopped before the cops are told
const IDLE_ARREST_PERIOD = 0.5;     // seconds between asking them to reconsider

// True when the simulation has nothing to do: feet on the floor, standing, no
// input, no speed. This is what the police mean by "he stopped".
final function bool IsStandingStill()
{
	if (Pawn == None || Move == None || !bMoveInitialized)
		return false;

	if (Pawn.Physics != PHYS_None)
		return false;

	if (!Move.onground || Move.onladder || Move.waterlevel >= 2)
		return false;

	// Nothing pressed. upmove is included because it is the swim/ladder axis and
	// a held jump belongs to the sim even on the ground.
	if (Move.forwardmove != 0.0 || Move.sidemove != 0.0 || Move.upmove != 0.0)
		return false;

	if (bPressedJump || bJumpLatched || Move.oldbuttonJump)
		return false;

	return (VSize(Move.velocity) <= IDLE_ARREST_SPEED);
}

final function DriveArrestAI(float DeltaTime)
{
	local Controller       C;
	local PoliceController Cop;
	local Actor            OldBase;
	local vector           OldAccel;

	if (Pawn == None || Pawn.Health <= 0)
		return;

	if (!IsStandingStill())
	{
		// Moving again: the dwell has to be earned back from scratch, so a player
		// who stops for a single frame between strafes never counts as frozen.
		IdleStillTime = 0.0;
		return;
	}

	IdleStillTime += DeltaTime;

	if (IdleStillTime < IDLE_ARREST_DWELL)
		return;

	IdleArrestTime -= DeltaTime;

	if (IdleArrestTime > 0.0)
		return;

	IdleArrestTime = IDLE_ARREST_PERIOD;

	OldBase  = Pawn.Base;
	OldAccel = Pawn.Acceleration;

	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		Cop = PoliceController(C);

		// Only cops who are already dealing with US, and only from the two states
		// that are sitting there waiting to see whether we complied. Every other
		// state either does not ask the question or has an answer already.
		if (Cop == None || Cop.Pawn == None || Cop.Attacker != Pawn)
			continue;

		if (Cop.GetStateName() != 'TellHimToFreeze'
			&& Cop.GetStateName() != 'TellHimToDropWeapon')
			continue;

		Pawn.Acceleration = vect(0,0,0);
		Pawn.SetPhysics(PHYS_Walking);

		Cop.DecideNextStateBasedOnAttacker(false);

		// Give the BASE back before the MODE. Native walking picks a floor for the pawn it
		// thinks it is carrying, so this restore is usually a base loss -- and a base loss
		// on a pawn already back on PHYS_None is P2Pawn.BaseChange's cue to set
		// PHYS_Falling. This order lands the loss while the pawn still reads PHYS_Walking.
		if (Pawn.Base != OldBase)
			Pawn.SetBase(OldBase);

		Pawn.SetPhysics(PHYS_None);
		Pawn.Acceleration = OldAccel;

		// The borrow above is a window in which PlayMoving() would answer
		// SetAnimRunning(), so re-pick now that PHYS_None is back. Forced, because a
		// reclaim earlier in this same frame may already have used the once-per-frame slot.
		SyncPawnAnimation(true);

		HoldPhysNone();
	}
}

// Dispatch the GoldSrc touch list as Unreal Bump() events.
final function DispatchTouches()
{
	local int   i;
	local Actor A;

	if (Pawn == None || Move == None)
		return;

	for (i = 0; i < Move.NumTouch; i++)
	{
		A = Move.TouchedActors[i];

		if (A == None || A.bDeleteMe || A == Pawn)
			continue;

		// Static world geometry has no script Bump() worth calling, and
		// skipping it keeps this cheap in corridors.
		if (A.bStatic || A.bWorldGeometry)
			continue;

		// Mirror what a real swept move does: notify both parties.
		A.Bump(Pawn);
		Pawn.Bump(A);
	}

	Move.NumTouch = 0;
}

// Resize the Unreal collision cylinder to match the active GoldSrc hull.
// Resize the Unreal cylinder to match the GoldSrc hull.
final function bool SyncHull(optional bool bLiftOrigin)
{
	local float WantRadius, WantHeight, OldHeight, DeltaZ;
	local vector Lifted;

	if (Pawn == None || Move == None)
		return false;

	WantRadius = Move.HullRadius();
	WantHeight = Move.HullHalfHeight();

	if (Pawn.CollisionRadius == WantRadius && Pawn.CollisionHeight == WantHeight)
		return true;

	OldHeight = Pawn.CollisionHeight;
	DeltaZ    = WantHeight - OldHeight;

	// Growing: lift the origin first so the feet stay put, otherwise the
	// resize itself can fail on the floor we are standing on.
	if (bLiftOrigin && DeltaZ > 0.0)
	{
		Lifted = Pawn.Location;
		Lifted.Z += DeltaZ;

		if (MovePawnTo(Lifted))
			Move.origin = Lifted;
	}

	if (!Pawn.SetCollisionSize(WantRadius, WantHeight))
	{
		// Could not fit. Undo the lift and report failure so the caller can
		// fall back to the ducked hull.
		if (bLiftOrigin && DeltaZ > 0.0)
		{
			Lifted    = Pawn.Location;
			Lifted.Z -= DeltaZ;

			if (MovePawnTo(Lifted))
				Move.origin = Lifted;
		}

		HoldPhysNone();

		return false;
	}

	// Shrinking: drop the origin AFTER the resize, same reasoning inverted.
	if (bLiftOrigin && DeltaZ < 0.0)
	{
		Lifted = Pawn.Location;
		Lifted.Z += DeltaZ;

		if (MovePawnTo(Lifted))
			Move.origin = Lifted;
	}

	HoldPhysNone();

	return true;
}

// Hand the pawn's collision cylinder back to P2's own dimensions.
// The ducked case needs the same treatment for a smaller delta: our ducked hull is
// 36 and P2's CrouchHeight is 40, so leaving ours in place makes native crouch
// physics perform the unlifted 4-unit grow itself. Hand back P2's crouch cylinder
// explicitly, lifted, so native physics finds the cylinder it expects.
final function bool RestoreStockHull(optional bool bCrouched)
{
	local float WantRadius, WantHeight, DeltaZ;
	local vector Lifted;

	if (Pawn == None)
		return false;

	if (bCrouched)
	{
		// CrouchRadius is 0 on some pawns; fall back to the standing radius,
		// which is what Pawn.uc's own crouch path uses.
		WantHeight = Pawn.CrouchHeight;
		WantRadius = Pawn.CrouchRadius;

		if (WantRadius <= 0.0)
			WantRadius = Pawn.Default.CollisionRadius;

		if (WantHeight <= 0.0)
			WantHeight = Pawn.Default.CollisionHeight;
	}
	else
	{
		WantRadius = Pawn.Default.CollisionRadius;
		WantHeight = Pawn.Default.CollisionHeight;
	}

	if (Pawn.CollisionRadius == WantRadius && Pawn.CollisionHeight == WantHeight)
	{
		RestoreStockEyeHeight(bCrouched);
		return true;
	}

	DeltaZ = WantHeight - Pawn.CollisionHeight;

	// Growing: lift first so the feet stay planted and the grow has room below.
	if (DeltaZ > 0.0)
	{
		Lifted    = Pawn.Location;
		Lifted.Z += DeltaZ;
		Pawn.SetLocation(Lifted);
	}

	if (!Pawn.SetCollisionSize(WantRadius, WantHeight))
	{
		// Undo the lift and stay on our hull. Ask the stock crouch code to
		// stand us up when the ceiling allows it.
		if (DeltaZ > 0.0)
		{
			Lifted    = Pawn.Location;
			Lifted.Z -= DeltaZ;
			Pawn.SetLocation(Lifted);
		}

		Pawn.bWantsToCrouch = true;
		return false;
	}

	// Shrinking: drop the origin AFTER the resize, same reasoning inverted.
	if (DeltaZ < 0.0)
	{
		Lifted    = Pawn.Location;
		Lifted.Z += DeltaZ;
		Pawn.SetLocation(Lifted);
	}

	RestoreStockEyeHeight(bCrouched);

	return true;
}

// Give the camera back.
final function RestoreStockEyeHeight(optional bool bCrouched)
{
	local float H;

	if (Pawn == None)
		return;

	if (bCrouched && Pawn.CrouchHeight > 0.0)
	{
		Pawn.BaseEyeHeight = 0.8 * Pawn.CrouchHeight;
		return;
	}

	H = StockBaseEyeHeight;

	if (H <= 0.0)
		H = Pawn.Default.BaseEyeHeight;

	Pawn.BaseEyeHeight = H;
	Pawn.EyeHeight     = H;
}

// Damage reaches the simulation through here and nowhere else.
function NotifyTakeHit(pawn InstigatedBy, vector HitLocation, int Damage, class<DamageType> damageType, vector Momentum)
{
	DriveDamage(Damage, damageType, Momentum);

	NotifyDamageDirection(InstigatedBy, HitLocation, Momentum);

	Super.NotifyTakeHit(InstigatedBy, HitLocation, Damage, DamageType, Momentum);
}

// How far back along the momentum to place an attacker we never saw. The
// indicator only ever uses the DIRECTION of that offset, so the distance just has
// to be far enough not to read as point blank.
const DAMAGE_DIR_REACH = 256.0;

// CHudHealth::MsgFunc_Damage    (cl_dll/health.cpp:119)
//
// Half-Life sends the client the position the damage came FROM and nothing else;
// the HUD works the direction out of that and holds it. Finding that position is
// the only part that is ours, since nothing hands it to us directly: an attacker's
// own location beats everything, then the momentum points back down the shot, and
// a hit with neither -- a fall, a hangover, drowning -- is left as no direction at
// all, which is the vector of zeroes Valve's own code reads as "nowhere". This is
// deliberately NOT inside DriveDamage: that one only runs while we own the pawn,
// and the indicator should still work in the middle of a cutscene.
final function NotifyDamageDirection(pawn InstigatedBy, vector HitLocation, vector Momentum)
{
	local GoldSrcHUD H;
	local vector     vecFrom;

	if (!bDamageIndicator || Pawn == None)
		return;

	H = GoldSrcHUD(myHUD);
	if (H == None)
		return;

	if (InstigatedBy != None)
		vecFrom = InstigatedBy.Location;
	else if (VSize(Momentum) > 0.0)
		vecFrom = Pawn.Location - Normal(Momentum) * DAMAGE_DIR_REACH;
	else
		vecFrom = HitLocation;

	H.CalcDamageDirection(vecFrom, Pawn.Location, Rotation);
}

// Our own damage driver: every effect a hit is allowed to have on the movement
// simulation happens here, in this order, and the stock damage path gets no
// other say.
final function DriveDamage(int Damage, class<DamageType> damageType, vector Momentum)
{
	local vector Kick, PreVel;
	local bool   bExplosive;

	if (!bGoldSrcMovement || Pawn == None || Move == None || !bMoveInitialized)
		return;

	// Only while we are the ones driving. In any other state stock movement owns
	// the pawn and stock damage handling is the correct behaviour.
	if (GetStateName() != 'PlayerGoldSrcWalking')
		return;

	PinVertical();

	ReclaimPawn();

	bExplosive = ClassIsChildOf(damageType, class'BaseFX.ExplodedDamage');

	// The pre-hit truth, sampled after the reclaim so it is the value the next
	// simulation frame would actually have started from.
	PreVel = Move.velocity;

	Kick = BudgetDamagePush(DamageKnockback(Damage, damageType, Momentum));

	Move.velocity += Kick;

	if (!bExplosive)
		CapStaggerSpeed(PreVel);

	// The hit's OWN vertical kick is part of the result the game intends -- this
	// is what blast jumping is -- so add it to the pinned value rather than
	// letting the pin undo it a moment later.
	PinVelZ += (Move.velocity.Z - PreVel.Z);

	// Same bound Valve puts on velocity after anything external adds to it.
	Move.PM_CheckVelocity();

	// Report what the simulation actually took, not what was offered: after the
	// budget, the ceiling and PM_CheckVelocity have all had their say, Kick is no
	// longer the delta, and the movedebug row is meant to read as truth.
	Move.DebugLastPush     = Move.velocity - PreVel;
	Move.DebugLastPushTime = Level.TimeSeconds;

	Pawn.Velocity = Move.velocity;
}

// A flinch may turn you, and may stagger you up to a run from a standstill, but
// it may not make you faster than you already were.
final function CapStaggerSpeed(vector PreVel)
{
	local vector Flat;
	local float  PreSpeed, PostSpeed, Ceiling;

	if (Move == None)
		return;

	Flat   = Move.velocity;
	Flat.Z = 0.0;

	PostSpeed = VSize(Flat);

	if (PostSpeed <= 0.0)
		return;

	PreVel.Z = 0.0;
	PreSpeed = VSize(PreVel);

	Ceiling = Move.maxspeed;
	if (Ceiling <= 0.0)
		Ceiling = Move.sv_maxspeed;

	Ceiling = FMax(PreSpeed, Ceiling);

	if (PostSpeed <= Ceiling)
		return;

	// Rescale, do not project: the direction the hit produced is kept, which is
	// what makes a shove from the side still read as a shove from the side.
	Flat *= Ceiling / PostSpeed;

	Move.velocity.X = Flat.X;
	Move.velocity.Y = Flat.Y;
}

// Share one frame's worth of damage push between all the hits that arrive in it,
// and cap the total at sv_maxdamagepush.
final function vector BudgetDamagePush(vector Kick)
{
	local vector Total, Added;
	local float  Cap, Mag;

	if (Move == None)
		return Kick;

	if (DamagePushFrame != Level.TimeSeconds)
	{
		DamagePushFrame = Level.TimeSeconds;
		DamagePushAccum = vect(0,0,0);
	}

	Total = DamagePushAccum + Kick;

	Cap = Move.sv_maxdamagepush;

	// Clamp the SUM, not the increment: two 400-unit shoves from opposite sides
	// still cancel, and two from the same side still only buy one cap's worth.
	if (Cap > 0.0)
	{
		Mag = VSize(Total);

		if (Mag > Cap)
			Total *= Cap / Mag;
	}

	Added           = Total - DamagePushAccum;
	DamagePushAccum = Total;

	return Added;
}

// The velocity a hit should actually add, reconstructed the way the PAWN got it.
final function vector DamageKnockback(int Damage, class<DamageType> damageType, vector Momentum)
{
	// Hits that did no damage never reached AddVelocity: P2Pawn.uc:2364 reports
	// them with the damage negated and returns before the push. Do not push
	// either, or armour and god mode would still shove the player around.
	if (Damage <= 0)
		return vect(0,0,0);

	// Explosives keep their boost, scaled by sv_explosionknockback. sv_knockback
	// deliberately does NOT apply on top: the two exist so that a flinch and a
	// blast can be tuned apart.
	if (ClassIsChildOf(damageType, class'BaseFX.ExplodedDamage'))
	{
		if (Move != None)
			Momentum *= Move.sv_explosionknockback;

		return Momentum;
	}

	if (ClassIsChildOf(damageType, class'BaseFX.BulletDamage'))
		Momentum *= BULLET_DAMP_MEAN;

	// sv_knockback trims the remaining (non-explosive) flinch only.
	if (Move != None)
		Momentum *= Move.sv_knockback;

	return Momentum;
}

// Body size: POSTAL 2's own dimensions vs literal scaled-Half-Life ones.
exec function sv_usep2hull(optional string OnOff)
{
	if (Move == None)
		return;

	if (OnOff == "1" || OnOff ~= "on")       Move.sv_usep2hull = true;
	else if (OnOff == "0" || OnOff ~= "off") Move.sv_usep2hull = false;
	else                                     Move.sv_usep2hull = !Move.sv_usep2hull;

	Move.SaveConfig();

	// Re-resolve the dimensions and resize the pawn right now, rather than
	// waiting for the next state re-entry. Keep the live velocity -- this is a
	// mid-play resize, not a fresh entry, so there is nothing to reseed from.
	if (Pawn != None)
	{
		Move.SyncP2HullDims();
		InitMoveState(true, true);
	}

	if (Move.sv_usep2hull)
		ClientMessage("Hull: POSTAL 2 size");
	else
		ClientMessage("Hull: Half-Life size");
}

// Console commands

exec function GoldSrc(optional string OnOff)
{
	if (OnOff == "0" || OnOff ~= "off" || OnOff ~= "false")
		bGoldSrcMovement = false;
	else if (OnOff == "1" || OnOff ~= "on" || OnOff ~= "true")
		bGoldSrcMovement = true;
	else
		bGoldSrcMovement = !bGoldSrcMovement;

	SaveConfig();

	if (bGoldSrcMovement)
	{
		ClientMessage("GoldSrc movement: ON");
		GotoState('PlayerGoldSrcWalking');
	}
	else
	{
		ClientMessage("GoldSrc movement: OFF");

		// Hand the pawn back through the SAME path every other exit uses --
		// PlayerGoldSrcWalking.EndState, which restores the cylinder with the origin lift
		// the hull change needs and keeps the crouch if we are ducked.
		if (Pawn != None && GetStateName() != 'PlayerGoldSrcWalking')
			RestoreStockHull(Move != None && Move.bDucking);

		GotoState('PlayerWalking');
	}
}

exec function Speedo(optional string OnOff)
{
	if (OnOff == "0")      bShowSpeedometer = false;
	else if (OnOff == "1") bShowSpeedometer = true;
	else                   bShowSpeedometer = !bShowSpeedometer;

	SaveConfig();
	ClientMessage("Speedometer:" @ OnOffStr(bShowSpeedometer));
}

exec function MoveDebug(optional string OnOff)
{
	if (OnOff == "0")      bShowMoveDebug = false;
	else if (OnOff == "1") bShowMoveDebug = true;
	else                   bShowMoveDebug = !bShowMoveDebug;

	SaveConfig();
	ClientMessage("Movement debug:" @ OnOffStr(bShowMoveDebug));
}

// GoldSrc's two console diagnostics, under their own names.
exec function net_graph(optional string OnOff)
{
	if (OnOff == "0")      bShowNetGraph = false;
	else if (OnOff != "")  bShowNetGraph = true;
	else                   bShowNetGraph = !bShowNetGraph;

	SaveConfig();
	ClientMessage("net_graph:" @ OnOffStr(bShowNetGraph));

	// Say it once, here, rather than have the player wonder why two of the four
	// rows never move: there is no connection to count in single player, and
	// Unreal exposes no byte counters to script even when there is one.
	if (bShowNetGraph && Level.NetMode == NM_Standalone)
		ClientMessage("  (fps and ping are live; in/out/loss/choke read 0 --"
			@ "single player has no net connection to measure)");
}

exec function cl_showpos(optional string OnOff)
{
	if (OnOff == "0")      bShowPos = false;
	else if (OnOff != "")  bShowPos = true;
	else                   bShowPos = !bShowPos;

	SaveConfig();
	ClientMessage("cl_showpos:" @ OnOffStr(bShowPos));
}

// The other place the first person weapon gets drawn from.
simulated event RenderOverlays(canvas Canvas)
{
	local GoldSrcHUD H;

	H = GoldSrcHUD(myHUD);

	if (H != None)
	{
		H.BobCtrlCalls++;
		H.ApplyViewModelBob();
	}

	Super.RenderOverlays(Canvas);

	if (H != None)
		H.RestoreViewModelBob();
}

// Source's viewmodel bob on or off. See GoldSrcHUD.CalcViewModelBob for what it
// is a port of and what it leaves out.
exec function cl_viewmodelbob(optional string OnOff)
{
	if (OnOff == "0")      bViewModelBob = false;
	else if (OnOff != "")  bViewModelBob = true;
	else                   bViewModelBob = !bViewModelBob;

	SaveConfig();
	ClientMessage("cl_viewmodelbob:" @ OnOffStr(bViewModelBob));
}

// How far the bob travels, as a multiple of Valve's amount. Deliberately the only
// bob knob: HL2 declares cl_bob, cl_bobcycle and cl_bobup next to the bob code but
// CalcViewmodelBob never reads any of them.
exec function cl_bobscale(optional string Value)
{
	if (Value != "")
	{
		ViewModelBobScale = FMax(0.0, float(Value));
		SaveConfig();
	}

	ClientMessage("cl_bobscale" @ ViewModelBobScale @ "(1 = Valve's amount)");
}

// Source's viewmodel lag on or off -- the gun swinging out behind a turn and
// settling back. See GoldSrcHUD.CalcViewModelLag.
exec function cl_viewmodelsway(optional string OnOff)
{
	if (OnOff == "0")      bViewModelSway = false;
	else if (OnOff != "")  bViewModelSway = true;
	else                   bViewModelSway = !bViewModelSway;

	SaveConfig();
	ClientMessage("cl_viewmodelsway:" @ OnOffStr(bViewModelSway));
}

// How far the gun swings out, as a multiple of Valve's amount.
exec function cl_swayscale(optional string Value)
{
	if (Value != "")
	{
		ViewModelSwayScale = FMax(0.0, float(Value));
		SaveConfig();
	}

	ClientMessage("cl_swayscale" @ ViewModelSwayScale @ "(1 = Valve's amount)");
}

// The pitch droop half of the sway, which is Valve's own separate switch
// (sv_viewmodel_lag_do_angles, default 1): looking up pushes the gun down and
// away, looking down brings it up and in.
exec function cl_swaypitch(optional string OnOff)
{
	if (OnOff == "0")      bViewModelSwayPitch = false;
	else if (OnOff != "")  bViewModelSwayPitch = true;
	else                   bViewModelSwayPitch = !bViewModelSwayPitch;

	SaveConfig();
	ClientMessage("cl_swaypitch:" @ OnOffStr(bViewModelSwayPitch));
}

// UnrealScript has no ternary operator.
final function string OnOffStr(bool b)
{
	if (b)
		return "ON";
	return "OFF";
}

// Degrees the view leans into a sideways slide. 0 turns it off; a negative value
// leans the other way, which is there because Unreal's roll sign is not Quake's
// and the only test that settles it is your own eyes.
exec function cl_viewroll(optional string Value)
{
	if (Value != "")
	{
		ViewRollAngle = float(Value);
		SaveConfig();
	}

	ClientMessage("cl_viewroll" @ ViewRollAngle);
}

// Sideways speed, in HL units/sec, at which the lean is fully wound out.
exec function cl_rollspeed(optional string Value)
{
	if (Value != "")
	{
		ViewRollSpeed = FMax(0.0, float(Value));
		SaveConfig();
	}

	ClientMessage("cl_rollspeed" @ ViewRollSpeed);
}

// GoldSrc's footstep timing, or POSTAL 2's own. Off gives you the stock rhythm
// back; the sounds themselves are P2's either way.
exec function cl_footsteps(optional string OnOff)
{
	if (OnOff == "0")      bGoldSrcFootSteps = false;
	else if (OnOff != "")  bGoldSrcFootSteps = true;
	else                   bGoldSrcFootSteps = !bGoldSrcFootSteps;

	SaveConfig();
	ClientMessage("cl_footsteps:" @ OnOffStr(bGoldSrcFootSteps));
}

// Half-Life's four wedges around the crosshair, pointing at whatever just hit you.
exec function cl_damageindicator(optional string OnOff)
{
	if (OnOff == "0")      bDamageIndicator = false;
	else if (OnOff != "")  bDamageIndicator = true;
	else                   bDamageIndicator = !bDamageIndicator;

	SaveConfig();
	ClientMessage("cl_damageindicator:" @ OnOffStr(bDamageIndicator));

	if (!bDamageIndicator && GoldSrcHUD(myHUD) != None)
		GoldSrcHUD(myHUD).ClearDamageDirection();
}

// Half-Life's bottom row layout, drawn with Postal's own heart, armor and ammo icons.
exec function cl_goldsrchud(optional string OnOff)
{
	local GoldSrcHUD H;

	H = GoldSrcHUD(myHUD);
	if (H == None)
		return;

	if (OnOff == "0")      H.bGoldSrcHud = false;
	else if (OnOff != "")  H.bGoldSrcHud = true;
	else                   H.bGoldSrcHud = !H.bGoldSrcHud;

	if (H.bGoldSrcHud)
		H.ApplyGoldSrcLayout();
	else
		H.RestoreP2Layout();

	H.LastHealth = -1;      // don't let a stale fade latch flash the new row
	H.LastArmor  = -1;
	H.LastAmmo   = -1;

	H.SaveConfig();
	ClientMessage("cl_goldsrchud:" @ OnOffStr(H.bGoldSrcHud));
}

// Colour of the whole bottom row: health, armor, ammo and the divider bars.
// One channel per command.
exec function cl_hudcolor_r(optional string Value)
{
	SetHudColorChannel(0, Value);
}

exec function cl_hudcolor_g(optional string Value)
{
	SetHudColorChannel(1, Value);
}

exec function cl_hudcolor_b(optional string Value)
{
	SetHudColorChannel(2, Value);
}

final function SetHudColorChannel(int Channel, string Value)
{
	local GoldSrcHUD H;
	local color C;

	H = GoldSrcHUD(myHUD);
	if (H == None)
		return;

	if (Value != "")
	{
		C = H.HudColor;

		switch (Channel)
		{
			case 0:   C.R = Clamp(int(Value), 0, 255);   break;
			case 1:   C.G = Clamp(int(Value), 0, 255);   break;
			case 2:   C.B = Clamp(int(Value), 0, 255);   break;
		}

		C.A = 255;
		H.HudColor = C;
		H.SaveConfig();
	}

	ClientMessage("cl_hudcolor:" @ int(H.HudColor.R) @ int(H.HudColor.G) @ int(H.HudColor.B));
}

// Resting brightness of that row, 0 to 255. Valve's MIN_ALPHA of 100 suits additive
// sprites, not text, so this sits higher by default.
exec function cl_hudalpha(optional string Value)
{
	local GoldSrcHUD H;

	H = GoldSrcHUD(myHUD);
	if (H == None)
		return;

	if (Value != "")
	{
		H.HudMinAlpha = FClamp(float(Value), 0.0, 255.0);
		H.SaveConfig();
	}

	ClientMessage("cl_hudalpha:" @ H.HudMinAlpha);
}

// Size of the row on top of the 480p reference scale.
exec function cl_hudscale(optional string Value)
{
	local GoldSrcHUD H;

	H = GoldSrcHUD(myHUD);
	if (H == None)
		return;

	if (Value != "")
	{
		H.HudScale = FClamp(float(Value), 0.25, 3.0);
		H.SaveConfig();
	}

	ClientMessage("cl_hudscale:" @ H.HudScale);
}

// Font step for the numbers, 0 smallest to 3 largest. FontInfo picks from a table,
// so this is a step and not a multiplier.
exec function cl_hudfontsize(optional string Value)
{
	local GoldSrcHUD H;

	H = GoldSrcHUD(myHUD);
	if (H == None)
		return;

	if (Value != "")
	{
		H.HudFontSize = Clamp(int(Value), 0, 3);
		H.SaveConfig();
	}

	ClientMessage("cl_hudfontsize:" @ H.HudFontSize);
}

// Diagnostic: does PlayerViewOffset move the weapon in this build at all?
exec function cl_bobtest(optional string Value)
{
	local Weapon W;
	local float Amount;
	local vector Base;

	if (Pawn == None || Pawn.Weapon == None)
	{
		ClientMessage("cl_bobtest: no weapon");
		return;
	}
	W = Pawn.Weapon;

	// Take the bob's hands off the field first, or its restore would undo this.
	if (GoldSrcHUD(myHUD) != None)
		GoldSrcHUD(myHUD).RestoreViewModelBob();

	Amount = 20.0;
	if (Value != "")
		Amount = float(Value);

	Base = W.Default.PlayerViewOffset;
	W.PlayerViewOffset = Base;
	W.PlayerViewOffset.Y += Amount;

	ClientMessage("cl_bobtest" @ Amount @ "-" @ W.Name @ "offset"
		@ W.PlayerViewOffset.X @ W.PlayerViewOffset.Y @ W.PlayerViewOffset.Z
		@ "(default Y" @ Base.Y $ ")");
	Log("GoldSrcBob: cl_bobtest" @ Amount @ "on" @ W.Name @ "class"
		@ string(W.Class) @ "offset" @ W.PlayerViewOffset.X
		@ W.PlayerViewOffset.Y @ W.PlayerViewOffset.Z, 'GoldSrc');
}

exec function ResetSpeed()
{
	if (Move != None)
		Move.ResetStats();
	ClientMessage("Speed stats reset.");
}

// StuckReport: everything around the hull, unfiltered.
final function ReportLine(string S)
{
	ClientMessage(S);
	Log("GoldSrcStuck: " $ S, 'GoldSrc');
}

// The flags that make an actor solid, or that explain why it should not be.
final function string ActorFlagStr(Actor A)
{
	local string S;

	if (A == None)
		return "";

	if (A.bHidden)                    S = S $ " hidden";
	if (A.bWorldGeometry)             S = S $ " worldgeo";
	if (A.bBlockPlayers)              S = S $ " blkPlayers";
	if (A.bBlockActors)               S = S $ " blkActors";
	if (!A.bCollideActors)            S = S $ " noCollideActors";
	if (!A.bBlockNonZeroExtentTraces) S = S $ " noBoxTrace";
	if (!A.bBlockZeroExtentTraces)    S = S $ " noLineTrace";
	if (A.bStatic)                    S = S $ " static";
	if (A.DrawType == DT_None)        S = S $ " noDraw";
	if (Volume(A) != None)            S = S $ " volume";
	if (BlockingVolume(A) != None)
	{
		S = S $ " BV";
		if (BlockingVolume(A).bClassBlocker)
			S = S $ "(classBlocker x"
				$ BlockingVolume(A).BlockedClasses.Length
				$ YesNo(BlockingVolume(A).bAllowOnlySpecifiedClasses, " allowOnly", "")
				$ ")";
	}

	return S;
}

// One actor, as the report prints it: is the simulation calling this solid, and
// what does it look like.
final function string ActorReportStr(Actor A)
{
	if (A == None)
		return "none";

	return string(A.Name) $ " (" $ string(A.Class.Name) $ ")"
		@ YesNo(Move.BlocksPlayer(A), "SOLID", "passable")
		$ ActorFlagStr(A);
}

exec function StuckReport()
{
	local vector E, Org, Dir, HL, HN, IterLoc, IterNorm;
	local rotator R;
	local Actor A, Nearest;
	local float Probe, Dist, BestDist;
	local int i, N;
	local string Names;

	if (Pawn == None || Move == None)
	{
		ClientMessage("StuckReport: no pawn.");
		return;
	}

	E     = Move.HullExtent();
	Org   = Pawn.Location;
	Probe = 12.0;

	ReportLine("== stuck report ==");

	ReportLine("hull       box " $ FmtV(E) $ "   pawn r" $ int(Pawn.CollisionRadius)
		$ " h" $ int(Pawn.CollisionHeight) $ "   sv_hullradius " $ int(Move.sv_hullradius)
		$ " -> " $ int(Move.HullRadius()) $ YesNo(Move.sv_usep2hull, "  (p2hull)", "  (hlhull)"));

	ReportLine("phys       " $ GetEnum(enum'EPhysics', Pawn.Physics)
		$ "  usehull " $ Move.usehull $ YesNo(Move.bDucking, "  ducking", "")
		$ "  onground " $ YesNo(Move.onground, "yes", "no"));

	ReportLine("origin     drift " $ FmtF(VSize(Move.origin - Pawn.Location))
		$ "   setloc refused " $ SetLocFails
		$ " (" $ SetLocSalvaged $ " salvaged, " $ SetLocClipped $ " cost speed)"
		$ "   embedded " $ YesNo(bLastMoveEmbedded, "YES", "no")
		$ "   stuck " $ Move.StuckFrames $ "/" $ Move.sv_maxstuckframes);

	// The refusal, which is the one question the rest of this report cannot answer.
	if (RefuseTime > 0.0)
		ReportLine("refused    " $ RefuseName $ " (" $ RefuseClass $ ")"
			$ "   wanted " $ FmtF(RefuseWanted) $ " moved " $ FmtF(RefuseMoved)
			$ "   n " $ FmtV(RefuseNormal)
			$ "   " $ FmtF(Level.TimeSeconds - RefuseTime) $ "s ago"
			$ YesNo(RefuseActor != None && Move.BlocksPlayer(RefuseActor),
				"   filter: SOLID", "   filter: PASSABLE"));
	else
		ReportLine("refused    nothing yet this session");

	// What the hull is standing inside right now. Given a two-unit vertical span
	// rather than a zero-length one because the iterator wants a direction to walk;
	// over a box this size that is still an overlap test, not a sweep.
	N = 0;
	foreach Pawn.TraceActors(class'Actor', A, IterLoc, IterNorm,
		Org + vect(0,0,1), Org - vect(0,0,1), E)
	{
		if (A == Pawn || A == self)
			continue;

		N++;
		ReportLine("inside     " $ ActorReportStr(A));
	}

	if (N == 0)
		ReportLine("inside     nothing (hull is clear of actors)");

	// The engine's own overlap list, which is kept up to date by our SetLocation
	// calls and does not depend on a trace agreeing. If something appears here and
	// not above, the trace cannot see it -- noBoxTrace is why.
	N = 0;
	foreach Pawn.TouchingActors(class'Actor', A)
	{
		N++;
		ReportLine("touching   " $ ActorReportStr(A));
	}

	if (N == 0)
		ReportLine("touching   nothing");

	// The level model is not an actor, so it needs its own question asked. A
	// zero-length box check against the world only: if this comes back solid the
	// origin is inside BSP or terrain.
	A = Pawn.Trace(HL, HN, Org, Org, false, E);
	ReportLine("inside bsp " $ YesNo(A != None,
		"YES -- origin is inside world geometry", "no -- world is clear here"));

	// Eight probes, one per 45 degrees, naming the nearest SOLID thing in each. A ring
	// of clears with no movement means the refusal is coming from the engine's own
	// encroachment test rather than from anything the simulation can see.
	for (i = 0; i < 8; i++)
	{
		R      = rot(0,0,0);
		R.Yaw  = i * 8192;
		Dir    = vector(R);

		Nearest  = None;
		BestDist = -1.0;
		Names    = "";

		foreach Pawn.TraceActors(class'Actor', A, IterLoc, IterNorm,
			Org + Dir * Probe, Org, E)
		{
			if (A == Pawn || A == self)
				continue;

			if (!Move.BlocksPlayer(A))
			{
				if (Names == "")
					Names = "   passing through:";
				Names = Names @ string(A.Name);
				continue;
			}

			Dist = VSize(IterLoc - Org);

			if (BestDist < 0.0 || Dist < BestDist)
			{
				BestDist = Dist;
				Nearest  = A;
			}
		}

		// And the level model, which TraceActors leaves out.
		A = Pawn.Trace(HL, HN, Org + Dir * Probe, Org, false, E);
		if (Move.BlocksPlayer(A))
		{
			Dist = VSize(HL - Org);
			if (BestDist < 0.0 || Dist < BestDist)
			{
				BestDist = Dist;
				Nearest  = A;
			}
		}

		if (Nearest == None)
			ReportLine(CompassStr(i) $ "      clear" $ Names);
		else
			ReportLine(CompassStr(i) $ "      " $ FmtF(BestDist) $ "u  "
				$ ActorReportStr(Nearest) $ Names);
	}

	ReportLine("== end ==   (also in Postal2.log)");
}

// Compass label for probe i, padded so the eight rows line up.
final function string CompassStr(int i)
{
	switch (i)
	{
		case 0:  return "east ";
		case 1:  return "ne   ";
		case 2:  return "north";
		case 3:  return "nw   ";
		case 4:  return "west ";
		case 5:  return "sw   ";
		case 6:  return "south";
	}
	return "se   ";
}

// Local formatters, so the report does not depend on the HUD being up.
final function string YesNo(bool b, string sTrue, string sFalse)
{
	if (b)
		return sTrue;
	return sFalse;
}

final function string FmtF(float F)
{
	return string(int(F * 100.0) / 100.0);
}

final function string FmtV(vector V)
{
	return "(" $ FmtF(V.X) $ ", " $ FmtF(V.Y) $ ", " $ FmtF(V.Z) $ ")";
}

// Generic cvar setter: sv_maxspeed 320, sv_gravity 800, etc.
exec function SetMoveVar(string VarName, float Value)
{
	if (Move == None)
		return;

	switch (Caps(VarName))
	{
		case "SV_MAXSPEED":      Move.sv_maxspeed = Value;      Move.maxspeed = Value; break;
		case "SV_ACCELERATE":    Move.sv_accelerate = Value;    break;
		case "SV_AIRACCELERATE": Move.sv_airaccelerate = Value; break;
		case "SV_FRICTION":      Move.sv_friction = Value;      break;
		case "SV_STOPSPEED":     Move.sv_stopspeed = Value;     break;
		case "SV_GRAVITY":       Move.sv_gravity = Value;       break;
		case "SV_STEPSIZE":      Move.sv_stepsize = Value;      break;
		case "SV_EDGEFRICTION":  Move.sv_edgefriction = Value;  break;
		case "SV_BOUNCE":        Move.sv_bounce = Value;        break;
		case "SV_MAXVELOCITY":   Move.sv_maxvelocity = Value;   break;
		case "SV_HULLRADIUS":    Move.sv_hullradius = Value;    break;
		case "WORLDSCALE":       Move.WorldScale = Value;       break;
		case "SV_FALLDAMAGE":    Move.sv_falldamage = int(Value); break;
		case "SV_KNOCKBACK":     Move.sv_knockback = FMax(0.0, Value); break;
		case "SV_EXPLOSIONKNOCKBACK": Move.sv_explosionknockback = FMax(0.0, Value); break;
		case "SV_MAXDAMAGEPUSH": Move.sv_maxdamagepush = FMax(0.0, Value); break;
		default:
			ClientMessage("Unknown movement var:" @ VarName);
			return;
	}

	Move.SaveConfig();
	ClientMessage(VarName @ "=" @ Value);
}

// Convenience wrappers so the cvars can be typed the GoldSrc way.
exec function sv_maxspeed(float V)      { SetMoveVar("sv_maxspeed", V); }
exec function sv_accelerate(float V)    { SetMoveVar("sv_accelerate", V); }
exec function sv_airaccelerate(float V) { SetMoveVar("sv_airaccelerate", V); }
exec function sv_friction(float V)      { SetMoveVar("sv_friction", V); }
exec function sv_stopspeed(float V)     { SetMoveVar("sv_stopspeed", V); }
exec function sv_gravity(float V)       { SetMoveVar("sv_gravity", V); }
exec function sv_stepsize(float V)      { SetMoveVar("sv_stepsize", V); }
exec function sv_edgefriction(float V)  { SetMoveVar("sv_edgefriction", V); }
exec function sv_bounce(float V)        { SetMoveVar("sv_bounce", V); }
exec function sv_maxvelocity(float V)   { SetMoveVar("sv_maxvelocity", V); }

// In HL units like the constant it replaces, so it is doubled on use: 16 gives a
// 32-unit half-width. HullRadius() reads it live, so a new value applies to the
// very next trace -- which is the point, it is the knob you walk into a snag with.
exec function sv_hullradius(float V)    { SetMoveVar("sv_hullradius", V); }

exec function sv_falldamage(optional string Mode)
{
	if (Move == None)
		return;

	if (Mode == "0")      Move.sv_falldamage = 0;
	else if (Mode == "1") Move.sv_falldamage = 1;
	else if (Mode == "2") Move.sv_falldamage = 2;
	else                  Move.sv_falldamage = (Move.sv_falldamage + 1) % 3;

	Move.SaveConfig();

	switch (Move.sv_falldamage)
	{
		case 0: ClientMessage("Fall damage: OFF");                                    break;
		case 1: ClientMessage("Fall damage: LESSER (flat 10 HP)");                   break;
		case 2: ClientMessage("Fall damage: REALISTIC (Valve's curve)");             break;
	}
}

// How hard a hit shoves you. Non-explosive damage only; blasts have their own
// scale (sv_explosionknockback) so the damage boost can be tuned separately.
exec function sv_knockback(optional string Value)
{
	if (Move == None)
		return;

	if (Value != "")
	{
		Move.sv_knockback = FMax(0.0, float(Value));
		Move.SaveConfig();
	}

	ClientMessage("sv_knockback" @ Move.sv_knockback
		@ "(bullets/melee; see sv_explosionknockback for blasts)");
}

// How much of an explosion's throw you keep -- the damage boost dial.
exec function sv_explosionknockback(optional string Value)
{
	if (Move == None)
		return;

	if (Value != "")
	{
		Move.sv_explosionknockback = FMax(0.0, float(Value));
		Move.SaveConfig();
	}

	ClientMessage("sv_explosionknockback" @ Move.sv_explosionknockback
		@ "(1 = all of P2's blast momentum, 0 = never pushed by explosions)");
}

// Ceiling on the push one frame of damage may add, in HL units per second --
// typed the way a HL player thinks about speed, stored scaled like the rest.
exec function sv_maxdamagepush(optional string Value)
{
	local float Scale;

	if (Move == None)
		return;

	Scale = FMax(Move.WorldScale, 0.0001);

	if (Value != "")
	{
		Move.sv_maxdamagepush = FMax(0.0, float(Value)) * Scale;
		Move.SaveConfig();
	}

	ClientMessage("sv_maxdamagepush" @ int(Move.sv_maxdamagepush / Scale + 0.5)
		@ "ups per frame of damage (0 = uncapped)");
}

exec function sv_enablebunnyhopcap(optional string OnOff)
{
	if (Move == None)
		return;

	if (OnOff == "1")      Move.sv_enablebunnyhopcap = true;
	else if (OnOff == "0") Move.sv_enablebunnyhopcap = false;
	else                   Move.sv_enablebunnyhopcap = !Move.sv_enablebunnyhopcap;

	Move.SaveConfig();

	if (Move.sv_enablebunnyhopcap)
		ClientMessage("Bunnyhop cap: ON (nerd)");
	else
		ClientMessage("Bunnyhop cap: OFF (how The Lord intended)");
}

// Autobunnyhop. Off = faithful HL1 (one jump per press). On = holding jump
// re-hops automatically on each landing.
exec function sv_autobunnyhop(optional string OnOff)
{
	if (Move == None)
		return;

	if (OnOff == "1" || OnOff ~= "on")       Move.sv_autobunnyhop = true;
	else if (OnOff == "0" || OnOff ~= "off") Move.sv_autobunnyhop = false;
	else                                     Move.sv_autobunnyhop = !Move.sv_autobunnyhop;

	Move.SaveConfig();

	if (Move.sv_autobunnyhop)
		ClientMessage("Autobunnyhop: ON");
	else
		ClientMessage("Autobunnyhop: OFF");
}

// Accelerated Back Hopping, imported wholesale from Half-Life 2. Look away from
// where you are going, hold the key that fights it, and hop: see
// GoldSrcMovement.PM_ABHJumpBoost for why that is the fast way round. It wants
// the bunnyhop cap off, which clamps the whole thing to 1.7x maxspeed if it is on.
exec function sv_enableabh(optional string OnOff)
{
	if (Move == None)
		return;

	if (OnOff == "1" || OnOff ~= "on")       Move.sv_enableabh = true;
	else if (OnOff == "0" || OnOff ~= "off") Move.sv_enableabh = false;
	else                                     Move.sv_enableabh = !Move.sv_enableabh;

	Move.SaveConfig();

	if (!Move.sv_enableabh)
	{
		ClientMessage("ABH: OFF");
		return;
	}

	ClientMessage("ABH: ON");

	if (Move.sv_enablebunnyhopcap)
		ClientMessage("...but sv_enablebunnyhopcap is ON, which caps it. Turn that off.");
}

// Whether an actor marked as world geometry still has to carry the block flags.
// On is the engine's own rule and the default; off is the old shortcut, kept so a
// suspected invisible wall can be confirmed in game in one keystroke.
exec function sv_strictblocking(optional string OnOff)
{
	if (Move == None)
		return;

	if (OnOff == "1" || OnOff ~= "on")       Move.sv_strictblocking = true;
	else if (OnOff == "0" || OnOff ~= "off") Move.sv_strictblocking = false;
	else                                     Move.sv_strictblocking = !Move.sv_strictblocking;

	Move.SaveConfig();

	if (Move.sv_strictblocking)
		ClientMessage("sv_strictblocking ON");
	else
		ClientMessage("sv_strictblocking OFF");
}

// The crackola effect on tap. Two things drive dual wielding, and CrackColaInv gets
// both through P2Player.BeginDualWielding: bCheatDualWield, which
// P2DualWieldWeapon.BringUp reads so every weapon raised from now on comes up
// doubled, and one ToggleDualWielding on the weapon already in hand, since a weapon
// that is up will not re-read the flag by itself. The only thing left out is the
// bottle's timer, which is the point.
exec function cl_forcedualwield(optional string OnOff)
{
	if (OnOff == "0" || OnOff ~= "off")      bForceDualWield = false;
	else if (OnOff == "1" || OnOff ~= "on")  bForceDualWield = true;
	else                                     bForceDualWield = !bForceDualWield;

	SaveConfig();
	ClientMessage("cl_forcedualwield:" @ OnOffStr(bForceDualWield));

	if (!ApplyForceDualWield() && bForceDualWield)
		ClientMessage("  (nothing in hand that comes in a pair -- the next one that does gets doubled)");
}

// Returns whether the weapon in hand could be spoken for. False means it has no left
// hand copy, so only the flag was set and the change shows on the next weapon.
final function bool ApplyForceDualWield()
{
	local P2DualWieldWeapon W;

	bCheatDualWield = bForceDualWield;

	if (Pawn == None)
		return false;

	W = P2DualWieldWeapon(Pawn.Weapon);

	// Either not a weapon that has a second copy at all, or xPatch turned dual
	// wielding off for it.
	if (W == None || W.bDisableDualWielding)
		return false;

	// A crackola is already running. It owns the weapon until it runs out, and
	// P2Player.SetupDualWielding(0) reads bCheatDualWield at that point to decide
	// whether the second gun stays, so the flag alone settles this.
	if (DualWieldUseTime > 0)
		return true;

	if (W.bDualWielding == bForceDualWield)
		return true;

	// Spawning the left weapon is what BringUp would have done at the next switch.
	if (W.LeftWeapon == None)
		W.SetupDualWielding();

	if (W.LeftWeapon == None)
		return false;

	W.GotoState('ToggleDualWielding');
	return true;
}

// Let the sniper scope open while the simulation owns the pawn.
exec function AltFire(optional float F)
{
	if (!bGoldSrcMovement
		|| Pawn == None
		|| Pawn.Weapon == None
		|| Pawn.Physics == PHYS_Walking
		|| GetStateName() != 'PlayerGoldSrcWalking'
		|| !Pawn.Weapon.IsA('RifleWeapon'))
	{
		Super.AltFire(F);
		return;
	}

	Pawn.SetPhysics(PHYS_Walking);

	Super.AltFire(F);

	// Back to the invariant, not to whatever was there before: PHYS_None is the only
	// mode this state may leave the pawn in. Not via HoldPhysNone, because this was
	// our own doing and not a mode the game stole from us.
	if (GetStateName() == 'PlayerGoldSrcWalking')
		Pawn.SetPhysics(PHYS_None);
}

// The GoldSrc movement state.
// Extends the stock PlayerWalking state deliberately. POSTAL 2 gates its save
// machinery on being in a PlayerWalking-derived state: P2Player.PrepForSave is a
// no-op stub at global scope and only does the real work when overridden inside
// state PlayerWalking, so from a sibling state the level-entry autosave never
// happens. We still fully override PlayerMove/ProcessMove/BeginState/EndState, so
// no stock movement leaks in.
state PlayerGoldSrcWalking extends PlayerWalking
{
ignores SeePlayer, HearNoise, Bump;

	// Water is handled inside the sim now (PM_CheckWater / PM_WaterMove), so we must
	// NOT hand off to the stock swimming states the way stock PlayerWalking does --
	// that would drop us out of GoldSrc the moment a toe touched a pool.
	function bool NotifyPhysicsVolumeChange(PhysicsVolume NewVolume)
	{
		return true;
	}

	function BeginState()
	{
		if (Pawn == None)
			return;

		if (Pawn.Mesh == None)
			Pawn.SetMesh();

		DoubleClickDir = DCLICK_None;
		bPressedJump   = false;

		// Take full control of physics.
		Pawn.SetPhysics(PHYS_None);

		// Whatever stock physics was doing up to this instant picked the pawn's animation
		// for the mode it owned, and PHYS_None has no reason to keep it. Re-pick once,
		// forced: this frame's slot may be spent on the reclaim that sent us here.
		SyncPawnAnimation(true);

		// Take full control of ladders too. bCanClimbLadders is the ONLY gate on both
		// stock grab paths -- CanGrabLadder (Engine/Pawn.uc:343), read by
		// LadderVolume.PawnEnteredVolume and PotentialClimbWatcher and nothing else -- so
		// clearing it keeps Pawn.ClimbLadder from ever running. The sim finds ladders.
		Pawn.bCanClimbLadders = false;

		// Preserve the duck state. We are re-entered constantly (damage, the map screen
		// and cutscenes all bounce us through stock PlayerWalking), and forcing the
		// standing hull every time is what used to wedge a crouched player in the ceiling.
		InitMoveState(true, true);

		// Stock PlayerWalking.BeginState calls CheckPrepForSave() so a level entered via a
		// finished movie still autosaves. We skipped Super.BeginState above, so reproduce
		// that one call; it is guarded by bDidPrepForSave, so it self-limits to once a map.
		CheckPrepForSave();
	}

	function EndState()
	{
		if (Pawn == None)
			return;

		// Hand ladders back to stock. Restoring from the class default is what P2 itself
		// does when a state releases this flag, and it cannot latch off if we are ever
		// exited without a matching BeginState.
		Pawn.bCanClimbLadders = Pawn.default.bCanClimbLadders;
		HeldLadder            = None;

		if (Move != None && Move.bDucking)
		{
			// Do NOT force the STANDING cylinder back on while ducked -- with geometry
			// overhead the pawn interpenetrates it and native physics then refuses to
			// move it at all. Keep the crouch, but hand back P2's own crouch cylinder
			// (40) rather than leaving ours (36), which native crouch would grow unlifted.
			Pawn.bWantsToCrouch = true;
			RestoreStockHull(true);
		}
		else
		{
			// Handing the pawn back to stock physics is a hull change too, with the
			// same centre-of-hull problem as the entry path: our standing half height
			// is 72 and P2's is 78, so growing about a fixed origin puts the feet 6
			// units under the floor at the moment native physics resumes. Lift first,
			// and if the bigger cylinder does not fit, leave our hull on.
			RestoreStockHull();
		}

		if (Pawn.Physics == PHYS_None)
			Pawn.SetPhysics(PHYS_Falling);
	}

	// Drive the simulation.
	function PlayerMove(float DeltaTime)
	{
		local rotator ViewRotation, PawnRotation;
		local vector  X, Y, Z;
		local float   MoveScale;
		local float   RawUp;
		local float   Drift;

		if (Pawn == None)
		{
			GotoState('Dead');
			return;
		}

		if (Move == None)
		{
			Move = new(Self) class'GoldSrcMovement';
			bMoveInitialized = false;
		}

		if (!bMoveInitialized)
			InitMoveState();

		// Other game systems (cutscenes, vehicles, ragdoll, being mugged)
		// legitimately change physics out from under us. If something has
		// taken the pawn off PHYS_None, don't fight it -- hand control back.
		if (Pawn.Physics != PHYS_None)
		{
			if (Pawn.Physics == PHYS_Karma || Pawn.Physics == PHYS_KarmaRagDoll)
			{
				Super.PlayerMove(DeltaTime);
				return;
			}

			// Otherwise reclaim it -- something reset us to Falling/Walking, or the
			// engine flipped us to PHYS_Swimming on entering water / PHYS_Ladder via
			// Pawn.ClimbLadder. We own water and ladders now, so those are reclaimed
			// like any other stomp and only the Karma cases above are ceded to stock.
			ReclaimPawn();
		}

		// --- Rotation ----------------------------------------------------
		// UpdateRotation ends by calling Pawn.FaceRotation(view), and FaceRotation only
		// strips the pitch on PHYS_Walking or PHYS_Falling, so on PHYS_None the pawn
		// keeps ours and we have to level it ourselves below.
		ViewRotation = Rotation;
		SetRotation(ViewRotation);
		UpdateRotation(DeltaTime, 1);

		if (Pawn.Rotation.Pitch != 0 || Pawn.Rotation.Roll != 0)
		{
			PawnRotation       = Pawn.Rotation;
			PawnRotation.Pitch = 0;
			PawnRotation.Roll  = 0;
			Pawn.SetRotation(PawnRotation);
		}

		// --- Feed the simulation ----------------------------------------

		// Something outside the movement code moved us (teleport, script,
		// vehicle). Re-sync rather than fighting it.
		SampleMeasuredSpeed(DeltaTime);

		Drift = VSize(Pawn.Location - Move.origin);

		if (Drift > 1.0)
		{
			// Second line of defence: ReclaimPawn refuses native displacement at the
			// moment it takes the mode back, which is where the damage case is caught.
			// This catches a stomp that came and went between our own frames.
			if (Drift > EXTERNAL_MOVE_DIST || !RestorePawnPosition())
			{
				Move.origin = Pawn.Location;

				if (Drift > EXTERNAL_MOVE_DIST)
					Move.velocity = Pawn.Velocity;

				PendingAdopted += Drift;
			}
		}

		Move.PM         = Pawn;
		Move.TraceOwner = Pawn;
		Move.frametime  = FMin(DeltaTime, 0.1);   // clamp huge hitches
		Move.dead       = (Pawn.Health <= 0);
		Move.maxspeed   = Move.sv_maxspeed;

		// Build forward/right from the VIEW rotation. GoldSrc derives wishdir
		// from view angles, not from the pawn's facing.
		ViewRotation       = Rotation;
		ViewRotation.Pitch = 0;
		ViewRotation.Roll  = 0;

		GetAxes(ViewRotation, X, Y, Z);
		Move.forward = X;
		Move.right   = Y;
		Move.up      = Z;

		// The FULL basis, pitch included. Swimming and ladder climbing are the two GoldSrc
		// paths that genuinely want a 3D wish vector -- you swim and climb where you look
		// -- and neither flattens, so neither meets the pitch-limit problem above.
		GetAxes(Rotation, X, Y, Z);
		Move.viewForward = X;
		Move.viewRight   = Y;
		Move.viewUp      = Z;

		// Map Unreal's input axes onto HL's +-400 forwardmove / sidemove --
		// IN SIMULATION UNITS.
		MoveScale = Move.HL_MAX_MOVE_CMD * Move.WorldScale
			/ FMax(1.0, MoveAxisMax);

		DebugRawAxes.X  = aForward;
		DebugRawAxes.Y  = aStrafe;
		DebugRawAxes.Z  = aUp;
		DebugAxisPeak   = FMax(DebugAxisPeak, FMax(Abs(aForward), Abs(aStrafe)));

		Move.forwardmove = aForward * MoveScale;
		Move.sidemove    = aStrafe  * MoveScale;

		// Raw, un-clamped per-axis fractions for PM_LadderMove only. Valve's ladder code
		// adds full speed per button with no diagonal clamp, and that overspeed is the fast
		// climb; forwardmove/sidemove have already lost it twice over.
		Move.ladderForwardFrac = FClamp(aForward / FMax(1.0, MoveAxisMax), -1.0, 1.0);
		Move.ladderSideFrac    = FClamp(aStrafe  / FMax(1.0, MoveAxisMax), -1.0, 1.0);

		// Buttons. The HELD state, not the one-shot bPressedJump, because GoldSrc's PM_Jump
		// does its own "don't pogo stick" edge detection via oldbuttons. Holding jump gives
		// exactly one jump per landing, which is what makes HL bunnyhopping work.
		RawUp = aUp;
		if (bDuck != 0)
			RawUp += JumpDuckAxisSpeed;

		Move.buttonJump = (RawUp > 1.0) || bJumpLatched || bPressedJump;

		// upmove is HL's +moveup / +movedown (cl_upspeed), which only water movement reads.
		// POSTAL 2 has no separate swim-up bind, but jump and duck are exactly the pair of
		// keys HL players use for it, and aUp already carries both with the right signs.
		if (Move.waterlevel > 0)
			Move.upmove = aUp * MoveScale;
		else
			Move.upmove = 0.0;

		// Respect POSTAL 2's crouch-toggle preference (P2Player.bCrouchToggle)
		// rather than forcing hold-to-crouch on players who configured toggle.
		if (bCrouchToggle)
		{
			if (bDuck != 0 && bDuckOld == 0)
				bGoldSrcDuckToggled = !bGoldSrcDuckToggled;

			Move.buttonDuck = bGoldSrcDuckToggled;
		}
		else
		{
			Move.buttonDuck = (bDuck != 0);
		}

		// A wheel-bound duck delivers its press and release inside a single frame, so the
		// held state above never sees it. GoldSrcDuckPulse holds duck down for a short
		// real-time window instead, which is what makes duckrolling work.
		if (DuckPulseTime > 0.0)
		{
			DuckPulseTime -= DeltaTime;
			Move.buttonDuck = true;
		}
		else if (bDuckLatched)
		{
			Move.buttonDuck = true;
		}

		bDuckLatched = false;
		bDuckOld     = bDuck;

		// Ducktap bind, held state only -- the sim runs the actual press/release cycle in
		// PM_DuckTap and keeps repeating it while this stays true, because only the sim
		// knows, that early in the frame, whether we are on the ground.
		Move.buttonDuckTap = (bDuckTap != 0) || bDuckTapHeld;

		// --- Ladders ------------------------------------------------------
		// Resolve the ladder plane from POSTAL 2's LadderVolume and hand it to
		// the sim, which then runs Valve's PM_LadderMove math on it.
		SyncLadderState();

		// --- Run one GoldSrc movement frame -----------------------------
		Move.PM_PlayerMove();

		// --- Write results back -----------------------------------------
		// PM_Duck / PM_UnDuck have ALREADY offset Move.origin by the hull delta, so no
		// extra lift belongs here -- but the resize and the teleport must happen in the
		// right ORDER, and the safe order is opposite for the two directions.
		if (Pawn.CollisionHeight > Move.HullHalfHeight())
		{
			SyncHull();          // shrink at the old origin, then move down
			ApplyMoveState();
		}
		else
		{
			ApplyMoveState();    // move up first, then grow about that centre
			SyncHull();
		}

		// Fire Bump() for everything the move ran into. Must happen after
		// the pawn is at its final position so handlers see correct state.
		DispatchTouches();

		bJumpLatched = false;
		bPressedJump = false;

		// Keep the pawn's animation state roughly in sync.
		UpdateMoveAnimation();

		// Drive footsteps ourselves, since AWDude.FootstepTimer drops every
		// sound behind an `if (Physics == PHYS_Walking)` test.
		UpdateFootSteps(DeltaTime);

		// Apply fall damage if PM_CheckFalling detected a hard landing this frame. Valve
		// splits this across pm_shared (punch) and player.cpp (damage); the sim wrote
		// LandFallVelocity, we read it once here and zero it so it cannot fire twice.
		if (Move.LandFallVelocity > 0.0)
		{
			ApplyFallDamage(Move.LandFallVelocity);
			Move.LandFallVelocity = 0.0;
		}

		// The simulation has now chosen a height of its own, so the pin has done
		// its job and must not outlive this frame -- holding it any longer would
		// fight our own gravity.
		bZPinned = false;

		// Last thing in the frame: if we have been standing still long enough to
		// count as having complied, let the police re-read the situation. The pawn
		// never leaves PHYS_None; see DriveArrestAI.
		DriveArrestAI(DeltaTime);

		UpdateDriftReadout(DeltaTime);
	}

	// Suppress the stock acceleration path entirely.
	function ProcessMove(float DeltaTime, vector NewAccel, eDoubleClickDir DoubleClickMove, rotator DeltaRot)
	{
	}
}

// Ladders.
final function SyncLadderState()
{
	local LadderVolume L, Best;

	if (Move == None || Pawn == None)
		return;

	// Still gliding away from a ladder we just jumped off.
	if (Move.ladderEjectTime > 0)
	{
		Move.onladder = false;
		HeldLadder    = None;
		return;
	}

	// Respect a map or mutator that has genuinely banned climbing for this
	// pawn. Our own state clears the live flag, so the default is the honest
	// answer here.
	if (!Pawn.default.bCanClimbLadders)
	{
		Move.onladder = false;
		HeldLadder    = None;
		return;
	}

	ForEach Pawn.TouchingActors(class'LadderVolume', L)
	{
		// One test, whether this is a fresh grab or the ladder we are already on
		// (see CanUseLadder). Touching the volume is only how a candidate gets
		// this far -- it is not, by itself, enough to be on the ladder.
		if (!CanUseLadder(L))
			continue;

		// Already climbing this one: hold on.
		if (L == HeldLadder)
		{
			Best = L;
			break;
		}

		if (Best == None)
			Best = L;
	}

	if (Best == None)
	{
		Move.onladder = false;
		HeldLadder    = None;
		return;
	}

	HeldLadder    = Best;
	Move.onladder = true;

	// NEGATED. LookDir points INTO the wall (it is the direction you must face to
	// climb), while Valve's trace.plane.normal points OUT of it, and every line of
	// PM_LadderMove is written against that orientation. Feeding LookDir straight
	// through is what made the jump shove the player forwards into the ladder.
	Move.ladderNormal = -Normal(Best.LookDir);
}

// Are we on this ladder?
final function bool CanUseLadder(LadderVolume L)
{
	local vector Bottom, Top;

	if (Pawn == None || L == None)
		return false;

	if (LadderExtent(L, Bottom, Top))
		return OnLadderExtent(Bottom, Top);

	// No nav points -- an unbuilt path, or a volume the builder never gave any. Fall
	// back to the volume, where EITHER test is enough because each covers the other's
	// blind spot: Encompasses wants the pawn's CENTRE inside, and the wall probe finds
	// nothing when the ladder is freestanding.
	return L.Encompasses(Pawn) || NearLadderWall(L);
}

// The ladder's real extent, from the Ladder actors that mark it.
final function bool LadderExtent(LadderVolume L, out vector Bottom, out vector Top)
{
	local Ladder Node;
	local int    Count;

	if (L == None)
		return false;

	// Guard the walk on Count: LadderList is native-built and const, and a cycle in it
	// would hang the game rather than misplace a ladder. The lowest and the highest
	// node give the axis, slope included -- a non-autopath ladder can be sloped.
	for (Node = L.LadderList; Node != None && Count < 64; Node = Node.LadderList)
	{
		if (Count == 0 || Node.Location.Z < Bottom.Z)
			Bottom = Node.Location;

		if (Count == 0 || Node.Location.Z > Top.Z)
			Top = Node.Location;

		Count++;
	}

	return Count >= 2;
}

// Is the pawn on the span LadderExtent found?
final function bool OnLadderExtent(vector Bottom, vector Top)
{
	local vector Flat, Seg;

	if (Pawn.Location.Z + Pawn.CollisionHeight < Bottom.Z - LADDER_END_SLACK
		|| Pawn.Location.Z - Pawn.CollisionHeight > Top.Z + LADDER_END_SLACK)
		return false;

	Seg    = Top - Bottom;
	Seg.Z  = 0;
	Flat   = Pawn.Location - Bottom;
	Flat.Z = 0;

	if (VSize(Seg) > 1.0)
		Flat -= Seg * FClamp((Flat Dot Seg) / (Seg Dot Seg), 0.0, 1.0);

	return VSize(Flat) <= Pawn.CollisionRadius + LADDER_AXIS_REACH;
}

// Are we actually AT the ladder wall?  (Fallback only -- see CanUseLadder.)
final function bool NearLadderWall(LadderVolume L)
{
	local vector HitLocation, HitNormal, Dir, Start, End;
	local float  Reach;

	if (Pawn == None || L == None)
		return false;

	// A vertical ladder mounted on a wall: probe horizontally.  For the odd
	// ceiling/floor hatch (LookDir.Z != 0) skip the probe rather than guess.
	Dir = Normal(L.LookDir);
	if (Abs(Dir.Z) > 0.7)
		return true;

	Reach = Pawn.CollisionRadius + 24.0;

	Start = Pawn.Location;
	End   = Start + Dir * Reach;

	if (Pawn.Trace(HitLocation, HitNormal, End, Start, true) != None)
		return true;

	Start.Z -= Pawn.CollisionHeight * 0.5;
	End      = Start + Dir * Reach;

	return Pawn.Trace(HitLocation, HitNormal, End, Start, true) != None;
}

// Footsteps.
final function UpdateFootSteps(float DeltaTime)
{
	local AWDude D;
	local float  Speed, Interval, Vol;

	if (Pawn == None || Move == None)
		return;

	D = AWDude(Pawn);
	if (D == None)
		return;

	if (bGoldSrcFootSteps)
	{
		UpdateGoldSrcFootSteps(D);
		return;
	}

	// Airborne: no steps, and reset so landing does not instantly fire one.
	if (!Move.onground)
	{
		FootStepAccum = 0.0;
		bWasOnGround  = false;
		return;
	}

	// Horizontal speed only -- GoldSrc keeps a little Z velocity while walking
	// on slopes and that must not speed up the footstep rhythm.
	Speed = VSize(Move.velocity * vect(1,1,0));

	// Landing: play immediately, matching AWDude.Landed's behaviour.
	if (!bWasOnGround)
	{
		bWasOnGround  = true;
		FootStepAccum = 0.0;

		if (Speed > 0.0)
			D.PlayFootstep(D.LAND_VOL, D.FOOTSTEP_RADIUS);

		return;
	}

	if (Speed <= 0.0)
	{
		FootStepAccum = 0.0;
		return;
	}

	// AWDude.Tick:934 -- interval shrinks as speed rises.
	//   running: GroundSpeed / Speed * RUN_FOOTSTEP_TIME
	//   walking: GroundSpeed * WalkingPct / Speed * WALK_FOOTSTEP_TIME
	if (Move.bDucking || bRun != 0)
	{
		Interval = D.Default.GroundSpeed * D.WalkingPct / Speed * D.WALK_FOOTSTEP_TIME;
		Vol      = D.WALK_VOL;
	}
	else
	{
		Interval = D.Default.GroundSpeed / Speed * D.RUN_FOOTSTEP_TIME;
		Vol      = D.RUN_VOL;
	}

	FootStepAccum += DeltaTime;

	if (Interval > 0.0 && FootStepAccum >= Interval)
	{
		FootStepAccum = 0.0;
		D.PlayFootstep(Vol, D.FOOTSTEP_RADIUS);
	}
}

// fvol for an ordinary running step in pm_shared.c, and the value P2's RUN_VOL
// stands in for. Every other step volume is carried across as a ratio of it.
const GOLDSRC_STEP_VOL_RUN = 0.5;

// The GoldSrc cadence. All the timing lives in the simulation, in
// PM_UpdateStepSound, so what is left here is handing over the step it queued --
// P2 still owns the sample, the radius and telling the neighbours they heard you.
// GoldSrc's fvol is a fraction of full volume and P2's is an absolute scalar, so
// the two are bridged at the one point they agree on: a running step on concrete
// is fvol 0.5 there and RUN_VOL here, and everything quieter or louder scales
// off that. Wading comes out at 1.3x a run, a ducked walk at 0.07x, and both are
// in the right relation to each other, which is the part you can hear.
final function UpdateGoldSrcFootSteps(AWDude D)
{
	local float Vol;

	// Keep the stock path's edge detector fed, so flipping cl_footsteps off
	// mid-stride does not fire a landing step on the next frame.
	bWasOnGround  = Move.onground;
	FootStepAccum = 0.0;

	if (!Move.bStepSoundPending)
		return;

	Move.bStepSoundPending = false;

	if (Move.bStepSoundLanding)
		Vol = D.LAND_VOL * (Move.StepSoundVol / GOLDSRC_STEP_VOL_RUN);
	else
		Vol = D.RUN_VOL * (Move.StepSoundVol / GOLDSRC_STEP_VOL_RUN);

	if (Vol > 0.0)
		D.PlayFootstep(Vol, D.FOOTSTEP_RADIUS);
}

// ApplyFallDamage
final function ApplyFallDamage(float HLFallVel)
{
	local float Dmg;

	if (Pawn == None || Move == None)
		return;

	Dmg = Move.PM_PlayerFallDamage(HLFallVel);
	if (Dmg > 0.0)
		Pawn.TakeDamage(int(Dmg), None, Pawn.Location, vect(0,0,0), class'Fell');
}

// V_CalcRoll    (cl_dll/view.cpp:214)
// Used by view and sv_user
//
// Degrees of roll for the sideways part of the current velocity. Valve takes the
// right vector straight from the view angles; pitch has no business in a
// horizontal dot product, so ours comes off the yaw alone -- which is also what
// keeps looking at the sky from quietly unrolling the lean.
final function float V_CalcRoll(rotator angles)
{
	local vector  forward, right, up;
	local rotator flat;
	local float   sign, side, value, rollspeed;

	flat.Yaw = angles.Yaw;
	GetAxes(flat, forward, right, up);

	side = Move.velocity Dot right;
	if (side < 0)
		sign = -1;
	else
		sign = 1;
	side = Abs(side);

	// cl_rollspeed is in HL units/sec like every other speed the player types.
	rollspeed = FMax(ViewRollSpeed * Move.WorldScale, 0.0001);

	value = ViewRollAngle;
	if (side < rollspeed)
		side = side * value / rollspeed;
	else
		side = value;

	return side * sign;
}

// CalcFirstPersonView
function CalcFirstPersonView(out vector CameraLocation, out rotator CameraRotation)
{
	local rotator Punch;
	local float   steptime, simorgZ, WS;

	Super.CalcFirstPersonView(CameraLocation, CameraRotation);

	if (!bGoldSrcMovement || Move == None || Pawn == None)
	{
		// Do not carry a stale lag across a mode switch.
		if (Pawn != None)
			StepSmoothOldZ = Pawn.Location.Z;

		StepSmoothLastTime = Level.TimeSeconds;
		StepSmoothShift    = 0.0;
		return;
	}

	if (VSize(Move.punchangle) >= 0.001)
	{
		Punch.Pitch = int(Move.punchangle.X * 182.044);
		Punch.Yaw   = int(Move.punchangle.Y * 182.044);
		Punch.Roll  = int(Move.punchangle.Z * 182.044);

		CameraRotation = Normalize(CameraRotation + Punch);
	}

	// Roll is induced by movement    (cl_dll/view.cpp:404, V_CalcViewRoll)
	if (ViewRollAngle != 0.0)
		CameraRotation.Roll += int(V_CalcRoll(CameraRotation) * 182.044);

	// smooth out stair step ups   (cl_dll/view.cpp:697)
	WS      = FMax(Move.WorldScale, 0.0001);
	simorgZ = Pawn.Location.Z;

	if (Move.onground && simorgZ - StepSmoothOldZ > 0)
	{
		steptime = Level.TimeSeconds - StepSmoothLastTime;
		if (steptime < 0)
			steptime = 0;

		StepSmoothOldZ += steptime * STEP_SMOOTH_SPEED * WS;

		if (StepSmoothOldZ > simorgZ)
			StepSmoothOldZ = simorgZ;

		if (simorgZ - StepSmoothOldZ > STEP_SMOOTH_MAX * WS)
			StepSmoothOldZ = simorgZ - STEP_SMOOTH_MAX * WS;

		// view.cpp:713. The gun half of the same shift is applied by GoldSrcHUD,
		// which is where this mod owns the view model offset.
		StepSmoothShift = StepSmoothOldZ - simorgZ;

		CameraLocation.Z += StepSmoothShift;
	}
	else
	{
		StepSmoothOldZ  = simorgZ;
		StepSmoothShift = 0.0;
	}

	StepSmoothLastTime = Level.TimeSeconds;
}

// POSTAL 2 sends the player to the STOCK PlayerWalking state from 12 different
// places in P2Player.uc -- taking damage, closing the map screen, ending a
// cutscene, leaving the sniping state. None of them know about ours.
function PlayerTick(float DeltaTime)
{
	// Reclaim PHYS_None BEFORE Super.PlayerTick, which dispatches into native
	// movement. P2Pawn.TakeDamage does `if (Physics == PHYS_None) SetMovementPhysics()`
	// (:2327), stomping us to PHYS_Walking mid-damage-call, and the pawn's native tick
	// can then walk-step and floor-snap against a hull it did not size -- that is the
	// "welded to the ground after taking damage" bug. Reclaiming here, at the very
	// first line of the tick, beats that race outright.
	if (bGoldSrcMovement && Pawn != None
		&& GetStateName() == 'PlayerGoldSrcWalking'
		&& Pawn.Physics != PHYS_None)
	{
		ReclaimPawn();
	}

	Super.PlayerTick(DeltaTime);

	// Must be an EXACT state test. P2 has eight states that extend PlayerWalking
	// (PlayerSniping, PlayerGettingMugged, PlayerPrepSave, ...) and IsInState() walks
	// the inheritance chain, so it would rip the player out of every one of them.
	if (bGoldSrcMovement && Pawn != None && IsStockMovementState(GetStateName()))
		GotoState('PlayerGoldSrcWalking');

	// The frame's last word on the physics mode. Everything above has finished with the
	// pawn, so whatever it reads now is what the pawn's OWN tick will run -- and
	// PHYS_None is the only answer that means the simulation owns this. See
	// HoldPhysNone for the base-loss route that keeps taking it.
	if (bGoldSrcMovement && GetStateName() == 'PlayerGoldSrcWalking')
		HoldPhysNone();
}

// The stock movement states we take back, tested by EXACT name (see the
// caller's note on why IsInState is unusable here).
final function bool IsStockMovementState(name S)
{
	return S == 'PlayerWalking'
		|| S == 'PlayerClimbing'
		|| S == 'PlayerStartSwimming'
		|| S == 'PlayerSwimming';
}

// Nudge the pawn's animation to match the simulated movement, since
// PHYS_None means the engine will not do it for us.
final function UpdateMoveAnimation()
{
	if (Pawn == None || Move == None)
		return;

	// Give the anim code a plausible ground speed to blend against.
	Pawn.GroundSpeed = Move.sv_maxspeed;
}

defaultproperties
{
	bGoldSrcMovement=true
	bShowSpeedometer=true
	bShowMoveDebug=false
	bShowNetGraph=false
	bShowPos=false
	bViewModelBob=true
	ViewModelBobScale=1.0
	bViewModelSway=true
	ViewModelSwayScale=1.0
	bViewModelSwayPitch=true
	bForceDualWield=false
	ViewRollAngle=0.65          // Half-Life's own cl_rollangle
	ViewRollSpeed=300.0         // Half-Life's own cl_rollspeed
	bGoldSrcFootSteps=true
	bDamageIndicator=true
	JumpDuckAxisSpeed=1200.0
	MoveAxisMax=1200.0
	DuckPulseSeconds=0.12
}
