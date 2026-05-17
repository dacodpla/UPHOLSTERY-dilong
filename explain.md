# Upholstery Project - Scripts Documentation

## Overview
This documentation explains how the scripts in the `src` folder interact to create the core gameplay loop of the Upholstery project. The game revolves around accepting upholstery jobs via a laptop browser, teleporting to client locations, completing minigames to repair furniture, and posting the results on an in-game social media platform called "Talkogram".

## Folder Structure
The `src` folder is divided into three main environments:
- **client**: Currently empty, but meant for purely client-side logic.
- **gui**: Client-side scripts that manage the UI (Laptop, HUDs, dev panels).
- **server**: Server-side scripts that handle data persistence, economy, remote requests, and player locations.
- **shared**: Modules accessible to both client and server, containing configuration and minigame logic.

---

## 1. GUI Scripts (`src/gui`)
These scripts run on the client and handle player interactions with menus and HUDs.

### `LaptopInteraction.client.luau`
- **Purpose**: Detects when the player interacts with the laptop prop in the 3D world.
- **How it works**: It attaches a `ProximityPrompt` to the laptop's screen part. When triggered, it fires a local `LaptopOpened` BindableEvent. It also runs a heartbeat check to auto-close the laptop GUI if the player walks too far away.

### `LaptopBrowser.client.luau`
- **Purpose**: The main controller for the in-game Laptop GUI.
- **How it works**: Listens for the `LaptopOpened` event to play a boot sequence. It manages navigation between different "apps" or pages (BrowsahHome, TalkogramFeed, MoneyMakerPage for jobs, ShopPage).
- **Key Features**:
  - **Job Board**: Invokes `RequestJobs` and creates UI cards for available jobs. Clicking "Accept" fires `AcceptJob` to the server and closes the laptop.
  - **Talkogram Feed**: Invokes `RequestFeed` and `RequestPost` to show social media posts and comments.
  - **Shop**: Handles purchasing tool upgrades by firing `PurchaseTool`.

### `GameplayClient.client.luau`
- **Purpose**: Manages the local player's experience *after* accepting a job.
- **How it works**: Listens to server remotes (`TeleportToLocation`, `TeleportToHub`) to move the player's camera/character.
- **Minigame Trigger**: When the player approaches the cloned furniture at the client location and triggers the "RepairPrompt", this script calls `MinigameRunner.Run` or `RunChain`.
- **Completion**: Once the minigame is complete, it waits for the player to use the "DoorPrompt" to exit, then fires `SubmitJobResult` to the server.

### `DevJobPanel.client.luau` & `DevTestButton.client.luau`
- **Purpose**: Development tools (only active in Roblox Studio).
- **DevJobPanel**: Shows a panel (toggled with F7) to instantly accept jobs without using the laptop.
- **DevTestButton**: Shows a panel (toggled with F8) to directly test individual minigames or chains without having to accept a job.

---

## 2. Server Scripts (`src/server`)
These handle authoritative game state, teleporting, and DataStores.

### `LaptopData.server.luau`
- **Purpose**: The backend for the laptop browser.
- **How it works**: Creates and listens to all `RemoteEvent` and `RemoteFunction` calls (e.g., `RequestJobs`, `AcceptJob`, `SubmitJobResult`).
- **Talkogram Backend**: Manages a DataStore (`TalkogramFeed`) to persist posts across servers. When a player finishes a job, `SubmitJobResult` creates an auto-post with their result (Perfect, Good, Pass) and saves it here.
- **Job Delegation**: When `AcceptJob` is fired, it passes the player and job details to `LocationManager`.

### `LocationManager.luau`
- **Purpose**: Tracks and manages client locations (e.g., Studio Apartment, Luxury Home) where players perform jobs.
- **How it works**:
  - Maintains a pool of available "slots" or rooms.
  - **Assignment**: When a job is accepted, it finds an empty slot, clones the requested furniture model from `ServerStorage`, randomizes its fabric/frame colors, adds a `RepairPrompt`, and teleports the player there.
  - **Release**: When the player leaves (or disconnects), it destroys the cloned furniture, resets the slot colors, frees up the slot in the pool, and teleports the player back to the hub.

### `PlayerData/PlayerData.server.luau`
- **Purpose**: Basic player data initialization.
- **How it works**: Listens for `PlayerAdded` and creates a `PlayerData` folder with a `usd` IntValue inside the player object.

---

## 3. Shared Scripts (`src/shared`)
Accessible by both client and server.

### `GameConfig.luau`
- **Purpose**: Centralized balance and configuration file.
- **Contents**: Stores all tunable numbers, such as minigame timings (approach times, tolerances), economy payouts, Talkogram settings, and available locations/colors. Using a single config ensures values aren't hardcoded randomly across different files.

### `Minigames/MinigameRunner.luau`
- **Purpose**: Orchestrates the execution of minigames on the client.
- **How it works**: Provides a clean API (`MinigameRunner.Run` and `MinigameRunner.RunChain`) to start a minigame, handle the UI blurring, instantiate the specific minigame module, wait for it to yield a result, and display a popup grading ("PERFECT!", "GOOD", "PASS", "FAIL").

### Minigame Modules (e.g., `TackRemoval.luau`, `StapleGunning.luau`, `SeamStitching.luau`, `FoamPadding.luau`)
- **Purpose**: The actual interactive mini-games.
- **Structure**: Each follows a standard interface: `Start(container, config)`, `GetResult()`, and `Cleanup()`.
- **Example (`TackRemoval.luau`)**: Spawns UI buttons ("tacks") with shrinking approach rings (osu!-style). The timing of the player's click relative to the ring determines their score, culminating in a final grade that is passed back to `MinigameRunner`.

---

## Full Gameplay Loop Summary
1. Player walks to laptop in the hub → `LaptopInteraction` fires event → `LaptopBrowser` opens.
2. Player clicks "Accept" on a job → Fires `AcceptJob` to server.
3. `LaptopData` receives remote → calls `LocationManager.Assign`.
4. `LocationManager` finds a slot, clones furniture, and teleports player via `TeleportToLocation` remote.
5. `GameplayClient` receives teleport, moves player, and highlights the broken furniture.
6. Player triggers Repair prompt → `GameplayClient` calls `MinigameRunner`.
7. Player plays minigame (e.g., `TackRemoval`) → Gets result.
8. Player uses Door prompt to leave → `GameplayClient` fires `SubmitJobResult`.
9. `LaptopData` receives result, creates a Talkogram post, and calls `LocationManager.Release`.
10. `LocationManager` cleans up the room and teleports player back to Hub.
