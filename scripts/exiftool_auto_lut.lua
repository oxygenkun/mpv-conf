--[[
ExifTool Auto LUT Script for MPV
This script uses exiftool to detect gamma information from video files and automatically applies appropriate LUTs.
Primary detection method: 'Acquisition Record Group Item Value: s-log3-cine'
--]]

local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'

-- ============================================================================
-- Configuration
-- ============================================================================

local o = {
    enabled = true,
    auto_apply = true,          -- Automatically apply LUT when file loads
    show_detection = true,      -- Show detection results in console
    lut_base_path = "~~home/lut/", -- Base path for LUT files
    fast_switching = true,      -- Enable fast LUT switching for playlist navigation
    cache_metadata = true,      -- Cache exiftool metadata to speed up switching
    exiftool_path = "exiftool", -- Path to exiftool executable
    timeout = 5,                -- Timeout for exiftool execution in seconds
}

-- ============================================================================
-- Constants
-- ============================================================================

local TIMEOUT_DELAYS = {
    file_loaded = 0.5,
    start_file = 0.1,
    playlist_pos = 0.05,
    path_change = 0.02,
}

local EXIFTOOL_TAGS = {
    "-AcquisitionRecordGroupItemValue",
    "-CaptureGammaEquation",
    "-ColorSpace",
    "-Gamma",
    "-TransferCharacteristics",
    "-ColorPrimaries",
    "-MatrixCoefficients",
}

-- ============================================================================
-- State Management
-- ============================================================================

local metadata_cache = {}
local current_lut_state = nil
local script_set_lut_path = nil  -- Track the LUT path set by script (nil = not set, "" = cleared)
local manual_lut_mode = false    -- Flag to indicate if user manually set LUT
local script_lut_changing = false  -- Flag to prevent detecting script changes as manual

-- ============================================================================
-- LUT Configuration
-- ============================================================================

local lut_mapping = {
    ["s-log3-cine"] = {
        lut_file = "SLog3SGamut3.CineToLC-709.cube",
        lut_type = "normalized",
        description = "Sony S-Log3 Cine to Rec.709"
    },
    ["s-log3"] = {
        lut_file = "SLog3SGamut3.CineToLC-709.cube",
        lut_type = "normalized",
        description = "Sony S-Log3 to Rec.709"
    },
    ["s-log2"] = {
        lut_file = "SLog3SGamut3.CineToSLog2-709.cube",
        lut_type = "normalized",
        description = "Sony S-Log2 to Rec.709"
    },
    ["rec709"] = {
        lut_file = "",
        lut_type = "auto",
        description = "Rec.709 (No LUT needed)"
    },
    ["v-log"] = {
        lut_file = "VLog_to_V709_forV35_ver100.cube",
        lut_type = "normalized",
        description = "Panasonic V-Log to Rec.709"
    },
    ["canon-log2"] = {
        lut_file = "CinemaGamut_CanonLog2-to-Canon709_65_Ver.1.0.cube",
        lut_type = "normalized",
        description = "Canon Log2 to Rec.709"
    },
    ["canon-log3"] = {
        lut_file = "CinemaGamut_CanonLog3-to-Canon709_65_Ver.1.0.cube",
        lut_type = "normalized",
        description = "Canon Log3 to Rec.709"
    },
    ["dji-osmo-p3"] = {
        lut_file = "Neutral_Osmo_P3.cube",
        lut_type = "normalized",
        description = "DJI Osmo Pocket 3 Neutral"
    }
}

-- ============================================================================
-- Utility Functions
-- ============================================================================

-- Check if LUT is manually set by user
local function is_manual_lut()
    if manual_lut_mode then
        return true
    end
    
    local current_lut = mp.get_property("image-lut") or ""
    -- If current LUT doesn't match what script set, it's manual
    if script_set_lut_path ~= nil and current_lut ~= script_set_lut_path then
        return true
    end
    
    return false
end

-- Clear LUT (with state tracking)
local function clear_lut(reason)
    if reason then
        msg.info(reason)
    end
    script_lut_changing = true
    mp.command("set image-lut \"\"")
    mp.command("set image-lut-type auto")
    script_set_lut_path = ""
    script_lut_changing = false
    current_lut_state = "none"
end

-- Check if path is a local file
local function is_local_file(path)
    -- Check if it's a URL (http, https, ftp, rtmp, rtsp, etc.)
    if path:match("^%a+://") then
        return false
    end
    -- Check if it's a local file path (Windows or Unix)
    return path:match("^[A-Za-z]:[/\\]") or path:match("^/")
end

