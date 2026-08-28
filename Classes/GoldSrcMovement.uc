// heres where the fun starts
class GoldSrcMovement extends Object;

const STOP_EPSILON              = 0.1;      
const MAX_CLIP_PLANES           = 5;       
const PLAYER_DUCKING_MULTIPLIER = 0.333;   
const TIME_TO_DUCK              = 0.4;      
const BUNNYJUMP_MAX_SPEED_FACTOR = 1.7;     // all values taken from pm_shared.c
const PM_CHECKSTUCK_MINTIME     = 0.05;     // pm_shared.c:1628

// HL hull dimensions (pm_shared.c lines 77-86).  These are scaled at runtime anyway.
const HL_VEC_HULL_MIN           = -36.0;
const HL_VEC_HULL_MAX           = 36.0;
const HL_VEC_VIEW               = 28.0;
const HL_VEC_DUCK_HULL_MIN      = -18.0;
const HL_VEC_DUCK_HULL_MAX      = 18.0;
const HL_VEC_DUCK_VIEW          = 12.0;

// The HL player hull is a 32x32 box, radius is 16 units.
const HL_HULL_RADIUS            = 16.0;

// Ground trace slope cosine.  A plane whose normal Z is below this is too
// steep to stand on.  Dimensionless, never scaled.
const PM_MAX_CLIMB_NORMAL       = 0.7;

// Half-Life's jump is defined as sqrt(2 * 800 * 45) so exactly enough
// velocity to rise 45 units under 800 gravity.  We keep it expressed that
// way so it stays correct when gravity/scale are retuned. (pm_shared.c:2594)
const HL_JUMP_HEIGHT            = 45.0;
const HL_REFERENCE_GRAVITY      = 800.0;

// Air acceleration wishspeed cap. (pm_shared.c:1288)
const HL_AIR_ACCEL_CAP          = 30.0;

// Movement command magnitude. HL clamps forwardmove/sidemove to +-400.
const HL_MAX_MOVE_CMD           = 400.0;

// --- Water (pm_shared.c PM_WaterMove / PM_Jump / PM_CheckWaterJump) ------

// Drift towards the bottom when no movement key is held. (pm_shared.c:1336)
const HL_WATER_SINK_SPEED       = 60.0;

// Swimming is deliberately slower than running. Dimensionless. (pm_shared.c:1351)
const HL_WATER_SPEED_FACTOR     = 0.8;

// Upward nudge per frame while the jump button is held underwater, i.e. the
// "swim up" that does not need a ledge. (pm_shared.c:2510)
const HL_WATER_JUMP_UP_SPEED    = 100.0;

// Water-jump (the mantle out of a pool onto a ledge). (pm_shared.c:2614)
const WJ_HEIGHT                 = 8.0;      // probe height above the origin
const HL_WJ_TRACE_DIST          = 24.0;     // how far forward we look for a wall
const HL_WJ_GLIDE_SPEED         = 50.0;     // pushed along -normal while gliding
const HL_WJ_UP_SPEED            = 225.0;    // the hop itself
const HL_WJ_TIME                = 2000.0;   // ms the glide lasts
const HL_WJ_MAX_TIME            = 10000.0;  // sanity clamp (pm_shared.c:2224)
const HL_WJ_SINK_CUTOFF         = 180.0;    // don't hop out if falling faster
const HL_WJ_WALL_NORMAL_Z       = 0.1;      // |normal.z| below this = vertical wall

// --- Landing: screen punch and fall damage (dlls/player.h:22-26) --------

// approx 60 feet -- the speed at which a fall does a full 100 damage.
const PLAYER_FATAL_FALL_SPEED        = 1024.0;

// approx 20 feet -- below this a fall is free.
const PLAYER_MAX_SAFE_FALL_SPEED     = 580.0;

// Damage per unit/sec of fall beyond the safe speed: 100 / (1024 - 580).
const DAMAGE_FOR_FALL_SPEED          = 0.2252252;

// Under this the landing is silent and does not punch the view.
const PLAYER_MIN_BOUNCE_SPEED        = 200.0;

// Won't punch the player's screen / make a scrape noise unless falling at
// least this fast.
const PLAYER_FALL_PUNCH_THRESHHOLD   = 350.0;

// pm_shared.c:2733 -- punchangle[2] = flFallVelocity * 0.013. Degrees per
// HL unit/sec, so dimensionless in our terms and left unscaled.
const HL_FALL_PUNCH_SCALE            = 0.013;

// pm_shared.c:2735 -- the pitch punch is clamped to this.
const HL_FALL_PUNCH_PITCH_MAX        = 8.0;

// cl_dll/view.cpp:1681 -- V_DropPunchAngle decays the punch by
// (10 + len * 0.5) * frametime per frame, along its own axis.
const HL_PUNCH_DECAY_BASE            = 10.0;
const HL_PUNCH_DECAY_RATE            = 0.5;

// sv_falldamage 1: flat damage regardless of how far you fell.
const HL_LESSER_FALL_DAMAGE          = 10.0;

// --- Ladders (pm_shared.c PM_LadderMove) --------------------------------

// Climb speed, clamped to maxspeed. (pm_shared.c:81)
const MAX_CLIMB_SPEED           = 200.0;

// Speed of the shove away from the ladder when you jump off. (pm_shared.c:2133)
const HL_LADDER_JUMP_SPEED      = 270.0;

// --- Footstep cadence (pm_shared.c PM_UpdateStepSound) -------------------

// Below velwalk no step plays at all; above velrun it is a run rather than a
// walk. The second pair is what a ducked player or a climber uses instead.
const HL_STEP_VELWALK           = 120.0;
const HL_STEP_VELRUN            = 210.0;
const HL_STEP_VELWALK_DUCKED    = 60.0;
const HL_STEP_VELRUN_DUCKED     = 80.0;

// flduck: extra milliseconds between steps while ducking. (pm_shared.c:530)
const HL_STEP_DUCK_DELAY        = 100.0;

// Milliseconds between steps, and the volume each plays at as a fraction of
// full. (pm_shared.c:560-618)
const HL_STEP_TIME_WALK         = 400.0;
const HL_STEP_TIME_RUN          = 300.0;
const HL_STEP_TIME_LADDER       = 350.0;
const HL_STEP_TIME_WADE         = 600.0;
const HL_STEP_VOL_WALK          = 0.2;
const HL_STEP_VOL_RUN           = 0.5;
const HL_STEP_VOL_LADDER        = 0.35;
const HL_STEP_VOL_WADE          = 0.65;

// 35% volume if ducking. (pm_shared.c:628)
const HL_STEP_DUCK_VOL_SCALE    = 0.35;

// Where the knee sits, as a fraction of the hull height below the origin. Valve
// probes brush contents there to tell wading from walking. (pm_shared.c:554)
const HL_STEP_KNEE_FRAC         = 0.3;

// --- ABH: Half-Life 2's jump speed boost --------------------------------
// (SDK 2013 game/shared/gamemovement.cpp:2465, the tail of CheckJumpButton)

// The fraction of forwardmove handed out as a bonus, and the fraction of
// maxspeed the bonus is allowed to reach. Ducked takes the small one; so does
// sprinting in HL2, which POSTAL 2 has no equivalent of.
const HL2_JUMP_BOOST_PERC       = 0.5;
const HL2_JUMP_BOOST_PERC_DUCK  = 0.1;

// Movement variables - the sv_* cvars from movevars_t (pm_movevars.h)

var config float WorldScale;        // P2 units per HL unit. 2.0.

var config float sv_maxspeed;       // 320 * scale
var config float sv_accelerate;     // 10   (dimensionless)
var config float sv_airaccelerate;  // 10   (dimensionless)
var config float sv_friction;       // 4    (dimensionless)
var config float sv_stopspeed;      // 100 * scale
var config float sv_gravity;        // 800 * scale
var config float sv_stepsize;       // 18  * scale, minus 1 for P2 stairs
var config float sv_maxvelocity;    // 2000 * scale
var config float sv_edgefriction;   // 2    (dimensionless)
var config float sv_bounce;         // 1    (dimensionless)

// HL's own anti-bunnyhop clamp is off by default. Stock GoldSrc calls this
// from PM_Jump, but it is what prevents unlimited bhop accel, so we gate it.
var config bool  sv_enablebunnyhopcap;

// Enabling this makes every hop frame-perfect, which is a different game
// feel (close to like a scripted run of HL with bxt_autojump on), so it is off
// by default and exists purely as a convenience toggle.
var config bool  sv_autobunnyhop;

// Accelerated Back Hopping, from Half-Life 2. Not GoldSrc behaviour either --
// see PM_ABHJumpBoost for the arithmetic and why holding the wrong direction is
// the thing that pays.
var config bool  sv_enableabh;

// Hull radius in HL units, so it doubles on use. 0 means automatic. 10 (=20
// scaled) is the widest box that fits everywhere P2's 28-radius cylinder does,
// because a box only clears a diagonal gap up to radius/sqrt(2).
var config float sv_hullradius;

// Whether world geometry has to carry the block flags like everything else.
var config bool  sv_strictblocking;

// Take the player's physical dimensions from POSTAL 2 instead of from
// Half-Life.
var config bool  sv_usep2hull;

// Filled in from the pawn's class defaults by SyncP2HullDims(). Zero means
// "not resolved yet", in which case the HL constants are used.
var float P2HullHeight;             // standing half height  (CollisionHeight)
var float P2DuckHullHeight;         // crouched half height  (CrouchHeight)
var float P2HullRadius;             // standing radius       (CollisionRadius)
var float P2ViewOfs;                // eye height above origin
var float P2DuckViewOfs;            // crouched eye height above origin

// Movement state -- the fields of playermove_t we actually need

var Pawn        PM;                 // The pawn being moved
var Actor       TraceOwner;         // Actor used to run traces

var vector      origin;             // pmove->origin
var vector      velocity;           // pmove->velocity
var vector      basevelocity;       // pmove->basevelocity

var vector      forward, right, up; // pmove->forward/right/up

var float       forwardmove;        // pmove->cmd.forwardmove
var float       sidemove;           // pmove->cmd.sidemove
var float       upmove;             // pmove->cmd.upmove

var bool        buttonJump;         // IN_JUMP this frame
var bool        buttonDuck;         // IN_DUCK this frame
var bool        oldbuttonJump;      // pmove->oldbuttons & IN_JUMP
var bool        oldbuttonDuck;      // pmove->oldbuttons & IN_DUCK

var bool        onground;           // pmove->onground != -1
var Actor       groundEntity;       // what we are standing on

var bool        bInDuck;            // pmove->bInDuck
var bool        bDucking;           // pmove->flags & FL_DUCKING
var float       flDuckTime;         // pmove->flDuckTime (milliseconds)
var int         usehull;            // 0 = standing, 1 = ducked
var float       view_ofs;           // pmove->view_ofs[2]

// Ducktap (Bunnymod XT's +bxt_ducktap). Not in pm_shared.c: like sv_autobunnyhop
// it drives buttonDuck the way a player's finger would, rather than changing the
// movement code.
var bool        buttonDuckTap;      // ducktap bind held this frame
var bool        ducktapOnce;        // one-shot request from the ducktap command
var bool        ducktapPressed;     // press issued; release it next frame

var float       frametime;          // pmove->frametime (seconds)
var float       friction;           // pmove->friction (entity friction, 1.0)
var float       gravityScale;       // pmove->gravity (entity gravity, 1.0)
var float       maxspeed;           // pmove->maxspeed
var bool        dead;

var float       flFallVelocity;     // for landing detection

// Screen punch (pmove->punchangle). X = pitch, Y = yaw, Z = roll, in DEGREES,
// matching HL's vec3_t angle order rather than Unreal's rotator.
var vector      punchangle;

// Speed of the landing PM_CheckFalling just processed, in HL units/sec, or 0 if
// we did not land hard. The controller reads it once a frame to apply fall
// damage; Valve splits it the same way, punch here and damage in player.cpp.
var float       LandFallVelocity;

