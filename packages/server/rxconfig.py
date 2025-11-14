import reflex as rx


config = rx.Config(
    app_name="nixstasis",
    db_url="sqlite:///nixstasis.db",
    plugins=[
        rx.plugins.TailwindV4Plugin(),
        rx.plugins.SitemapPlugin(),
    ],
    loglevel=rx.constants.LogLevel.INFO,
    show_built_with_reflex=False,
)