-- Normalize gamma value
local function normalize_gamma(gamma_value)
    return gamma_value:gsub("%s+", "-"):gsub("_", "-")
end

-- Parse a single metadata line
local function parse_metadata_line(line, metadata)
    -- Parse Acquisition Record Group Item Value (primary detection)
    local acquisition_value = line:match("AcquisitionRecordGroupItemValue%s*:%s*(.+)")
    if acquisition_value then
        acquisition_value = acquisition_value:gsub("^%s*(.-)%s*$", "%1")
        metadata.acquisition_value = acquisition_value:lower()
        msg.info("✓ Found Acquisition Record Group Item Value: " .. acquisition_value)
        return
    end
    
    -- Parse CaptureGammaEquation (alternative detection)
    local gamma_equation = line:match("CaptureGammaEquation%s*:%s*(.+)")
    if gamma_equation then
        gamma_equation = gamma_equation:gsub("^%s*(.-)%s*$", "%1")
        metadata.gamma_equation = gamma_equation:lower()
        msg.info("✓ Found CaptureGammaEquation: " .. gamma_equation)
        return
    end
    
    -- Parse ColorSpace
    local color_space = line:match("ColorSpace%s*:%s*(.+)")
    if color_space then
        color_space = color_space:gsub("^%s*(.-)%s*$", "%1")
        metadata.color_space = color_space
        msg.info("✓ Found ColorSpace: " .. color_space)
        return
    end
    
    -- Parse Gamma
    local gamma = line:match("Gamma%s*:%s*(.+)")
    if gamma then
        gamma = gamma:gsub("^%s*(.-)%s*$", "%1")
        metadata.gamma = gamma
        msg.info("✓ Found Gamma: " .. gamma)
        return
    end
    
    -- Parse TransferCharacteristics
    local transfer = line:match("TransferCharacteristics%s*:%s*(.+)")
    if transfer then
        transfer = transfer:gsub("^%s*(.-)%s*$", "%1")
        metadata.transfer_characteristics = transfer
        msg.info("✓ Found TransferCharacteristics: " .. transfer)
        return
    end
    
    -- Parse ColorPrimaries
    local primaries = line:match("ColorPrimaries%s*:%s*(.+)")
    if primaries then
        primaries = primaries:gsub("^%s*(.-)%s*$", "%1")
        metadata.color_primaries = primaries
        msg.info("✓ Found ColorPrimaries: " .. primaries)
        return
    end
    
    -- Parse MatrixCoefficients
    local matrix = line:match("MatrixCoefficients%s*:%s*(.+)")
    if matrix then
        matrix = matrix:gsub("^%s*(.-)%s*$", "%1")
        metadata.matrix_coefficients = matrix
        msg.info("✓ Found MatrixCoefficients: " .. matrix)
        return
    end
end

-- Determine detected gamma from metadata
local function detect_gamma_from_metadata(metadata)
    local detected_gamma = nil
    
    -- Priority 1: Acquisition Record Group Item Value (most reliable for Sony)
    if metadata.acquisition_value then
        detected_gamma = metadata.acquisition_value
        msg.info("✓ Using Acquisition Record Group Item Value: " .. detected_gamma)
    -- Priority 2: CaptureGammaEquation
    elseif metadata.gamma_equation then
        detected_gamma = metadata.gamma_equation
        msg.info("✓ Using CaptureGammaEquation: " .. detected_gamma)
    -- Priority 3: TransferCharacteristics
    elseif metadata.transfer_characteristics then
        detected_gamma = metadata.transfer_characteristics:lower()
        msg.info("✓ Using TransferCharacteristics: " .. detected_gamma)
    -- Priority 4: Gamma field
    elseif metadata.gamma then
        detected_gamma = metadata.gamma:lower()
        msg.info("✓ Using Gamma field: " .. detected_gamma)
    end
    
    if detected_gamma then
        detected_gamma = normalize_gamma(detected_gamma)
        msg.info("✓ Final detected gamma: " .. detected_gamma)
    else
        msg.warn("⚠ No gamma information detected")
    end
    
    return detected_gamma
end

-- Display detected metadata
local function display_metadata(metadata)
    if not o.show_detection then
        return
    end
    
    msg.info("=== METADATA DETECTED ===")
    local fields = {
        acquisition_value = "Acquisition Record Group Item Value",
        gamma_equation = "CaptureGammaEquation",
        color_space = "ColorSpace",
        gamma = "Gamma",
        transfer_characteristics = "TransferCharacteristics",
        color_primaries = "ColorPrimaries",
        matrix_coefficients = "MatrixCoefficients",
        detected_gamma = "Detected Gamma",
    }
    
    for key, label in pairs(fields) do
        if metadata[key] then
            msg.info(label .. ": " .. metadata[key])
        end
    end
