// this adds the HUD elements that show the player's speed, acceleration, and velocity graph, and also implements the viewmodel bob and sway from Half-Life 2
class GoldSrcHUD extends AWWrapHUD;

var config color SpeedColor;
var config color LabelColor;
var config color DebugColor;
var config color AccelColor;
var config color DecelColor;

// graph history for the velocity graph, which is drawn in the lower right corner of the screen
// graph is not shown by default but can be enabled with the console variable cl_showvelocitygraph

const GRAPH_SAMPLES = 96;
var float GraphSpeed[96];
var int   GraphIndex;
var bool  bGraphFilled;

var config bool bShowVelocityGraph;

var float LastSpeed;        // for the accel/decel indicator
var float DisplayAccel;     // smoothed d(speed)/dt

// net_graph and cl_showpos recreations

const FPS_WINDOW = 0.25;    // seconds of frames averaged into the fps readout

var float LastFrameTime;    // Level.TimeSeconds at the previous DrawHUD
var float FpsAccumTime;     // real seconds accumulated in the current window
var int   FpsFrames;        // frames counted in the current window
var float DisplayFps;

var config color NetGraphColor;
var config color ShowPosColor;

// damage direction indicator, ported from CHudHealth in cl_dll/health.cpp
//
// The four values are how strongly the last hit came from each side, 0..1, and
// they live here rather than on the player for the same reason Valve keeps them on
// the HUD: they are latched in SCREEN space at the moment of the hit, so turning
// round afterwards does not drag the wedges with you.
var float AttackFront;      // m_fAttackFront
var float AttackRear;       // m_fAttackRear
var float AttackLeft;       // m_fAttackLeft
var float AttackRight;      // m_fAttackRight
var float PainLastTime;     // our own, because UpdateFps owns LastFrameTime

var config color PainColor;

const PAIN_THRESHOLD  = 0.3;    // health.cpp:269, how far off-axis still counts
const PAIN_MIN_DRAW   = 0.4;    // :307, below this the wedge is dropped outright
const PAIN_MIN_SHADE  = 0.5;    // :310, the floor under the brightness
const PAIN_FADE_RATE  = 2.0;    // :304, m_flTimeDelta * 2 per frame
const PAIN_NEAR_DIST  = 100.0;  // :261, Valve's 50 units at P2's doubled scale

// Valve's pain sprite is 24 wide and 9 deep at 640x480, and every placement below
// is written in terms of those two numbers, so they scale as one.
const PAIN_SPR_W      = 24.0;
const PAIN_SPR_H      = 9.0;
const PAIN_REF_HEIGHT = 480.0;

// How much narrower the end nearest the crosshair is. Valve had an actual sprite;
// this is the shape of it.
const PAIN_TAPER      = 0.35;
const PAIN_SLICES     = 8;

// source viewmodel bob and sway, ported from CBaseHLCombatWeapon::CalcViewmodelBob and CBaseViewModel::CalcViewModelLag from Source SDK 2013
// the bob is applied in HUD.PostRender and the sway is applied in Controller.RenderOverlays 
// so both are bracketed around the draw of the viewmodel and can write to its PlayerViewOffset safely.
const HL2_BOB_CYCLE_MAX = 0.45;     // basehlcombatweapon_shared.cpp:235
const HL2_BOB_UP        = 0.5;      // :237
const BOB_PI            = 3.14159265;

// HL2_BOB_CYCLE_MIN (1.0) and HL2_BOB (0.002) are defined alongside those two in
// Valve's file but never read by either function, and neither are the cvars
// cl_bob / cl_bobcycle / cl_bobup declared under them - CalcViewmodelBob uses
// the defines and its own literals throughout. they are not reproduced here,
// because a dial that is wired to nothing is worse than no dial. the single
// honest knob is GoldSrcPlayer.ViewModelBobScale.

var float BobTime;          // bobtime      (static in CalcViewmodelBob)
var float LastBobTime;      // lastbobtime  (ditto)
var float VerticalBob;      // g_verticalBob
var float LateralBob;       // g_lateralBob

// the weapon we have an offset written into right now and its real value.
var Weapon BobWeapon;
var Pawn   BobPawn;         // the pawn whose CalcDrawOffset places it
var vector BobSaved;        // the offset as it was before we touched it
var vector BobWrote;        // the offset we left standing for the draw
var vector BobDrawLoc;      // the weapon's Location at the moment we wrote it
var bool   bBobApplied;
var bool   bBobViaXPatch;   // wrote xOffsetX/Y/Z instead of PlayerViewOffset
var bool   bBobDrawn;       // the weapon actor moved between the write and the restore
var bool   bBobStomped;     // our value was gone again by the time we restored
var int    BobHUDCalls;     // applies driven by HUD.PostRender
var int    BobCtrlCalls;    // applies driven by Controller.RenderOverlays
var string BobDiag;         // why the last apply did nothing; movedebug shows it

// source viewmodel lag, ported from CBaseViewModel::CalcViewModelLag from Source SDK 2013

const MAX_VM_LAG = 1.5;         // g_fMaxViewModelLag, :459
const VM_LAG_SPEED = 5.0;       // flSpeed, :477
const VM_LAG_SCALE = 5.0;       // the offset multiplier at :492

var vector LagOffset;           // the finished offset, Source units, view space
var vector LastFacing;          // m_vecLastFacing
var bool   bLastFacingValid;    // LastFacing has been seeded
var float  LastLagTime;         // our stand-in for gpGlobals->frametime
var float  LagGap;              // flDiff: how far the gun's facing trails the view

// half-life hud yippie

var config bool bGoldSrcHud;
var config color HudColor;
var config float HudMinAlpha; // resting brightness. hud.h MIN_ALPHA is 100, mud on text
var config float HudScale;    // sits on top of the 480p scale, the whole row
var config int HudFontSize;   // FontInfo size step for the numbers

const HL_FADE_TIME = 100.0;
const HL_FADE_RATE = 20.0;
const HL_CRIT_HEALTH = 15;

const HL_FONT_H = 25.0;
const HL_DIGIT_W = 20.0;
const HL_REF_HEIGHT = 480.0;
const HL_ICON_H = 40.0;
const HL_BAR_FRAC = 16.0; // health.cpp uses HealthWidth/10, thinner reads better here

var float HealthFade, ArmorFade, AmmoFade; // one per elem.
var int LastHealth, LastArmor, LastAmmo; // what fade we watching
var float HudFadeTime, AmmoFadeTime; // stand in for fps

var HudPos SavedInvPos; // where Postal had the item box, thats gonna be for the way back
var bool bSavedInvPos;


// the first person weapon is drawn from inside HUD.PostRender so the bob is applied there,
// and the sway is applied in Controller.RenderOverlays, so both are bracketed around the draw and can write to the viewmodel's PlayerViewOffset safely

simulated event PostRender(canvas Canvas)
{
	BobHUDCalls++;
	ApplyViewModelBob();
	Super.PostRender(Canvas);
	RestoreViewModelBob();
}

simulated final function ApplyViewModelBob()
{
	local GoldSrcPlayer GP;
	local Pawn P;
	local Weapon W;
	local P2Weapon PW;

	// left over from the last frame, if any, and the one that will be restored after the draw
	if (bBobApplied)
		RestoreViewModelBob();

	GP = GoldSrcPlayer(PlayerOwner);
	if (GP == None)
	{
		BobBail("no GoldSrcPlayer");
		return;
	}

	if (GP.Move == None)
	{
		BobBail("no Move");
		return;
	}

	// Both knobs off still has to fall through while a stair step is being smoothed
	// out: that offset is not decoration, it is what keeps the gun from drifting
	// away from a camera the movement code just lowered.
	if (!GP.bViewModelBob && !GP.bViewModelSway && GP.StepSmoothShift == 0.0)
	{
		BobBail("off (cl_viewmodelbob 0, cl_viewmodelsway 0)");
		return;
	}

	// third person draws the pawn and not the viewmodel, so the bob is irrelevant
	if (GP.bBehindView)
	{
		BobBail("third person");
		return;
	}

	// viewtarget first, because the pawn can be None if the player is dead or in a camera
	P = Pawn(GP.ViewTarget);
	if (P == None)
		P = GP.Pawn;

	if (P == None)
	{
		BobBail("no pawn");
		return;
	}

	if (P.Weapon == None)
	{
		BobBail("no weapon");
		return;
	}
	W = P.Weapon;

	BobWeapon  = W;
	BobPawn    = P;
	BobDrawLoc = W.Location;
	PW         = P2Weapon(W);

	// xPatch rebuilds the viewmodel's PlayerViewOffset from its own xOffsetX/Y/Z, 
	// so if it is present and has overwritten those values we have to write them instead of the PlayerViewOffset. 
	// the two are equivalent, but the xPatch path is more direct and avoids a copy of the vector.

	bBobViaXPatch = (PW != None) && PW.xDisplayOverwrite;

	if (bBobViaXPatch)
	{
		BobSaved.X  = PW.xOffsetX;
		BobSaved.Y  = PW.xOffsetY;
		BobSaved.Z  = PW.xOffsetZ;
		BobWrote    = BobSaved + ViewModelOffset(GP, P, W);
		PW.xOffsetX = BobWrote.X;
		PW.xOffsetY = BobWrote.Y;
		PW.xOffsetZ = BobWrote.Z;
	}
	else
	{
		BobSaved           = W.PlayerViewOffset;
		BobWrote           = BobSaved + ViewModelOffset(GP, P, W);
		W.PlayerViewOffset = BobWrote;
	}

	bBobApplied = True;
	BobBail("applied");
}