// Footstep cadence (pmove->flTimeStepSound). The rhythm is ours, the sound is
// not: PM_PlayStepSound only leaves a step pending here, and the controller
// hands it to AWDude.PlayFootstep, which is what knows the material.
var float       flTimeStepSound;    // ms until the next step is allowed
var bool        bStepSoundPending;  // a step is due; the controller clears it
var float       StepSoundVol;       // fvol, 0..1
var bool        bStepSoundLanding;  // came from PM_CheckFalling, not the cadence

// --- Debug / telemetry (read by the HUD) -------------------------------
var vector      DebugWishDir;
var float       DebugWishSpeed;
var float       DebugTakeoffSpeed;  // horizontal speed at moment of jump
var string      DebugMoveState;
var vector      DebugLastPush;      // velocity the last damage frame added
var float       DebugLastPushTime;  // Level.TimeSeconds it landed

// The last thing that stopped a move sideways or upwards, i.e. the answer to
// "what am I walking into that I cannot see". Written by PM_PlayerTrace, read by
// the movedebug overlay, and by nothing in the simulation itself.
var Actor       BlockActor;
var string      BlockName;          // resolved once, at the moment it is recorded
var string      BlockClass;
var vector      BlockNormal;
var float       BlockTime;          // Level.TimeSeconds it was recorded
var bool        BlockHidden;        // bHidden: invisible, so unfindable by eye
var bool        BlockWorldGeo;      // bWorldGeometry: BSP, terrain, mesh or volume
var bool        BlockIsVolume;      // a brush volume rather than a mesh or the world
var bool        BlockProbe;         // found by an embedded check, not a swept move

// --- Trace results (output of PM_PlayerTrace) --------------------------
// UnrealScript requires all vars to be declared before any function.
var float       TraceFraction;
var vector      TraceEndPos;
var vector      TracePlaneNormal;
var Actor       TraceHitActor;
var bool        TraceStartSolid;
var bool        TraceAllSolid;

// Unstick support (pm_shared.c:146 rgv3tStuckTable, :3198 PM_CreateStuckTable).
var vector      StuckTable[54];
var bool        bStuckTableInit;
var int         StuckLast;          // rgStuckLast[][]
var bool        bWasStuck;          // for the HUD/debug readout
var int         StuckFrames;        // consecutive frames reported stuck
var int         WeldNudges;         // times PM_WalkMove had to break a flush weld

// Safety valve. PM_CheckStuck refusing to move is correct GoldSrc behaviour, but
// it trusts a zero-length trace to report "inside solid". After this many
// consecutive stuck frames we give up and move anyway rather than freeze.
var config int  sv_maxstuckframes;

// Fall damage mode.
var config int  sv_falldamage;

// Scale on the knockback a hit adds to the simulation, for NON-explosive damage
// only (see GoldSrcPlayer.DamageKnockback).
var config float sv_knockback;

// Scale on EXPLOSIVE knockback (GoldSrcPlayer.DamageKnockback).
var config float sv_explosionknockback;

// Ceiling on the velocity one frame of damage may add, in P2 units per second.
var config float sv_maxdamagepush;

// Touch list (pm_shared.c:642 PM_AddToTouched). SetLocation() is a teleport, so
// Unreal never generates the Bump()/Touch() a swept move would; like GoldSrc we
// record what the traces hit and dispatch it after the move. Without this,
// walking into a POSTAL 2 door never opens it. Only the actor is kept -- Bump()
// needs nothing else.
var Actor       TouchedActors[16];      // MAX_PHYSENTS equivalent
var int         NumTouch;

// Water state (playermove_t waterlevel / watertype / waterjumptime)
var int         waterlevel;         // pmove->waterlevel, 0..3

// World Z of the surface waterlevel was measured against, or a large negative
// number when dry. Not a Valve field: they re-probe brush contents at the knee
// in PM_UpdateStepSound, and one latched height answers the same question
// without a second search.
var float       waterSurfaceZ;

// Water-jump latch. Non-zero means "gliding out of the water onto a ledge",
// during which the horizontal velocity is pinned to waterjumpMovedir so the
// player cannot steer back off the ledge mid-mantle. Milliseconds.
var float       waterjumptime;      // pmove->waterjumptime
var vector      waterjumpMovedir;   // pmove->movedir

// Cache for the volume SEARCH half of PM_CheckWater. Not a Valve field: theirs
// is three point tests against an already-loaded BSP, ours has to ask the engine
// for the pawn's touching volumes, and that runs two to four times a frame for an
// answer that cannot change until the pawn MOVES. Keyed on the pawn's location,
// so it refreshes itself and there is no invalidation call to forget.
var Pawn          WaterScanPawn;
var PhysicsVolume WaterScanVolume;
var vector        WaterScanOrigin;
var bool          bWaterScanValid;

// Per-frame cost counters for the movedebug readout -- traces are the only
// expensive thing here, so the count belongs on screen. Both hold the PREVIOUS
// frame's total, snapshotted at the top of PM_PlayerMove.
var int         TraceCount;         // native Trace() calls, frame in progress
var int         TracesPerFrame;     // native Trace() calls, frame just finished
var int         WaterScans;         // volume searches, frame in progress
var int         WaterScansPerFrame; // volume searches, frame just finished

// Ladder state
var bool        onladder;           // pLadder != NULL
// trace.plane.normal: points OUT of the wall, towards the player -- the negation
// of LadderVolume.LookDir, which points into it. The controller flips the sign
// when it fills this in. Get it wrong and jump shoves you into the ladder.
var vector      ladderNormal;

// Per-axis ladder input, -1..1, straight off the raw axes.
var float       ladderForwardFrac;
var float       ladderSideFrac;

// Jumping off a ladder throws the player out at 270 units, but the LadderVolume
// is much bigger than the ladder brush GoldSrc would have traced, so we stay
// inside it for several frames. Without a latch PM_LadderMove re-grabs and kills
// the jump in midair, so blank the ladder for a moment and let the eject leave.
var float       ladderEjectTime;    // milliseconds

// Full view basis, pitch included (Valve's AngleVectors of pmove->angles).
var vector      viewForward, viewRight, viewUp;

// Scaled accessors.  Length constants scale; dimensionless ones do not.

// Resolve P2's dimensions off the pawn's class defaults. Cheap, and re-run
// whenever the pawn changes, because DrawScale-adjusted pawns (Leprechaun) and
// the various P2 player classes do not all share one size.
final function SyncP2HullDims()
{
	if (PM == None)
		return;

	P2HullHeight     = PM.Default.CollisionHeight;
	P2HullRadius     = PM.Default.CollisionRadius;
	P2DuckHullHeight = PM.Default.CrouchHeight;
	P2ViewOfs        = PM.Default.EyeHeight;

	// CrouchRadius is 0 on some pawns; Pawn.uc's own crouch path falls back to
	// the standing radius in that case.
	if (P2DuckHullHeight <= 0.0)
		P2DuckHullHeight = P2HullHeight * 0.5;

	// P2 has no separate crouched eye height. Keep the eye the same distance
	// below the top of the hull as it is when standing, which is what the
	// stock crouch interpolation converges to.
	P2DuckViewOfs = P2ViewOfs - (P2HullHeight - P2DuckHullHeight);

	if (P2DuckViewOfs > P2DuckHullHeight)
		P2DuckViewOfs = P2DuckHullHeight;
}

// True only once SyncP2HullDims has resolved a usable standing height.
final function bool UsingP2Hull()
{
	return sv_usep2hull && P2HullHeight > 0.0;
}

final function float HullMin()
{
	if (UsingP2Hull())
		return -P2HullHeight;
	return HL_VEC_HULL_MIN * WorldScale;
}

final function float HullMax()
{
	if (UsingP2Hull())
		return P2HullHeight;
	return HL_VEC_HULL_MAX * WorldScale;
}

final function float DuckHullMin()
{
	if (UsingP2Hull())
		return -P2DuckHullHeight;
	return HL_VEC_DUCK_HULL_MIN * WorldScale;
}

final function float DuckHullMax()
{
	if (UsingP2Hull())
		return P2DuckHullHeight;
	return HL_VEC_DUCK_HULL_MAX * WorldScale;
}

final function float ViewOfs()
{
	if (UsingP2Hull())
		return P2ViewOfs;
	return HL_VEC_VIEW * WorldScale;
}

final function float DuckViewOfs()
{
	if (UsingP2Hull())
		return P2DuckViewOfs;
	return HL_VEC_DUCK_VIEW * WorldScale;
}

final function float HullRadius()
{
	// An explicit sv_hullradius always wins, so the snag workaround keeps
	// working in either mode.
	if (sv_hullradius > 0)
		return sv_hullradius * WorldScale;
	if (UsingP2Hull())
		return P2HullRadius;
	return HL_HULL_RADIUS * WorldScale;
}
// Half-height of the current hull.
final function float HullHalfHeight()
{
	if (usehull == 2)
		return 0.0;             // point hull
	if (usehull == 1)
		return (DuckHullMax() - DuckHullMin()) * 0.5;
	return (HullMax() - HullMin()) * 0.5;
}

// Half-height of a hull we are NOT currently in, without disturbing the one we
// are. Callers that have to know where a hull change will leave the origin need
// this before committing to the change; see GoldSrcPlayer.HullFitsAfterSync.
final function float HullHalfHeightFor(int TestHull)
{
	local int   SavedHull;
	local float H;

	SavedHull = usehull;
	usehull   = TestHull;
	H         = HullHalfHeight();
	usehull   = SavedHull;

	return H;
}

// The box extent handed to Trace(). Unreal traces from the *centre* of the
// box, whereas GoldSrc traces from the player's origin (which sits at the
// centre of the hull too), so these line up directly.
final function vector HullExtent()
{
	local vector E;

	if (usehull == 2)
		return vect(0,0,0);

	E.X = HullRadius();
	E.Y = HullRadius();
	E.Z = HullHalfHeight();
	return E;
}

// This is the ONLY function that is not a direct port; it maps GoldSrc's
// hull trace onto Unreal's Trace(). Everything else is pure HL math.

// Clearance kept off every impact point.
const PM_TRACE_EPSILON = 0.25;      // HL units of clearance kept off every impact

// Unreal's Trace() returns every actor with bCollideActors set, which includes
// triggers, pickups, decorations and volumes; GoldSrc's PM_PlayerTrace only ever
// reports SOLID geometry. Anything non-blocking is treated as empty space.
final function bool BlocksPlayer(Actor A)
{
	if (A == None)
		return false;

	// Never collide with ourselves.
	if (A == PM || A == TraceOwner)
		return false;

	// The world itself. BSP comes back as the LevelInfo, terrain as its
	// TerrainInfo, and neither one sets a block flag it could be tested on.
	if (A == TraceOwner.Level || LevelInfo(A) != None || TerrainInfo(A) != None)
		return true;

	// The old rule, kept only as an A/B switch.
	if (!sv_strictblocking && A.bWorldGeometry)
		return true;

	// Otherwise it has to block players AND actors, the way the engine reads it.
	return (A.bBlockPlayers && A.bBlockActors);
}

// Remember the last thing that walled a move off, for the movedebug overlay's
// "touch" row. Diagnostic only: nothing in the simulation reads any of it.
final function NoteBlocker(Actor A, vector N, optional bool bProbe)
{
	if (A == None || TraceOwner == None)
		return;

	BlockNormal = N;
	BlockTime   = TraceOwner.Level.TimeSeconds;
	BlockProbe  = bProbe;

	// Two name-to-string conversions are the only expensive part, and the identity
	// only changes when the actor does. Leaning on one wall for a second at 100fps
	// would otherwise rebuild the same two strings a hundred times over.
	if (A == BlockActor)
		return;

	BlockActor    = A;
	BlockName     = string(A.Name);
	BlockClass    = string(A.Class.Name);
	BlockHidden   = A.bHidden;
	BlockWorldGeo = A.bWorldGeometry;
	BlockIsVolume = (Volume(A) != None);
}

