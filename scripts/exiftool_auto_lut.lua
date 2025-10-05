--[[
ExifTool Auto LUT Script for MPV
This script uses exiftool to detect gamma information from video files and automatically applies appropriate LUTs.
Primary detection method: 'Acquisition Record Group Item Value: s-log3-cine'
--]]

local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'

-- Configuration
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

-- Cache for exiftool metadata to speed up switching
local metadata_cache = {}
local current_lut_state = nil

-- LUT mapping based on detected gamma values
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

-- Function to run exiftool and get metadata
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
        -- "-g",                    -- Group names
        "-AcquisitionRecordGroupItemValue",  -- Specific tag we want
        "-CaptureGammaEquation", -- Alternative gamma tag
        "-ColorSpace",           -- Color space info
        "-Gamma",                -- Gamma info
        "-TransferCharacteristics", -- Transfer characteristics
        "-ColorPrimaries",       -- Color primaries
        "-MatrixCoefficients",   -- Matrix coefficients
        video_path
    }
    
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
    local lines = {}
    for line in result.stdout:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    
    msg.info("=== PARSING EXIFTOOL OUTPUT ===")
    for i, line in ipairs(lines) do
        msg.debug("Line " .. i .. ": " .. line)
        
        -- Parse Acquisition Record Group Item Value (primary detection)
        local acquisition_value = line:match("AcquisitionRecordGroupItemValue%s*:%s*(.+)")
        if acquisition_value then
            acquisition_value = acquisition_value:gsub("^%s*(.-)%s*$", "%1") -- trim whitespace
            metadata.acquisition_value = acquisition_value:lower()
            msg.info("✓ Found Acquisition Record Group Item Value: " .. acquisition_value)
        end
        
        -- Parse CaptureGammaEquation (alternative detection)
        local gamma_equation = line:match("CaptureGammaEquation%s*:%s*(.+)")
        if gamma_equation then
            gamma_equation = gamma_equation:gsub("^%s*(.-)%s*$", "%1") -- trim whitespace
            metadata.gamma_equation = gamma_equation:lower()
            msg.info("✓ Found CaptureGammaEquation: " .. gamma_equation)
        end
        
        -- Parse ColorSpace
        local color_space = line:match("ColorSpace%s*:%s*(.+)")
        if color_space then
            color_space = color_space:gsub("^%s*(.-)%s*$", "%1") -- trim whitespace
            metadata.color_space = color_space
            msg.info("✓ Found ColorSpace: " .. color_space)
        end
        
        -- Parse Gamma
        local gamma = line:match("Gamma%s*:%s*(.+)")
        if gamma then
            gamma = gamma:gsub("^%s*(.-)%s*$", "%1") -- trim whitespace
            metadata.gamma = gamma
            msg.info("✓ Found Gamma: " .. gamma)
        end
        
        -- Parse TransferCharacteristics
        local transfer = line:match("TransferCharacteristics%s*:%s*(.+)")
        if transfer then
            transfer = transfer:gsub("^%s*(.-)%s*$", "%1") -- trim whitespace
            metadata.transfer_characteristics = transfer
            msg.info("✓ Found TransferCharacteristics: " .. transfer)
        end
        
        -- Parse ColorPrimaries
        local primaries = line:match("ColorPrimaries%s*:%s*(.+)")
        if primaries then
            primaries = primaries:gsub("^%s*(.-)%s*$", "%1") -- trim whitespace
            metadata.color_primaries = primaries
            msg.info("✓ Found ColorPrimaries: " .. primaries)
        end
        
        -- Parse MatrixCoefficients
        local matrix = line:match("MatrixCoefficients%s*:%s*(.+)")
        if matrix then
            matrix = matrix:gsub("^%s*(.-)%s*$", "%1") -- trim whitespace
            metadata.matrix_coefficients = matrix
            msg.info("✓ Found MatrixCoefficients: " .. matrix)
        end
    end
    
    -- Determine the best gamma detection method
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
        -- Normalize the gamma value
        detected_gamma = detected_gamma:gsub("%s+", "-"):gsub("_", "-")
        metadata.detected_gamma = detected_gamma
        msg.info("✓ Final detected gamma: " .. detected_gamma)
    else
        msg.warn("⚠ No gamma information detected")
    end
    
    -- Cache the result
    if o.cache_metadata then
        metadata_cache[video_path] = metadata
    end
    
    msg.info("=== EXIFTOOL DETECTION COMPLETE ===")
    return metadata
end

-- Function to apply LUT based on detected gamma
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
    
    if lut_config.lut_file == "" then
        -- Clear any existing LUT for Rec.709
        msg.info("Clearing existing LUT (Rec.709 detected)")
        mp.command("set image-lut \"\"")
        mp.command("set image-lut-type auto")
        msg.info("✓ SUCCESS: Applied: " .. lut_config.description .. " (LUT cleared)")
        return true
    else
        -- Apply the specified LUT
        local lut_path = o.lut_base_path .. lut_config.lut_file
        msg.info("Applying LUT file: " .. lut_path)
        msg.info("LUT type: " .. lut_config.lut_type)
        
        mp.command("set image-lut \"" .. lut_path .. "\"")
        mp.command("set image-lut-type " .. lut_config.lut_type)
        
        msg.info("✓ SUCCESS: Applied: " .. lut_config.description)
        msg.info("✓ LUT file: " .. lut_path)
        return true
    end