// Why the last apply did nothing. Read back by movedebug; deliberately does no
// logging of its own -- this runs on every rendered frame, and the version that
// wrote a line whenever the reason changed could be provoked into writing to
// Postal2.log at frame rate, which is a disk hit inside the render path.

simulated final function BobBail(string Why)
{
	BobDiag = Why;
}

simulated final function RestoreViewModelBob()
{
	local P2Weapon PW;
	local vector Now;

	if (!bBobApplied)
		return;

	if (BobWeapon != None)
	{
		PW = P2Weapon(BobWeapon);

		if (bBobViaXPatch && PW != None)
		{
			Now.X = PW.xOffsetX;
			Now.Y = PW.xOffsetY;
			Now.Z = PW.xOffsetZ;
		}
		else
			Now = BobWeapon.PlayerViewOffset;

		bBobDrawn   = (BobWeapon.Location != BobDrawLoc);
		bBobStomped = (VSize(Now - BobWrote) > 0.001);

		if (bBobViaXPatch && PW != None)
		{
			PW.xOffsetX = BobSaved.X;
			PW.xOffsetY = BobSaved.Y;
			PW.xOffsetZ = BobSaved.Z;
		}
		else
			BobWeapon.PlayerViewOffset = BobSaved;
	}

	BobWeapon   = None;
	BobPawn     = None;
	bBobApplied = False;
}


// lowkey this is where the bob is calculated, but the actual application is in ApplyViewModelBob and the restoration is in RestoreViewModelBob. 
// the bob is calculated every frame, but only applied if the weapon is drawn and the player is in first person.

simulated final function CalcViewModelBob(GoldSrcPlayer GP, Pawn P)
{
	local vector v;
	local float speed, bob_offset, cycle, dt;

	dt = Level.TimeSeconds - LastBobTime;

	if (dt <= 0.0)
		return;

	dt          = FMin(dt, 0.1);
	LastBobTime = Level.TimeSeconds;

	// find the speed of the player
	v   = P.Velocity;
	v.Z = 0;
	speed = VSize(v) / FMax(GP.Move.WorldScale, 0.0001);    // -> to hammer units

	speed = FClamp(speed, -320, 320);

	bob_offset = speed / 320.0;         // RemapVal( speed, 0, 320, 0.0f, 1.0f )

	BobTime += dt * bob_offset;

	// calc the vertical bob
	cycle = BobTime - int(BobTime / HL2_BOB_CYCLE_MAX) * HL2_BOB_CYCLE_MAX;
	cycle /= HL2_BOB_CYCLE_MAX;

	if (cycle < HL2_BOB_UP)
		cycle = BOB_PI * cycle / HL2_BOB_UP;
	else
		cycle = BOB_PI + BOB_PI * (cycle - HL2_BOB_UP) / (1.0 - HL2_BOB_UP);

	VerticalBob = speed * 0.005;
	VerticalBob = VerticalBob * 0.3 + VerticalBob * 0.7 * Sin(cycle);

	VerticalBob = FClamp(VerticalBob, -7.0, 4.0);

	// calc the lateral bob
	cycle = BobTime - int((BobTime / HL2_BOB_CYCLE_MAX) * 2) * (HL2_BOB_CYCLE_MAX * 2);
	cycle /= (HL2_BOB_CYCLE_MAX * 2);

	if (cycle < HL2_BOB_UP)
		cycle = BOB_PI * cycle / HL2_BOB_UP;
	else
		cycle = BOB_PI + BOB_PI * (cycle - HL2_BOB_UP) / (1.0 - HL2_BOB_UP);

	LateralBob = speed * 0.005;
	LateralBob = LateralBob * 0.3 + LateralBob * 0.7 * Sin(cycle);
	LateralBob = FClamp(LateralBob, -7.0, 4.0);
}

// translation of CBaseHLCombatWeapon::CalcViewmodelBob, basehlcombatweapon_shared.cpp:235

simulated final function vector ViewModelBobOffset(GoldSrcPlayer GP)
{
	local vector Bob;

	Bob.X = VerticalBob * 0.1;
	Bob.Y = LateralBob  * 0.8;
	Bob.Z = VerticalBob * 0.1;

	// bob is calculated in hammer units, but the viewmodel is drawn in world units, so scale it down to world units before returning it
	return Bob * GP.ViewModelBobScale * GP.Move.WorldScale;
}

simulated final function CalcViewModelLag(GoldSrcPlayer GP, Pawn P)
{
	local rotator ViewRot;
	local vector  Fwd, Rgt, Up, Diff;
	local float   dt, Speed, Len, PitchDeg;

	dt = Level.TimeSeconds - LastLagTime;

	// same reasoning as in CalcViewModelBob ## if the frame time is zero or negative, the viewmodel is not moving and there is no lag to calculate.
	if (dt <= 0.0)
		return;

	ViewRot = P.GetViewRotation();
	GetAxes(ViewRot, Fwd, Rgt, Up);

	if (!bLastFacingValid || dt > 0.25)
	{
		LastFacing       = Fwd;
		bLastFacingValid = True;
		LastLagTime      = Level.TimeSeconds;
		LagOffset        = vect(0,0,0);
		LagGap           = 0.0;
		return;
	}

	dt          = FMin(dt, 0.1);
	LastLagTime = Level.TimeSeconds;

	Diff = Fwd - LastFacing;

	Speed = VM_LAG_SPEED;

	Len = VSize(Diff);
	LagGap = Len;

	if (Len > MAX_VM_LAG && MAX_VM_LAG > 0.0)
		Speed *= Len / MAX_VM_LAG;

	LastFacing = Normal(LastFacing + Diff * (Speed * dt));

	LagOffset.X = -VM_LAG_SCALE * (Diff Dot Fwd);
	LagOffset.Y = -VM_LAG_SCALE * (Diff Dot Rgt);
	LagOffset.Z = -VM_LAG_SCALE * (Diff Dot Up);

	if (!GP.bViewModelSwayPitch)
		return;

	// the DROOOOOOOPY
	PitchDeg = (ViewRot.Pitch & 65535) * 360.0 / 65536.0;
	if (PitchDeg > 180.0)
		PitchDeg -= 360.0;

	LagOffset.X += PitchDeg * 0.035;
	LagOffset.Y += PitchDeg * 0.03;
	LagOffset.Z += PitchDeg * 0.02;
}

// sway finished offset
simulated final function vector ViewModelLagOffset(GoldSrcPlayer GP)
{
	return LagOffset * GP.ViewModelSwayScale * GP.Move.WorldScale;
}