final function PM_PlayerTrace(vector vStart, vector vEnd)
{
	local vector HitLocation, HitNormal, Extent, Delta, Dir;
	local vector BestNormal, IterLoc, IterNorm;
	local Actor  HitActor, BestActor, IterActor;
	local float  DistTotal, DistMoved, BestDist, Dist;

	Extent = HullExtent();
	Delta  = vEnd - vStart;

	TraceStartSolid  = false;
	TraceAllSolid    = false;
	TracePlaneNormal = vect(0,0,0);
	TraceHitActor    = None;

	DistTotal = VSize(Delta);

	// Degenerate move (used as a "is this spot free?" probe).
	if (DistTotal < 0.000001)
	{
		TraceFraction = 1.0;
		TraceEndPos   = vEnd;

		TraceCount++;
		HitActor = TraceOwner.Trace(HitLocation, HitNormal, vEnd, vStart, true, Extent);

		if (BlocksPlayer(HitActor))
		{
			TraceHitActor   = HitActor;
			TraceStartSolid = true;
			TraceAllSolid   = true;
			TraceFraction   = 0.0;

			// The whole point of the diagnostic: this branch is the one that fires
			// while the player cannot move at all.
			NoteBlocker(HitActor, vect(0,0,0), true);
		}
		return;
	}

	Dir      = Normal(Delta);
	BestDist = -1.0;

	// One native sweep settles the ordinary case. Trace() reports the NEAREST thing
	// of any kind, so if that thing is solid -- or there is nothing in the way at
	// all -- there is nothing nearer left to find.
	TraceCount++;
	HitActor = TraceOwner.Trace(HitLocation, HitNormal, vEnd, vStart, true, Extent);

	if (HitActor == None)
	{
		TraceFraction = 1.0;
		TraceEndPos   = vEnd;
		return;
	}

	if (BlocksPlayer(HitActor))
	{
		BestDist   = VSize(HitLocation - vStart);
		BestNormal = HitNormal;
		BestActor  = HitActor;
	}
	else
	{
		// A non-blocking actor is nearest, so it stands between us and whatever really
		// stops us, and Trace() will not look past it. What one of them hides is not
		// some sliver: the stock trigger cylinder is eighty units across before a level
		// designer scales it up around a doorway.
		TraceCount++;

		foreach TraceOwner.TraceActors(class'Actor', IterActor, IterLoc, IterNorm,
			vEnd, vStart, Extent)
		{
			if (BlocksPlayer(IterActor))
			{
				Dist = VSize(IterLoc - vStart);

				if (BestDist < 0.0 || Dist < BestDist)
				{
					BestDist   = Dist;
					BestNormal = IterNorm;
					BestActor  = IterActor;
				}
			}
		}

		TraceCount++;
		HitActor = TraceOwner.Trace(HitLocation, HitNormal, vEnd, vStart, false, Extent);

		// Filter it like every other hit. BlocksPlayer is this file's only
		// definition of solid, and a non-blocking hit must not become a wall here
		// when the engine's own movement would have let us through it.
		if (BlocksPlayer(HitActor))
		{
			Dist = VSize(HitLocation - vStart);

			if (BestDist < 0.0 || Dist < BestDist)
			{
				BestDist   = Dist;
				BestNormal = HitNormal;
				BestActor  = HitActor;
			}
		}
	}

	// Nothing solid anywhere along the span.
	if (BestActor == None)
	{
		TraceFraction = 1.0;
		TraceEndPos   = vEnd;
		return;
	}

	TraceHitActor    = BestActor;
	TracePlaneNormal = BestNormal;

	// Diagnostic only. A floor is not interesting -- the ground row already names
	// that one -- so only walls and ceilings are recorded here, which is what an
	// invisible thing you cannot walk past looks like from inside the tracer.
	if (BestNormal.Z < PM_MAX_CLIMB_NORMAL)
		NoteBlocker(BestActor, BestNormal);

	DistMoved = BestDist;

	// Keep the tracer's clearance: back the impact point off along the sweep
	// direction, never behind the start. A sweep that opens flush against a face is
	// a sweep that cannot move. See PM_TRACE_EPSILON.
	DistMoved -= PM_TRACE_EPSILON * WorldScale;

	if (DistMoved < 0.0)
		DistMoved = 0.0;

	TraceEndPos   = vStart + Dir * DistMoved;
	TraceFraction = FClamp(DistMoved / DistTotal, 0.0, 1.0);

	// Unreal has no startsolid/allsolid for extent traces, so the embedded case has
	// to be recognised. A zero-length normal with no distance covered is the
	// signature but not proof -- a legal sweep that opens flush reports the same --
	// so probe the start point and know. PM_FlyMove answers allsolid by zeroing the
	// velocity, and a wrong guess there is a movement freeze.
	if (TraceFraction <= 0.0 && VSize(BestNormal) < 0.001)
	{
		TraceStartSolid = true;

		TraceCount++;
		HitActor      = TraceOwner.Trace(HitLocation, HitNormal, vStart, vStart, true, Extent);
		TraceAllSolid = BlocksPlayer(HitActor);

		if (TraceAllSolid)
			NoteBlocker(HitActor, HitNormal, true);
	}
}

// Convenience: is a point free of world geometry for our current hull?
final function bool PM_TestPlayerPosition(vector TestPos)
{
	PM_PlayerTrace(TestPos, TestPos);
	return (TraceHitActor == None);
}

// PM_AddToTouched    (pm_shared.c:642)
final function bool PM_AddToTouched(Actor HitActor, vector impactvelocity, vector normal, vector point)
{
	local int i;

	if (HitActor == None)
		return false;

	// The world itself is not an entity we need to notify.
	if (HitActor == TraceOwner || HitActor == PM)
		return false;

	for (i = 0; i < NumTouch; i++)
	{
		if (TouchedActors[i] == HitActor)
			break;
	}

	if (i != NumTouch)                  // Already in list.
		return false;

	if (NumTouch >= 16)                 // Too many entities were touched
		return false;

	TouchedActors[NumTouch]   = HitActor;
	NumTouch++;

	return true;
}

// Same test, but for an explicit hull (0 = standing, 1 = ducked) without
// disturbing the caller's usehull.
final function bool PM_TestHullPosition(vector TestPos, int TestHull)
{
	local int  savedHull;
	local bool bFree;

	savedHull = usehull;
	usehull   = TestHull;

	bFree = PM_TestPlayerPosition(TestPos);

	usehull = savedHull;
	return bFree;
}

// PM_CreateStuckTable    (pm_shared.c:3198)
final function PM_CreateStuckTable()
{
	local float x, y, z;
	local int   idx, i;
	local float zi[3];

	if (bStuckTableInit)
		return;

	idx = 0;

	// --- Little Moves ---------------------------------------------------
	x = 0; y = 0;
	// Z moves
	for (z = -0.125; z <= 0.125; z += 0.125)
	{
		StuckTable[idx] = vect(0,0,0);
		StuckTable[idx].Z = z;
		idx++;
	}

	x = 0; z = 0;
	// Y moves
	for (y = -0.125; y <= 0.125; y += 0.125)
	{
		StuckTable[idx] = vect(0,0,0);
		StuckTable[idx].Y = y;
		idx++;
	}

	y = 0; z = 0;
	// X moves
	for (x = -0.125; x <= 0.125; x += 0.125)
	{
		StuckTable[idx] = vect(0,0,0);
		StuckTable[idx].X = x;
		idx++;
	}

	// Remaining multi axis nudges.
	for (x = -0.125; x <= 0.125; x += 0.250)
	{
		for (y = -0.125; y <= 0.125; y += 0.250)
		{
			for (z = -0.125; z <= 0.125; z += 0.250)
			{
				StuckTable[idx].X = x;
				StuckTable[idx].Y = y;
				StuckTable[idx].Z = z;
				idx++;
			}
		}
	}

	// --- Big Moves ------------------------------------------------------
	x = 0; y = 0;
	zi[0] = 0.0;
	zi[1] = 1.0;
	zi[2] = 6.0;

	for (i = 0; i < 3; i++)
	{
		// Z moves
		z = zi[i];
		StuckTable[idx] = vect(0,0,0);
		StuckTable[idx].Z = z;
		idx++;
	}

	x = 0; z = 0;
	// Y moves
	for (y = -2.0; y <= 2.0; y += 2.0)
	{
		StuckTable[idx] = vect(0,0,0);
		StuckTable[idx].Y = y;
		idx++;
	}

	y = 0; z = 0;
	// X moves
	for (x = -2.0; x <= 2.0; x += 2.0)
	{
		StuckTable[idx] = vect(0,0,0);
		StuckTable[idx].X = x;
		idx++;
	}

	// Remaining multi axis nudges.
	for (i = 0; i < 3; i++)
	{
		z = zi[i];

		for (x = -2.0; x <= 2.0; x += 2.0)
		{
			for (y = -2.0; y <= 2.0; y += 2.0)
			{
				StuckTable[idx].X = x;
				StuckTable[idx].Y = y;
				StuckTable[idx].Z = z;
				idx++;
			}
		}
	}

	bStuckTableInit = true;
}

// PM_GetRandomStuckOffsets    (pm_shared.c:1603)
final function int PM_GetRandomStuckOffsets(out vector offset)
{
	local int idx;

	PM_CreateStuckTable();

	idx = StuckLast;
	StuckLast++;

	idx = idx % 54;

	// Offsets are HL units; convert to engine units.
	offset = StuckTable[idx] * WorldScale;

	return idx;
}

// pm_shared.c:1614
final function PM_ResetStuckOffsets()
{
	StuckLast = 0;
}

// PM_CheckStuck    (pm_shared.c:1630)
final function bool PM_CheckStuck()
{
	local vector base, offset, test;
	local int    i;

	// If position is okay, exit
	if (PM_TestPlayerPosition(origin))
	{
		PM_ResetStuckOffsets();
		bWasStuck   = false;
		StuckFrames = 0;
		return false;
	}

	bWasStuck = true;
	StuckFrames++;
	base      = origin;

	i = PM_GetRandomStuckOffsets(offset);

	test = base + offset;

	if (PM_TestPlayerPosition(test))
	{
		PM_ResetStuckOffsets();

		// SDK: only actually take the position for the "big" offsets.
		if (i >= 27)
			origin = test;

		return false;
	}

	// Still stuck. If the player is mashing jump or duck, try harder -- walk
	// the whole table looking for any free spot. (The SDK does the equivalent
	// forcible unstick sweep when a flailing player is stuck.)
	if (buttonJump || buttonDuck)
	{
		for (i = 0; i < 54; i++)
		{
			offset = StuckTable[i] * WorldScale;
			test   = base + offset;

			if (PM_TestPlayerPosition(test))
			{
				PM_ResetStuckOffsets();
				origin = test;
				return false;
			}
		}

		// Nothing in the table worked. As a last resort try the ducked hull,
		// which is how a player wedged under geometry gets out.
		if (usehull == 0 && PM_TestHullPosition(base, 1))
		{
			usehull  = 1;
			bDucking = true;
			bInDuck  = false;
			view_ofs = DuckViewOfs();
			return false;
		}
	}

	// Safety valve: never let the unstick logic itself become a hard freeze.
	if (sv_maxstuckframes > 0 && StuckFrames > sv_maxstuckframes)
		return false;

	return true;
}

// See if the player has a bogus velocity value.   (pm_shared.c:670)
final function PM_CheckVelocity()
{
	// Bound velocity. UnrealScript has no NaN test, so we only clamp.
	if (velocity.X >  sv_maxvelocity) velocity.X =  sv_maxvelocity;
	else if (velocity.X < -sv_maxvelocity) velocity.X = -sv_maxvelocity;

	if (velocity.Y >  sv_maxvelocity) velocity.Y =  sv_maxvelocity;
	else if (velocity.Y < -sv_maxvelocity) velocity.Y = -sv_maxvelocity;

	if (velocity.Z >  sv_maxvelocity) velocity.Z =  sv_maxvelocity;
	else if (velocity.Z < -sv_maxvelocity) velocity.Z = -sv_maxvelocity;
}

