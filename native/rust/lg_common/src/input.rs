//! 输入 JSON 解析（engine_abi.h v2 约定）：
//!   {"type":"point","phase":"down|move|up|cancel","x":0.5,"y":0.5,"pointer":1}
//!   {"type":"key","code":"ok|cancel|menu|up|down|left|right|speed|auto|skip|
//!                        save|load|text","state":"down|up","repeat":false}
//!   {"type":"text","utf8":"…"}
//!
//! x/y 为渲染面归一化坐标（0~1）；壳负责乘以表面像素尺寸。
//! 各上游核心的按键码差异由壳各自映射（本模块只给 VK 基准）。

use serde_json::Value;

#[derive(Debug, Clone, PartialEq)]
pub enum LgInput {
    /// phase：0=down 1=move 2=up 3=cancel（Android MotionEvent 语义）。
    Point {
        phase: u8,
        x: f64,
        y: f64,
        pointer: u32,
    },
    Key {
        name: String,
        down: bool,
    },
    Text(String),
}

/// 解析单条输入事件 JSON；格式不符返回 None（调用方静默丢弃并记日志）。
pub fn parse(json: &str) -> Option<LgInput> {
    let v: Value = serde_json::from_str(json).ok()?;
    match v.get("type")?.as_str()? {
        "point" => {
            let phase = match v.get("phase")?.as_str()? {
                "down" => 0u8,
                "move" => 1,
                "up" => 2,
                "cancel" => 3,
                _ => return None,
            };
            Some(LgInput::Point {
                phase,
                x: v.get("x")?.as_f64()?,
                y: v.get("y")?.as_f64()?,
                pointer: v.get("pointer").and_then(Value::as_u64).unwrap_or(1) as u32,
            })
        }
        "key" => Some(LgInput::Key {
            name: v.get("code")?.as_str()?.to_owned(),
            down: v.get("state").and_then(Value::as_str) != Some("up"),
        }),
        "text" => Some(LgInput::Text(
            v.get("utf8")?.as_str()?.to_owned(),
        )),
        _ => None,
    }
}

/// 逻辑键名 → Windows VK 码基准（各核心按需再映射：sena 用 UTF-8 字符、
/// siglus Android 用 AKEYCODE、artemis/rfvp 吃 VK）。
pub fn vk_code(name: &str) -> u32 {
    match name {
        "ok" | "enter" => 13,       // VK_RETURN
        "cancel" => 27,             // VK_ESCAPE
        "up" => 38,                 // VK_UP
        "down" => 40,               // VK_DOWN
        "left" => 37,               // VK_LEFT
        "right" => 39,              // VK_RIGHT
        "menu" => 112,              // VK_F1（引擎惯例：菜单/设置）
        "save" => 113,              // VK_F2
        "load" => 114,              // VK_F3
        "skip" => 115,              // VK_F4
        "auto" => 116,              // VK_F5
        "speed" | "ctrl" => 17,     // VK_CONTROL（快进）
        "text" | "space" => 32,     // VK_SPACE（下一句）
        "back" => 27,               // VK_ESCAPE
        _ => 0,
    }
}

/// 逻辑键名 → AKEYCODE 基准（Android KeyEvent）。
pub fn akeycode(name: &str) -> i32 {
    match name {
        "ok" | "enter" => 66,   // AKEYCODE_ENTER
        "cancel" => 4,          // AKEYCODE_BACK
        "up" => 19,
        "down" => 20,
        "left" => 21,
        "right" => 22,
        "menu" => 82,           // AKEYCODE_MENU
        "save" => 133,          // F2
        "load" => 134,
        "skip" => 135,
        "auto" => 136,
        "speed" | "ctrl" => 113, // AKEYCODE_CTRL_LEFT
        "text" | "space" => 62,
        "back" => 4,
        _ => 0,
    }
}