// The gun half of the stair-step smoothing:  view->origin[2] += oldz - simorg[2]
// (cl_dll/view.cpp:714). GoldSrcPlayer.CalcFirstPersonView has already done the
// camera half and left the shift in StepSmoothShift.
//
// Valve moves the camera and the view model by the same amount, so the gun holds
// still on screen while the origin climbs. P2 places the gun off the PAWN --
// P2Weapon.RenderOverlays does SetLocation(Instigator.Location +
// Instigator.CalcDrawOffset(self)) -- which the camera shift never reaches, so
// doing only the camera half leaves the gun behind and it reads as the gun
// floating up out of the frame. That is the bug this closes.
//
// PlayerViewOffset is not a world offset. CalcDrawOffset (P2Pawn.uc:787) spends it
// as ((0.9/Weapon.DisplayFOV * 100 * offset) >> GetViewRotation()), so to land a
// world delta of exactly StepSmoothShift on Z it has to be unrotated into view
// space and pre-divided by that 90/DisplayFOV factor. Both halves matter: the view
// is nearly always pitched somewhere while climbing stairs, and DisplayFOV is per
// weapon. Same units either way, because the xPatch path writes xOffsetX/Y/Z and
// P2Weapon rebuilds PlayerViewOffset out of them (:2417).
simulated final function vector ViewModelStepOffset(GoldSrcPlayer GP, Pawn P, Weapon W)
{
	local vector WorldShift;
	local float  FOVScale;

	if (GP.StepSmoothShift == 0.0 || W == None || P == None)
		return vect(0,0,0);

	WorldShift.Z = GP.StepSmoothShift;

	FOVScale = 1.0;
	if (W.DisplayFOV > 0.0)
		FOVScale = W.DisplayFOV / 90.0;

	return (WorldShift << P.GetViewRotation()) * FOVScale;
}

simulated final function vector ViewModelOffset(GoldSrcPlayer GP, Pawn P, Weapon W)
{
	local vector Ofs;

	if (GP.bViewModelBob)
	{
		CalcViewModelBob(GP, P);
		Ofs += ViewModelBobOffset(GP);
	}

	if (GP.bViewModelSway)
	{
		CalcViewModelLag(GP, P);
		Ofs += ViewModelLagOffset(GP);
	}
	else
	{

		bLastFacingValid = False;
		LagOffset        = vect(0,0,0);
		LagGap           = 0.0;
	}

	// Not decoration like the two above -- this one only holds the gun still
	// against a camera the movement code moved, so it is not gated on either knob.
	Ofs += ViewModelStepOffset(GP, P, W);

	return Ofs;
}

simulated function DrawHUD(canvas Canvas)
{
	Super.DrawHUD(Canvas);

	// draw ours last so it sits on top of the stock HUD.
	DrawGoldSrcOverlay(Canvas);
}

simulated final function DrawGoldSrcOverlay(canvas Canvas)
{
	local GoldSrcPlayer GP;
	local GoldSrcMovement M;

	GP = GoldSrcPlayer(PlayerOwner);
	if (GP == None)
		return;

	UpdateFps();

	if (GP.bShowNetGraph)
		DrawNetGraph(Canvas);

	if (GP.bShowPos)
		DrawShowPos(Canvas, GP.Move);

	// Before the Move check below: a hit lands the same whether or not the
	// simulation is the thing that is driving.
	if (GP.bDamageIndicator)
		DrawPain(Canvas);

	M = GP.Move;
	if (M == None)
		return;

	// track accel for readout
	UpdateAccel(M);

	if (GP.bShowSpeedometer)
		DrawSpeedometer(Canvas, M);

	if (bShowVelocityGraph && GP.bShowSpeedometer)
		DrawVelocityGraph(Canvas, M);

	if (GP.bShowMoveDebug)
		DrawMoveDebug(Canvas, M);
}

simulated final function ClearDamageDirection()
{
	AttackFront = 0;
	AttackRear  = 0;
	AttackLeft  = 0;
	AttackRight = 0;
}

// CHudHealth::CalcDamageDirection    (cl_dll/health.cpp:234)
//
// Valve's locals read oddly: `front` is the dot with RIGHT and `side` is the dot
// with FORWARD. The names are crossed, the arithmetic under them is not, and it is
// transcribed as written rather than tidied so the two files still diff.
simulated final function CalcDamageDirection(vector vecFrom, vector vecOrigin, rotator vecAngles)
{
	local vector forward, right, up;
	local float  side, front, f;
	local float  flDistToTarget;

	if (vecFrom == vect(0,0,0))
	{
		ClearDamageDirection();
		return;
	}

	vecFrom = vecFrom - vecOrigin;

	flDistToTarget = VSize(vecFrom);

	vecFrom = Normal(vecFrom);
	GetAxes(vecAngles, forward, right, up);

	front = vecFrom Dot right;
	side  = vecFrom Dot forward;

	if (flDistToTarget <= PAIN_NEAR_DIST)
	{
		// Close enough that there is no useful direction: light all four.
		AttackFront = 1;
		AttackRear  = 1;
		AttackRight = 1;
		AttackLeft  = 1;
		return;
	}

	if (side > 0)
	{
		if (side > PAIN_THRESHOLD)
			AttackFront = FMax(AttackFront, side);
	}
	else
	{
		f = Abs(side);
		if (f > PAIN_THRESHOLD)
			AttackRear = FMax(AttackRear, f);
	}

	if (front > 0)
	{
		if (front > PAIN_THRESHOLD)
			AttackRight = FMax(AttackRight, front);
	}
	else
	{
		f = Abs(front);
		if (f > PAIN_THRESHOLD)
			AttackLeft = FMax(AttackLeft, f);
	}
}

// CHudHealth::GetPainColor    (cl_dll/health.cpp:143)
//
// Valve keeps a health-scaled gradient in there behind an #if 0 and ships the
// two-colour version, so that is what this is.
simulated final function color GetPainColor()
{
	local color C;
	local int   iHealth;

	iHealth = 100;
	if (PlayerOwner != None && PlayerOwner.Pawn != None)
		iHealth = PlayerOwner.Pawn.Health;

	if (iHealth > 25)
		return PainColor;

	C.R = 250;
	C.G = 0;
	C.B = 0;
	return C;
}

// CHudHealth::DrawPain    (cl_dll/health.cpp:293)
//
// Every placement here is Valve's, spelled in units of the sprite it no longer
// has: the wedges sit two of their own short sides out from the crosshair. Valve
// draws them additively with the colour pre-scaled by the shade; a canvas tile
// blends on alpha instead, so the shade is carried there and the colour left alone.
simulated final function DrawPain(canvas Canvas)
{
	local float fFade, S, W, H, CX, CY;
	local color C;
	local int   a, shade;

	if (AttackFront == 0 && AttackRear == 0 && AttackLeft == 0 && AttackRight == 0)
	{
		PainLastTime = Level.TimeSeconds;
		return;
	}

	// TODO:  get the shift value of the health
	a = 255;    // max brightness until then

	// Clamped, or one loading screen's worth of elapsed time would swallow the
	// whole indicator before its first frame is drawn.
	fFade        = FClamp(Level.TimeSeconds - PainLastTime, 0.0, 1.0) * PAIN_FADE_RATE;
	PainLastTime = Level.TimeSeconds;

	S  = Canvas.ClipY / PAIN_REF_HEIGHT;
	W  = PAIN_SPR_W * S;
	H  = PAIN_SPR_H * S;
	CX = Canvas.ClipX * 0.5;
	CY = Canvas.ClipY * 0.5;

	C = GetPainColor();

	// SPR_Draw top
	if (AttackFront > PAIN_MIN_DRAW)
	{
		shade = int(a * FMax(AttackFront, PAIN_MIN_SHADE));
		DrawPainWedge(Canvas, CX - W * 0.5, CY - H * 3, W, H, 0, C, shade);
		AttackFront = FMax(0, AttackFront - fFade);
	}
	else
		AttackFront = 0;

	if (AttackRight > PAIN_MIN_DRAW)
	{
		shade = int(a * FMax(AttackRight, PAIN_MIN_SHADE));
		DrawPainWedge(Canvas, CX + H * 2, CY - W * 0.5, H, W, 1, C, shade);
		AttackRight = FMax(0, AttackRight - fFade);
	}
	else
		AttackRight = 0;

	if (AttackRear > PAIN_MIN_DRAW)
	{
		shade = int(a * FMax(AttackRear, PAIN_MIN_SHADE));
		DrawPainWedge(Canvas, CX - W * 0.5, CY + H * 2, W, H, 2, C, shade);
		AttackRear = FMax(0, AttackRear - fFade);
	}
	else
		AttackRear = 0;

	if (AttackLeft > PAIN_MIN_DRAW)
	{
		shade = int(a * FMax(AttackLeft, PAIN_MIN_SHADE));
		DrawPainWedge(Canvas, CX - H * 3, CY - W * 0.5, H, W, 3, C, shade);
		AttackLeft = FMax(0, AttackLeft - fFade);
	}
	else
		AttackLeft = 0;
}

