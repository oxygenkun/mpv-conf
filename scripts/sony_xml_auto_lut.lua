--[[
Sony XML Auto LUT Script for MPV
This script automatically detects Sony camera XML metadata files and applies appropriate LUTs
based on the CaptureGammaEquation value found in the XML file.
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
    cache_xml_data = true,      -- Cache XML metadata to speed up switching
    pre_scan_playlist = true,   -- Pre-scan playlist files for XML metadata
}

-- Cache for XML metadata to speed up switching
local xml_cache = {}
local current_lut_state = nil

-- LUT mapping based on CaptureGammaEquation
local lut_mapping = {
    ["s-log3-cine"] = {
        lut_file = "SLog3SGamut3.CineToLC-709.cube",
        lut_type = "normalized",
        description = "Sony S-Log3 to Rec.709"
    },
    ["s-log3"] = {
        lut_file = "SLog3SGamut3.CineToLC-709.cube",
        lut_type = "normalized",
        description = "Sony S-Log3 to Rec.709"
    },
    ["rec709"] = {
        lut_file = "",
        lut_type = "auto",
        description = "Rec.709 (No LUT needed)"
    },
    -- Add more mappings as needed
    ["s-log2"] = {
        lut_file = "SLog3SGamut3.CineToSLog2-709.cube",
        lut_type = "normalized",
        description = "Sony S-Log2 to Rec.709"
    }
}

-- Function to find Sony XML file
local function find_sony_xml(video_path)
    msg.info("=== XML FILE SEARCH STAGE ===")
    msg.info("Video path: " .. (video_path or "nil"))
    
    if not video_path or video_path == "" then
        msg.error("❌ FAILED: No video path provided")
        return nil
    end
    
    local dir, filename = utils.split_path(video_path)
    if not filename then
        msg.error("❌ FAILED: Cannot extract filename from path")
        return nil
    end
    
    msg.info("Directory: " .. (dir or "nil"))
    msg.info("Filename: " .. filename)
    
    -- Remove file extension
    local name_without_ext = filename:match("(.+)%..+$") or filename
    msg.info("Name without extension: " .. name_without_ext)
    
    -- Common Sony XML naming patterns
    local xml_patterns = {
        name_without_ext .. "M01.XML",  -- Most common pattern
        name_without_ext .. "01.XML",   -- Alternative pattern
        name_without_ext .. ".XML",     -- Simple pattern
    }
    
    msg.info("Searching for XML files with patterns:")
    for i, pattern in ipairs(xml_patterns) do
        msg.info("  " .. i .. ". " .. pattern)
    end
    
    for i, pattern in ipairs(xml_patterns) do
        local xml_path = dir .. pattern
        msg.info("Checking pattern " .. i .. ": " .. xml_path)
        
        -- Check if file exists by trying to read it
        local file = io.open(xml_path, "r")
        if file then
            file:close()
            msg.info("✓ SUCCESS: Found Sony XML file: " .. xml_path)
            return xml_path
        else
            msg.info("❌ Not found: " .. xml_path)
        end
    end
    
    msg.info("❌ FAILED: No Sony XML file found for: " .. filename)
    return nil
end

-- Function to parse Sony XML file
local function parse_sony_xml(xml_path)
    msg.info("=== XML PARSING STAGE ===")
    msg.info("Attempting to open XML file: " .. xml_path)
    
    local file = io.open(xml_path, "r")
    if not file then
        msg.error("❌ FAILED: Cannot open XML file: " .. xml_path)
        return nil
    end
    msg.info("✓ SUCCESS: XML file opened successfully")
    
    local xml_content = file:read("*all")
    file:close()
    
    if not xml_content then
        msg.error("❌ FAILED: Cannot read XML file content")
        return nil
    end
    msg.info("✓ SUCCESS: XML content read successfully (" .. string.len(xml_content) .. " characters)")
    
    local metadata = {}
    
    -- Parse CaptureGammaEquation - try both formats
    msg.info("--- Parsing CaptureGammaEquation ---")
    
    -- Format 1: <Item name="CaptureGammaEquation" value="s-log3-cine"/>
    local gamma_equation = xml_content:match('<Item name="CaptureGammaEquation" value="([^"]+)"')
    if gamma_equation then
        msg.info("✓ SUCCESS: Found CaptureGammaEquation (Item format): " .. gamma_equation)
        metadata.gamma_equation = gamma_equation:lower():gsub("%s+", "-") -- normalize spacing
        msg.info("✓ Normalized gamma equation: " .. metadata.gamma_equation)
    else
        msg.info("⚠ Format 1 failed, trying Format 2...")
        -- Format 2: <CaptureGammaEquation>value</CaptureGammaEquation>
        gamma_equation = xml_content:match("<CaptureGammaEquation>([^<]+)</CaptureGammaEquation>")
        if gamma_equation then
            msg.info("✓ SUCCESS: Found CaptureGammaEquation (direct format): " .. gamma_equation)
            metadata.gamma_equation = gamma_equation:lower():gsub("%s+", "-")
            msg.info("✓ Normalized gamma equation: " .. metadata.gamma_equation)
        else
            msg.error("❌ FAILED: CaptureGammaEquation not found in XML")
            msg.debug("XML content preview (first 500 chars): " .. string.sub(xml_content, 1, 500))
        end
    end
    
    -- Parse CaptureColorPrimaries
    msg.info("--- Parsing CaptureColorPrimaries ---")
    local color_primaries = xml_content:match('<Item name="CaptureColorPrimaries" value="([^"]+)"')
    if color_primaries then
        metadata.color_primaries = color_primaries
        msg.info("✓ SUCCESS: Found CaptureColorPrimaries: " .. color_primaries)
    else
        msg.info("⚠ CaptureColorPrimaries not found")
    end
    
    -- Parse additional useful metadata
    msg.info("--- Parsing Additional Metadata ---")
    
    local device_model = xml_content:match('<Device manufacturer="[^"]*" modelName="([^"]+)"')
    if device_model then
        metadata.camera_model = device_model
        msg.info("✓ SUCCESS: Found Camera Model: " .. device_model)
    else
        msg.info("⚠ Camera Model not found")
    end
    
    local lens_model = xml_content:match('<Lens modelName="([^"]+)"')
    if lens_model then
        metadata.lens_model = lens_model
        msg.info("✓ SUCCESS: Found Lens Model: " .. lens_model)
    else
        msg.info("⚠ Lens Model not found")
    end
    
    local video_codec = xml_content:match('<VideoFrame videoCodec="([^"]+)"')
    if video_codec then
        metadata.video_codec = video_codec
        msg.info("✓ SUCCESS: Found Video Codec: " .. video_codec)
    else
        msg.info("⚠ Video Codec not found")
    end
    
    local capture_fps = xml_content:match('<VideoFrame[^>]+captureFps="([^"]+)"')
    if capture_fps then
        metadata.capture_fps = capture_fps
        msg.info("✓ SUCCESS: Found Capture FPS: " .. capture_fps)
    else
        msg.info("⚠ Capture FPS not found")
    end
    
    msg.info("=== XML PARSING COMPLETE ===")
    return metadata
end

-- Function to get cached XML metadata or parse if not cached
local function get_xml_metadata(video_path)
    if not video_path then
        return nil
    end
    
    -- Check cache first
    if o.cache_xml_data and xml_cache[video_path] then
        msg.debug("✓ Using cached XML metadata for: " .. video_path)
        return xml_cache[video_path]
    end
    
    -- Find and parse XML file
    local xml_path = find_sony_xml(video_path)
    if not xml_path then
        -- Cache negative result to avoid repeated searches
        if o.cache_xml_data then
            xml_cache[video_path] = false
        end
        return nil
    end
    
    local metadata = parse_sony_xml(xml_path)
    
    -- Cache the result
    if o.cache_xml_data then
        xml_cache[video_path] = metadata or false
    end
    
    return metadata
end

-- Function to pre-scan playlist for XML metadata
local function pre_scan_playlist()
    if not o.pre_scan_playlist then
        return
    end
    
    local playlist = mp.get_property_native("playlist", {})
    if not playlist or #playlist <= 1 then
        return
    end
    
    msg.info("Pre-scanning playlist for XML metadata...")
    local scanned_count = 0
    
    for i, entry in ipairs(playlist) do
        if entry.filename and not xml_cache[entry.filename] then
            local metadata = get_xml_metadata(entry.filename)
            if metadata then
                scanned_count = scanned_count + 1
                msg.debug("Pre-scanned: " .. entry.filename .. " → " .. (metadata.gamma_equation or "no gamma"))
            end
        end
    end
    
    if scanned_count > 0 then
        msg.info("✓ Pre-scanned " .. scanned_count .. " files with XML metadata")
    end
end

-- Function to apply LUT based on gamma equation
local function apply_lut_for_gamma(gamma_equation)
    msg.info("=== LUT APPLICATION STAGE ===")
    msg.info("Gamma equation: " .. (gamma_equation or "nil"))
    
    if not gamma_equation then
        msg.error("❌ FAILED: No gamma equation found, skipping LUT application")
        return false
    end
    
    local lut_config = lut_mapping[gamma_equation]
    if not lut_config then
        msg.error("❌ FAILED: No LUT mapping found for gamma equation: " .. gamma_equation)
        msg.info("Available LUT mappings:")
        for key, config in pairs(lut_mapping) do
            msg.info("  - " .. key .. " → " .. config.description)
        end
        return false
    end
    
    msg.info("✓ SUCCESS: Found LUT mapping for: " .. gamma_equation)
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
local function apply_lut_with_state_check(gamma_equation, video_path)
    -- Check if we need to change the LUT state
    if current_lut_state == gamma_equation then
        msg.debug("LUT state unchanged (" .. (gamma_equation or "none") .. "), skipping application")
        return true
    end
    
    msg.info("=== FAST LUT SWITCHING ===")
    msg.info("Previous LUT state: " .. (current_lut_state or "none"))
    msg.info("New LUT state: " .. (gamma_equation or "none"))
    
    local success = apply_lut_for_gamma(gamma_equation)
    if success then
        current_lut_state = gamma_equation
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
    local metadata = get_xml_metadata(video_path)
    
    if metadata and metadata.gamma_equation then
        msg.info("Fast switching to LUT for: " .. metadata.gamma_equation)
        apply_lut_with_state_check(metadata.gamma_equation, video_path)
    else
        -- No XML metadata found, clear LUT if currently applied
        if current_lut_state and current_lut_state ~= "none" then
            msg.info("No XML metadata, clearing LUT")
            mp.command("set image-lut \"\"")
            mp.command("set image-lut-type auto")
            current_lut_state = "none"
        end
    end
end
-- Function to process Sony XML and apply LUT
local function process_sony_xml_and_apply_lut()
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
        msg.debug("Not a local file, skipping XML detection")
        return
    end
    
    msg.info("=== SONY XML AUTO LUT ===")
    msg.info("Video file: " .. mp.get_property("filename", "unknown"))
    
    -- Get metadata (from cache or by parsing)
    local metadata = get_xml_metadata(video_path)
    if not metadata then
        msg.info("No Sony XML metadata file found")
        -- Clear LUT if no metadata found
        if current_lut_state and current_lut_state ~= "none" then
            msg.info("Clearing LUT (no XML metadata)")
            mp.command("set image-lut \"\"")
            mp.command("set image-lut-type auto")
            current_lut_state = "none"
        end
        return
    end
    
    -- Show detected metadata
    if o.show_detection then
        msg.info("=== SONY METADATA DETECTED ===")
        if metadata.camera_model then
            msg.info("Camera Model: " .. metadata.camera_model)
        end
        if metadata.lens_model then
            msg.info("Lens Model: " .. metadata.lens_model)
        end
        if metadata.gamma_equation then
            msg.info("Gamma Equation: " .. metadata.gamma_equation)
        end
        if metadata.color_primaries then
            msg.info("Color Primaries: " .. metadata.color_primaries)
        end
        if metadata.video_codec then
            msg.info("Video Codec: " .. metadata.video_codec)
        end
        if metadata.capture_fps then
            msg.info("Capture FPS: " .. metadata.capture_fps)
        end
    end
    
    -- Apply LUT if auto_apply is enabled
    if o.auto_apply and metadata.gamma_equation then
        local success = apply_lut_with_state_check(metadata.gamma_equation, video_path)
        if success then
            msg.info("LUT automatically applied based on XML metadata")
        else
            msg.info("No suitable LUT found for this gamma equation")
        end
    end
    
    msg.info("=== END SONY XML PROCESSING ===")
end

-- Manual command to force XML processing
local function manual_process_xml()
    process_sony_xml_and_apply_lut()
end

-- Event handler for file loaded
local function on_file_loaded()
    -- Immediate fast switch attempt
    if o.fast_switching then
        fast_lut_switch()
    end
    
    -- Full processing with small delay to ensure file is properly loaded
    mp.add_timeout(0.5, process_sony_xml_and_apply_lut)
    
    -- Pre-scan playlist in background
    if o.pre_scan_playlist then
        mp.add_timeout(2.0, pre_scan_playlist)
    end
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
mp.add_key_binding("Ctrl+x", "sony-xml-auto-lut", manual_process_xml)

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
mp.register_script_message("sony-xml-process", manual_process_xml)

msg.info("Sony XML Auto LUT script loaded with fast switching")
msg.info("Press 'Ctrl+x' to manually process Sony XML metadata")
msg.info("Auto-processing: " .. (o.auto_apply and "enabled" or "disabled"))
msg.info("Fast switching: " .. (o.fast_switching and "enabled" or "disabled"))
msg.info("XML caching: " .. (o.cache_xml_data and "enabled" or "disabled"))
msg.info("Playlist pre-scan: " .. (o.pre_scan_playlist and "enabled" or "disabled"))
