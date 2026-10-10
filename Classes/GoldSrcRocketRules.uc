// GoldSrcRocketRules
// Quake-style rocket jumping: the player's OWN explosives stop hurting them, but
// still launch them. This is the half of the toggle the movement code cannot
// reach.
//
// The knockback itself is free -- P2 computes explosion momentum and damage
// independently (BaseFX/Explosion.uc:143-154) and P2Pawn applies the momentum on
// its own, so zeroing the damage never touches the push. What zeroing the damage
// DOES change is which branch of P2Pawn.TakeDamage runs: with no damage the pawn
// never dies (so a point-blank rocket can no longer kill the player) and it
// reports the hit to the controller as a NEGATED damage. GoldSrcPlayer notices
// that negated self-explosive hit and drives the launch through the simulation by
// hand -- see GoldSrcPlayer.DriveDamage.
//
// The rules object is registered once per level by GoldSrcPlayer.EnsureRocketRules
// and reads the flag off the player every time, so it can stay in the chain while
// the toggle is off and cost nothing.
class GoldSrcRocketRules extends GameRules;

function int NetDamage( int OriginalDamage, int Damage, pawn injured, pawn instigatedBy,
						vector HitLocation, vector Momentum, class<DamageType> DamageType )
{
	local GoldSrcPlayer GP;

	// Everyone else in the chain gets their say first (P2 itself may register
	// rules), then we take the last word.
	if (NextGameRules != None)
		Damage = NextGameRules.NetDamage(OriginalDamage, Damage, injured, instigatedBy, HitLocation, Momentum, DamageType);

	if (Damage > 0
		&& injured != None
		&& injured == instigatedBy
		&& ClassIsChildOf(DamageType, class'BaseFX.ExplodedDamage'))
	{
		GP = GoldSrcPlayer(injured.Controller);
		if (GP != None && GP.bQuakeRockets)
			Damage = 0;
	}

	return Damage;
}

defaultproperties
{
}
