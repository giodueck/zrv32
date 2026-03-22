//////////////////////////////////////////////////////////////////////////////////
//                                                                              //
// StyleAsCode exporter v2.0 - Style data exported as a values array            //
//                                                                              //
// USAGE: On init call: GuiLoadStyleGenesis();                                   //
//                                                                              //
// more info and bugs-report:  github.com/raysan5/raygui                        //
// feedback and support:       ray[at]raylibtech.com                            //
//                                                                              //
// Copyright (c) 2020-2025 raylib technologies (@raylibtech)                    //
//                                                                              //
//////////////////////////////////////////////////////////////////////////////////

const rg = @import("raygui");

const GENESIS_STYLE_PROPS_COUNT = 23;

// Custom style name: Genesis
const genesisStyleProps = [_]rg.StyleProp{
    .{ .controlId = 0, .propertyId = 0, .propertyValue = @bitCast(@as(u32, 0x667384ff)) }, // DEFAULT_BORDER_COLOR_NORMAL
    .{ .controlId = 0, .propertyId = 1, .propertyValue = @bitCast(@as(u32, 0x181b1eff)) }, // DEFAULT_BASE_COLOR_NORMAL
    .{ .controlId = 0, .propertyId = 2, .propertyValue = @bitCast(@as(u32, 0xc2c8d0ff)) }, // DEFAULT_TEXT_COLOR_NORMAL
    .{ .controlId = 0, .propertyId = 3, .propertyValue = @bitCast(@as(u32, 0xd3dbdfff)) }, // DEFAULT_BORDER_COLOR_FOCUSED
    .{ .controlId = 0, .propertyId = 4, .propertyValue = @bitCast(@as(u32, 0xa7afb0ff)) }, // DEFAULT_BASE_COLOR_FOCUSED
    .{ .controlId = 0, .propertyId = 5, .propertyValue = @bitCast(@as(u32, 0x020202ff)) }, // DEFAULT_TEXT_COLOR_FOCUSED
    .{ .controlId = 0, .propertyId = 6, .propertyValue = @bitCast(@as(u32, 0x181b1eff)) }, // DEFAULT_BORDER_COLOR_PRESSED
    .{ .controlId = 0, .propertyId = 7, .propertyValue = @bitCast(@as(u32, 0xac3c3cff)) }, // DEFAULT_BASE_COLOR_PRESSED
    .{ .controlId = 0, .propertyId = 8, .propertyValue = @bitCast(@as(u32, 0xdededeff)) }, // DEFAULT_TEXT_COLOR_PRESSED
    .{ .controlId = 0, .propertyId = 9, .propertyValue = @bitCast(@as(u32, 0x3e4550ff)) }, // DEFAULT_BORDER_COLOR_DISABLED
    .{ .controlId = 0, .propertyId = 10, .propertyValue = @bitCast(@as(u32, 0x2e353dff)) }, // DEFAULT_BASE_COLOR_DISABLED
    .{ .controlId = 0, .propertyId = 11, .propertyValue = @bitCast(@as(u32, 0x484f57ff)) }, // DEFAULT_TEXT_COLOR_DISABLED
    .{ .controlId = 0, .propertyId = 16, .propertyValue = @bitCast(@as(u32, 0x00000010)) }, // DEFAULT_TEXT_SIZE
    .{ .controlId = 0, .propertyId = 17, .propertyValue = @bitCast(@as(u32, 0x00000000)) }, // DEFAULT_TEXT_SPACING
    .{ .controlId = 0, .propertyId = 18, .propertyValue = @bitCast(@as(u32, 0x96a3b4ff)) }, // DEFAULT_LINE_COLOR
    .{ .controlId = 0, .propertyId = 19, .propertyValue = @bitCast(@as(u32, 0x292c33ff)) }, // DEFAULT_BACKGROUND_COLOR
    .{ .controlId = 0, .propertyId = 20, .propertyValue = @bitCast(@as(u32, 0x00000008)) }, // DEFAULT_TEXT_LINE_SPACING
    .{ .controlId = 1, .propertyId = 5, .propertyValue = @bitCast(@as(u32, 0x97a9aeff)) }, // LABEL_TEXT_COLOR_FOCUSED
    .{ .controlId = 4, .propertyId = 5, .propertyValue = @bitCast(@as(u32, 0xa69a9aff)) }, // SLIDER_TEXT_COLOR_FOCUSED
    .{ .controlId = 4, .propertyId = 6, .propertyValue = @bitCast(@as(u32, 0xc3ccd5ff)) }, // SLIDER_BORDER_COLOR_PRESSED
    .{ .controlId = 6, .propertyId = 6, .propertyValue = @bitCast(@as(u32, 0xa7aeb5ff)) }, // CHECKBOX_BORDER_COLOR_PRESSED
    .{ .controlId = 9, .propertyId = 5, .propertyValue = @bitCast(@as(u32, 0xa9a5a5ff)) }, // TEXTBOX_TEXT_COLOR_FOCUSED
    .{ .controlId = 10, .propertyId = 5, .propertyValue = @bitCast(@as(u32, 0xc9c7c7ff)) }, // VALUEBOX_TEXT_COLOR_FOCUSED
};

// Style loading function: Genesis
pub fn GuiLoadStyleGenesis() void {
    // Load style properties provided
    // NOTE: Default properties are propagated
    inline for (genesisStyleProps) |prop| {
        rg.cdef.GuiSetStyle(@enumFromInt(prop.controlId), prop.propertyId, prop.propertyValue);
    }

    //-----------------------------------------------------------------

    // TODO: Custom user style setup: Set specific properties here (if required)
    // i.e. Controls specific BORDER_WIDTH, TEXT_PADDING, TEXT_ALIGNMENT
}
