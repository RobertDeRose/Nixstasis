"""Sidebar component for the app."""

import reflex as rx

from .. import styles


class SidebarState(rx.State):
    active_tab: str

    def set_active(self, tab: str):
        self.active_tab = tab

    @rx.event
    def set_initial_tab(self):
        from nixstasis.templates.template import ALL_PAGES

        path = self.router.url.path
        tab = ALL_PAGES[path].get("title") if path in ALL_PAGES else "Dashboard"
        self.set_active(tab)


def header(with_menu: bool = False) -> rx.Component:
    """Sidebar header.

    Returns:
        The sidebar header component.

    """
    return rx.hstack(
        # The logo.
        rx.icon("tower-control", color=rx.color("accent"), size=50),
        rx.el.span("Nixstasis", class_name="font-bold text-2xl"),
        rx.spacer(),
        rx.cond(with_menu, menu_button()),
        align="center",
        width="100%",
        padding="" if with_menu else "0.35em",
        padding_y="1.25em" if with_menu else "",
        padding_x=["1em", "1em", "2em"] if with_menu else "",
        margin_bottom="1em",
    )


def footer() -> rx.Component:
    """Sidebar footer.

    Returns:
        The sidebar footer component.

    """
    return rx.hstack(
        rx.link(
            rx.text("CheckDocs", size="3"),
            href="https://checkdocs.checkpoint-service.com/",
            color_scheme="gray",
            underline="none",
        ),
        rx.spacer(),
        justify="start",
        align="center",
        width="100%",
        padding="0.35em",
    )


def _menu_item(text: str, icon: str, href: str) -> rx.Component:
    """Sidebar item.

    Args:
        text: The text of the item.
        icon: The icon of the item.
        url: The URL of the item.

    Returns:
        rx.Component: The sidebar item component.
    """

    is_active = SidebarState.active_tab == text

    return rx.link(
        rx.hstack(
            rx.icon(icon, size=20),
            rx.text(text, size="4"),
            width="100%",
            padding_x="0.5rem",
            padding_y="0.75rem",
            color=rx.cond(is_active, rx.color("accent"), rx.color("gray")),
            align="center",
            style={
                "_hover": {
                    "bg": rx.color("accent", 4),
                    "color": rx.color("accent", 11),
                },
                "border-radius": "0.5em",
            },
        ),
        href=href,
        underline="none",
        weight="medium",
        width="100%",
        on_click=lambda: SidebarState.set_active(text),
    )


def menu_items() -> rx.Component:
    from nixstasis.templates.template import ALL_PAGES

    return rx.vstack(
        *[
            _menu_item(
                text=page.get("title", page["route"].strip("/").capitalize()),
                icon=page.get("icon", "page_content"),
                href=page["route"],
            )
            for page in ALL_PAGES.values()
        ],
        spacing="1",
        width="100%",
    )


def menu_button() -> rx.Component:
    return rx.drawer.root(
        rx.drawer.trigger(
            rx.icon("align-justify"),
        ),
        rx.drawer.overlay(z_index="5"),
        rx.drawer.portal(
            rx.drawer.content(
                rx.vstack(
                    rx.hstack(
                        rx.spacer(),
                        rx.drawer.close(rx.icon(tag="x")),
                        justify="end",
                        width="100%",
                    ),
                    rx.divider(),
                    menu_items(),
                    rx.spacer(),
                    footer(),
                    spacing="4",
                    width="100%",
                ),
                top="auto",
                left="auto",
                height="100%",
                width="20em",
                padding="1em",
                bg=rx.color("gray", 1),
            ),
            width="100%",
        ),
        direction="right",
    )


def navbar() -> rx.Component:
    """The navbar.

    Returns:
        The navbar component.

    """
    return rx.el.nav(
        header(with_menu=True),
        display=["block", "block", "block", "block", "block", "none"],
        position="sticky",
        background_color=rx.color("gray", 1),
        top="0px",
        z_index="5",
        border_bottom=styles.border,
    )


def sidebar() -> rx.Component:
    """The sidebar.

    Returns:
        The sidebar component.
    """

    return rx.fragment(
        navbar(),
        rx.flex(
            rx.vstack(
                header(),
                menu_items(),
                rx.spacer(),
                footer(),
                justify="end",
                align="end",
                width=styles.sidebar_content_width,
                height="100dvh",
                padding="1em",
            ),
            display=["none", "none", "none", "none", "none", "flex"],
            max_width=styles.sidebar_width,
            width="auto",
            height="100%",
            position="sticky",
            justify="end",
            top="0px",
            left="0px",
            flex="1",
            bg=rx.color("gray", 2),
        ),
        on_mount=SidebarState.set_initial_tab,
    )
