#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
mod api_native;
mod app_native;
mod models;
fn main() -> eframe::Result {
    let options = eframe::NativeOptions {
        viewport: eframe::egui::ViewportBuilder::default()
            .with_title("JScope Tactical Control")
            .with_inner_size([1600.0, 950.0])
            .with_min_inner_size([1100.0, 700.0]),
        ..Default::default()
    };
    eframe::run_native(
        "JScope Tactical Control",
        options,
        Box::new(|cc| Ok(Box::new(app_native::JScopeApp::new(cc)))),
    )
}
