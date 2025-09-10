# Copilot Instructions for NameFilter SourceMod Plugin

## Repository Overview

This repository contains **NameFilter**, a SourceMod plugin that filters and enforces player names on Source engine game servers. The plugin provides real-time name filtering using regex patterns, forced name assignments, and automatic replacement of inappropriate names.

### Key Features
- Real-time name filtering using configurable regex patterns
- Admin commands to force specific names on players (`sm_forcename`, `sm_forcednames`, `sm_namefilter_reload`)
- Automatic replacement names for banned/filtered content
- UTF-8 name handling and proper termination
- Translation support for multiple languages
- Persistent name enforcement through SteamID tracking
- Menu-driven interface for managing forced names
- Debug logging system with configurable verbosity

## Technical Environment

- **Language**: SourcePawn (SourceMod scripting language)
- **Platform**: SourceMod 1.12+ (minimum version 1.11.0 supported)
- **Build Tool**: SourceKnight (see `sourceknight.yaml`)
- **Current Version**: 2.0.3 (see plugin myinfo)
- **Dependencies**: 
  - SourceMod core (SDKTools, Regex)
  - MultiColors plugin (for colored chat messages)
  - BaseComm (for gag detection)
- **Compiler**: SourcePawn Compiler (spcomp) via SourceKnight automation

## Project Structure

```
addons/sourcemod/
├── scripting/
│   └── NameFilter.sp          # Main plugin source code
├── configs/
│   └── NameFilter.cfg         # Configuration with regex patterns and names
└── translations/
    └── namefilter.phrases.txt # Translation strings
.github/
├── workflows/
│   └── ci.yml                 # CI/CD pipeline
sourceknight.yaml              # Build configuration
```

## Build System & Testing

### Building the Plugin
The project uses SourceKnight for automated building and dependency management:

```bash
# Using SourceKnight (recommended - used in CI)
# The build process is automated via GitHub Actions
# Local builds require SourceKnight installation

# Manual compilation (if SourceMod compiler available)
spcomp -i includes/ addons/sourcemod/scripting/NameFilter.sp
```

### SourceKnight Configuration
The `sourceknight.yaml` file defines:
- SourceMod 1.11.0-git6934 dependency
- MultiColors plugin dependency from GitHub
- Build output to `/addons/sourcemod/plugins`
- Package structure for releases

### CI/CD Pipeline
- Automated builds on push/PR to main/master branches
- Uses GitHub Actions with Ubuntu 24.04
- Uses `maxime1907/action-sourceknight@v1` action
- Creates packaged releases with plugins, configs, and translations
- Artifacts include complete SourceMod addon structure

### Testing Changes
1. The plugin builds automatically in CI - no local build environment needed
2. Download built artifacts from GitHub Actions
3. Deploy to a test SourceMod server
4. Test with various player names containing:
   - Unicode characters
   - Banned patterns (admin, specific words)
   - Empty/short names
   - UTF-8 edge cases
5. Use debug mode: `sm_namefilter_debug 1` for detailed logging

## Code Architecture

### Core Components

1. **Name Filtering Engine** (`FilterName()`)
   - Applies regex patterns to clean names
   - Handles UTF-8 character validation
   - Replaces matches with censor character

2. **Banned Name Detection**
   - Secondary regex patterns for completely banned names
   - Forces random replacement names

3. **Forced Name System**
   - Admin commands to permanently assign names
   - SteamID-based persistence using KeyValues
   - Database stored in `configs/NameFilter.cfg`

4. **Event Handling**
   - `player_changename` event hooks (pre-hook to block broadcasts)
   - `SayText2` user message interception for chat filtering
   - Prevents broadcast of filtered name changes
   - Uses `g_iBlockNameChangeEvents` counter to manage event suppression
   - `RequestFrame()` for deferred name changes to avoid conflicts

### Key Global Variables
```sourcepawn
KeyValues g_Kv;                    // Config file handler
StringMap g_SMsteamID;             // SteamID -> Forced name mapping
Regex g_FilterExpr;                // Main filter regex
ArrayList g_BannedExprs;           // Banned pattern regexes
ArrayList g_ReplacementNames;      // Random replacement names
```

## Development Guidelines

### SourcePawn Best Practices (Enforced in this project)
- Use `#pragma semicolon 1` and `#pragma newdecls required`
- Prefix global variables with `g_`
- Use camelCase for local variables, PascalCase for functions
- Always use `delete` for cleanup (never check for null first)
- Use StringMap/ArrayList instead of basic arrays
- All file operations must be asynchronous where possible
- Proper memory management - delete handles when done

### Code Style Specifics
```sourcepawn
// Good: Global variable naming
StringMap g_SMsteamID;
ConVar g_hNFDebug;

// Good: Function naming and structure
public void OnPluginStart()
{
    // Initialization code
}

// Good: Memory management
delete g_Kv;
g_Kv = new KeyValues("NameFilter");

// Good: Error handling
if (!g_Kv.ImportFromFile(g_sFilePath))
{
    delete g_Kv;
    SetFailState("ImportFromFile() failed!");
}
```

