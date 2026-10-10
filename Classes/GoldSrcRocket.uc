///////////////////////////////////////////////////////////////////////////////
// GoldSrcRocket
//
// The Quake-style rocket. Everything about how it behaves -- collision, the
// explosion, the smoke trail, the cat rider -- is inherited from
// LauncherProjectile untouched. Only the flight numbers change, because POSTAL 2's
// rocket and a Quake rocket differ in exactly two ways:
//
//   * P2's rocket leaves the tube slowly (250 ups) and a moment later BlastOff
//     thrusts it up to speed along a forward acceleration ramp. A Quake rocket is
//     already at full speed the instant it exists.
//   * P2's rocket is lobbed upward by TossZ, so aiming it is a small lob. A Quake
//     rocket flies dead straight along the crosshair.
//
// So we raise Speed, drop the ramp and the lob, and leave the rest alone.
///////////////////////////////////////////////////////////////////////////////
class GoldSrcRocket extends LauncherProjectile;

defaultproperties
{
	// Already at full speed on frame one -- 6x the stock 250 -- and no forward
	// acceleration ramp to build up to.
	Speed=1500.000000
	MaxSpeed=8000.000000
	ForwardAccelerationMag=0.000000

	// Straight out of the tube: no upward lob, no take-off kick.
	TossZ=0.000000
	BlastOffVelMag=0.000000

	// Detonate on contact, as always.
	bBounce=false
}
