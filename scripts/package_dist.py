#!/usr/bin/env python3
"""
Primus Modularization & Multi-Path Distribution Exporter
Target: Vanilla WoW 1.12.1 (Lua 5.0.2)

Builds and synchronizes:
1. Path 1: Standalone Plug-and-Play Addons (with embedded Libs/PrimusCore/ & ## OptionalDeps: PrimusCore)
2. Path 2: Shared PrimusCore (Engine only)
3. Path 3: Master PrimusSuite (All-in-one overhaul)
4. Optional: Publishes all standalone addons to https://github.com/primus-tech/primus-standalone
"""

import os
import sys
import shutil
import subprocess

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDONS_ROOT = os.path.dirname(REPO_ROOT)
DIST_DIR = os.path.join(REPO_ROOT, "dist", "primus-standalone")

def ensure_dir(path):
    os.makedirs(path, exist_ok=True)

def copy_tree(src, dst):
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst)

def embed_primus_core(target_dir):
    libs_dir = os.path.join(target_dir, "Libs", "PrimusCore")
    ensure_dir(libs_dir)
    copy_tree(os.path.join(REPO_ROOT, "Core"), os.path.join(libs_dir, "Core"))
    copy_tree(os.path.join(REPO_ROOT, "Media"), os.path.join(libs_dir, "Media"))

CORE_LUA_FILES = [
    "Core\\Bootstrap\\Bootstrap.lua",
    "Core\\Utils\\Utils.lua",
    "Core\\Utils\\Items.lua",
    "Core\\Memory\\Memory.lua",
    "Core\\Debug\\Debug.lua",
    "Core\\Time\\Time.lua",
    "Core\\Events\\Events.lua",
    "Core\\DB\\DB.lua",
    "Core\\DB\\VanillaItemPrices.lua",
    "Core\\DB\\BasePriceDB.lua",
    "Core\\Media\\Media.lua",
    "Core\\Media\\Audio.lua",
    "Core\\Skinner\\Skinner.lua",
    "Core\\Anim\\Anim.lua",
    "Core\\Widgets\\Widgets.lua",
    "Core\\Widgets\\ContextMenu.lua",
    "Core\\Keybind\\Keybind.lua",
    "Core\\Console\\Console.lua",
    "Core\\Comm\\ChatThrottleLib.lua",
    "Core\\Comm\\Comm.lua",
    "Core\\Auras\\Auras.lua",
    "Core\\Chat\\Chat.lua",
    "Core\\State\\State.lua",
    "Core\\Hider\\Hider.lua",
    "Core\\Mover\\Mover.lua",
    "Core\\Map\\Map.lua",
    "Core\\Tooltip\\TooltipConstants.lua",
    "Core\\Tooltip\\TooltipSkin.lua",
    "Core\\Tooltip\\TooltipAnchor.lua",
    "Core\\Tooltip\\TooltipUnit.lua",
    "Core\\Tooltip\\TooltipItem.lua",
    "Core\\Tooltip\\TooltipScanner.lua",
    "Core\\Tooltip\\Tooltip.lua",
    "Core\\Config\\Options.lua",
]

CORE_TOC_SECTION = "\n".join(CORE_LUA_FILES)
EMBEDDED_CORE_TOC_SECTION = "\n".join(["Libs\\PrimusCore\\" + f for f in CORE_LUA_FILES])

def build_primus_core(target_dir):
    print("Building PrimusCore (Shared Engine)...")
    ensure_dir(target_dir)
    copy_tree(os.path.join(REPO_ROOT, "Core"), os.path.join(target_dir, "Core"))
    copy_tree(os.path.join(REPO_ROOT, "Media"), os.path.join(target_dir, "Media"))
    
    toc_content = f"""## Interface: 11200
## Title: PrimusCore
## Notes: Shared Foundation, Media, Skinner, Mover, and Tooltip Platform for Primus Addons
## Author: Primus
## Version: 1.0.0
## SavedVariables: PrimusGlobalDB
## SavedVariablesPerCharacter: PrimusCharDB

{CORE_TOC_SECTION}
"""
    with open(os.path.join(target_dir, "PrimusCore.toc"), "w") as f:
        f.write(toc_content)

