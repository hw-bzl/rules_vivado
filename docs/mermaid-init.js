// Renders the `<pre class="mermaid">` blocks mdbook-mermaid emits, picking
// mermaid's light or dark theme from the mdBook theme and re-rendering
// when the reader switches themes (mdBook swaps the class on <html>).
(() => {
    const darkThemes = ["ayu", "navy", "coal"];
    const html = document.documentElement;
    const diagrams = Array.from(document.querySelectorAll("pre.mermaid"));
    if (diagrams.length === 0 || typeof mermaid === "undefined") {
        return;
    }
    const sources = diagrams.map((el) => el.textContent);

    const currentTheme = () =>
        darkThemes.some((cls) => html.classList.contains(cls)) ? "dark" : "default";

    let renderedTheme = null;
    const render = () => {
        const theme = currentTheme();
        if (theme === renderedTheme) {
            return;
        }
        renderedTheme = theme;
        mermaid.initialize({ startOnLoad: false, theme });
        diagrams.forEach((el, i) => {
            el.removeAttribute("data-processed");
            el.textContent = sources[i];
        });
        mermaid.run({ nodes: diagrams });
    };

    render();
    new MutationObserver(render).observe(html, { attributes: true, attributeFilter: ["class"] });
})();