end

-- ============================================================================
-- ExifTool Metadata Functions
-- ============================================================================

-- Run exiftool and get metadata
local function get_exiftool_metadata(video_path)
    if not video_path or video_path == "" then
        msg.error("❌ No video path provided")
        return nil
    end
    
    -- Check cache first
    if o.cache_metadata and metadata_cache[video_path] then
        msg.debug("✓ Using cached exiftool metadata for: " .. video_path)
        return metadata_cache[video_path]
    end
    
    msg.info("=== EXIFTOOL DETECTION STAGE ===")
    msg.info("Video path: " .. video_path)
    
    -- Check if file exists
    local file = io.open(video_path, "r")
    if not file then
        msg.error("❌ File does not exist: " .. video_path)
        return nil
    end
    file:close()
    
    -- Build exiftool command
    local exiftool_cmd = {
        o.exiftool_path,
        "-s",                    -- Short output format
        video_path
    }
    
    -- Add all tags
    for _, tag in ipairs(EXIFTOOL_TAGS) do
        table.insert(exiftool_cmd, tag)
    end
    
    msg.info("Running exiftool command...")
    msg.info("Command: " .. table.concat(exiftool_cmd, " "))
    
    -- Execute exiftool using modern mp.command_native
    local result = mp.command_native({
        name = "subprocess",
        args = exiftool_cmd,
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
        capture_size = 1024 * 1024, -- 1MB limit
    })
    
    if result.status ~= 0 then
        msg.error("❌ ExifTool failed with status: " .. result.status)
        if result.stderr and result.stderr ~= "" then
            msg.error("ExifTool error: " .. result.stderr)
        end
        return nil
    end
    
    if not result.stdout or result.stdout == "" then
        msg.warn("⚠ No metadata found by exiftool")
        return nil
    end
    
    msg.info("✓ ExifTool executed successfully")
    msg.info("Raw exiftool output: " .. result.stdout)
    
    -- Parse the output
    local metadata = {}
    msg.info("=== PARSING EXIFTOOL OUTPUT ===")
    for line in result.stdout:gmatch("[^\r\n]+") do
        msg.debug("Line: " .. line)
        parse_metadata_line(line, metadata)
    end
    
    -- Determine detected gamma
    local detected_gamma = detect_gamma_from_metadata(metadata)
    if detected_gamma then
        metadata.detected_gamma = detected_gamma
    end
    
    -- Cache the result
    if o.cache_metadata then
        metadata_cache[video_path] = metadata
    end
    
    msg.info("=== EXIFTOOL DETECTION COMPLETE ===")
    return metadata
end

-- ============================================================================
-- LUT Management Functions
-- ============================================================================

-- Apply LUT based on detected gamma
local function apply_lut_for_gamma(gamma_value)
    msg.info("=== LUT APPLICATION STAGE ===")
    msg.info("Detected gamma: " .. (gamma_value or "nil"))
    
    if not gamma_value then
        msg.error("❌ No gamma value detected, skipping LUT application")
        return false
    end
    
    local lut_config = lut_mapping[gamma_value]
    if not lut_config then
        msg.error("❌ No LUT mapping found for gamma: " .. gamma_value)
        msg.info("Available LUT mappings:")
        for key, config in pairs(lut_mapping) do
            msg.info("  - " .. key .. " → " .. config.description)
        end
        return false
    end
    
    msg.info("✓ Found LUT mapping for: " .. gamma_value)
    msg.info("LUT Config: " .. lut_config.description)
    
    -- Mark that script is changing LUT to prevent false manual detection
    script_lut_changing = true
    
    if lut_config.lut_file == "" then
        -- Clear any existing LUT for Rec.709
        msg.info("Clearing existing LUT (Rec.709 detected)")
        mp.command("set image-lut \"\"")
        mp.command("set image-lut-type auto")
        script_set_lut_path = ""
        manual_lut_mode = false  -- Reset manual mode when script sets LUT
        msg.info("✓ SUCCESS: Applied: " .. lut_config.description .. " (LUT cleared)")
        script_lut_changing = false
        return true
    else
        -- Apply the specified LUT
        local lut_path = o.lut_base_path .. lut_config.lut_file
        msg.info("Applying LUT file: " .. lut_path)
        msg.info("LUT type: " .. lut_config.lut_type)
        
        mp.command("set image-lut \"" .. lut_path .. "\"")
        mp.command("set image-lut-type " .. lut_config.lut_type)
        script_set_lut_path = lut_path
        manual_lut_mode = false  -- Reset manual mode when script sets LUT
        
        msg.info("✓ SUCCESS: Applied: " .. lut_config.description)
        msg.info("✓ LUT file: " .. lut_path)
        script_lut_changing = false
        return true
    end