// more color stuff

simulated final function color ScaleHudColors(color C, float a)
{
	local color Out;

	Out.R = int(float(C.R) * a / 255.0);
	Out.G = int(float(C.G) * a / 255.0);
	Out.B = int(float(C.B) * a / 255.0);
	Out.A = 255;
	return Out;
}


simulated final function float HudFlashAlpha(out float Fade, out int Last, int Value, float Delta)
{
	local float Floor;

	Floor = FClamp(HudMinAlpha, 0.0, 255.0);

	if (Value != Last)
	{
		Last = Value;
		Fade = HL_FADE_TIME;
	}

	if (Fade <= 0.0)
		return Floor;

	Fade -= Delta * HL_FADE_RATE;
	if (Fade < 0.0)
		Fade = 0.0;

	return Floor + (Fade / HL_FADE_TIME) * (255.0 - Floor);
}

simulated final function float HudRowScale(canvas Canvas)
{
	return (Canvas.ClipY / HL_REF_HEIGHT) * FMax(HudScale, 0.1);
}

// health.cpp:213, y = ScreenHeight - m_iFontHeight - m_iFontHeight / 2
simulated final function float HudRowY(canvas Canvas)
{
	return Canvas.ClipY - HL_FONT_H * 1.5 * HudRowScale(Canvas);
}

simulated final function DrawHudDivider(canvas Canvas, float X, float Y, float S, color C)
{
	Canvas.Style = ERenderStyle.STY_Normal;
	Canvas.SetDrawColor(C.R, C.G, C.B, 255);
	Canvas.SetPos(X, Y);
	Canvas.DrawTile(Texture'engine.WhiteSquareTexture',
			FMax(HL_DIGIT_W * S / HL_BAR_FRAC, 1.0), HL_FONT_H * S, 0, 0, 1, 1);
}

simulated function DrawHealthAndArmor(canvas Canvas, float Scale)
{
	local float Delta;

	if (!bGoldSrcHud)
	{
		Super.DrawHealthAndArmor(Canvas, Scale);
		return;
	}

	Delta = FClamp(Level.TimeSeconds - HudFadeTime, 0.0, 0.1);
	HudFadeTime = Level.TimeSeconds;

	DrawGoldSrcHealth(Canvas, Delta);
	DrawGoldSrcArmor(Canvas, Delta);
}

simulated function DrawWeapon(canvas Canvas, float Scale)
{
	if (!bGoldSrcHud)
	{
		Super.DrawWeapon(Canvas, Scale);
		return;
	}

	DrawGoldSrcAmmo(Canvas);
}

simulated function PostBeginPlay()
{
	Super.PostBeginPlay();

	if (InvIndex < IconPos.Length)
	{
		SavedInvPos = IconPos[InvIndex];
		bSavedInvPos = true;
	}

	if (bGoldSrcHud)
		ApplyGoldSrcLayout();
}


// the item box drops to just above the ammo row instead of Postal's right hand column
simulated final function ApplyGoldSrcLayout()
{
	if (InvIndex < IconPos.Length)
	{
		IconPos[InvIndex].X = 0.935;
		IconPos[InvIndex].Y = 0.800;
	}
}

simulated final function RestoreP2Layout()
{
	if (bSavedInvPos && InvIndex < IconPos.Length)
	{
		IconPos[InvIndex] = SavedInvPos;
	}
}


simulated final function DrawGoldSrcHealth(canvas Canvas, float Delta)
{
	local Texture Tex;
	local int    UseHealth, HealthColor;
	local float HeartW, HeartH, PumpScale, UseScale;
	local float Y, S, a, SlotW, NumRight;
	local color C;

	if (PawnOwner == None)
		return;
	S = HudRowScale(Canvas);
	Y = HudRowY(Canvas);

	UseHealth = PawnOwner.GetHealthPercent();

	if (UseHealth > 100)
		HealthColor = 100;
	else
		HealthColor = UseHealth;

	if (UseHealth == 0 && PawnOwner.Health > 0)
		UseHealth = 1;

	a = HudFlashAlpha(HealthFade, LastHealth, UseHealth, Delta);
	if (UseHealth <= HL_CRIT_HEALTH)
		a = 255.0;

	SlotW = HL_ICON_H * S;      // fixed: the beat must not shove the number or the bar

	Tex = Texture(HeartIcon);
	if (Tex != None)
	{
		PumpScale = 64.0 / Tex.VSize;
		HeartW = Tex.USize + (HeartPumpSizeX * PumpScale * Tex.USize - Tex.USize / 4);
		HeartH = Tex.VSize + (HeartPumpSizeY * PumpScale * Tex.VSize - Tex.VSize / 4);
		UseScale = SlotW / Tex.VSize;
		HeartW *= UseScale;
		HeartH *= UseScale;

		Canvas.Style = ERenderStyle.STY_Masked;
		if (OurPlayer != None && OurPlayer.CatnipUseTime > 0)
			Canvas.SetDrawColor(155 + HealthColor, 55 + HealthColor * 2, 0);
		else
			Canvas.SetDrawColor(155 + HealthColor, 55 + HealthColor * 2, 55 + HealthColor * 2);

		// health.cpp centres the cross one CrossWidth in, so the beat grows around
		// that point and the rest of the row stays put
		Canvas.SetPos(SlotW - HeartW * 0.5, Y + (HL_FONT_H * S - HeartH) * 0.5);
		Canvas.DrawTile(Tex, HeartW, HeartH, 0, 0, Tex.USize, Tex.VSize);
	}

	// three digits, right aligned, so it grows leftward like Valve's number sprites
	NumRight = SlotW * 1.2 + HL_DIGIT_W * S * 3.0;
	C = ScaleHudColors(HudColor, a);

	MyFont.DrawTextEx(Canvas, CanvasWidth, NumRight, Y, ""$UseHealth, HudFontSize, , EJ_Right, C);
	DrawHudDivider(Canvas, NumRight + HL_DIGIT_W * S * 0.5, Y, S, C);
}

// battery.cpp: the battery sits at ScreenWidth/5 on the same row, its number right
// after the icon, no divider
simulated final function DrawGoldSrcArmor(canvas Canvas, float Delta)
{
	local Texture Tex;
	local int   UseArmor;
	local float X, Y, S, a, IconW, IconH, UseScale;

	if (PawnOwner == None || OurPlayer == None)
		return;

	UseArmor = PawnOwner.GetArmorPercent();
	if (UseArmor <= 0)
		return;

	S = HudRowScale(Canvas);
	Y = HudRowY(Canvas);
	X = Canvas.ClipX / 5.0;

	a = HudFlashAlpha(ArmorFade, LastArmor, UseArmor, Delta);

	Tex = OurPlayer.HudArmorIcon;
	IconW = HL_ICON_H * S;

	if (Tex != None)
	{
		UseScale = (HL_ICON_H * S) / Tex.VSize;
		IconW = Tex.USize * UseScale;
		IconH = Tex.VSize * UseScale;

		Canvas.Style = ERenderStyle.STY_Masked;
		Canvas.DrawColor = DefaultIconColor;
		Canvas.SetPos(X, Y + (HL_FONT_H * S - IconH) * 0.5);
		Canvas.DrawTile(Tex, IconW, IconH, 0, 0, Tex.USize, Tex.VSize);
	}

	MyFont.DrawTextEx(Canvas, CanvasWidth, X + IconW + HL_DIGIT_W * S * 3.0, Y,
		""$UseArmor, HudFontSize, , EJ_Right, ScaleHudColors(HudColor, a));
}

