import reflex as rx


def _badge(status: str):
    badge_mapping = {
        "Online": ("plug", "Online", "green"),
        "Offline": ("unplug", "Offline", "red"),
    }
    icon, text, color_scheme = badge_mapping.get(status, ("loader", "Pending", "yellow"))
    return rx.badge(
        rx.icon(icon, size=16),
        text,
        color_scheme=color_scheme,
        radius="large",
        variant="surface",
        size="2",
    )


def status_badge(status: str):
    return rx.match(
        status,
        ("Online", _badge("Online")),
        ("Offline", _badge("Offline")),
        _badge("Offline"),
    )
