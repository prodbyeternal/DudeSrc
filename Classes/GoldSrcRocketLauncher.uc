///////////////////////////////////////////////////////////////////////////////
// GoldSrcRocketLauncher
//
// The Quake-style rocket launcher.
//
// POSTAL 2's LauncherWeapon is a CHARGED weapon: you hold Fire to fuel the
// rocket, release to launch, and a full charge turns it into a seeking rocket
// that flies slowly and then accelerates. None of that is Quake. Here a single
// tap spends one rocket and fires a fast, straight GoldSrcRocket immediately.
//
// The toggle: GoldSrcPlayer.bQuakeGun ("dudesrc_quakegun") turns this behaviour
// off. It does not swap the weapon's class at runtime -- you cannot change an
// object's class -- the weapon simply reads the flag and, when it is off,
// delegates every override straight back to Super, which is the stock charged
// launcher. One class therefore serves both flavours and the toggle is instant.
//
// NPCs never see the Quake behaviour: their controller is not a GoldSrcPlayer,
// so QuakeGunOn() reads false and they charge and fire exactly as before.
///////////////////////////////////////////////////////////////////////////////
class GoldSrcRocketLauncher extends LauncherWeapon;

// How much "fuel" a Quake rocket is handed. This only becomes the projectile's
// LifeSpan (its range); the projectile sets its own speed. Long enough that a
// rocket fired down a long sight-line does not sputter out on the way.
const QUAKE_ROCKET_CHARGE_TIME = 6.0;

///////////////////////////////////////////////////////////////////////////////
// Are we firing the Quake way? Only a player who asked for it, via the toggle.
// Everyone else -- including an NPC holding one of these -- gets stock behaviour.
///////////////////////////////////////////////////////////////////////////////
final function bool QuakeGunOn()
{
	return Instigator != None
		&& GoldSrcPlayer(Instigator.Controller) != None
		&& GoldSrcPlayer(Instigator.Controller).bQuakeGun;
}