// ammo.cpp: bottom right, the clip then the | bar then the reserve then the icon.
// x = ScreenWidth - 8 * AmmoWidth - iIconWidth when there's a clip to show.
simulated final function DrawGoldSrcAmmo(canvas Canvas)
{
	local P2Weapon W;
	local P2AmmoInv Ammo;
	local Texture Tex;
	local string ClipStr, ResStr;
	local bool  bHasClip;
	local float Y, S, a, Delta, DigitW, IconW, IconH, UseScale;
	local float Left, BarX, ResRight;
	local color C;

	if (PawnOwner == None || PawnOwner.Weapon == None)
		return;

	Ammo = P2AmmoInv(PawnOwner.Weapon.AmmoType);
	if (Ammo == None || !Ammo.bShowAmmoOnHud)
		return;

	W = P2Weapon(PawnOwner.Weapon);
	bHasClip = (W != None && W.default.ReloadCount != 0 && !W.bHideReloadCount);

	if (Ammo.bShowAmmoAsPercent)
	{
		bHasClip = false;
		ResStr = ""$int(100.0 * float(Ammo.AmmoAmount) / float(Ammo.MaxAmmo))$"%";
	}
	else if (bHasClip)
	{
		ClipStr = ""$W.ReloadCount;
		ResStr  = ""$Ammo.AmmoAmount;
	}
	else
	{
		ResStr = ""$Ammo.AmmoAmount;
		if (Ammo.bShowMaxAmmoOnHud)
			ResStr = ResStr$"/"$Ammo.MaxAmmo;
	}

	S      = HudRowScale(Canvas);
	Y      = HudRowY(Canvas);
	DigitW = HL_DIGIT_W * S;

	Delta = FClamp(Level.TimeSeconds - AmmoFadeTime, 0.0, 0.1);
	AmmoFadeTime = Level.TimeSeconds;
	a = HudFlashAlpha(AmmoFade, LastAmmo, Ammo.AmmoAmount, Delta);
	C = ScaleHudColors(HudColor, a);

	// Postal lets a weapon override the ammo icon, so honour that first
	if (W != None && W.OverrideHUDIcon != None)
		Tex = W.OverrideHUDIcon;
	else
		Tex = Texture(PawnOwner.Weapon.AmmoType.Texture);

	IconW = HL_ICON_H * S;
	if (Tex != None)
	{
		UseScale = (HL_ICON_H * S) / Tex.VSize;
		IconW = Tex.USize * UseScale;
		IconH = Tex.VSize * UseScale;
	}

	if (bHasClip)
	{
		Left     = Canvas.ClipX - 8.0 * DigitW - IconW;
		BarX     = Left + 3.5 * DigitW;
		ResRight = BarX + DigitW / HL_BAR_FRAC + 3.5 * DigitW;

		MyFont.DrawTextEx(Canvas, CanvasWidth, Left + 3.0 * DigitW, Y, ClipStr, HudFontSize, , EJ_Right, C);
		DrawHudDivider(Canvas, BarX, Y, S, C);
	}
	else
		ResRight = Canvas.ClipX - DigitW - IconW;

	MyFont.DrawTextEx(Canvas, CanvasWidth, ResRight, Y, ResStr, HudFontSize, , EJ_Right, C);

	if (Tex != None)
	{
		Canvas.Style = ERenderStyle.STY_Masked;
		Canvas.DrawColor = DefaultIconColor;
		Canvas.SetPos(ResRight + DigitW * 0.5, Y + (HL_FONT_H * S - IconH) * 0.5 - IconH / 8.0);
		Canvas.DrawTile(Tex, IconW, IconH, 0, 0, Tex.USize, Tex.VSize);
	}
}

// One wedge, narrowing towards the crosshair. Dir is Valve's sprite frame number:
// 0 top, 1 right, 2 bottom, 3 left. The canvas fills rectangles and nothing else,
// so the taper is sliced out of them.

simulated final function DrawPainWedge(canvas Canvas, float X, float Y, float RW, float RH, int Dir, color C, int A)
{
	local int   i;
	local float t, scale, sw, sh, step;

	Canvas.Style = ERenderStyle.STY_Normal;
	Canvas.SetDrawColor(C.R, C.G, C.B, A);

	if (Dir == 0 || Dir == 2)
	{
		step = RH / float(PAIN_SLICES);

		for (i = 0; i < PAIN_SLICES; i++)
		{
			t = float(i) / float(PAIN_SLICES - 1);

			if (Dir == 0)
				scale = 1.0 - (1.0 - PAIN_TAPER) * t;
			else
				scale = PAIN_TAPER + (1.0 - PAIN_TAPER) * t;

			sw = RW * scale;

			// One pixel of overlap: without it the seams show as gaps.
			Canvas.SetPos(X + (RW - sw) * 0.5, Y + float(i) * step);
			Canvas.DrawTile(Texture'engine.WhiteSquareTexture', sw, step + 1, 0, 0, 1, 1);
		}

		return;
	}

	step = RW / float(PAIN_SLICES);

	for (i = 0; i < PAIN_SLICES; i++)
	{
		t = float(i) / float(PAIN_SLICES - 1);

		if (Dir == 1)
			scale = PAIN_TAPER + (1.0 - PAIN_TAPER) * t;
		else
			scale = 1.0 - (1.0 - PAIN_TAPER) * t;

		sh = RH * scale;

		Canvas.SetPos(X + float(i) * step, Y + (RH - sh) * 0.5);
		Canvas.DrawTile(Texture'engine.WhiteSquareTexture', step + 1, sh, 0, 0, 1, 1);
	}
}

// smooth the accel readout and push the current speed into the graph history for the velocity graph

simulated final function UpdateAccel(GoldSrcMovement M)
{
	local float Spd, dt, Inst;

	Spd = M.HorizontalSpeedHL();
	dt  = M.frametime;

	if (dt > 0.0)
	{
		Inst         = (Spd - LastSpeed) / dt;
		DisplayAccel = DisplayAccel + (Inst - DisplayAccel) * 0.15;
	}

	LastSpeed = Spd;

	// push to graph history
	//
	// Only DrawVelocityGraph reads this, and bShowVelocityGraph is off by default
	// (it is an ini-only switch), so without the gate every frame in the shipped
	// configuration writes a sample nobody will ever draw. Resetting the cursor on
	// the way past means the graph starts empty when it is switched on rather than
	// drawing a ring buffer full of speeds from minutes ago.
	if (!bShowVelocityGraph)
	{
		GraphIndex   = 0;
		bGraphFilled = false;
		return;
	}

	GraphSpeed[GraphIndex] = Spd;
	GraphIndex++;
	if (GraphIndex >= GRAPH_SAMPLES)
	{
		GraphIndex   = 0;
		bGraphFilled = true;
	}
}

// bunnymod xt users favourite feature. SHOUTOUT MY BOY YALTER

simulated final function DrawSpeedometer(canvas Canvas, GoldSrcMovement M)
{
	local float Spd, BaseX, BaseY, XL, YL;
	local string S;

	Spd = M.HorizontalSpeedHL();

	Canvas.Font       = Canvas.MedFont;
	Canvas.Style      = ERenderStyle.STY_Normal;
	Canvas.FontScaleX = 1.0;
	Canvas.FontScaleY = 1.0;

	// Speed now, and the speed the last jump left the ground at in brackets after
	// it -- the two numbers a bunnyhop is actually judged on. No label and no unit:
	// the row is read hundreds of times a run and the words never change.
	S = int(Spd + 0.5) @ "(" $ int(M.DebugTakeoffSpeed / FMax(M.WorldScale, 0.0001) + 0.5) $ ")";

	Canvas.StrLen(S, XL, YL);

	BaseX = (Canvas.ClipX * 0.5) - (XL * 0.5);
	BaseY = Canvas.ClipY - (Canvas.ClipY * 0.18);

	// Drop shadow for legibility on bright scenery.
	Canvas.SetDrawColor(0, 0, 0, 160);
	Canvas.SetPos(BaseX + 1, BaseY + 1);
	Canvas.DrawText(S, false);

	Canvas.SetDrawColor(SpeedColor.R, SpeedColor.G, SpeedColor.B, SpeedColor.A);
	Canvas.SetPos(BaseX, BaseY);
	Canvas.DrawText(S, false);

	// accel readout
	if (Abs(DisplayAccel) > 5.0)
	{
		Canvas.Font = Canvas.SmallFont;

		if (DisplayAccel > 0)
		{
			S = "+" $ int(DisplayAccel + 0.5);
			Canvas.SetDrawColor(AccelColor.R, AccelColor.G, AccelColor.B, AccelColor.A);
		}
		else
		{
			S = string(int(DisplayAccel - 0.5));
			Canvas.SetDrawColor(DecelColor.R, DecelColor.G, DecelColor.B, DecelColor.A);
		}

		Canvas.StrLen(S, XL, YL);
		Canvas.SetPos((Canvas.ClipX * 0.5) - (XL * 0.5), BaseY + YL + 2);
		Canvas.DrawText(S, false);
	}
}

