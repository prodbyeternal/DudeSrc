# DudeSrc
UnrealScript mod for Postal 2

# Compiling

The project requires you to have POSTed SDK installed. Create a new folder called "GoldSrcMovement" and drop in the repo's contents to the root of the SDK.
Then, run "ucc.exe make" to compile the mod, then drop the GoldSrcMovement.u file into your retail game's System directory.

# Installing

## Postal 2

Drop the GoldSourceMovement.u file into the System folder in your Postal 2 install, then open Postal2.ini and add
the following lines.

```ini
; line 28, [Engine.Engine] - change Console=FPSGame.FPSConsoleExt
Console=GoldSrcMovement.GoldSrcConsole

; line 109, [Engine.GameEngine] - after ServerActors=UWeb.WebServer
ServerActors=GoldSrcMovement.GoldSrcInjector
```

## Paradise Lost (DS 1.3)

Paradise Lost is a separate install with its own System folder, but it already
looks in the main game's System folder for packages (ParadiseLost.ini `Paths`
includes `..\..\System\*.u`), so the same GoldSrcMovement.u covers it. Open
`Paradise Lost\System\ParadiseLost.ini` and make the same two edits.

```ini
; [Engine.Engine] - change Console=FPSGame.FPSConsoleExt
Console=GoldSrcMovement.GoldSrcConsole

; [Engine.GameEngine] - after ServerActors=UWeb.WebServer
ServerActors=GoldSrcMovement.GoldSrcInjector
```

Note that this replaces Paradise Lost's own player controller and HUD with the
mod's, exactly as it does in the base game. Movement, weapons and the shovel all
keep working, but Paradise Lost specific controller behaviour (notably the
mounted weapon handling in PLDudePlayer) and its own HUD are traded away for
GoldSrc movement.

The `Console=` line is the one that actually does the work: the console patches
the game type class defaults before the first level loads, and the engine reads
those at Login. Paradise Lost ships `PLGame.PLGameInfo` instead of the base
game's `AWPGameInfo`, so the mod names it (and `TWPGameInfo` / `CreditsGameInfo`)
by string at runtime rather than referencing a class the SDK does not have.

## Rocket launcher (DS 1.3)

By default the rocket launcher is the Quake one: a tap fires a single fast, dead
straight rocket, with no charging and no seeking rocket. This is on by default and
applies to launchers found in maps, stocked by Paradise Lost's vending machine, and
handed out by loadouts and cheats. `dudesrc_quakegun 0` puts the game's charged,
seeking launcher back; `dudesrc_quakegun 1` restores the Quake one.

Blast jumps are a touch stronger than the ordinary explosion knockback:
`sv_rocketjumpboost` (default 1.35) multiplies the launch from a blast *you* set
off -- a rocket or a grenade at your own feet -- and nothing else. Enemy blasts and
the damage you deal to enemies are unaffected. Combine it with
`dudesrc_quakerockets` to jump without hurting yourself.

# Half Life 1 SDK LICENSE
======================

Half Life 1 SDK Copyright© Valve Corp.  

THIS DOCUMENT DESCRIBES A CONTRACT BETWEEN YOU AND VALVE CORPORATION (“Valve”).  PLEASE READ IT BEFORE DOWNLOADING OR USING THE HALF LIFE 1 SDK (“SDK”). BY DOWNLOADING AND/OR USING THE SOURCE ENGINE SDK YOU ACCEPT THIS LICENSE. IF YOU DO NOT AGREE TO THE TERMS OF THIS LICENSE PLEASE DON’T DOWNLOAD OR USE THE SDK.

You may, free of charge, download and use the SDK to develop a modified Valve game running on the Half-Life engine.  You may distribute your modified Valve game in source and object code form, but only for free. Terms of use for Valve games are found in the Steam Subscriber Agreement located here: http://store.steampowered.com/subscriber_agreement/ 

You may copy, modify, and distribute the SDK and any modifications you make to the SDK in source and object code form, but only for free.  Any distribution of this SDK must include this license.txt and third_party_licenses.txt.  
 
Any distribution of the SDK or a substantial portion of the SDK must include the above copyright notice and the following: 

DISCLAIMER OF WARRANTIES.  THE SOURCE SDK AND ANY OTHER MATERIAL DOWNLOADED BY LICENSEE IS PROVIDED “AS IS”.  VALVE AND ITS SUPPLIERS DISCLAIM ALL WARRANTIES WITH RESPECT TO THE SDK, EITHER EXPRESS OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, IMPLIED WARRANTIES OF MERCHANTABILITY, NON-INFRINGEMENT, TITLE AND FITNESS FOR A PARTICULAR PURPOSE.  

LIMITATION OF LIABILITY.  IN NO EVENT SHALL VALVE OR ITS SUPPLIERS BE LIABLE FOR ANY SPECIAL, INCIDENTAL, INDIRECT, OR CONSEQUENTIAL DAMAGES WHATSOEVER (INCLUDING, WITHOUT LIMITATION, DAMAGES FOR LOSS OF BUSINESS PROFITS, BUSINESS INTERRUPTION, LOSS OF BUSINESS INFORMATION, OR ANY OTHER PECUNIARY LOSS) ARISING OUT OF THE USE OF OR INABILITY TO USE THE ENGINE AND/OR THE SDK, EVEN IF VALVE HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.  
 
 
If you would like to use the SDK for a commercial purpose, please contact Valve at sourceengine@valvesoftware.com.