// Slide off of the impacting object.  Returns the blocked flags:
//   0x01 == floor
//   0x02 == step / wall
// (pm_shared.c:715)
final function int PM_ClipVelocity(vector inVel, vector normal, out vector outVel, float overbounce)
{
	local float backoff, changeVal, angle;
	local int   blocked;

	angle   = normal.Z;
	blocked = 0x00;                     // Assume unblocked.

	if (angle > 0)                      // Floor
		blocked = blocked | 0x01;
	if (angle == 0)                     // Vertical wall / step
		blocked = blocked | 0x02;

	// Determine how far along plane to slide based on incoming direction.
	backoff = (inVel dot normal) * overbounce;

	changeVal = normal.X * backoff;
	outVel.X  = inVel.X - changeVal;
	if (outVel.X > -STOP_EPSILON && outVel.X < STOP_EPSILON) outVel.X = 0;

	changeVal = normal.Y * backoff;
	outVel.Y  = inVel.Y - changeVal;
	if (outVel.Y > -STOP_EPSILON && outVel.Y < STOP_EPSILON) outVel.Y = 0;

	changeVal = normal.Z * backoff;
	outVel.Z  = inVel.Z - changeVal;
	if (outVel.Z > -STOP_EPSILON && outVel.Z < STOP_EPSILON) outVel.Z = 0;

	return blocked;
}

// Applies HALF a frame of gravity before the move; PM_FixupGravityVelocity does
// the other half after it, which is what makes the ballistic integration
// second-order-accurate. The 0.5 is not a bug -- see Valve's own comment.
final function PM_AddCorrectGravity()
{
	local float ent_gravity;

	if (gravityScale != 0.0)
		ent_gravity = gravityScale;
	else
		ent_gravity = 1.0;

	// Add gravity so they'll be in the correct position during movement
	// yes, this 0.5 looks wrong, but it's not.
	velocity.Z -= (ent_gravity * sv_gravity * 0.5 * frametime);
	velocity.Z += basevelocity.Z * frametime;
	basevelocity.Z = 0;

	PM_CheckVelocity();
}

// PM_FixupGravityVelocity   (pm_shared.c:769)
final function PM_FixupGravityVelocity()
{
	local float ent_gravity;

	if (gravityScale != 0.0)
		ent_gravity = gravityScale;
	else
		ent_gravity = 1.0;

	// Get the correct velocity for the end of the dt
	velocity.Z -= (ent_gravity * sv_gravity * frametime * 0.5);

	PM_CheckVelocity();
}

// The basic solid body movement clip that slides along multiple planes.
// (pm_shared.c:794)
final function int PM_FlyMove()
{
	local int     bumpcount, numbumps;
	local vector  dir;
	local float   d;
	local int     numplanes;
	local vector  planes[5];            // MAX_CLIP_PLANES
	local vector  primal_velocity, original_velocity, new_velocity;
	local int     i, j;
	local vector  endPos;
	local float   time_left, allFraction;
	local int     blocked;
	local bool    bBreak;

	numbumps  = 4;                      // Bump up to four times
	blocked   = 0;                      // Assume not blocked
	numplanes = 0;                      //  and not sliding along any planes

	original_velocity = velocity;       // Store original velocity
	primal_velocity   = velocity;

	allFraction = 0;
	time_left   = frametime;            // Total time for this movement operation.

	for (bumpcount = 0; bumpcount < numbumps; bumpcount++)
	{
		if (velocity.X == 0 && velocity.Y == 0 && velocity.Z == 0)
			break;

		// Assume we can move all the way from the current origin to the end point.
		endPos = origin + time_left * velocity;

		// See if we can make it from origin to end point.
		PM_PlayerTrace(origin, endPos);

		allFraction += TraceFraction;

		// If we started in a solid object, or we were in solid space
		// the whole way, zero out our velocity and return that we
		// are blocked by floor and wall.
		if (TraceAllSolid)
		{
			velocity = vect(0,0,0);
			return 4;
		}

		// If we moved some portion of the total distance, then
		// copy the end position into the origin and zero the plane counter.
		if (TraceFraction > 0)
		{
			origin            = TraceEndPos;
			original_velocity = velocity;
			numplanes         = 0;
		}

		// If we covered the entire distance, we are done and can return.
		if (TraceFraction == 1)
			break;

		// Save entity that blocked us (since fraction was < 1.0) for contact.
		// Add it if it's not already in the list!!!    (pm_shared.c:864)
		PM_AddToTouched(TraceHitActor, velocity, TracePlaneNormal, TraceEndPos);

		// If the plane we hit has a high z component in the normal,
		// then it's probably a floor.
		if (TracePlaneNormal.Z > PM_MAX_CLIMB_NORMAL)
			blocked = blocked | 1;      // floor

		// If the plane has a zero z component in the normal, it's a step or wall.
		if (TracePlaneNormal.Z == 0)
			blocked = blocked | 2;      // step / wall

		// Reduce amount of frametime left by total time left * fraction covered.
		time_left -= time_left * TraceFraction;

		// Did we run out of planes to clip against?
		if (numplanes >= MAX_CLIP_PLANES)
		{
			// this shouldn't really happen. Stop our movement if so.
			velocity = vect(0,0,0);
			break;
		}

		// Set up next clipping plane
		planes[numplanes] = TracePlaneNormal;
		numplanes++;

		// modify original_velocity so it parallels all of the clip planes
		if (!onground || friction != 1)     // reflect player velocity
		{
			for (i = 0; i < numplanes; i++)
			{
				if (planes[i].Z > PM_MAX_CLIMB_NORMAL)
				{
					// floor or slope
					PM_ClipVelocity(original_velocity, planes[i], new_velocity, 1);
					original_velocity = new_velocity;
				}
				else
				{
					PM_ClipVelocity(original_velocity, planes[i], new_velocity,
						1.0 + sv_bounce * (1 - friction));
				}
			}

			velocity          = new_velocity;
			original_velocity = new_velocity;
		}
		else
		{
			bBreak = false;

			for (i = 0; i < numplanes; i++)
			{
				PM_ClipVelocity(original_velocity, planes[i], velocity, 1);

				for (j = 0; j < numplanes; j++)
				{
					if (j != i)
					{
						// Are we now moving against this plane?
						if ((velocity dot planes[j]) < 0)
							break;      // not ok
					}
				}

				if (j == numplanes)     // Didn't have to clip, so we're ok
					break;
			}

			// Did we go all the way through plane set?
			if (i != numplanes)
			{
				// go along this plane
				// velocity is set in clipping call, no need to set again.
			}
			else
			{
				// go along the crease
				if (numplanes != 2)
				{
					velocity = vect(0,0,0);
					bBreak = true;
				}
				else
				{
					dir      = planes[0] cross planes[1];
					d        = dir dot velocity;
					velocity = dir * d;
				}
			}

			if (bBreak)
				break;

			// if original velocity is against the original velocity,
			// stop dead to avoid tiny oscillations in sloping corners.
			if ((velocity dot primal_velocity) <= 0)
			{
				velocity = vect(0,0,0);
				break;
			}
		}
	}

	if (allFraction == 0)
		velocity = vect(0,0,0);

	return blocked;
}

// PM_Accelerate    (pm_shared.c:986)
final function PM_Accelerate(vector wishdir, float wishspeed, float accel)
{
	local float addspeed, accelspeed, currentspeed;

	// Dead player's don't accelerate
	if (dead)
		return;

	// See if we are changing direction a bit
	currentspeed = velocity dot wishdir;

	// Reduce wishspeed by the amount of veer.
	addspeed = wishspeed - currentspeed;

	// If not going to add any speed, done.
	if (addspeed <= 0)
		return;

	// Determine amount of acceleration.
	accelspeed = accel * frametime * wishspeed * friction;

	// Cap at addspeed
	if (accelspeed > addspeed)
		accelspeed = addspeed;

	// Adjust velocity.
	velocity += accelspeed * wishdir;
}

// PM_AirAccelerate   (pm_shared.c:1275)
final function PM_AirAccelerate(vector wishdir, float wishspeed, float accel)
{
	local float addspeed, accelspeed, currentspeed, wishspd;

	if (dead)
		return;

	wishspd = wishspeed;

	// Cap speed
	if (wishspd > HL_AIR_ACCEL_CAP * WorldScale)
		wishspd = HL_AIR_ACCEL_CAP * WorldScale;

	// Determine veer amount
	currentspeed = velocity dot wishdir;

	// See how much to add
	addspeed = wishspd - currentspeed;

	// If not adding any, done.
	if (addspeed <= 0)
		return;

	// Determine acceleration speed after acceleration
	// NOTE: uses the *uncapped* wishspeed -- this is not a typo, it is
	// what makes GoldSrc air strafing work.
	accelspeed = accel * wishspeed * frametime * friction;

	// Cap it
	if (accelspeed > addspeed)
		accelspeed = addspeed;

	// Adjust pmove vel.
	velocity += accelspeed * wishdir;
}

// PM_Friction    (pm_shared.c:1198)
final function PM_Friction()
{
	local float  speed, newspeed, control, fric, drop;
	local vector newvel, startPos, stopPos;

	// Calculate speed
	speed = VSize(velocity);

	// If too slow, return
	if (speed < 0.1)
		return;

	drop = 0;

	// apply ground friction
	if (onground)
	{
		// Trace 16 units ahead (scaled) and 34 down (scaled) to see if we
		// are near a ledge; if so apply edgefriction.
		startPos.X = origin.X + (velocity.X / speed) * 16.0 * WorldScale;
		startPos.Y = origin.Y + (velocity.Y / speed) * 16.0 * WorldScale;
		startPos.Z = origin.Z - HullHalfHeight();

		stopPos.X  = startPos.X;
		stopPos.Y  = startPos.Y;
		stopPos.Z  = startPos.Z - 34.0 * WorldScale;

		// Probe for a ledge with a zero-extent (line) trace, matching HL's
		// use of a point trace here. FastTrace only reports world geometry,
		// which is exactly what we want -- triggers must not affect friction.
		if (TraceOwner.FastTrace(stopPos, startPos))
			fric = sv_friction * sv_edgefriction;
		else
			fric = sv_friction;

		fric *= friction;               // player friction

		// Bleed off some speed, but if we have less than the bleed
		// threshold, bleed the threshold amount.
		if (speed < sv_stopspeed)
			control = sv_stopspeed;
		else
			control = speed;

		// Add the amount to the drop amount.
		drop += control * fric * frametime;
	}

	// scale the velocity
	newspeed = speed - drop;
	if (newspeed < 0)
		newspeed = 0;

	// Determine proportion of old speed we are using.
	newspeed /= speed;

	// Adjust velocity according to proportion.
	newvel   = velocity * newspeed;
	velocity = newvel;
}

