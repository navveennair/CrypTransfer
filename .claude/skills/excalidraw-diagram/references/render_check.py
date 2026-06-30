from playwright.sync_api import sync_playwright

with open("cryptransfer_erd.excalidraw", encoding="utf-8") as f:
    content = f.read()

with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page(viewport={"width": 1600, "height": 1100})
    page.goto("https://excalidraw.com", wait_until="networkidle")
    page.wait_for_timeout(1500)

    page.evaluate(
        """(content) => {
            const dt = new DataTransfer();
            const file = new File([content], 'cryptransfer_erd.excalidraw', { type: 'application/json' });
            dt.items.add(file);
            const target = document.querySelector('.excalidraw') || document.body;
            for (const type of ['dragenter', 'dragover', 'drop']) {
                const ev = new DragEvent(type, { bubbles: true, cancelable: true });
                Object.defineProperty(ev, 'dataTransfer', { value: dt });
                target.dispatchEvent(ev);
            }
        }""",
        content,
    )

    page.wait_for_timeout(2000)
    page.keyboard.press("Shift+1")  # zoom to fit
    page.wait_for_timeout(500)
    page.screenshot(path="erd_preview.png", full_page=False)
    browser.close()

print("saved erd_preview.png")
