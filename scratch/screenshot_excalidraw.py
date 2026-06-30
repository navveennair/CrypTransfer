import sys
from playwright.sync_api import sync_playwright

file_path = sys.argv[1]
out_path = sys.argv[2]
focus_x = float(sys.argv[3]) if len(sys.argv) > 3 else 430
focus_y = float(sys.argv[4]) if len(sys.argv) > 4 else 320
zoom_steps = int(sys.argv[5]) if len(sys.argv) > 5 else 12

with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page(viewport={"width": 1600, "height": 1200})
    page.add_init_script("delete window.showOpenFilePicker;")
    page.goto("https://excalidraw.com", wait_until="networkidle")
    page.wait_for_timeout(1500)

    with page.expect_file_chooser(timeout=10000) as fc_info:
        page.get_by_text("Open", exact=True).first.click()
    fc = fc_info.value
    fc.set_files(file_path)
    page.wait_for_timeout(2000)

    page.keyboard.press("Shift+1")
    page.wait_for_timeout(800)

    page.mouse.move(focus_x, focus_y)
    page.keyboard.down("Control")
    for _ in range(zoom_steps):
        page.mouse.wheel(0, -120)
        page.wait_for_timeout(20)
    page.keyboard.up("Control")

    page.wait_for_timeout(500)
    page.screenshot(path=out_path, full_page=False)
    browser.close()
    print(f"Saved screenshot to {out_path}")