### Configuration Management
- All settings stored in `addons/sourcemod/configs/NameFilter.cfg`
- KeyValues format with sections: main settings, banned patterns, replacement names
- Runtime reloading supported via `sm_namefilter_reload` command
- Backward compatibility for old config paths

## Common Development Tasks

### Available Admin Commands
- `sm_forcename <player> <new_name>` - Force a permanent name on a player (requires ADMFLAG_BAN)
- `sm_forcednames` - View menu of all forced names with management options (requires ADMFLAG_BAN)
- `sm_namefilter_reload` - Reload configuration file (requires ADMFLAG_CONFIG)

### ConVars
- `sm_namefilter_debug` - Enable/disable debug logging (0/1, default: 0)

### Adding New Filter Patterns
1. Edit `addons/sourcemod/configs/NameFilter.cfg`
2. Add to "banned" section for complete name replacement:
   ```
   "banned"
   {
       "1" "[Aa4]+[Dd]+[Mm]+[IiL1]+[nN]+"    // Blocks "admin" variations
       "2" "@((!?)me|(c?)t(s?)|(!?)admins|(!?)friends|random((c?)t?)|humans|spec|alive|dead|aim|bots)"
       "3" "YourNewPattern"                   // Add new patterns here
   }
   ```
3. Modify "filter" regex for character substitution (current: removes non-ASCII)
4. Add replacement names to "names" section (currently has 23 soccer player names)
5. Test with `sm_namefilter_reload` command
6. Use `sm_namefilter_debug 1` to see pattern matching in real-time

### Adding Admin Commands
1. Register with `RegAdminCmd()` in `OnPluginStart()`
2. Add command handler function following this pattern:
   ```sourcepawn
   public Action Command_MyCommand(int client, int args)
   {
       // Input validation
       if (args != expected_args)
       {
           CReplyToCommand(client, "%t", "Usage");
           return Plugin_Handled;
       }
       
       // Command logic here
       
       return Plugin_Handled;
   }
   ```
3. Add translation strings to `namefilter.phrases.txt`
4. Use appropriate admin flags (ADMFLAG_BAN for name forcing, ADMFLAG_CONFIG for reloading)
5. Follow existing pattern for permission checks and colored responses using MultiColors

### Debugging
- Enable debug mode: `sm_namefilter_debug 1`
- Use `NF_DebugLog()` function for debug output
- Check SourceMod error logs for regex compilation errors
- Monitor name change events in server console

### Adding Translation Support
1. Add new phrases to `addons/sourcemod/translations/namefilter.phrases.txt`
2. Use `%t` format in `CReplyToCommand()` calls
3. Follow existing format patterns for consistency

## Performance Considerations

### Optimization Guidelines
- Regex compilation is expensive - done once at config load
- Name filtering happens on every name change - keep efficient
- Use `RequestFrame()` for deferred name setting to avoid conflicts
- StringMap lookups are O(1) - preferred over linear searches
- Cache regex results where possible

### Memory Management
- Always `delete` KeyValues, StringMaps, ArrayLists when done
- Use `.Clear()` sparingly as it can cause memory leaks
- Prefer creating new objects over clearing existing ones
- Monitor handle usage in production environments

## Troubleshooting

### Common Issues
1. **Regex compilation errors**: Check regex syntax in config file
2. **Name changes not working**: Verify `g_iBlockNameChangeEvents` logic
3. **UTF-8 problems**: Use `TerminateNameUTF8()` for proper handling
4. **Config not loading**: Check file paths and permissions
5. **Infinite regex loops**: The code includes a 100-iteration guard against SourceMod regex bugs
6. **Bad UTF-8 encoding**: Plugin automatically clears names with invalid UTF-8 sequences

### Known Limitations
- **SourceMod Regex Bug**: The plugin includes a guard loop (max 100 iterations) to prevent infinite loops in regex processing
- **UTF-8 Handling**: Malformed UTF-8 sequences will result in name clearing
- **Performance**: Complex regex patterns on high-traffic servers may impact performance

### Debug Workflow
1. Enable debug logging: `sm_namefilter_debug 1`
2. Monitor plugin output in server console
3. Test with problematic names manually
4. Check regex patterns with online regex testers
5. Verify config file syntax with KeyValues validator

## Integration Points

### Dependencies
- **MultiColors**: Provides colored chat formatting (`CReplyToCommand`)
- **BaseComm**: Used to detect gagged players
- **SDKTools**: Core SourceMod functionality
- **Regex**: Built-in SourceMod regex support

### Hook Points
- Player name change events
- Chat message interception
- Client connection/disconnection
- Admin command system

This documentation should provide sufficient context for effective development and maintenance of the NameFilter plugin. Always test changes on a development server before deploying to production.