end

-- Apply LUT with state tracking and manual LUT check
local function apply_lut_with_state_check(gamma_value, video_path)
    -- Check if user manually set LUT, if so, skip automatic operations
    if is_manual_lut() then
        msg.info("⚠ Manual LUT detected, skipping automatic LUT application")
        return false
    end
    
    -- Check if we need to change the LUT state
    if current_lut_state == gamma_value then
        msg.debug("LUT state unchanged (" .. (gamma_value or "none") .. "), skipping application")
        return true
    end
    
    msg.info("=== FAST LUT SWITCHING ===")
    msg.info("Previous LUT state: " .. (current_lut_state or "none"))
    msg.info("New LUT state: " .. (gamma_value or "none"))
    
    local success = apply_lut_for_gamma(gamma_value)
    if success then
        current_lut_state = gamma_value
        msg.info("✓ LUT state updated successfully")
    else
        -- If LUT application failed (e.g., gamma not in mapping), clear LUT if currently applied
        if current_lut_state and current_lut_state ~= "none" then
            if not is_manual_lut() then
                clear_lut("LUT application failed, clearing existing LUT")
            else
                msg.info("LUT application failed, but manual LUT detected, keeping current LUT")
            end
        end
    end
    
    return success
end

-- Handle LUT clearing when no metadata or no gamma detected
local function handle_lut_clearing(reason)
    if current_lut_state and current_lut_state ~= "none" then
        if not is_manual_lut() then
            clear_lut(reason)
        else
            msg.info("Manual LUT detected, keeping current LUT")
        end
    end
end

-- ============================================================================
-- Video Processing Functions
-- ============================================================================

-- Fast LUT switching function for playlist navigation
local function fast_lut_switch()
    if not o.fast_switching then
        return
    end
    
    -- Check if user manually set LUT, if so, skip automatic operations
    if is_manual_lut() then
        msg.debug("Manual LUT detected, skipping fast LUT switch")
        return
    end
    
    local video_path = mp.get_property("path")
    if not video_path then
        return
    end
    
    msg.debug("=== FAST LUT SWITCH TRIGGERED ===")
    msg.debug("Video path: " .. video_path)
    
    -- Try to get cached metadata first
    local metadata = get_exiftool_metadata(video_path)
    
    if metadata and metadata.detected_gamma then
        msg.info("Fast switching to LUT for: " .. metadata.detected_gamma)
        local success = apply_lut_with_state_check(metadata.detected_gamma, video_path)
        -- If LUT application failed and we still have a LUT applied, clear it
        if not success and current_lut_state and current_lut_state ~= "none" then
            handle_lut_clearing("LUT application failed, clearing existing LUT")
        end
    else
        -- No metadata found, clear LUT if currently applied
        handle_lut_clearing("No gamma metadata, clearing LUT")
    end
end

-- Process video file and apply LUT
local function process_video_and_apply_lut()
    if not o.enabled then
        return
    end
    
    local video_path = mp.get_property("path")
    if not video_path then
        msg.debug("No video path available")
        return
    end
    
    -- Skip if not a local file
    if not is_local_file(video_path) then
        msg.debug("Not a local file, skipping exiftool detection")
        return
    end
    
    msg.info("=== EXIFTOOL AUTO LUT ===")
    msg.info("Video file: " .. mp.get_property("filename", "unknown"))
    
    -- Get metadata using exiftool
    local metadata = get_exiftool_metadata(video_path)
    if not metadata then
        msg.info("No metadata found by exiftool")
        handle_lut_clearing("Clearing LUT (no metadata)")
        return
    end
    
    -- Show detected metadata
    display_metadata(metadata)
    
    -- Apply LUT if auto_apply is enabled
    if o.auto_apply and metadata.detected_gamma then
        local success = apply_lut_with_state_check(metadata.detected_gamma, video_path)
        if success then
            msg.info("LUT automatically applied based on exiftool metadata")
        else
            msg.info("No suitable LUT found for this gamma value")
            handle_lut_clearing("Clearing existing LUT (no suitable mapping found)")
        end
    elseif o.auto_apply and not metadata.detected_gamma then
        -- No gamma detected, clear LUT if currently applied
        handle_lut_clearing("No gamma detected, clearing LUT")
    end
    
    msg.info("=== END EXIFTOOL PROCESSING ===")
