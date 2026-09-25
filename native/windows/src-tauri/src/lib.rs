use tauri::{LogicalPosition, LogicalSize, Manager};
use tauri_plugin_updater::UpdaterExt;

const PREFERRED_DESKTOP_ZOOM: f64 = 0.67;
const MIN_SAFE_ZOOM: f64 = 0.55;
const TARGET_CONTENT_WIDTH: f64 = 1280.0;
const TARGET_CONTENT_HEIGHT: f64 = 760.0;

fn workspace_zoom_factor(window_width: f64, window_height: f64) -> f64 {
    if window_width <= 0.0 || window_height <= 0.0 {
        return PREFERRED_DESKTOP_ZOOM;
    }

    // 67% is the Edusentia Windows desktop baseline. Only compact work areas
    // zoom farther out when necessary so the application retains a useful
    // desktop-sized CSS viewport instead of introducing avoidable scrolling.
    let width_fit = window_width / TARGET_CONTENT_WIDTH;
    let height_fit = window_height / TARGET_CONTENT_HEIGHT;

    PREFERRED_DESKTOP_ZOOM
        .min(width_fit)
        .min(height_fit)
        .clamp(MIN_SAFE_ZOOM, PREFERRED_DESKTOP_ZOOM)
}

fn configure_responsive_window(window: &tauri::WebviewWindow) -> tauri::Result<()> {
    let monitor = match window.current_monitor()? {
        Some(monitor) => Some(monitor),
        None => match window.primary_monitor()? {
            Some(monitor) => Some(monitor),
            None => window.available_monitors()?.into_iter().next(),
        },
    };

    let Some(monitor) = monitor else {
        // Even when monitor discovery is unavailable, keep the requested
        // Edusentia desktop workspace baseline.
        window.set_zoom(PREFERRED_DESKTOP_ZOOM)?;
        return Ok(());
    };

    // Tauri exposes the monitor work area excluding taskbars/docks in physical
    // pixels. Convert to logical pixels so Windows DPI scaling is respected.
    let scale = monitor.scale_factor().max(0.5);
    let work_area = monitor.work_area();
    let work_x = work_area.position.x as f64 / scale;
    let work_y = work_area.position.y as f64 / scale;
    let work_width = work_area.size.width as f64 / scale;
    let work_height = work_area.size.height as f64 / scale;

    if work_width <= 0.0 || work_height <= 0.0 {
        window.set_zoom(PREFERRED_DESKTOP_ZOOM)?;
        return Ok(());
    }

    // Keep the normal desktop experience generous while supporting smaller
    // school laptops, high-DPI displays and compact Windows devices.
    let min_width = work_width.min(760.0);
    let min_height = work_height.min(520.0);
    let target_width = (work_width * 0.92).min(1600.0).max(min_width);
    let target_height = (work_height * 0.90).min(1000.0).max(min_height);

    window.set_min_size(Some(LogicalSize::new(min_width, min_height)))?;
    window.set_size(LogicalSize::new(target_width, target_height))?;

    let x = work_x + ((work_width - target_width) / 2.0).max(0.0);
    let y = work_y + ((work_height - target_height) / 2.0).max(0.0);
    window.set_position(LogicalPosition::new(x, y))?;

    // Use WebView2/Tauri native zoom instead of CSS transform scaling. This
    // preserves pointer coordinates, fixed-position elements and scroll bounds.
    window.set_zoom(workspace_zoom_factor(target_width, target_height))?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn close(a: f64, b: f64) -> bool {
        (a - b).abs() < 0.000_001
    }

    #[test]
    fn desktop_uses_67_percent_baseline() {
        assert!(close(workspace_zoom_factor(1600.0, 1000.0), 0.67));
    }

    #[test]
    fn normal_laptop_keeps_67_percent_baseline() {
        assert!(close(workspace_zoom_factor(1256.0, 691.0), 0.67));
    }

    #[test]
    fn compact_width_zooms_farther_out_to_fit() {
        assert!(close(workspace_zoom_factor(800.0, 600.0), 0.625));
    }

    #[test]
    fn very_small_workspace_never_goes_below_safe_floor() {
        assert!(close(workspace_zoom_factor(500.0, 400.0), 0.55));
    }
}

fn configure_native_updater(app: &tauri::App) -> tauri::Result<()> {
    if option_env!("EDUSENTIA_NEON_ENABLE_NATIVE_UPDATER") != Some("1") {
        return Ok(());
    }

    app.handle()
        .plugin(tauri_plugin_updater::Builder::new().build())?;

    let handle = app.handle().clone();
    tauri::async_runtime::spawn(async move {
        let updater = match handle.updater() {
            Ok(updater) => updater,
            Err(error) => {
                eprintln!("native_updater_unavailable: {error}");
                return;
            }
        };

        match updater.check().await {
            Ok(Some(update)) => {
                let target_version = update.version.clone();
                if let Err(error) = update.download_and_install(|_, _| {}, || {}).await {
                    eprintln!("native_update_failed version={target_version}: {error}");
                }
            }
            Ok(None) => {}
            Err(error) => eprintln!("native_update_check_failed: {error}"),
        }
    });

    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            configure_native_updater(app)?;
            if let Some(window) = app.get_webview_window("main") {
                // Sizing and workspace zoom are best-effort. The conservative
                // tauri.conf fallback still opens correctly if an API is unavailable.
                let _ = configure_responsive_window(&window);
                window.show()?;
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running Edusentia Enterprise Neon Edition");
}
