# GoldSource.uc
UnrealScript mod for Postal 2

Currently, the mod is still under heavy development. Stay tuned.

# Compiling

The project requires you to have POSTed SDK installed. Create a new folder called "GoldSrcMovement" and drop in the repo's contents to the root of the SDK.
Then, run "ucc.exe make" to compile the mod, then drop the GoldSrcMovement.u file into your retail game's System directory.

# Installing

Drop the GoldSourceMovement.u file into the System folder in your Postal 2 install, then open Postal2.ini and add
the following lines.

```ini
; line 28, [Engine.Engine] - change Console=FPSGame.FPSConsoleExt
Console=GoldSrcMovement.GoldSrcConsole

; line 109, [Engine.GameEngine] - after ServerActors=UWeb.WebServer
ServerActors=GoldSrcMovement.GoldSrcInjector
```
