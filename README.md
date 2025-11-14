# Welcome to Nixstasis

This project is built using the following tools:

* [`Python 3.13+`](https://docs.python.org/3.13/)
* [`uv`](https://docs.astral.sh/uv/getting-started/installation/): Project and dependency management
* [`Reflex`](https://reflex.dev/open-source/): Front-end and Back-end development in pure Python

## Project Structure

This project has the following directory structure:

```bash
├── README.md
├── assets
├── rxconfig.py
└── nixstasis
    ├── __init__.py
    ├── backend
    │   ├── __init__.py
    │   └── . . .
    ├── components
    │   ├── __init__.py
    │   └── . . .
    ├── pages
    │   ├── __init__.py
    │   └── . . .
    ├── models.py
    ├── states
    │   ├── __init__.py
    │   └── . . .
    ├── styles.py
    ├── templates
    │   ├── __init__.py
    │   └── . . .
    └── nixstasis.py
```

See [Reflex's Project Structure docs](https://reflex.dev/docs/getting-started/project-structure/) for more general
information about the Reflex project structure.

### Adding Pages

In this project, pages are defined in `nixstasis/pages/`. Each page is a function that returns a Reflex component. For
example, to edit the index page you modify `nixstasis/pages/index.py`. See the [pages
docs](https://reflex.dev/docs/pages/routes/) for more information on pages.

In this project, instead of using `rx.add_page` or the `@rx.page` decorator, it uses the `@template` decorator from
`nixstasis/templates/template.py`.

To add a new page:

1. Add a new file in `nixstasis/pages/`. Its recommend to use one file per page, but you can also group pages in a
   single file.
2. Add a new function with the `@template` decorator, which takes the same arguments as `@rx.page`.
3. Import the page in `nixstasis/pages/__init__.py` file and it will automatically be added to the app.
4. Order the pages in `nixstasis/components/sidebar.py` and `nixstasis/components/navbar.py`.

### Adding Components

In order to keep the code organized, its recommend putting components that are used across multiple pages in to the
`nixstasis/components/` directory.

In this project, there is a sidebar component in `nixstasis/components/sidebar.py` as well as a navbar in
`nixstasis/components/navbar.py`.

### Adding State

As the app grows, its recommend using [substates](https://reflex.dev/docs/substates/overview/) to organize state.

You can either define substates in their own files, or if the state is specific to a page, you can define it in the page
file itself.

## Running Nixstasis in Development Mode

To run the application locally for development and debugging there is a `VSCode` launch configuration called `Start
Nixstasis`. This will invoke `reflex run` and attached the debugger to the instance.