// PM_WalkMove    (pm_shared.c:1030)
final function PM_WalkMove()
{
	local int     clip;
	local bool    oldonground;
	local vector  wishvel, wishdir;
	local float   spd, fmove, smove, wishspeed;
	local vector  dest;
	local vector  originalPos, originalvel;
	local vector  downPos, downvel, upPos;
	local float   downdist, updist;
	local bool    bUseDown;

	// Copy movement amounts
	fmove = forwardmove;
	smove = sidemove;

	// Zero out z components of movement vectors
	forward.Z = 0;
	right.Z   = 0;

	forward = Normal(forward);          // Normalize remainder of vectors.
	right   = Normal(right);

	// Determine x and y parts of velocity
	wishvel.X = forward.X * fmove + right.X * smove;
	wishvel.Y = forward.Y * fmove + right.Y * smove;
	wishvel.Z = 0;                      // Zero out z part of velocity

	wishdir   = wishvel;                // Determine magnitude of speed of move
	wishspeed = VSize(wishdir);
	wishdir   = Normal(wishdir);

	// Clamp to server defined max speed
	if (wishspeed > maxspeed && maxspeed > 0)
	{
		wishvel   = wishvel * (maxspeed / wishspeed);
		wishspeed = maxspeed;
	}

	DebugWishDir   = wishdir;
	DebugWishSpeed = wishspeed;

	// Set pmove velocity
	velocity.Z = 0;
	PM_Accelerate(wishdir, wishspeed, sv_accelerate);
	velocity.Z = 0;

	// Add in any base velocity to the current velocity.
	velocity += basevelocity;

	spd = VSize(velocity);

	if (spd < 1.0)
	{
		velocity = vect(0,0,0);
		return;
	}

	oldonground = onground;

	// first try just moving to the destination
	dest.X = origin.X + velocity.X * frametime;
	dest.Y = origin.Y + velocity.Y * frametime;
	dest.Z = origin.Z;

	// first try moving directly to the next spot
	PM_PlayerTrace(origin, dest);

	// If we made it all the way, then copy trace end as new player position.
	if (TraceFraction == 1)
	{
		origin = TraceEndPos;
		return;
	}

	if (!oldonground)                   // Don't walk up stairs if not on ground.
		return;

	// Try sliding forward both on ground and up 16 pixels
	// take the move that goes farthest
	originalPos = origin;               // Save out original pos &
	originalvel = velocity;             //  velocity.

	// Slide move
	clip = PM_FlyMove();

	// Copy the results out
	downPos = origin;
	downvel = velocity;

	// Reset original values.
	origin   = originalPos;
	velocity = originalvel;

	// Start out up one stair height
	dest    = origin;
	dest.Z += sv_stepsize;

	PM_PlayerTrace(origin, dest);

	// If we started okay and made it part of the way at least,
	// copy the results to the movement start position and then
	// run another move try.
	if (!TraceStartSolid && !TraceAllSolid)
		origin = TraceEndPos;

	// slide move the rest of the way.
	clip = PM_FlyMove();

	// Now try going back down from the end point, press down the stepheight
	dest    = origin;
	dest.Z -= sv_stepsize;

	PM_PlayerTrace(origin, dest);

	bUseDown = false;

	// If we are not on the ground any more then use the original movement attempt
	if (TracePlaneNormal.Z < PM_MAX_CLIMB_NORMAL)
	{
		bUseDown = true;
	}
	else
	{
		// If the trace ended up in empty space, copy the end over to the origin.
		if (!TraceStartSolid && !TraceAllSolid)
			origin = TraceEndPos;

		// Copy this origin to up.
		upPos = origin;

		// decide which one went farther
		downdist = (downPos.X - originalPos.X) * (downPos.X - originalPos.X)
		         + (downPos.Y - originalPos.Y) * (downPos.Y - originalPos.Y);
		updist   = (upPos.X   - originalPos.X) * (upPos.X   - originalPos.X)
		         + (upPos.Y   - originalPos.Y) * (upPos.Y   - originalPos.Y);

		if (downdist > updist)
			bUseDown = true;
	}

	if (bUseDown)
	{
		origin   = downPos;
		velocity = downvel;
	}
	else
	{
		// copy z value from slide move
		velocity.Z = downvel.Z;
	}

	// Backend safety net, not part of the port. If the player asked to move and both
	// attempts came back at the origin, we are flush against the surface we stand on
	// and Unreal's box sweep cannot open out of it (see PM_TRACE_EPSILON). One nudge
	// up by the clearance and a retry of the flat slide breaks it; if the nudge is
	// not free we change nothing and leave it to PM_CheckStuck.
	if (wishspeed > 0.0 && origin.X == originalPos.X && origin.Y == originalPos.Y)
	{
		dest    = originalPos;
		dest.Z += PM_TRACE_EPSILON * WorldScale * 2.0;

		if (PM_TestPlayerPosition(dest))
		{
			origin   = dest;
			velocity = originalvel;

			PM_FlyMove();

			if (origin.X == originalPos.X && origin.Y == originalPos.Y)
			{
				// The nudge did not help, so it was a wall and not a weld. Put
				// the result back rather than leaving the player hovering.
				origin   = downPos;
				velocity = downvel;
			}
			else
			{
				WeldNudges++;
			}
		}
	}
}

// PM_AirMove    (pm_shared.c:1413)
final function PM_AirMove()
{
	local vector wishvel, wishdir;
	local float  fmove, smove, wishspeed;

	// Copy movement amounts
	fmove = forwardmove;
	smove = sidemove;

	// Zero out z components of movement vectors
	forward.Z = 0;
	right.Z   = 0;

	// Renormalize
	forward = Normal(forward);
	right   = Normal(right);

	// Determine x and y parts of velocity
	wishvel.X = forward.X * fmove + right.X * smove;
	wishvel.Y = forward.Y * fmove + right.Y * smove;
	wishvel.Z = 0;                      // Zero out z part of velocity

	// Determine magnitude of speed of move
	wishdir   = wishvel;
	wishspeed = VSize(wishdir);
	wishdir   = Normal(wishdir);

	// Clamp to server defined max speed
	if (wishspeed > maxspeed && maxspeed > 0)
	{
		wishvel   = wishvel * (maxspeed / wishspeed);
		wishspeed = maxspeed;
	}

	DebugWishDir   = wishdir;
	DebugWishSpeed = wishspeed;

	PM_AirAccelerate(wishdir, wishspeed, sv_airaccelerate);

	// Add in any base velocity to the current velocity.
	velocity += basevelocity;

	PM_FlyMove();
}

// PM_WaterMove    (pm_shared.c:1317)
final function PM_WaterMove()
{
	local vector wishvel, wishdir, start, dest, temp;
	local float  wishspeed, speed, newspeed, addspeed, accelspeed;

	// user intentions
	wishvel = viewForward * forwardmove + viewRight * sidemove;

	// Sinking after no other movement occurs
	if (forwardmove == 0.0 && sidemove == 0.0 && upmove == 0.0)
		wishvel.Z -= HL_WATER_SINK_SPEED * WorldScale;  // drift towards bottom
	else    // Go straight up by upmove amount.
		wishvel.Z += upmove;

	// Copy it over and determine speed
	wishdir   = wishvel;
	wishspeed = VSize(wishdir);
	wishdir   = Normal(wishdir);

	// Cap speed.
	if (wishspeed > maxspeed && maxspeed > 0)
	{
		wishvel   = wishvel * (maxspeed / wishspeed);
		wishspeed = maxspeed;
	}

	// Slow us down a bit.
	wishspeed *= HL_WATER_SPEED_FACTOR;

	DebugWishDir   = wishdir;
	DebugWishSpeed = wishspeed;

	velocity += basevelocity;

	// Water friction. Unlike PM_Friction this is applied to all three
	// components, and with no stopspeed floor.
	temp     = velocity;
	speed    = VSize(temp);

	if (speed > 0)
	{
		newspeed = speed - frametime * speed * sv_friction * friction;

		if (newspeed < 0)
			newspeed = 0;

		velocity = velocity * (newspeed / speed);
	}
	else
		newspeed = 0;

	// water acceleration
	if (wishspeed < 0.1)
		return;

	addspeed = wishspeed - newspeed;
	if (addspeed > 0)
	{
		// NOTE: Valve accelerates along the normalized WISHVEL here, not along
		// wishdir. Those differ whenever the speed cap above rescaled wishvel,
		// so the distinction is preserved.
		wishvel    = Normal(wishvel);
		accelspeed = sv_accelerate * wishspeed * frametime * friction;

		if (accelspeed > addspeed)
			accelspeed = addspeed;

		velocity += wishvel * accelspeed;
	}

	// Now move
	// assume it is a stair or a slope, so press down from stepheight above
	dest     = origin + velocity * frametime;
	start    = dest;
	start.Z += sv_stepsize + 1.0 * WorldScale;

	PM_PlayerTrace(start, dest);

	if (!TraceStartSolid && !TraceAllSolid)     // FIXME: check steep slope?
	{	// walked up the step, so just keep result and exit
		origin = TraceEndPos;
		return;
	}

	// Try moving straight along out normal path.
	PM_FlyMove();
}

// PM_WaterJump    (pm_shared.c:2222)
final function PM_WaterJump()
{
	if (waterjumptime > HL_WJ_MAX_TIME)
		waterjumptime = HL_WJ_MAX_TIME;

	if (waterjumptime == 0)
		return;

	waterjumptime -= frametime * 1000.0;

	if (waterjumptime < 0 || waterlevel == 0)
		waterjumptime = 0;

	velocity.X = waterjumpMovedir.X;
	velocity.Y = waterjumpMovedir.Y;
}

// PM_CheckWaterJump    (pm_shared.c:2615)
final function PM_CheckWaterJump()
{
	local vector vecStart, vecEnd, flatforward, flatvelocity, wallNormal;
	local float  curspeed;
	local int    savehull;

	// Already water jumping.
	if (waterjumptime > 0)
		return;

	// Don't hop out if we just jumped in
	if (velocity.Z < -HL_WJ_SINK_CUTOFF * WorldScale)
		return;     // only hop out if we are moving up

	// See if we are backing up
	flatvelocity.X = velocity.X;
	flatvelocity.Y = velocity.Y;
	flatvelocity.Z = 0;

	// Must be moving
	curspeed     = VSize(flatvelocity);
	flatvelocity = Normal(flatvelocity);

	// see if near an edge
	flatforward.X = viewForward.X;
	flatforward.Y = viewForward.Y;
	flatforward.Z = 0;
	flatforward   = Normal(flatforward);

	// Are we backing into water from steps or something? If so, don't pop forward
	if (curspeed != 0.0 && (flatvelocity dot flatforward) < 0.0)
		return;

	vecStart    = origin;
	vecStart.Z += WJ_HEIGHT * WorldScale;

	vecEnd = vecStart + flatforward * (HL_WJ_TRACE_DIST * WorldScale);

	// Trace, this trace should use the point sized collision hull.
	savehull = usehull;
	usehull  = 2;

	PM_PlayerTrace(vecStart, vecEnd);

	if (TraceFraction < 1.0 && Abs(TracePlaneNormal.Z) < HL_WJ_WALL_NORMAL_Z)  // Facing a near vertical wall?
	{
		wallNormal = TracePlaneNormal;

		// Re-probe at the height of the top of the hull: if THAT is clear, the wall is
		// only as tall as we are and there is somewhere to land. HL uses the max of the
		// hull we were ACTUALLY using, not of the point hull.
		if (savehull == 1)
			vecStart.Z += DuckHullMax() - WJ_HEIGHT * WorldScale;
		else
			vecStart.Z += HullMax() - WJ_HEIGHT * WorldScale;

		vecEnd = vecStart + flatforward * (HL_WJ_TRACE_DIST * WorldScale);

		waterjumpMovedir = wallNormal * (-HL_WJ_GLIDE_SPEED * WorldScale);

		PM_PlayerTrace(vecStart, vecEnd);

		if (TraceFraction == 1.0)
		{
			waterjumptime = HL_WJ_TIME;
			velocity.Z    = HL_WJ_UP_SPEED * WorldScale;
			oldbuttonJump = true;
		}
	}

	// Reset the collision hull
	usehull = savehull;
}