def build_standalone_merchant(target_dir):
    print("Building PrimusMerchant (Standalone Economy Suite)...")
    ensure_dir(target_dir)
    embed_primus_core(target_dir)
    
    src_mod = os.path.join(REPO_ROOT, "Modules", "Utility", "PrimusMerchant")
    files = [
        "PrimusMerchantData.lua",
        "PrimusMerchantScan.lua",
        "PrimusMerchantGraph.lua",
        "PrimusMerchantSkin.lua",
        "PrimusMerchantExplorer.lua",
        "PrimusMerchant.lua",
    ]
    for fn in files:
        shutil.copy2(os.path.join(src_mod, fn), os.path.join(target_dir, fn))
        
    toc_content = f"""## Interface: 11200
## Title: PrimusMerchant
## Notes: Economy, Auction House 10s Scanner, Valuation & Offline Market Explorer
## Author: Primus
## Version: 1.0.0
## OptionalDeps: PrimusCore
## SavedVariables: PrimusMerchantDB

{EMBEDDED_CORE_TOC_SECTION}
PrimusMerchantData.lua
PrimusMerchantScan.lua
PrimusMerchantGraph.lua
PrimusMerchantSkin.lua
PrimusMerchantExplorer.lua
PrimusMerchant.lua
"""
    with open(os.path.join(target_dir, "PrimusMerchant.toc"), "w") as f:
        f.write(toc_content)

def build_standalone_roleplay(target_dir):
    print("Building PrimusRoleplay (Standalone RP Suite)...")
    ensure_dir(target_dir)
    embed_primus_core(target_dir)

    src_mod = os.path.join(REPO_ROOT, "Modules", "Social", "PrimusRoleplay")
    files = [
        "PrimusConstants.lua", "PrimusIcons.lua", "PrimusProtocols.lua", "PrimusComms.lua",
        "PrimusIconPicker.lua", "PrimusCardPreview.lua", "PrimusRPWidgets.lua",
        "PrimusRPTabIdentity.lua", "PrimusRPTabAppearance.lua", "PrimusRPTabPersonality.lua",
        "PrimusRPTabLore.lua", "PrimusRPTabRules.lua", "PrimusRPTabMatchmaking.lua",
        "PrimusRPTabSettings.lua", "PrimusRPSheet.lua", "PrimusGlance.lua", "PrimusTooltip.lua",
        "PrimusDirFlyout.lua", "PrimusMapPins.lua", "PrimusDirectory.lua", "PrimusEmotes.lua",
        "PrimusListener.lua", "PrimusElephant.lua", "PrimusDice.lua", "PrimusExtended.lua",
        "PrimusImporter.lua", "PrimusTray.lua", "PrimusRoleplay.lua"
    ]
    for fn in files:
        if os.path.exists(os.path.join(src_mod, fn)):
            shutil.copy2(os.path.join(src_mod, fn), os.path.join(target_dir, fn))

    toc_lines = [
        "## Interface: 11200",
        "## Title: PrimusRoleplay",
        "## Notes: Complete Character Sheet, DiceMaster D20, Directory, & Immersion Suite",
        "## Author: Primus",
        "## Version: 1.0.0",
        "## OptionalDeps: PrimusCore",
        "## SavedVariables: PrimusRoleplayDB",
        "",
        EMBEDDED_CORE_TOC_SECTION,
    ]
    for fn in files:
        toc_lines.append(fn)

    with open(os.path.join(target_dir, "PrimusRoleplay.toc"), "w") as f:
        f.write("\n".join(toc_lines) + "\n")

