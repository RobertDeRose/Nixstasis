// Color mode toggle that mirrors the Docusaurus docs: it cycles system, light, dark; stores the choice under the
// same localStorage key ("theme", removed for system); and sets the same html attributes.
(function () {
  var root = document.documentElement;
  var media = matchMedia('(prefers-color-scheme: dark)');
  var button = document.querySelector('.theme-toggle');
  var next = {system: 'light', light: 'dark', dark: 'system'};

  function systemMode() {
    return media.matches ? 'dark' : 'light';
  }

  function apply(choice) {
    root.setAttribute('data-theme-choice', choice);
    root.setAttribute('data-theme', choice === 'system' ? systemMode() : choice);
    button.setAttribute('aria-label', 'Switch between dark and light mode (currently ' + choice + ' mode)');
    button.title = choice + ' mode';
  }

  button.addEventListener('click', function () {
    var choice = next[root.getAttribute('data-theme-choice')] || 'light';
    try {
      if (choice === 'system') localStorage.removeItem('theme');
      else localStorage.setItem('theme', choice);
    } catch (e) {}
    apply(choice);
  });

  media.addEventListener('change', function () {
    if (root.getAttribute('data-theme-choice') === 'system') apply('system');
  });

  apply(root.getAttribute('data-theme-choice') || 'system');
})();
