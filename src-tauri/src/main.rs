// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    // WebKitGTK GPU compatibility fix for Linux
    // Disables DMA-BUF renderer to prevent "GBM EGL display" errors on systems
    // with incompatible GPU drivers. See README for details on enabling GPU acceleration.
    #[cfg(target_os = "linux")]
    {
        if std::env::var("WEBKIT_DISABLE_DMABUF_RENDERER").is_err() {
            std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
        }
    }

    maestro_linux_lib::run()
}