def build_standalone_quest(target_dir):
    print("Building PrimusQuest (Standalone Quest Suite)...")
    ensure_dir(target_dir)
    embed_primus_core(target_dir)

    src_mod = os.path.join(REPO_ROOT, "Modules", "Player", "PrimusQuest")
    
    # Copy DB subdirectories
    copy_tree(os.path.join(src_mod, "DB"), os.path.join(target_dir, "DB"))
    copy_tree(os.path.join(src_mod, "DB-Turtle"), os.path.join(target_dir, "DB-Turtle"))

    files = [
        "Overwrites.lua",
        "Patchtable.lua",
        "Database.lua",
        "Map.lua",
        "Tracker.lua",
        "Quest.lua",
        "Browser.lua",
        "PrimusQuest.lua",
    ]
    for fn in files:
        shutil.copy2(os.path.join(src_mod, fn), os.path.join(target_dir, fn))

    toc_content = f"""## Interface: 11200
## Title: PrimusQuest
## Notes: Complete Quest Database, Map Pin Resolution, Quest Tracker & Browser
## Author: Primus
## Version: 1.0.0
## OptionalDeps: PrimusCore
## SavedVariables: PrimusQuestDB

{EMBEDDED_CORE_TOC_SECTION}
DB\\init.lua
DB\\items.lua
DB\\units.lua
DB\\objects.lua
DB\\quests.lua
DB\\quests-itemreq.lua
DB\\refloot.lua
DB\\zones.lua
DB\\minimap.lua
DB\\areatrigger.lua
DB\\meta.lua
DB\\enUS\\items.lua
DB\\enUS\\units.lua
DB\\enUS\\objects.lua
DB\\enUS\\quests.lua
DB\\enUS\\professions.lua
DB\\enUS\\zones.lua
DB-Turtle\\items-turtle.lua
DB-Turtle\\units-turtle.lua
DB-Turtle\\objects-turtle.lua
DB-Turtle\\quests-turtle.lua
DB-Turtle\\quests-itemreq-turtle.lua
DB-Turtle\\refloot-turtle.lua
DB-Turtle\\zones-turtle.lua
DB-Turtle\\minimap-turtle.lua
DB-Turtle\\areatrigger-turtle.lua
DB-Turtle\\meta-turtle.lua
DB-Turtle\\enUS\\items-turtle.lua
DB-Turtle\\enUS\\units-turtle.lua
DB-Turtle\\enUS\\objects-turtle.lua
DB-Turtle\\enUS\\quests-turtle.lua
DB-Turtle\\enUS\\professions-turtle.lua
DB-Turtle\\enUS\\zones-turtle.lua
Overwrites.lua
Patchtable.lua
Database.lua
Map.lua
Tracker.lua
Quest.lua
Browser.lua
PrimusQuest.lua
"""
    with open(os.path.join(target_dir, "PrimusQuest.toc"), "w") as f:
        f.write(toc_content)

def build_standalone_bags(target_dir):
    print("Building PrimusBags (Standalone Inventory Suite)...")
    ensure_dir(target_dir)
    embed_primus_core(target_dir)

    src_mod = os.path.join(REPO_ROOT, "Modules", "Player", "PrimusBags")
    files = ["PrimusCategories.lua", "PrimusSort.lua", "PrimusBags.lua"]
    for fn in files:
        shutil.copy2(os.path.join(src_mod, fn), os.path.join(target_dir, fn))

    toc_content = f"""## Interface: 11200
## Title: PrimusBags
## Notes: Unified Continuous Grid, Container & Categorized Inventory with Auto-Sort
## Author: Primus
## Version: 1.0.0
## OptionalDeps: PrimusCore
## SavedVariables: PrimusBagsDB

{EMBEDDED_CORE_TOC_SECTION}
PrimusCategories.lua
PrimusSort.lua
PrimusBags.lua
"""
    with open(os.path.join(target_dir, "PrimusBags.toc"), "w") as f:
        f.write(toc_content)

def build_standalone_talk(target_dir):
    print("Building PrimusTalk (Standalone Chat & Whisper Suite)...")
    ensure_dir(target_dir)
    embed_primus_core(target_dir)

    src_mod = os.path.join(REPO_ROOT, "Modules", "Social", "PrimusTalk")
    files = [
        "PrimusTalkCore.lua",
        "PrimusTalkChat.lua",
        "PrimusTalkChatEvents.lua",
        "PrimusTalkMessages.lua",
        "PrimusTalkSocial.lua",
        "PrimusTalkInput.lua",
        "PrimusTalkFilterMenu.lua",
        "PrimusTalkCopy.lua",
        "PrimusTalkFrame.lua",
        "PrimusTalkOptions.lua",
        "PrimusTalk.lua",
    ]
    for fn in files:
        shutil.copy2(os.path.join(src_mod, fn), os.path.join(target_dir, fn))

    toc_content = f"""## Interface: 11200
## Title: PrimusTalk
## Notes: Modern Chat Overhaul, Whisper Tabs, Message Logging & Social Suite
## Author: Primus
## Version: 1.0.0
## OptionalDeps: PrimusCore
## SavedVariables: PrimusTalkDB

{EMBEDDED_CORE_TOC_SECTION}
PrimusTalkCore.lua
PrimusTalkChat.lua
PrimusTalkChatEvents.lua
PrimusTalkMessages.lua
PrimusTalkSocial.lua
PrimusTalkInput.lua
PrimusTalkFilterMenu.lua
PrimusTalkCopy.lua
PrimusTalkFrame.lua
PrimusTalkOptions.lua
PrimusTalk.lua
"""
    with open(os.path.join(target_dir, "PrimusTalk.toc"), "w") as f:
        f.write(toc_content)