end

-- ============================================================================
-- Command Handlers
-- ============================================================================

-- Manual command to force processing
local function manual_process_video()
    process_video_and_apply_lut()
end

-- Command to reset manual LUT mode (allow script to take control again)
local function reset_manual_lut_mode()
    manual_lut_mode = false
    script_set_lut_path = nil
    msg.info("✓ Manual LUT mode reset, script will resume automatic LUT operations")
end

-- ============================================================================
-- Event Handlers
-- ============================================================================

-- Event handler for file loaded
local function on_file_loaded()
    -- Check initial LUT state when file loads
    local initial_lut = mp.get_property("image-lut") or ""
    if initial_lut ~= "" and script_set_lut_path == nil then
        -- There's a LUT but script hasn't set one yet - could be from config or manual
        msg.debug("Initial LUT detected: " .. initial_lut)
    end
    
    -- Immediate fast switch attempt
    if o.fast_switching then
        fast_lut_switch()
    end
    
    -- Full processing with small delay to ensure file is properly loaded
    mp.add_timeout(TIMEOUT_DELAYS.file_loaded, process_video_and_apply_lut)
end

-- Event handler for start file (even faster response)
local function on_start_file()
    if o.fast_switching then
        mp.add_timeout(TIMEOUT_DELAYS.start_file, fast_lut_switch)
    end
end

-- Event handler for playlist position change
local function on_playlist_pos_changed()
    if o.fast_switching then
        msg.debug("Playlist position changed, triggering fast LUT switch")
        mp.add_timeout(TIMEOUT_DELAYS.playlist_pos, fast_lut_switch)
    end
end

-- Monitor LUT changes to detect manual user modifications
local function on_lut_changed(name, lut_path)
    -- Skip detection if script is currently changing LUT
    if script_lut_changing then
        return
    end
    
    local current_lut = lut_path or ""
    
    -- If script has set a LUT path, check if current LUT matches
    if script_set_lut_path ~= nil then
        if current_lut ~= script_set_lut_path then
            -- LUT doesn't match what script set, user manually changed it
            manual_lut_mode = true
            msg.info("⚠ Manual LUT detected: " .. (current_lut ~= "" and current_lut or "cleared"))
            msg.info("Automatic LUT operations will be disabled until script sets a new LUT")
        else
            -- LUT matches script setting, reset manual mode (in case it was set before)
            manual_lut_mode = false
        end
    else
        -- Script hasn't set any LUT yet, but there's a LUT now - could be manual or from config
        -- Only mark as manual if we had a previous state
        if current_lut_state and current_lut_state ~= "none" and current_lut ~= "" then
            manual_lut_mode = true
            msg.info("⚠ Manual LUT detected: " .. current_lut)
            msg.info("Automatic LUT operations will be disabled until script sets a new LUT")
        end
    end
end

-- ============================================================================
-- Initialization
-- ============================================================================

-- Key bindings
mp.add_key_binding("Ctrl+e", "exiftool-auto-lut", manual_process_video)
mp.add_key_binding("Ctrl+Shift+e", "exiftool-reset-manual-lut", reset_manual_lut_mode)

-- Event listeners
mp.register_event("file-loaded", on_file_loaded)
mp.register_event("start-file", on_start_file)

-- Property observers for faster response
mp.observe_property("playlist-pos", "number", on_playlist_pos_changed)
mp.observe_property("path", "string", function(name, path)
    if o.fast_switching and path then
        msg.debug("Path changed, triggering fast LUT switch")
        mp.add_timeout(TIMEOUT_DELAYS.path_change, fast_lut_switch)
    end
end)

-- Monitor LUT changes
mp.observe_property("image-lut", "string", on_lut_changed)

-- Script messages
mp.register_script_message("exiftool-process", manual_process_video)

-- Startup message
msg.info("ExifTool Auto LUT script loaded with fast switching")
msg.info("Press 'Ctrl+e' to manually process video metadata")
msg.info("Press 'Ctrl+Shift+e' to reset manual LUT mode")
msg.info("Auto-processing: " .. (o.auto_apply and "enabled" or "disabled"))
msg.info("Fast switching: " .. (o.fast_switching and "enabled" or "disabled"))
msg.info("Metadata caching: " .. (o.cache_metadata and "enabled" or "disabled"))
msg.info("ExifTool path: " .. o.exiftool_path)
msg.info("Manual LUT protection: enabled (script will not override manually set LUTs)")