end

-- Function to apply LUT with state tracking
local function apply_lut_with_state_check(gamma_value, video_path)
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
    end
    
    return success
end

-- Fast LUT switching function for playlist navigation
local function fast_lut_switch()
    if not o.fast_switching then
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
        apply_lut_with_state_check(metadata.detected_gamma, video_path)
    else
        -- No metadata found, clear LUT if currently applied
        if current_lut_state and current_lut_state ~= "none" then
            msg.info("No gamma metadata, clearing LUT")
            mp.command("set image-lut \"\"")
            mp.command("set image-lut-type auto")
            current_lut_state = "none"
        end
    end
end

-- Function to process video file and apply LUT
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
    if not video_path:match("^[A-Za-z]:[/\\]") and not video_path:match("^/") then
        msg.debug("Not a local file, skipping exiftool detection")
        return
    end
    
    msg.info("=== EXIFTOOL AUTO LUT ===")
    msg.info("Video file: " .. mp.get_property("filename", "unknown"))
    
    -- Get metadata using exiftool
    local metadata = get_exiftool_metadata(video_path)
    if not metadata then
        msg.info("No metadata found by exiftool")
        -- Clear LUT if no metadata found
        if current_lut_state and current_lut_state ~= "none" then
            msg.info("Clearing LUT (no metadata)")
            mp.command("set image-lut \"\"")
            mp.command("set image-lut-type auto")
            current_lut_state = "none"
        end
        return
    end
    
    -- Show detected metadata
    if o.show_detection then
        msg.info("=== METADATA DETECTED ===")
        if metadata.acquisition_value then
            msg.info("Acquisition Record Group Item Value: " .. metadata.acquisition_value)
        end
        if metadata.gamma_equation then
            msg.info("CaptureGammaEquation: " .. metadata.gamma_equation)
        end
        if metadata.color_space then
            msg.info("ColorSpace: " .. metadata.color_space)
        end
        if metadata.gamma then
            msg.info("Gamma: " .. metadata.gamma)
        end
        if metadata.transfer_characteristics then
            msg.info("TransferCharacteristics: " .. metadata.transfer_characteristics)
        end
        if metadata.color_primaries then
            msg.info("ColorPrimaries: " .. metadata.color_primaries)
        end
        if metadata.matrix_coefficients then
            msg.info("MatrixCoefficients: " .. metadata.matrix_coefficients)
        end
        if metadata.detected_gamma then
            msg.info("Detected Gamma: " .. metadata.detected_gamma)
        end
    end
    
    -- Apply LUT if auto_apply is enabled
    if o.auto_apply and metadata.detected_gamma then
        local success = apply_lut_with_state_check(metadata.detected_gamma, video_path)
        if success then
            msg.info("LUT automatically applied based on exiftool metadata")
        else
            msg.info("No suitable LUT found for this gamma value")
        end
    end
    
    msg.info("=== END EXIFTOOL PROCESSING ===")
end

-- Manual command to force processing
local function manual_process_video()
    process_video_and_apply_lut()
end

-- Event handler for file loaded
local function on_file_loaded()
    -- Immediate fast switch attempt
    if o.fast_switching then
        fast_lut_switch()
    end
    
    -- Full processing with small delay to ensure file is properly loaded
    mp.add_timeout(0.5, process_video_and_apply_lut)
end

-- Event handler for start file (even faster response)
local function on_start_file()
    if o.fast_switching then
        mp.add_timeout(0.1, fast_lut_switch)
    end
end

-- Event handler for playlist position change
local function on_playlist_pos_changed()
    if o.fast_switching then
        msg.debug("Playlist position changed, triggering fast LUT switch")
        mp.add_timeout(0.05, fast_lut_switch)
    end
end

-- Key binding for manual processing
mp.add_key_binding("Ctrl+e", "exiftool-auto-lut", manual_process_video)

-- Event listeners
mp.register_event("file-loaded", on_file_loaded)
mp.register_event("start-file", on_start_file)

-- Property observers for faster response
mp.observe_property("playlist-pos", "number", on_playlist_pos_changed)
mp.observe_property("path", "string", function(name, path)
    if o.fast_switching and path then
        msg.debug("Path changed, triggering fast LUT switch")
        mp.add_timeout(0.02, fast_lut_switch)
    end
end)

-- Script messages
mp.register_script_message("exiftool-process", manual_process_video)

msg.info("ExifTool Auto LUT script loaded with fast switching")
msg.info("Press 'Ctrl+e' to manually process video metadata")
msg.info("Auto-processing: " .. (o.auto_apply and "enabled" or "disabled"))
msg.info("Fast switching: " .. (o.fast_switching and "enabled" or "disabled"))
msg.info("Metadata caching: " .. (o.cache_metadata and "enabled" or "disabled"))
msg.info("ExifTool path: " .. o.exiftool_path)