def build_standalone_combat(target_dir):
    print("Building PrimusCombat (Standalone Tactical Combat & HUD Suite)...")
    ensure_dir(target_dir)
    embed_primus_core(target_dir)

    src_combat = os.path.join(REPO_ROOT, "Modules", "Combat")
    src_hud = os.path.join(REPO_ROOT, "Modules", "HUD")

    combat_files = [
        ("PrimusCombatLog", "PrimusCombatLog.lua"),
        ("PrimusCombatAuras", "PrimusCombatAuras.lua"),
        ("PrimusThreat", "PrimusThreat.lua"),
        ("PrimusHealComm", "PrimusHealComm.lua"),
        ("PrimusCastBar", "PrimusCastBar.lua"),
        ("PrimusCooldowns", "PrimusCooldowns.lua"),
        ("PrimusRange", "PrimusRange.lua"),
        ("PrimusTactical", "PrimusTactical.lua"),
    ]
    for sub, fn in combat_files:
        p = os.path.join(src_combat, sub, fn)
        if os.path.exists(p):
            shutil.copy2(p, os.path.join(target_dir, fn))

    hud_files = [
        ("PrimusAuras", "PrimusAuras.lua"),
        ("PrimusHud", "PrimusWings.lua"),
        ("PrimusHud", "PrimusMiniBars.lua"),
        ("PrimusHud", "PrimusActiveAssist.lua"),
        ("PrimusHud", "PrimusTimers.lua"),
        ("PrimusHud", "PrimusTriage.lua"),
        ("PrimusHud", "PrimusHud.lua"),
    ]
    for sub, fn in hud_files:
        p = os.path.join(src_hud, sub, fn)
        if os.path.exists(p):
            shutil.copy2(p, os.path.join(target_dir, fn))

    toc_content = f"""## Interface: 11200
## Title: PrimusCombat
## Notes: Tactical Combat HUD, CastBar, Cooldown Pulse, Threat Meter & HealComm
## Author: Primus
## Version: 1.0.0
## OptionalDeps: PrimusCore
## SavedVariables: PrimusCombatDB

{EMBEDDED_CORE_TOC_SECTION}
PrimusCombatLog.lua
PrimusCombatAuras.lua
PrimusThreat.lua
PrimusHealComm.lua
PrimusCastBar.lua
PrimusCooldowns.lua
PrimusRange.lua
PrimusTactical.lua
PrimusAuras.lua
PrimusWings.lua
PrimusMiniBars.lua
PrimusActiveAssist.lua
PrimusTimers.lua
PrimusTriage.lua
PrimusHud.lua
"""
    with open(os.path.join(target_dir, "PrimusCombat.toc"), "w") as f:
        f.write(toc_content)

def build_standalone_hotbars(target_dir):
    print("Building PrimusHotbars (Standalone Action Bars Suite)...")
    ensure_dir(target_dir)
    embed_primus_core(target_dir)

    src_mod = os.path.join(REPO_ROOT, "Modules", "Bars", "PrimusHotbars")
    files = ["PrimusButtons.lua", "PrimusXPBar.lua", "PrimusMicroBags.lua", "PrimusHotbars.lua"]
    for fn in files:
        shutil.copy2(os.path.join(src_mod, fn), os.path.join(target_dir, fn))

    toc_content = f"""## Interface: 11200
## Title: PrimusHotbars
## Notes: Clean Modular Action Bars, Micro Bag Bar, XP Tracker & Stance Handling
## Author: Primus
## Version: 1.0.0
## OptionalDeps: PrimusCore
## SavedVariables: PrimusHotbarsDB

{EMBEDDED_CORE_TOC_SECTION}
PrimusButtons.lua
PrimusXPBar.lua
PrimusMicroBags.lua
PrimusHotbars.lua
"""
    with open(os.path.join(target_dir, "PrimusHotbars.toc"), "w") as f:
        f.write(toc_content)

