// dropin replacement for AWPGameInfo that sets the default player controller and HUD to GoldSrcMovement's versions
class GoldSrcGameInfo extends AWPGameInfo;

defaultproperties
{
	PlayerControllerClassName="GoldSrcMovement.GoldSrcPlayer"
	HUDType="GoldSrcMovement.GoldSrcHUD"
}