// PM_LadderMove    (pm_shared.c:2057)
final function PM_LadderMove()
{
	local vector floorPoint, vpn, v_right;
	local vector intended, perp, cross, lateral, tmp;
	local float  fwd, rt, flSpeed, normalAmt;
	local bool   onFloor;
	local int    savehull;

	if (!onladder)
		return;

	// On ladder, convert movement to be relative to the ladder
	floorPoint    = origin;
	floorPoint.Z += (HullMin() - 1.0 * WorldScale);

	// Valve asks PM_PointContents(floor) == CONTENTS_SOLID here, and that has to
	// stay a POINT test: a full-hull sweep down to the feet is blocked by whatever
	// the hull already rests against, so it would report "on floor" everywhere.
	savehull = usehull;
	usehull  = 2;
	onFloor  = !PM_TestPlayerPosition(floorPoint);
	usehull  = savehull;

	// MOVETYPE_FLY: no gravity while on the ladder.
	gravityScale = 0;

	flSpeed = MAX_CLIMB_SPEED * WorldScale;

	// they shouldn't be able to move faster than their maxspeed
	if (flSpeed > maxspeed)
		flSpeed = maxspeed;

	vpn     = viewForward;
	v_right = viewRight;

	if (bDucking)
		flSpeed *= PLAYER_DUCKING_MULTIPLIER;

	// HL sums flSpeed over IN_FORWARD/IN_BACK/IN_MOVELEFT/IN_MOVERIGHT; ours arrive
	// already summed as the two ladder fractions.
	fwd = flSpeed * ladderForwardFrac;
	rt  = flSpeed * ladderSideFrac;

	if (buttonJump)
	{
		// Jump off: shove away from the ladder and hand back to walking.
		// The eject latch stops us from re-grabbing the (much larger than a
		// GoldSrc ladder brush) LadderVolume on the very next frame.
		velocity        = ladderNormal * (HL_LADDER_JUMP_SPEED * WorldScale);
		onladder        = false;
		ladderEjectTime = 500.0;
		oldbuttonJump   = true;
		return;
	}

	if (fwd != 0 || rt != 0)
	{
		// Calculate player's intended velocity
		intended = vpn * fwd + v_right * rt;

		// Perpendicular in the ladder plane
		tmp    = vect(0,0,1);
		perp   = Normal(tmp cross ladderNormal);

		// decompose velocity into ladder plane
		normalAmt = intended dot ladderNormal;

		// This is the velocity into the face of the ladder
		cross = ladderNormal * normalAmt;

		// This is the player's additional velocity
		lateral = intended - cross;

		// This turns the velocity into the face of the ladder into velocity that is
		// roughly vertically perpendicular to the face of the ladder. NOTE: it IS
		// possible to face up and move down or face down and move up, by design.
		tmp      = ladderNormal cross perp;
		velocity = lateral - tmp * normalAmt;

		if (onFloor && normalAmt > 0)   // On ground moving away from the ladder
			velocity += ladderNormal * (MAX_CLIMB_SPEED * WorldScale);
	}
	else
	{
		velocity = vect(0,0,0);
	}
}

// PM_CheckWater    (pm_shared.c:1471)
final function bool PM_CheckWater()
{
	local PhysicsVolume V, Best;
	local float  feetZ, midZ, eyeZ, surfaceZ, bestSurfaceZ;
	local float  hullBottom, hullTop;

	// Assume that we are not in water at all.
	waterlevel    = 0;
	waterSurfaceZ = -100000.0;

	if (PM == None)
		return false;

	// The three sample heights, in world space. Valve offsets from the origin
	// by player_mins[2]+1, by (mins[2]+maxs[2])*0.5, and by view_ofs[2].
	if (usehull == 1)
	{
		hullBottom = DuckHullMin();
		hullTop    = DuckHullMax();
	}
	else
	{
		hullBottom = HullMin();
		hullTop    = HullMax();
	}

	feetZ = origin.Z + hullBottom + 1.0 * WorldScale;
	midZ  = origin.Z + (hullBottom + hullTop) * 0.5;
	eyeZ  = origin.Z + view_ofs;

	// Find the highest water surface the pawn is actually in contact with.
	// Highest wins so that overlapping volumes behave like the deeper one,
	// which is what Priority does for the engine's own PhysicsVolume pick.
	if (bWaterScanValid && WaterScanPawn == PM && PM.Location == WaterScanOrigin)
	{
		Best = WaterScanVolume;
	}
	else
	{
		bestSurfaceZ = -100000.0;

		ForEach PM.TouchingActors(class'PhysicsVolume', V)
		{
			if (!V.bWaterVolume)
				continue;

			surfaceZ = V.Location.Z + V.CollisionHeight;

			if (surfaceZ > bestSurfaceZ)
			{
				bestSurfaceZ = surfaceZ;
				Best         = V;
			}
		}

		WaterScanPawn   = PM;
		WaterScanVolume = Best;
		WaterScanOrigin = PM.Location;
		bWaterScanValid = true;

		WaterScans++;
	}

	// No touching water volume. The engine's own two answers still get a say
	// below -- returning here would make the whole depth reading depend on the
	// touch list being complete, and it is not our bookkeeping to vouch for.
	if (Best != None)
	{
		// Read the surface height live rather than trusting the cached scan, so a
		// water volume that is itself moving is never a frame stale in the depth
		// test even when the search behind it was reused.
		bestSurfaceZ = Best.Location.Z + Best.CollisionHeight;
		waterSurfaceZ = bestSurfaceZ;

		// Are we under water? (not solid and not empty?)
		if (feetZ <= bestSurfaceZ)
		{
			// We are at least at level one
			waterlevel = 1;

			// Now check a point that is at the player hull midpoint.
			if (midZ <= bestSurfaceZ)
			{
				// Set a higher water level.
				waterlevel = 2;

				// Now check the eye position. (view_ofs is relative to the origin)
				if (eyeZ <= bestSurfaceZ)
					waterlevel = 3;     // In over our eyes
			}
		}
	}

	// The engine tracks the origin and the eye itself, and its answers beat our
	// reconstructed surface height because they account for volume shapes our bounds
	// approximation does not. Only ever RAISE the level from these.
	if (PM.PhysicsVolume != None && PM.PhysicsVolume.bWaterVolume)
	{
		if (waterlevel < 2)
			waterlevel = 2;

		if (Best == None)
			Best = PM.PhysicsVolume;
	}

	if (PM.HeadVolume != None && PM.HeadVolume.bWaterVolume)
	{
		waterlevel = 3;

		if (Best == None)
			Best = PM.HeadVolume;
	}

	if (waterlevel == 0 || Best == None)
		return false;

	// If the depth came from the engine's two answers rather than from the search,
	// no surface height was ever read. Take it off whichever volume answered.
	if (waterSurfaceZ < -99999.0)
		waterSurfaceZ = Best.Location.Z + Best.CollisionHeight;

	// Adjust velocity based on water current, if any. Valve reads this from the
	// CONTENTS_CURRENT_* brush contents; Unreal spells it ZoneVelocity.
	// The deeper we are, the stronger the current.
	if (Best.ZoneVelocity != vect(0,0,0))
		basevelocity += Normal(Best.ZoneVelocity) * (50.0 * WorldScale * waterlevel);

	return waterlevel > 1;
}

// PM_InWater    (pm_shared.c:1466)
final function bool PM_InWater()
{
	return waterlevel > 1;
}

// PM_CategorizePosition    (pm_shared.c:1542)
const PM_GROUND_SLACK = 1.5;    // HL units of floor gap we tolerate once landed

// The same slack in P2 units, for the controller: a const belongs to the class
// that declares it, and this one is a fact about the ground both sides need.
final function float GroundSlack()
{
	return PM_GROUND_SLACK * WorldScale;
}

final function PM_CategorizePosition()
{
	local vector point;
	local bool   bWasOnGround;

	// Doing this before we move may introduce a potential latency in water
	// detection, but doing it after can get us stuck on the bottom in water. We call
	// this several times a frame, and the converse case corrects itself.
	PM_CheckWater();

	bWasOnGround = onground;

	// if the player hull point one unit down is solid, the player is on ground
	point.X = origin.X;
	point.Y = origin.Y;
	point.Z = origin.Z - 2.0 * WorldScale;

	if (velocity.Z > 180.0 * WorldScale)    // Shooting up really fast. Definitely not on ground.
	{
		onground     = false;
		groundEntity = None;
	}
	else
	{
		// Try and move down.
		PM_PlayerTrace(origin, point);

		// If we hit a steep plane, we are not on ground
		if (TracePlaneNormal.Z < PM_MAX_CLIMB_NORMAL)
		{
			onground     = false;       // too steep
			groundEntity = None;
		}
		else
		{
			onground     = (TraceHitActor != None);
			groundEntity = TraceHitActor;
		}

		// If we are on something...
		if (onground)
		{
			// Then we are not in water jump sequence
			waterjumptime = 0;

			// If we could make the move, drop us down that 1 pixel -- on the
			// landing frame always, and after that only if the floor has got
			// further away than the engine's own resting gap. See PM_GROUND_SLACK.
			if (waterlevel < 2 && !TraceStartSolid && !TraceAllSolid
				&& (!bWasOnGround
					|| (origin.Z - TraceEndPos.Z) > PM_GROUND_SLACK * WorldScale))
			{
				origin = TraceEndPos;
			}
		}
	}
}

// PM_PlayStepSound    (pm_shared.c:293)
//
// Valve's version is where the sample is chosen and played. Ours only records
// that a step is due: POSTAL 2's own AWDude.PlayFootstep already picks the sound
// from the material underfoot, which is a better answer than GoldSrc's
// seven-texture table can give here, and the simulation has no business touching
// the sound system anyway.
final function PM_PlayStepSound(float fvol, optional bool bLanding)
{
	bStepSoundPending = true;
	StepSoundVol      = fvol;
	bStepSoundLanding = bLanding;
}

// PM_UpdateStepSound    (pm_shared.c:497)
final function PM_UpdateStepSound()
{
	local bool  fWalking, fLadder;
	local float fvol;
	local float speed, velrun, velwalk, flduck;
	local float height, kneeZ;

	if (flTimeStepSound > 0)
		return;

	// Valve tests FL_FROZEN here, which is the flag a dead or held player carries.
	if (dead)
		return;

	// PM_CatagorizeTextureType goes here in Valve's version, to pick the sample and
	// its per-material volume. P2 does that itself, in PlayFootstep.

	speed = VSize(velocity);

	// determine if we are on a ladder
	fLadder = onladder;

	// UNDONE: need defined numbers for run, walk, crouch, crouch run velocities!!!!
	if (bDucking || fLadder)
	{
		velwalk = HL_STEP_VELWALK_DUCKED * WorldScale;
		velrun  = HL_STEP_VELRUN_DUCKED * WorldScale;
		flduck  = HL_STEP_DUCK_DELAY;
	}
	else
	{
		velwalk = HL_STEP_VELWALK * WorldScale;
		velrun  = HL_STEP_VELRUN * WorldScale;
		flduck  = 0;
	}

	// If we're on a ladder or on the ground, and we're moving fast enough,
	//  play step sound.  Also, if flTimeStepSound is zero, get the new
	//  sound right away - we just started moving in new level.
	if ((fLadder || onground) && speed > 0.0
		&& (speed >= velwalk || flTimeStepSound == 0))
	{
		fWalking = speed < velrun;

		height = HullHalfHeight() * 2.0;
		kneeZ  = origin.Z - HL_STEP_KNEE_FRAC * height;

		// find out what we're stepping in or on...
		if (fLadder)
		{
			fvol            = HL_STEP_VOL_LADDER;
			flTimeStepSound = HL_STEP_TIME_LADDER;
		}
		else if (waterlevel > 0 && kneeZ <= waterSurfaceZ)
		{
			// Knee deep: wading, which is slower and louder than anything else.
			fvol            = HL_STEP_VOL_WADE;
			flTimeStepSound = HL_STEP_TIME_WADE;
		}
		else if (fWalking)
		{
			// Valve's second water probe, at the feet, and every entry of the texture
			// table under it agree on these numbers -- only DIRT (0.25 / 0.55) and VENT
			// (0.4 / 0.7) are louder, and telling those apart is choosing a SAMPLE,
			// which is P2's job.
			fvol            = HL_STEP_VOL_WALK;
			flTimeStepSound = HL_STEP_TIME_WALK;
		}
		else
		{
			fvol            = HL_STEP_VOL_RUN;
			flTimeStepSound = HL_STEP_TIME_RUN;
		}

		flTimeStepSound += flduck;      // slower step time if ducking

		// play the sound
		// 35% volume if ducking
		if (bDucking)
			fvol *= HL_STEP_DUCK_VOL_SCALE;

		PM_PlayStepSound(fvol);
	}
}