def build_standalone_unitframes(target_dir):
    print("Building PrimusUnitFrames (Standalone Unit Frames Suite)...")
    ensure_dir(target_dir)
    embed_primus_core(target_dir)

    src_units = os.path.join(REPO_ROOT, "Modules", "Units")
    shutil.copy2(os.path.join(src_units, "PrimusUnitBase", "PrimusUnitBase.lua"), os.path.join(target_dir, "PrimusUnitBase.lua"))
    shutil.copy2(os.path.join(src_units, "PrimusUnitFrames", "PrimusUnitFrames.lua"), os.path.join(target_dir, "PrimusUnitFrames.lua"))

    toc_content = f"""## Interface: 11200
## Title: PrimusUnitFrames
## Notes: Ultra-Responsive Player, Target, Target of Target, Pet & Party Frames
## Author: Primus
## Version: 1.0.0
## OptionalDeps: PrimusCore
## SavedVariables: PrimusUnitFramesDB

{EMBEDDED_CORE_TOC_SECTION}
PrimusUnitBase.lua
PrimusUnitFrames.lua
"""
    with open(os.path.join(target_dir, "PrimusUnitFrames.toc"), "w") as f:
        f.write(toc_content)

def clean_legacy_addons():
    legacy_folders = [
        "PUIMerchant", "PUIRoleplay", "PUIQuest", "PUIBags",
        "PUITalk", "PUICombat", "PUIHotbars", "PUIUnitFrames", "PrimusUI"
    ]
    for leg in legacy_folders:
        p = os.path.join(ADDONS_ROOT, leg)
        if os.path.exists(p):
            print(f"Cleaning legacy Addon directory: {leg}...")
            shutil.rmtree(p)

def build_all_to_directory(base_dir):
    ensure_dir(base_dir)
    build_primus_core(os.path.join(base_dir, "PrimusCore"))
    build_standalone_merchant(os.path.join(base_dir, "PrimusMerchant"))
    build_standalone_roleplay(os.path.join(base_dir, "PrimusRoleplay"))
    build_standalone_quest(os.path.join(base_dir, "PrimusQuest"))
    build_standalone_bags(os.path.join(base_dir, "PrimusBags"))
    build_standalone_talk(os.path.join(base_dir, "PrimusTalk"))
    build_standalone_combat(os.path.join(base_dir, "PrimusCombat"))
    build_standalone_hotbars(os.path.join(base_dir, "PrimusHotbars"))
    build_standalone_unitframes(os.path.join(base_dir, "PrimusUnitFrames"))