// the velgraph

simulated final function DrawVelocityGraph(canvas Canvas, GoldSrcMovement M)
{
	local int   i, idx, Count;
	local float GW, GH, GX, GY, BarW, Peak, V, H;

	GW = 192.0;
	GH = 48.0;
	GX = (Canvas.ClipX * 0.5) - (GW * 0.5);
	GY = Canvas.ClipY - (Canvas.ClipY * 0.18) - GH - 12;

	if (bGraphFilled)
		Count = GRAPH_SAMPLES;
	else
		Count = GraphIndex;

	if (Count < 2)
		return;

	// scale to tallest sample
	Peak = 320.0;
	for (i = 0; i < Count; i++)
	{
		if (GraphSpeed[i] > Peak)
			Peak = GraphSpeed[i];
	}

	// backing panel
	Canvas.SetDrawColor(0, 0, 0, 90);
	Canvas.SetPos(GX, GY);
	Canvas.DrawTile(Texture'engine.WhiteSquareTexture', GW, GH, 0, 0, 1, 1);

	BarW = GW / float(GRAPH_SAMPLES);

	Canvas.SetDrawColor(SpeedColor.R, SpeedColor.G, SpeedColor.B, 200);

	for (i = 0; i < Count; i++)
	{
		// walk the buffer oldest-to-newest so the graph scrolls left
		if (bGraphFilled)
			idx = (GraphIndex + i) % GRAPH_SAMPLES;
		else
			idx = i;

		V = GraphSpeed[idx];
		H = (V / Peak) * GH;

		if (H < 1.0)
			H = 1.0;

		Canvas.SetPos(GX + (float(i) * BarW), GY + GH - H);
		Canvas.DrawTile(Texture'engine.WhiteSquareTexture', FMax(BarW - 1, 1), H, 0, 0, 1, 1);
	}
}

// framerate which is averaged over FPS_WINDOW seconds.
simulated final function UpdateFps()
{
	local float dt;

	if (LastFrameTime <= 0.0)
	{
		LastFrameTime = Level.TimeSeconds;
		return;
	}

	dt            = (Level.TimeSeconds - LastFrameTime) / FMax(Level.TimeDilation, 0.0001);
	LastFrameTime = Level.TimeSeconds;

	if (dt <= 0.0)
		return;

	FpsAccumTime += dt;
	FpsFrames++;

	if (FpsAccumTime >= FPS_WINDOW)
	{
		DisplayFps   = float(FpsFrames) / FpsAccumTime;
		FpsAccumTime = 0.0;
		FpsFrames    = 0;
	}
}

// EVERY SOURCE ENGINE PLAYER'S FAVOURITE COMMAND ON JAH.

simulated final function DrawNetGraph(canvas Canvas)
{
	local float RX, Y, XL, YL;
	local int   Ping;

	Canvas.Font       = Canvas.SmallFont;
	Canvas.Style      = ERenderStyle.STY_Normal;
	Canvas.FontScaleX = 1.0;
	Canvas.FontScaleY = 1.0;

	Canvas.StrLen("Wg", XL, YL);

	if (PlayerOwner != None && PlayerOwner.PlayerReplicationInfo != None)
		Ping = PlayerOwner.PlayerReplicationInfo.Ping;

	RX = Canvas.ClipX - 16;
	Y  = Canvas.ClipY - 16 - (YL * 4);

	DrawRight(Canvas, RX, Y, "fps: " $ int(DisplayFps + 0.5) $ "   ping: " $ Ping,
		NetGraphColor);
	Y += YL;

	DrawRight(Canvas, RX, Y, "in :  0.00   0.00 k/s   0.0/s", NetGraphColor);
	Y += YL;

	DrawRight(Canvas, RX, Y, "out:  0.00   0.00 k/s   0.0/s", NetGraphColor);
	Y += YL;

	DrawRight(Canvas, RX, Y, "loss: 0   choke: 0", NetGraphColor);
}
// hello half life 2


simulated final function DrawShowPos(canvas Canvas, GoldSrcMovement M)
{
	local vector  Pos, Vel;
	local rotator R;
	local float   X, Y, YL, XL, Scale;

	if (PlayerOwner == None)
		return;

	if (M != None)
		Scale = M.WorldScale;
	else
		Scale = class'GoldSrcMovement'.default.WorldScale;

	Scale = FMax(Scale, 0.0001);

	if (PlayerOwner.Pawn != None)
	{
		Pos = PlayerOwner.Pawn.Location;
		Vel = PlayerOwner.Pawn.Velocity;
	}
	else
	{
		Pos = PlayerOwner.Location;
	}

	// our own velocity when we have it

	if (M != None)
		Vel = M.velocity;

	R = PlayerOwner.Rotation;

	Canvas.Font       = Canvas.SmallFont;
	Canvas.Style      = ERenderStyle.STY_Normal;
	Canvas.FontScaleX = 1.0;
	Canvas.FontScaleY = 1.0;

	Canvas.StrLen("Wg", XL, YL);

	X = 12;
	Y = 12;

	DrawPosLine(Canvas, X, Y, "pos:", Fmt2(Pos.X), Fmt2(Pos.Y), Fmt2(Pos.Z));
	Y += YL;

	DrawPosLine(Canvas, X, Y, "ang:", Fmt2(-UnrToDeg(R.Pitch)), Fmt2(UnrToDeg(R.Yaw)),
		Fmt2(UnrToDeg(R.Roll)));
	Y += YL;

	DrawPosLine(Canvas, X, Y, "vel:", Fmt2(VSize(Vel) / Scale), "", "");
}

simulated final function DrawPosLine(canvas Canvas, float X, float Y, string Label,
	string A, string B, string C)
{
	local float ColW;

	ColW = 76;

	DrawShadowed(Canvas, X, Y, Label, ShowPosColor);

	if (A != "")
		DrawRight(Canvas, X + 44 + ColW, Y, A, ShowPosColor);

	if (B != "")
		DrawRight(Canvas, X + 44 + (ColW * 2), Y, B, ShowPosColor);

	if (C != "")
		DrawRight(Canvas, X + 44 + (ColW * 3), Y, C, ShowPosColor);
}

// another like dumbahh dev readout because i gotta keep it safe

