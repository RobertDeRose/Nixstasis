import reflex as rx


config = rx.Config(
    # The name of the application, used for project identification
    app_name="nixstasis",
    # Database connection string
    # Currently using SQLite for local development/deployment
    db_url="sqlite:///nixstasis.db",
    # List of Reflex plugins enabled for this project
    plugins=[
        # Tailwind CSS version 4 integration for styling
        rx.plugins.TailwindV4Plugin(),
        # Sitemap generator for SEO (though this app is largely authenticated)
        rx.plugins.SitemapPlugin(),
    ],
    # Application logging level
    loglevel=rx.constants.LogLevel.INFO,
    # Hide the "Built with Reflex" badge from the UI
    show_built_with_reflex=False,
)