def write_standalone_readme(target_dir):
    readme_content = """# Primus Standalone Addon Suite for Vanilla WoW (1.12.1)

Welcome to the **Primus Standalone Addons** repository. This repository hosts plug-and-play standalone versions of all modules from the [PrimusSuite](https://github.com/primus-tech/primussuite) platform.

## 📦 What's Included

Every addon in this repository is **100% self-contained** and plug-and-play:

| AddOn Directory | Description | Commands |
| :--- | :--- | :--- |
| **`PrimusCore`** | Shared Foundation & Engine (Media, Skinner, Mover, Map & Tooltips) | `/primus`, `/pui` |
| **`PrimusMerchant`** | Auction House 10s Scanner, Pricing Model, Valuation & Offline Explorer | `/primus ah`, `/pui market` |
| **`PrimusRoleplay`** | Comprehensive RP Character Sheet, DiceMaster D20, Directory & Map Pins | `/primus rp`, `/rp` |
| **`PrimusQuest`** | Quest DB (Classic + Turtle WoW), Map Pin Resolver & Tracker | `/primus quest`, `/pq` |
| **`PrimusBags`** | Unified Continuous Grid, Discrete Container & Categorized Inventory with Auto-Sort | `/primus bags`, `/sort` |
| **`PrimusTalk`** | Chat Overhaul, Whisper Tabs, Message Logging & Social Suite | `/primus chat` |
| **`PrimusCombat`** | Tactical Combat HUD, CastBar, Cooldown Pulse & HealComm | `/primus combat` |
| **`PrimusHotbars`** | Action Bars, Micro Bag Bar & XP Tracker | `/primus bars` |
| **`PrimusUnitFrames`** | Unit Frames (Player, Target, Party, Pet) | `/primus uf` |

---

## 🚀 Installation

1. Download or clone this repository.
2. Copy any (or all) desired addon folders directly into your `World of Warcraft/Interface/AddOns/` directory.
3. If you install multiple standalone addons, you can optionally also install **`PrimusCore`** to share a single in-memory engine footprint!

---

## 🛡️ Standalone Architecture (Zero Bloat)
Each standalone addon includes an embedded fallback copy of `Libs/PrimusCore/` and is marked with `## OptionalDeps: PrimusCore`.
- If installed alone: it boots immediately with 0 external dependencies.
- If `PrimusCore` is present: `PrimusCore` loads first and master election yields embedded copies instantly with 0ms / 0 KB overhead.
"""
    with open(os.path.join(target_dir, "README.md"), "w") as f:
        f.write(readme_content)

def publish_standalone_repo():
    print("=" * 60)
    print("Publishing Standalone Addons to https://github.com/primus-tech/primus-standalone")
    print("=" * 60)
    
    ensure_dir(DIST_DIR)
    build_all_to_directory(DIST_DIR)
    write_standalone_readme(DIST_DIR)

    # Git init / remote setup
    git_dir = os.path.join(DIST_DIR, ".git")
    if not os.path.exists(git_dir):
        subprocess.run(["git", "init", "-b", "main"], cwd=DIST_DIR, check=True)

    # Get token from ~/.git-credentials if available
    remote_url = "https://github.com/primus-tech/primus-standalone.git"
    cred_path = os.path.expanduser("~/.git-credentials")
    if os.path.exists(cred_path):
        import re
        with open(cred_path) as f:
            creds = f.read()
        m = re.search(r"https://(?:([^:]+):)?([^@]+)@github\.com", creds)
        if m:
            token = m.group(2)
            remote_url = f"https://{token}@github.com/primus-tech/primus-standalone.git"

    subprocess.run(["git", "remote", "remove", "origin"], cwd=DIST_DIR, check=False)
    subprocess.run(["git", "remote", "add", "origin", remote_url], cwd=DIST_DIR, check=True)

    subprocess.run(["git", "config", "user.name", "primus-tech"], cwd=DIST_DIR, check=True)
    subprocess.run(["git", "config", "user.email", "primustech@users.noreply.github.com"], cwd=DIST_DIR, check=True)

    subprocess.run(["git", "add", "-A"], cwd=DIST_DIR, check=True)
    subprocess.run(["git", "commit", "-m", "release: synchronize latest standalone addons from PrimusSuite"], cwd=DIST_DIR, check=False)
    
    print("Pushing to remote origin main on primus-tech/primus-standalone...")
    subprocess.run(["git", "push", "-u", "origin", "main", "--force"], cwd=DIST_DIR, check=True)
    print("Successfully published to https://github.com/primus-tech/primus-standalone!")

def main():
    publish_mode = "--publish" in sys.argv or "--push" in sys.argv

    print(f"Primus Build & Sync Pipeline")
    print(f"Repo Root:   {REPO_ROOT}")
    print(f"AddOns Dest: {ADDONS_ROOT}")
    print("=" * 60)

    # 1. Clean legacy PUI addon directories in Interface/AddOns/
    clean_legacy_addons()

    # 2. Build Standalone Modules directly into local WoW Interface/AddOns/
    build_all_to_directory(ADDONS_ROOT)

    print("=" * 60)
    print("Local AddOn Sync Complete!")

    # 3. Publish to GitHub primus-standalone repository if requested
    if publish_mode:
        publish_standalone_repo()

if __name__ == "__main__":
    main()