// PM_CheckFalling    (pm_shared.c:2679)
final function PM_CheckFalling()
{
	local float HLFallVel, fvol;
	local bool  bDamaging;

	LandFallVelocity = 0.0;

	HLFallVel = flFallVelocity;
	if (WorldScale > 0.0)
		HLFallVel /= WorldScale;

	if (onground && !dead && HLFallVel >= PLAYER_FALL_PUNCH_THRESHHOLD)
	{
		fvol = 0.5;

		if (waterlevel > 0)
		{
			// Landing in water: Valve leaves this branch empty. fvol stays at 0.5, so a
			// landing cushioned by water STILL punches the view -- it is only the DAMAGE
			// that water cancels, and that is bDamaging below.
		}
		else if (HLFallVel > PLAYER_MAX_SAFE_FALL_SPEED)
		{
			// After this point, we start doing damage.
			bDamaging = true;
			fvol      = 1.0;
		}
		else if (HLFallVel > PLAYER_MAX_SAFE_FALL_SPEED / 2)
		{
			// Bootscrape territory: loud, but harmless.
			fvol = 0.85;
		}
		else if (HLFallVel < PLAYER_MIN_BOUNCE_SPEED)
		{
			fvol = 0;
		}

		if (fvol > 0.0)
		{
			// Play landing step right away
			flTimeStepSound = 0;

			PM_UpdateStepSound();

			// play step sound for current texture. Valve fires this ON TOP of the one
			// PM_UpdateStepSound just queued -- two sounds for one landing. We have a
			// single pending slot, so the louder landing volume simply wins.
			PM_PlayStepSound(fvol, true);

			// Knock the screen around a little bit, temporary effect.
			punchangle.Z = HLFallVel * HL_FALL_PUNCH_SCALE;

			if (punchangle.X > HL_FALL_PUNCH_PITCH_MAX)
				punchangle.X = HL_FALL_PUNCH_PITCH_MAX;

			// Hand the landing to the controller for fall damage. Valve gates its damage on
			// the same speed test as fvol above and on NOT being in water (player.cpp:2601),
			// so a fall broken by water costs nothing. bDamaging carries both.
			if (bDamaging)
				LandFallVelocity = HLFallVel;
		}
	}

	if (onground)
		flFallVelocity = 0;
}

// PM_PlayerFallDamage
final function float PM_PlayerFallDamage(float HLFallVel)
{
	if (sv_falldamage <= 0)
		return 0.0;

	// Flat rate: enough to sting, never enough to be the thing that killed
	// you. Deliberately ignores how far you fell.
	if (sv_falldamage == 1)
		return HL_LESSER_FALL_DAMAGE;

	// Valve subtracts the speed a player is allowed to fall without being hurt, so
	// the damage is based on the excess rather than on the entire fall.
	return FMax(0.0, (HLFallVel - PLAYER_MAX_SAFE_FALL_SPEED) * DAMAGE_FOR_FALL_SPEED);
}

// PM_DropPunchAngle    (cl_dll/view.cpp:1676, V_DropPunchAngle)
final function PM_DropPunchAngle()
{
	local float  Len;
	local vector Dir;

	Len = VSize(punchangle);
	if (Len <= 0.0)
	{
		punchangle = vect(0,0,0);
		return;
	}

	Dir  = punchangle / Len;
	Len -= (HL_PUNCH_DECAY_BASE + Len * HL_PUNCH_DECAY_RATE) * frametime;

	if (Len <= 0.0)
	{
		punchangle = vect(0,0,0);
		return;
	}

	punchangle = Dir * Len;
}

// PM_PreventMegaBunnyJumping    (pm_shared.c:2442)
final function PM_PreventMegaBunnyJumping()
{
	local float spd, fraction, maxscaledspeed;

	maxscaledspeed = BUNNYJUMP_MAX_SPEED_FACTOR * maxspeed;

	// Don't divide by zero
	if (maxscaledspeed <= 0.0)
		return;

	spd = VSize(velocity);

	if (spd <= maxscaledspeed)
		return;

	fraction = (maxscaledspeed / spd) * 0.65;   // Returns the modifier for the velocity

	velocity = velocity * fraction;             // Crop it down!
}

// PM_Jump    (pm_shared.c:2472)
final function PM_Jump()
{
	local float jumpGravity;

	if (dead)
	{
		oldbuttonJump = true;           // don't jump again until released
		return;
	}

	// See if we are waterjumping. If so, decrement count and return.
	if (waterjumptime > 0)
	{
		waterjumptime -= frametime * 1000.0;
		if (waterjumptime < 0)
			waterjumptime = 0;
		return;
	}

	// If we are in the water most of the way...
	if (waterlevel >= 2)
	{	// swimming, not jumping
		onground     = false;
		groundEntity = None;

		// We move up a certain amount. Only plain water exists in POSTAL 2, so
		// the CONTENTS_SLIME (80) and lava (50) branches are folded away.
		velocity.Z = HL_WATER_JUMP_UP_SPEED * WorldScale;

		return;
	}

	// No more effect
	if (!onground)
	{
		// Flag that we jumped.
		oldbuttonJump = true;           // don't jump again until released
		return;                         // in air, so no effect
	}

	// HL: "don't pogo stick" -- the jump button must be released and pressed
	// again for each hop. sv_autobunnyhop bypasses the latch so that holding
	// jump re-fires on the first grounded frame after landing.
	if (oldbuttonJump && !sv_autobunnyhop)
		return;                         // don't pogo stick

	// In the air now.
	onground     = false;
	groundEntity = None;

	if (sv_enablebunnyhopcap)
		PM_PreventMegaBunnyJumping();

	// Record takeoff speed for the HUD before gravity fixup.
	DebugTakeoffSpeed = VSize(vect(1,1,0) * velocity);

	// Accelerate upward. HL uses sqrt(2 * 800 * 45); we express it against our own
	// gravity so the jump still clears the same fraction of the player's height if
	// sv_gravity is retuned.
	jumpGravity = HL_REFERENCE_GRAVITY * WorldScale;

	velocity.Z = Sqrt(2.0 * jumpGravity * HL_JUMP_HEIGHT * WorldScale);

	// Add a little forward velocity based on your current forward velocity - if
	// you are not sprinting. Half-Life 2 only, and the same slot it sits in there:
	// after the upward accelerate, before gravity is finished.
	if (sv_enableabh)
		PM_ABHJumpBoost();

	// Decay it for simulation
	PM_FixupGravityVelocity();

	// Flag that we jumped.
	oldbuttonJump = true;               // don't jump again until released
}

// The Half-Life 2 jump speed boost, transcribed whole. (gamemovement.cpp:2465,
// the tail of CGameMovement::CheckJumpButton)
//
// This is all of Accelerated Back Hopping. The bonus is meant to be clipped so it
// cannot accumulate, and Valve wrote the clip as a subtraction that goes NEGATIVE
// once you are already past the goal speed -- fine on its own, since a negative
// addition along your direction of travel is a brake. But the sign is then taken
// from the INPUT rather than from the velocity, and the vector is the VIEW's
// forward rather than the direction you are moving. Hold a key that disagrees with
// where you are going -- look backwards and press forward -- and the brake is
// applied against a velocity pointing the other way, so it lands on top of your
// speed instead of against it. Each hop then leaves 2*S - 1.5*maxspeed, which
// doubles away from the fixed point and is why ABH runs away with itself.
final function PM_ABHJumpBoost()
{
	local vector vecForward;
	local float  flSpeedBoostPerc, flSpeedAddition, flMaxSpeed, flNewSpeed;

	// AngleVectors of the view angles, flattened. Ours is built from the view yaw
	// alone already, so zeroing Z only restates that -- and unlike Valve's it
	// cannot degenerate when you are looking straight up.
	vecForward   = forward;
	vecForward.Z = 0;
	vecForward   = Normal(vecForward);

	// We give a certain percentage of the current forward movement as a bonus to
	// the jump speed. That bonus is clipped to not accumulate over time.
	// HL2 also takes the small percentage while sprinting; P2 has no sprint.
	if (bDucking)
		flSpeedBoostPerc = HL2_JUMP_BOOST_PERC_DUCK;
	else
		flSpeedBoostPerc = HL2_JUMP_BOOST_PERC;

	flSpeedAddition = Abs(forwardmove * flSpeedBoostPerc);
	flMaxSpeed      = maxspeed + (maxspeed * flSpeedBoostPerc);
	flNewSpeed      = flSpeedAddition + HorizontalSpeed();

	// If we're over the maximum, we want to only boost as much as will get us to
	// the goal speed
	if (flNewSpeed > flMaxSpeed)
		flSpeedAddition -= flNewSpeed - flMaxSpeed;

	if (forwardmove < 0.0)
		flSpeedAddition *= -1.0;

	// Add it on
	velocity += vecForward * flSpeedAddition;
}

// PM_SplineFraction    (pm_shared.c:1885)
final function float PM_SplineFraction(float value, float scale)
{
	local float valueSquared;

	value = scale * value;
	valueSquared = value * value;

	// Nice little ease-in, ease-out spline-like curve
	return 3 * valueSquared - 2 * valueSquared * value;
}

// Is there room to stand up, if unducking would leave us at newOrigin?
final function bool PM_CanStandUpAt(vector newOrigin)
{
	local float  CurMin, CurMax, Band;
	local vector Probe;

	// The hull we are in right now, which is not always the ducked one: a duck
	// released before TIME_TO_DUCK is up arrives with bInDuck set and the standing
	// hull still fitted, and that is what the ducktap launch is built on.
	if (usehull == 1)
	{
		CurMin = DuckHullMin();
		CurMax = DuckHullMax();
	}
	else
	{
		CurMin = HullMin();
		CurMax = HullMax();
	}

	// Above: from our current top up to where the standing top will land.
	Band = (newOrigin.Z + HullMax()) - (origin.Z + CurMax);

	if (Band > 0.0)
	{
		Probe    = origin;
		Probe.Z += Band;

		PM_PlayerTrace(origin, Probe);

		if (TraceFraction < 1.0)
			return false;
	}

	// Below. Zero while on the ground, where the feet do not move.
	Band = (origin.Z + CurMin) - (newOrigin.Z + HullMin());

	if (Band > 0.0)
	{
		Probe    = origin;
		Probe.Z -= Band;

		PM_PlayerTrace(origin, Probe);

		if (TraceFraction < 1.0)
			return false;
	}

	return true;
}

// PM_UnDuck    (pm_shared.c:1918)
final function PM_UnDuck()
{
	local vector newOrigin;

	newOrigin = origin;

	if (onground)
	{
		// HL: newOrigin += (player_mins[1] - player_mins[0]), the ducked hull's floor
		// minus the standing hull's. That value is positive, so standing up raises the
		// centre while the feet stay put.
		newOrigin.Z += (DuckHullMin() - HullMin());
	}

	// See if we are stuck? If so, stay ducked with the duck hull until we have a
	// clear spot. Asked as a sweep rather than Valve's startsolid probe -- see
	// PM_CanStandUpAt for why the probe cannot answer it on this backend.
	if (!PM_CanStandUpAt(newOrigin))
		return;

	usehull    = 0;
	bDucking   = false;
	bInDuck    = false;
	view_ofs   = ViewOfs();
	flDuckTime = 0;
	origin     = newOrigin;

	// Recategorize position since ducking can change origin
	PM_CategorizePosition();
}

// PM_DuckTap    (not pm_shared.c -- Bunnymod XT's +bxt_ducktap)
final function PM_DuckTap()
{
	if (dead || (!buttonDuckTap && !ducktapOnce))
	{
		ducktapPressed = false;
		ducktapOnce    = false;
		return;
	}

	if (ducktapPressed)
	{
		// Release frame. PM_Duck takes the else branch into PM_UnDuck, which lifts us
		// clear of the floor if we are still standing on it; if we walked off an edge
		// between the two frames instead, the next touchdown starts a fresh tap.
		buttonDuck     = false;
		ducktapPressed = false;
		ducktapOnce    = false;         // a one-shot request is now spent
	}
	else if (onground)
	{
		// Press frame: one frame only, and only from the ground.
		buttonDuck     = true;
		ducktapPressed = true;
	}
	else
	{
		// Airborne: hold the button off. Pressing duck with onground == -1
		// finishes the duck immediately, which shrinks the hull mid-flight and
		// leaves the release with nothing to lift.
		buttonDuck = false;
	}
}