///////////////////////////////////////////////////////////////////////////////
// One tap, one rocket. The stock weapon is the ONLY place that spends ammo and
// it lives in the Charging state we are skipping, so we spend it here -- one
// rocket per tap, not the base five -- then run the same release path the
// Charging state runs when you let go.
///////////////////////////////////////////////////////////////////////////////
function InstantFire()
{
	if (AmmoType == None || !AmmoType.HasAmmo())
		return;

	// Keep Notify_ShootLauncher's give-back bookkeeping consistent, hand the
	// rocket its range, and stop RecordChargeTime from ever overwriting the
	// constant (it is only reachable from the charge states, but say so anyway).
	ChargeStartAmmo  = AmmoType.AmmoAmount;
	ChargeTime       = QUAKE_ROCKET_CHARGE_TIME;
	bChargedTimeSaved = true;

	P2AmmoInv(AmmoType).UseAmmoForShot(1);

	// Exactly what Charging.Tick does on release, minus the charging.
	ShootIt();
	ClientShootIt();
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
simulated function Fire(float Value)
{
	if (!QuakeGunOn())
	{
		Super.Fire(Value);
		return;
	}

	if (AmmoType == None || !AmmoType.HasAmmo())
	{
		ClientForceFinish();
		ServerForceFinish();
		return;
	}

	bAltFiring = false;
	InstantFire();
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
simulated function AltFire(float Value)
{
	if (!QuakeGunOn())
	{
		Super.AltFire(Value);
		return;
	}

	if (AmmoType == None || !AmmoType.HasAmmo())
		return;

	// Alt-fire is the same straight rocket; there is no seeking rocket to keep
	// apart from it any more.
	bAltFiring = true;
	InstantFire();
}

///////////////////////////////////////////////////////////////////////////////
// Spawn the rocket. This runs from the mesh animation notify, exactly as the
// stock weapon's does -- firing from Fire() instead would fire twice. This is
// the stock function's normal-rocket branch only: no seeking rocket, and no
// charge to give back.
///////////////////////////////////////////////////////////////////////////////
function Notify_ShootLauncher()
{
	local vector StartTrace, X, Y, Z, markerpos, HitNormal, HitLocation;
	local actor HitActor;
	local GoldSrcRocket lpro;
	local float giveback;

	if (!QuakeGunOn())
	{
		Super.Notify_ShootLauncher();
		return;
	}

	if (AmmoType == None)
		return;

	GetAxes(Instigator.GetViewRotation(),X,Y,Z);
	StartTrace = GetFireStart(X,Y,Z);
	AdjustedAim = Instigator.AdjustAim(AmmoType, StartTrace, 2*AimError);
	ShootStyleChanger = 0;

	// Make sure we are not generating this on the other side of a thin wall.
	HitActor = Trace(HitLocation, HitNormal, Instigator.Location, StartTrace, true);
	if (HitActor == None
		|| (!HitActor.bStatic
			&& !HitActor.bWorldGeometry))
	{
		lpro = spawn(class'GoldSrcRocket',Instigator,,StartTrace, AdjustedAim);
		if (lpro != None)
		{
			lpro.Instigator = Instigator;

			// Compensate for catnip time, if necessary. Don't do this for NPCs.
			if (FPSPawn(Instigator) != None
				&& FPSPawn(Instigator).bPlayer)
				ChargeTime /= Level.TimeDilation;

			lpro.SetupShot(ChargeTime);
			lpro.AddRelativeVelocity(Instigator.Velocity);

			// Touch any actor that was in between, just in case.
			if (HitActor != None)
				HitActor.Bump(lpro);

			// xPatch: it is catable, same as the stock launcher.
			if (bCatWasOnGun || RepeatCatGun == 1)
			{
				PlaySound(CatViolateSound);
				lpro.CatConvert(CatSkin);
				bCatWasOnGun = false;
				if (RepeatCatGun == 1)
				{
					bCatWasOnGun = true;
					CatOnGun = 1;
				}
			}
		}
	}

	// If we did not make a valid rocket, give the ammo back.
	if (lpro == None)
	{
		giveback = ChargeStartAmmo - AmmoType.AmmoAmount;
		if (giveback > 0)
			AmmoType.AddAmmo(giveback);
	}
	else
	{
		// Say we just fired.
		ShotCount++;

		// Only make a new danger marker if the consecutive fires were as high
		// as the max.
		if (ShotCount >= ShotCountMaxForNotify
			&& Instigator.Controller != None
			&& ShotMarkerMade != None)
		{
			ShotCount -= ShotCountMaxForNotify;

			markerpos = Instigator.Location;

			ShotMarkerMade.static.NotifyControllersStatic(
				Level,
				ShotMarkerMade,
				FPSPawn(Instigator),
				None,
				ShotMarkerMade.default.CollisionRadius,
				markerpos);
		}
	}

	// Reset the ammo we started with.
	ChargeStartAmmo = AmmoType.AmmoAmount;
}

///////////////////////////////////////////////////////////////////////////////
// The stock versions of these two test `Class == Class'LauncherWeapon'`, which a
// subclass fails, so a subclassed launcher would silently stop swapping to the
// classic hands and stop accepting a cat. Test for our own class instead.
///////////////////////////////////////////////////////////////////////////////
function bool CanSwapHands()
{
	return (Class == Class'GoldSrcRocketLauncher');
}

function bool ReadyForCat()
{
	return (AmmoType != None
			&& AmmoType.HasAmmo()
			&& CatOnGun == 0
			&& !bPutCatOnGun
			&& IsInState('Idle')
			&& Class == Class'GoldSrcRocketLauncher');
}

///////////////////////////////////////////////////////////////////////////////
// Default properties
///////////////////////////////////////////////////////////////////////////////
defaultproperties
{
	// The dual-wield firing logic lives in the Charging states we removed, so two
	// of these at once would half-work. Refuse it rather than ship the half.
	bDisableDualWielding=true

	HudHint1="Tap %KEY_Fire% to fire."
	HudHint2="Instant rocket, no charging."
}