simulated final function DrawMoveDebug(canvas Canvas, GoldSrcMovement M)
{
	local GoldSrcPlayer GP;
	local float X, Y, YL, XL;
	local string GroundStr;
	local string StompStr;
	local name  BodyAnim;
	local float BodyFrame, BodyRate;

	GP = GoldSrcPlayer(PlayerOwner);

	X = 16;
	Y = Canvas.ClipY * 0.30;

	Canvas.Font       = Canvas.SmallFont;
	Canvas.Style      = ERenderStyle.STY_Normal;
	Canvas.FontScaleX = 1.0;
	Canvas.FontScaleY = 1.0;

	Canvas.StrLen("Wg", XL, YL);

	if (M.onground)
		GroundStr = "ONGROUND";
	else
		GroundStr = "AIR";

	DebugLine(Canvas, X, Y, YL, 0, "-- DudeSrc debug HUD --");
	Y += YL;

	DebugLine(Canvas, X, Y, YL, 0, "velocity   " $ VecStr(M.velocity / FMax(M.WorldScale, 0.0001)));
	Y += YL;

	DebugLine(Canvas, X, Y, YL, 0, "horiz spd  " $ FmtF(M.HorizontalSpeedHL()) @ "ups");
	Y += YL;

	// same speed measured the other way round

	if (GP != None)
	{
		DebugLine(Canvas, X, Y, YL, 0, "measured   " $ FmtF(GP.MeasuredSpeedHL) @ "ups");
		Y += YL;

		// who moved the pawn and what we did about it. every hit takes us off
		// PHYS_None (P2Pawn.uc:2327), so "stomp" counts hits landing on us; "drift"
		// is the displacement that produced. kept means the simulation adopted it,
		// put back means it was native physics and we refused it. sustained fire
		// should show stomps with put-back climbing and kept at zero. see
		// GoldSrcPlayer.RestorePawnPosition.
		if (GP.LastStompPhysics != '')
		{
			StompStr = string(GP.LastStompPhysics);
			if (Level.TimeSeconds - GP.LastStompTime > 1.0)
				StompStr = StompStr $ " (idle)";

			DebugLine(Canvas, X, Y, YL, 0, "stomp      " $ StompStr
				$ "  " $ GP.StompsPerSec $ "/s");
			Y += YL;
		}

		if (GP.DriftAdoptedHL > 0.5 || GP.DriftRefusedHL > 0.5)
		{
			DebugLine(Canvas, X, Y, YL, 0, "drift      kept " $ FmtF(GP.DriftAdoptedHL)
				$ "  put back " $ FmtF(GP.DriftRefusedHL) @ "ups");
			Y += YL;
		}

		// the pawn's body animation and the mode it was chosen for. P2MoCapPawn
		// picks a LOOPING run animation for every physics mode except PHYS_None
		// (PlayMoving, :1848) and its footstep notify checks nothing at all
		// (Notify_Footstep, :5463), so a run loop left behind by a stolen physics
		// window is audible forever. Standing still here should read an idle pose
		// (s*_base*) on phys PHYS_None; a run name while stopped is that bug.
		// See GoldSrcPlayer.SyncPawnAnimation.
		//
		// The mode, the base and the hold count belong on this row too, because
		// they are the same story: the pawn loses PHYS_None whenever it loses a
		// base it should not have had (P2Pawn.BaseChange:1281), and holds counts
		// every time that had to be undone. phys must read PHYS_None at all
		// times; base is None once the simulation has settled, and anything else
		// means a stolen mode based us on something. See HoldPhysNone.
		if (GP.Pawn != None)
		{
			GP.Pawn.GetAnimParams(0, BodyAnim, BodyFrame, BodyRate);

			DebugLine(Canvas, X, Y, YL, 0, "body anim  " $ BodyAnim
				$ "  rate " $ FmtF(BodyRate)
				$ "  " $ GetEnum(enum'EPhysics', GP.Pawn.Physics));
			Y += YL;

			DebugLine(Canvas, X, Y, YL, 0, "phys hold  " $ GP.PhysHolds
				$ "  base " $ GP.Pawn.Base);
			Y += YL;

			// The other two thirds of the position diagnostic (GoldSrcPlayer:118):
			// whether SetLocation is being refused, and whether the pawn was inside
			// something the last time it was.
			DebugLine(Canvas, X, Y, YL, 0, "setloc     refused " $ GP.SetLocFails
				$ "  salvaged " $ GP.SetLocSalvaged
				$ "  clipped " $ GP.SetLocClipped
				$ "  embedded " $ YesNo(GP.bLastMoveEmbedded, "YES", "no"));
			Y += YL;

			// ...and WHAT refused it, which no other row can tell you, because the
			// touch row is filtered through BlocksPlayer and a refusal is by
			// definition something that filter passes. Watch this one while walking
			// into a snag: it names the actor, or says the engine objected to the
			// destination itself rather than to anything on the way to it.
			if (GP.RefuseTime > 0.0)
			{
				DebugLine(Canvas, X, Y, YL, 0, "refused    " $ GP.RefuseName
					$ " (" $ GP.RefuseClass $ ")"
					$ "  want " $ FmtF(GP.RefuseWanted)
					$ "  got " $ FmtF(GP.RefuseMoved)
					$ "  " $ FmtF(GP.Level.TimeSeconds - GP.RefuseTime) $ "s");
				Y += YL;
			}
		}
	}

	// what the frame actually costs
	DebugLine(Canvas, X, Y, YL, 0, "cost       " $ M.TracesPerFrame $ " traces  "
		$ M.WaterScansPerFrame $ " wscan");
	Y += YL;

	DebugLine(Canvas, X, Y, YL, 0, "vert spd   " $ FmtF(M.VerticalSpeedHL()) @ "ups");
	Y += YL;

	DebugLine(Canvas, X, Y, YL, 0, "state      " $ GroundStr @ "/" @ M.DebugMoveState);
	Y += YL;

	// what the ground trace actually found, and how steep the last plane we hit
	// was. the row above is derived from this one -- onground is nothing more than
	// "the downward trace found something" -- so AIR here while standing on a floor
	// means the trace is being masked by something non-blocking parked in it, and
	// LevelInfo means BSP while a name like StaticMeshActor42 means a mesh. normal
	// z under 0.70 is too steep to stand on by HL's rule and reads as AIR on purpose.
	DebugLine(Canvas, X, Y, YL, 0, "ground     " $ M.groundEntity
		$ "  normal z " $ FmtF(M.TracePlaneNormal.Z));
	Y += YL;

	// What is in the way. "touch" is the last thing a sideways or upward move ran
	// into -- an invisible wall is an actor here with hidden in its flags -- and
	// "overlap" is everything the hull is standing inside right now, straight off
	// the pawn's own touch list, which is where triggers and volumes show up.
	DebugLine(Canvas, X, Y, YL, 0, "touch      " $ BlockerStr(M));
	Y += YL;

	DebugLine(Canvas, X, Y, YL, 0, "overlap    " $ OverlapStr(M.PM));
	Y += YL;

	DebugLine(Canvas, X, Y, YL, 0, "ducking    " $ YesNo(M.bDucking, "yes", "no")
		$ "  hull " $ M.usehull);
	Y += YL;

	// the input side

	if (GP != None)
	{
		DebugLine(Canvas, X, Y, YL, 0, "axis       " $ VecStr(GP.DebugRawAxes)
			$ "  peak " $ FmtF(GP.DebugAxisPeak) $ "/" $ FmtF(GP.MoveAxisMax));
		Y += YL;
	}

	DebugLine(Canvas, X, Y, YL, 0, "wishdir    " $ VecStr(M.DebugWishDir));
	Y += YL;

	DebugLine(Canvas, X, Y, YL, 0, "wishspeed  " $ FmtF(M.DebugWishSpeed / FMax(M.WorldScale, 0.0001)));
	Y += YL;

	DebugLine(Canvas, X, Y, YL, 0, "accel      " $ FmtF(DisplayAccel) @ "ups/s");
	Y += YL;

	DebugLine(Canvas, X, Y, YL, 0, "takeoff    " $ FmtF(M.DebugTakeoffSpeed / FMax(M.WorldScale, 0.0001)));
	Y += YL;

	DebugLine(Canvas, X, Y, YL, 0, "frametime  " $ FmtF(M.frametime * 1000.0) @ "ms");
	Y += YL;

	// every time PM_WalkMove had to nudge us out of a flush contact to move at
	// all. climbing while you cannot move means the weld is the flush-trace one
	// and the nudge is not enough, staying at zero while you cannot move means
	// whatever is holding you is not the walk move
	DebugLine(Canvas, X, Y, YL, 0, "weld       nudges " $ M.WeldNudges
		$ "   stuck " $ YesNo(M.bWasStuck, "YES", "no") $ "/" $ M.StuckFrames);
	Y += YL;

	// what the last hit actually added to the simulation, in hammer units, and how
	// long ago. this is the number to watch when tuning the knockback dials, a
	// blast reading far above the cap means the push did not come through
	// GoldSrcPlayer.DriveDamage at all
	if (M.DebugLastPushTime > 0.0)
	{
		DebugLine(Canvas, X, Y, YL, 0, "dmg push   "
			$ FmtF(VSize(M.DebugLastPush) / FMax(M.WorldScale, 0.0001)) @ "ups   z "
			$ FmtF(M.DebugLastPush.Z / FMax(M.WorldScale, 0.0001)) $ "   "
			$ FmtF(Level.TimeSeconds - M.DebugLastPushTime) $ "s ago");
	}
	else
	{
		DebugLine(Canvas, X, Y, YL, 0, "dmg push   none yet");
	}
	Y += YL;

	// the bob magnitudes, in Source units: the offset CalcViewModelBob produced this frame
	DebugLine(Canvas, X, Y, YL, 0, "vm bob     v " $ FmtF(VerticalBob)
		$ "  l " $ FmtF(LateralBob) $ "   " $ BobDiag);
	Y += YL;

	// what became of it
	DebugLine(Canvas, X, Y, YL, 0, "vm bob     off " $ VecStr(BobWrote)
		$ "  drawn " $ YesNo(bBobDrawn, "y", "N")
		$ "  stomp " $ YesNo(bBobStomped, "Y", "n")
		$ "  hud " $ BobHUDCalls $ "  ctrl " $ BobCtrlCalls
		$ YesNo(bBobViaXPatch, "  (xPatch)", ""));
	Y += YL;

	// the sway offset, in Source units: the offset CalcViewModelLag produced this frame
	DebugLine(Canvas, X, Y, YL, 0, "vm sway    " $ VecStr(LagOffset)
		$ "  gap " $ FmtF(LagGap) $ "/" $ FmtF(MAX_VM_LAG));
	Y += YL;

	Y += YL * 0.5;

	DebugLine(Canvas, X, Y, YL, 0, "sv_maxspeed      " $ FmtF(M.sv_maxspeed));
	Y += YL;
	DebugLine(Canvas, X, Y, YL, 0, "sv_accelerate    " $ FmtF(M.sv_accelerate));
	Y += YL;
	DebugLine(Canvas, X, Y, YL, 0, "sv_airaccelerate " $ FmtF(M.sv_airaccelerate));
	Y += YL;
	DebugLine(Canvas, X, Y, YL, 0, "sv_friction      " $ FmtF(M.sv_friction));
	Y += YL;
	DebugLine(Canvas, X, Y, YL, 0, "sv_stopspeed     " $ FmtF(M.sv_stopspeed));
	Y += YL;
	DebugLine(Canvas, X, Y, YL, 0, "sv_gravity       " $ FmtF(M.sv_gravity));
	Y += YL;
	DebugLine(Canvas, X, Y, YL, 0, "knockback        " $ FmtF(M.sv_knockback)
		$ "  expl " $ FmtF(M.sv_explosionknockback)
		$ "  cap " $ int(M.sv_maxdamagepush / FMax(M.WorldScale, 0.0001) + 0.5));
	Y += YL;
	DebugLine(Canvas, X, Y, YL, 0, "bhop cap         "
		$ YesNo(M.sv_enablebunnyhopcap, "ON", "OFF"));
	Y += YL;
	DebugLine(Canvas, X, Y, YL, 0, "autobhop         "
		$ YesNo(M.sv_autobunnyhop, "ON", "OFF"));
}