// PM_Duck    (pm_shared.c:1962)
final function PM_Duck()
{
	local float timeVal, duckFraction, fMore;
	local bool  buttonsChanged, nButtonPressed;

	buttonsChanged = (oldbuttonDuck != buttonDuck);
	nButtonPressed = buttonsChanged && buttonDuck;

	oldbuttonDuck = buttonDuck;

	if (dead)
	{
		if (bDucking)
			PM_UnDuck();
		return;
	}

	// Ducked movement is a third speed.
	if (bDucking)
	{
		forwardmove *= PLAYER_DUCKING_MULTIPLIER;
		sidemove    *= PLAYER_DUCKING_MULTIPLIER;
		upmove      *= PLAYER_DUCKING_MULTIPLIER;
	}

	if (buttonDuck || bInDuck || bDucking)
	{
		if (buttonDuck)
		{
			if (nButtonPressed && !bDucking)
			{
				// Use 1 second so super long jump will work
				flDuckTime = 1000;
				bInDuck    = true;
			}

			timeVal = FMax(0.0, (1.0 - flDuckTime / 1000.0));

			if (bInDuck)
			{
				// Finish ducking immediately if duck time is over or not on ground
				if ((flDuckTime / 1000.0 <= (1.0 - TIME_TO_DUCK)) || !onground)
				{
					usehull  = 1;
					view_ofs = DuckViewOfs();
					bDucking = true;
					bInDuck  = false;

					// HACKHACK - Fudge for collision bug - no time to fix this properly
					// (Valve's own comment.) HL: origin -= (player_mins[1] - player_mins[0]),
					// which is +18, so the hull shrinks around the feet instead of the feet
					// rising off the floor.
					if (onground)
					{
						origin.Z -= (DuckHullMin() - HullMin());
						PM_CategorizePosition();
					}
				}
				else
				{
					fMore        = (DuckHullMin() - HullMin());
					duckFraction = PM_SplineFraction(timeVal, (1.0 / TIME_TO_DUCK));
					view_ofs     = ((DuckViewOfs() - fMore) * duckFraction)
					             + (ViewOfs() * (1 - duckFraction));
				}
			}
		}
		else
		{
			// Try to unduck
			PM_UnDuck();
		}
	}
}

// PM_ReduceTimers    (pm_shared.c:2903)
final function PM_ReduceTimers()
{
	local float msec;

	msec = frametime * 1000.0;

	if (flTimeStepSound > 0)
	{
		flTimeStepSound -= msec;
		if (flTimeStepSound < 0)
			flTimeStepSound = 0;
	}

	if (flDuckTime > 0)
	{
		flDuckTime -= msec;
		if (flDuckTime < 0)
			flDuckTime = 0;
	}

	// Not in pm_shared.c -- see the ladderEjectTime declaration for why the
	// Unreal ladder backend needs it.
	if (ladderEjectTime > 0)
	{
		ladderEjectTime -= msec;
		if (ladderEjectTime < 0)
			ladderEjectTime = 0;
	}
}

// PM_CheckParameters    (pm_shared.c:2835)
final function PM_CheckParameters()
{
	local float spd, fRatio;

	spd = Sqrt(forwardmove * forwardmove + sidemove * sidemove + upmove * upmove);

	if (spd != 0.0 && spd > maxspeed)
	{
		fRatio       = maxspeed / spd;
		forwardmove *= fRatio;
		sidemove    *= fRatio;
		upmove      *= fRatio;
	}

	if (dead)
	{
		forwardmove = 0;
		sidemove    = 0;
		upmove      = 0;
	}
}

// PM_PlayerMove    (pm_shared.c:2941)
final function PM_PlayerMove()
{
	// Close the books on the frame just finished. Everything the controller did
	// after our last return is still in the counters, which is the point: the
	// readout is meant to be the whole frame's cost.
	TracesPerFrame     = TraceCount;
	WaterScansPerFrame = WaterScans;
	TraceCount         = 0;
	WaterScans         = 0;

	// One-frame handoff to the controller; only PM_CheckFalling sets it, and the
	// ladder/water branches below return before reaching it, so it has to be
	// cleared here rather than there or a landing would be paid for twice.
	LandFallVelocity = 0.0;

	// Spring the screen punch back towards level. Valve does this once per rendered
	// frame on the client (view.cpp:695); we do it once per movement frame, before
	// PM_CheckFalling can set a new one.
	PM_DropPunchAngle();

	// Assume we don't touch anything    (pm_shared.c:2952)
	NumTouch = 0;

	// Adjust speeds etc.
	PM_CheckParameters();

	PM_ReduceTimers();

	// Always try and unstick us. (pm_shared.c:2972)
	// This is what lets the player recover after being shoved into geometry by
	// damage, a cutscene, a teleport or a hull resize.
	if (PM_CheckStuck())
	{
		DebugMoveState = "Stuck";

		// Wedged, and whatever velocity put us here is still pointing into the
		// obstruction. Re-integrating it every frame undoes the nudges PM_CheckStuck
		// finds, which is how being shot into a corner used to pin the player until they
		// died. One frame of grace for a fast bhop, then drop the momentum.
		if (StuckFrames >= 2)
			velocity = vect(0,0,0);

		return;                         // Can't move, we're stuck
	}

	// Now that we are "unstuck", see where we are.
	// (This calls PM_CheckWater() first, so waterlevel is live from here on.)
	PM_CategorizePosition();

	// If we are not on ground, store off how fast we are moving down
	if (!onground)
		flFallVelocity = -velocity.Z;

	// Valve's ladder detection sits here, immediately above this call; ours ran on
	// the controller before the frame started, so onladder is already good.
	PM_UpdateStepSound();

	// Drive buttonDuck for the ducktap bind, if it is held. Must be the last
	// word on that button before PM_Duck consumes it.
	PM_DuckTap();

	PM_Duck();

	// --- MOVETYPE_FLY: on a ladder --------------------------------------
	// Valve's dispatch picks the movetype from PM_Ladder() before the switch;
	// ours reads the flag the controller resolved in SyncLadderState.
	if (onladder)
	{
		DebugMoveState = "Ladder";

		PM_LadderMove();

		PM_CheckWater();

		// Perform the move accounting for any base velocity.
		velocity += basevelocity;
		PM_FlyMove();
		velocity -= basevelocity;

		PM_CheckVelocity();
		return;
	}

	// --- MOVETYPE_WALK ---------------------------------------------------
	// Gravity is suppressed entirely while swimming -- PM_WaterMove's own
	// friction and the 60 u/s sink replace it.
	if (!PM_InWater())
		PM_AddCorrectGravity();

	// If we are leaping out of the water, just update the counters.
	if (waterjumptime > 0)
	{
		DebugMoveState = "WaterJump";

		PM_WaterJump();
		PM_FlyMove();

		// Make sure waterlevel is set correctly
		PM_CheckWater();
		return;
	}

	// If we are swimming in the water, see if we are nudging against a place we
	// can jump up out of, and, if so, start our jump. Otherwise, if we are not
	// moving up, then reset jump timer to 0.
	if (waterlevel >= 2)
	{
		DebugMoveState = "Water";

		if (waterlevel == 2)
			PM_CheckWaterJump();

		// If we are falling again, then we must not be trying to jump out of
		// water any more.
		if (velocity.Z < 0 && waterjumptime > 0)
			waterjumptime = 0;

		// Was jump button pressed?
		if (buttonJump)
			PM_Jump();
		else
			oldbuttonJump = false;

		// Perform regular water movement
		PM_WaterMove();

		velocity -= basevelocity;

		// Get a final position
		PM_CategorizePosition();

		return;
	}

	// Not underwater.

	// Was jump button pressed?
	if (buttonJump)
		PM_Jump();
	else
		oldbuttonJump = false;

	// Friction is handled before we add in any base velocity. That way, if we
	// are on a conveyor, we don't slow when standing still, relative to the
	// conveyor.
	if (onground)
	{
		velocity.Z = 0.0;
		PM_Friction();
	}

	// Make sure velocity is valid.
	PM_CheckVelocity();

	// Are we on ground now?
	if (onground)
	{
		DebugMoveState = "Walk";
		PM_WalkMove();
	}
	else
	{
		DebugMoveState = "Air";
		PM_AirMove();                   // Take into account movement when in air.
	}

	// Set final flags.
	PM_CategorizePosition();

	// Now pull the base velocity back out.
	velocity -= basevelocity;

	// Make sure velocity is valid.
	PM_CheckVelocity();

	// Add any remaining gravitational component.
	if (!PM_InWater())
		PM_FixupGravityVelocity();

	// If we are on ground, no downward velocity.
	if (onground)
		velocity.Z = 0;

	// See if we landed on the ground with enough force to play a landing sound.
	// (pm_shared.c:3189 -- last thing in the walk branch, after velocity.Z has
	// been zeroed, which is why it reads flFallVelocity and not velocity.)
	PM_CheckFalling();
}

// Helpers

// Horizontal (XY) speed, in engine units.
final function float HorizontalSpeed()
{
	local vector v;
	v = velocity;
	v.Z = 0;
	return VSize(v);
}

// Speed converted back into Half-Life units, for display.
final function float HorizontalSpeedHL()
{
	if (WorldScale <= 0)
		return HorizontalSpeed();
	return HorizontalSpeed() / WorldScale;
}

final function float VerticalSpeedHL()
{
	if (WorldScale <= 0)
		return velocity.Z;
	return velocity.Z / WorldScale;
}

// Reset the speedometer's counters.
final function ResetStats()
{
	DebugTakeoffSpeed = 0;
	WeldNudges        = 0;
}

defaultproperties
{
	WorldScale=2.0

	// Stock Half-Life values. Lengths are pre-multiplied by WorldScale (2.0);
	// dimensionless coefficients are left alone.
	sv_maxspeed=640.0           // HL 320
	sv_accelerate=10.0          // HL 10   (dimensionless)
	sv_airaccelerate=10.0       // HL 10   (dimensionless)
	sv_friction=4.0             // HL 4    (dimensionless)
	sv_stopspeed=200.0          // HL 100
	sv_gravity=1600.0           // HL 800
	// The one length that is deliberately NOT 2x its HL value. 18*2=36 fails on P2's
	// own stair geometry -- the police station steps refuse a 36 probe -- while 35
	// climbs them and every other staircase tested. Measured in game, not derived.
	sv_stepsize=35.0            // HL 18 (=36 scaled); 35 is what P2 stairs need
	sv_maxvelocity=4000.0       // HL 2000
	sv_edgefriction=2.0         // HL 2    (dimensionless)
	sv_bounce=1.0               // HL 1    (dimensionless)

	sv_enablebunnyhopcap=false  // HL ships with this ON; off = unlimited bhop
	sv_autobunnyhop=false       // NOT HL behaviour; on = hold jump to hop
	sv_enableabh=false          // HL2 behaviour; on = back hopping accelerates

	sv_hullradius=0.0           // 0 = auto: P2's own radius with sv_usep2hull,
	                            // else HL 16 (=32 scaled). Given in HL units, so
	                            // it doubles on use; 10 (=20) inscribes the box in
	                            // P2's 28 cylinder, the fix for diagonal doorways.
	sv_usep2hull=true           // Be POSTAL 2 sized, not scaled-HL sized, so
	                            // the player matches the NPCs and the art.

	sv_maxstuckframes=10        // safety valve on the unstick logic

	sv_strictblocking=true      // world geometry needs the block flags too,
	                            // which is the rule native movement uses

	sv_falldamage=2             // 0 off, 1 flat 10 HP, 2 HL's height curve

	sv_knockback=1.0            // non-explosive hit knockback scale
	sv_explosionknockback=0.5   // explosive knockback scale -- the damage boost,
	                            // halved so a blast shoves instead of flinging
	sv_maxdamagepush=1000.0     // HL 500 ups: most one frame of damage may add
	                            // in total, however many hits it arrives in

	friction=1.0
	gravityScale=1.0
	maxspeed=640.0
	usehull=0
}