simulated final function DebugLine(canvas Canvas, float X, float Y, float YL, int Kind, string S)
{
	Canvas.SetDrawColor(0, 0, 0, 170);
	Canvas.SetPos(X + 1, Y + 1);
	Canvas.DrawText(S, false);

	Canvas.SetDrawColor(DebugColor.R, DebugColor.G, DebugColor.B, DebugColor.A);
	Canvas.SetPos(X, Y);
	Canvas.DrawText(S, false);
}

// unrealscript has no ternary operator, this is just a small helper for readability.
simulated final function string YesNo(bool b, string sTrue, string sFalse)
{
	if (b)
		return sTrue;
	return sFalse;
}

// text with the same drop shadow DebugLine uses in any color
simulated final function DrawShadowed(canvas Canvas, float X, float Y, string S, color C)
{
	Canvas.SetDrawColor(0, 0, 0, 170);
	Canvas.SetPos(X + 1, Y + 1);
	Canvas.DrawText(S, false);

	Canvas.SetDrawColor(C.R, C.G, C.B, C.A);
	Canvas.SetPos(X, Y);
	Canvas.DrawText(S, false);
}

// as above but ending at RX instead of starting at X.
simulated final function DrawRight(canvas Canvas, float RX, float Y, string S, color C)
{
	local float XL, YL;

	Canvas.StrLen(S, XL, YL);
	DrawShadowed(Canvas, RX - XL, Y, S, C);
}

// unreal's 16-bit rotator units to degrees, wrapped to (-180, 180].
simulated final function float UnrToDeg(int Unr)
{
	local float Deg;

	Deg = (float(Unr & 65535) * 360.0) / 65536.0;

	if (Deg > 180.0)
		Deg -= 360.0;

	return Deg;
}

// two decimal places - the width cl_showpos and net_graph print at.
simulated final function string Fmt2(float V)
{
	local int Whole, Frac;
	local string Sign, FracStr;

	if (V < 0)
	{
		Sign = "-";
		V    = -V;
	}

	Whole = int(V);
	Frac  = int((V - float(Whole)) * 100.0 + 0.5);

	if (Frac >= 100)
	{
		Whole++;
		Frac = 0;
	}

	FracStr = string(Frac);
	if (Frac < 10)
		FracStr = "0" $ FracStr;

	return Sign $ Whole $ "." $ FracStr;
}

// compact fixed-ish float formatting (unrealscript has no printf).
simulated final function string FmtF(float V)
{
	local int Whole, Frac;
	local string Sign;

	if (V < 0)
	{
		Sign = "-";
		V    = -V;
	}

	Whole = int(V);
	Frac  = int((V - float(Whole)) * 10.0 + 0.5);

	if (Frac >= 10)
	{
		Whole++;
		Frac = 0;
	}

	return Sign $ Whole $ "." $ Frac;
}

simulated final function string VecStr(vector V)
{
	return "(" $ FmtF(V.X) $ ", " $ FmtF(V.Y) $ ", " $ FmtF(V.Z) $ ")";
}

// The "touch" row: what the tracer last refused to let us through, sideways or
// upwards. GoldSrcMovement.NoteBlocker resolved the identity when it recorded it,
// so this only formats. Age is shown because a blocker goes stale the moment you
// walk away from it and a name left on screen would read as a wall that is still
// there.
simulated final function string BlockerStr(GoldSrcMovement M)
{
	local float Age;
	local string Flags;

	if (M.BlockActor == None)
		return "nothing yet";

	Age = Level.TimeSeconds - M.BlockTime;

	if (Age > 1.0)
		return "clear   (last was " $ M.BlockName $ ", " $ FmtF(Age) $ "s ago)";

	if (M.BlockHidden)
		Flags = Flags $ " hidden";
	if (M.BlockWorldGeo)
		Flags = Flags $ " worldgeo";
	if (M.BlockIsVolume)
		Flags = Flags $ " volume";

	// Read the block flags off the actor rather than caching them: they are what
	// says whether this thing has any business being solid to a player, and a
	// worldgeo brush with neither of them set is the shape the police station
	// fence took. Cheap, and BlockActor goes None by itself if it is destroyed.
	if (!M.BlockActor.bBlockPlayers)
		Flags = Flags $ " NOblkPlayers";
	if (!M.BlockActor.bBlockActors)
		Flags = Flags $ " NOblkActors";

	// EMBEDDED means the hull is inside it, not walking into it -- the difference
	// between a wall and being stuck.
	return M.BlockName $ " (" $ M.BlockClass $ ")"
		$ YesNo(M.BlockProbe, "  EMBEDDED", "  nz " $ FmtF(M.BlockNormal.Z))
		$ Flags;
}

// The "overlap" row: everything the hull is inside right now. This is the pawn's
// own Touching list, which the engine keeps up to date through our SetLocation
// calls, so it costs nothing to read and it is where triggers and volumes -- the
// things with no visible surface at all -- turn up. Capped at three names because
// a fourth would run off the side of the screen.
simulated final function string OverlapStr(Pawn P)
{
	local Actor A;
	local string S;
	local int N;

	if (P == None)
		return "no pawn";

	foreach P.TouchingActors(class'Actor', A)
	{
		if (N >= 3)
		{
			S = S $ " +more";
			break;
		}

		if (N > 0)
			S = S $ ", ";

		S = S $ string(A.Name);
		N++;
	}

	if (N == 0)
		return "nothing";

	return S;
}

defaultproperties
{
	SpeedColor=(R=255,G=255,B=255,A=255)
	LabelColor=(R=190,G=190,B=190,A=255)
	DebugColor=(R=120,G=255,B=120,A=255)
	AccelColor=(R=120,G=255,B=120,A=255)
	DecelColor=(R=255,G=140,B=140,A=255)
	NetGraphColor=(R=255,G=255,B=255,A=255)
	ShowPosColor=(R=255,G=255,B=255,A=255)
	PainColor=(R=255,G=160,B=0,A=255)   // RGB_YELLOWISH, hud.h
	HudColor=(R=255,G=16,B=16,A=255)    // RGB_REDISH, hud.h
	HudMinAlpha=200.0
	HudScale=0.85
	HudFontSize=1

	bGoldSrcHud=false
	bShowVelocityGraph=false
}

// this is all just a big fucking mess.
