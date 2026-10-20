import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';
import type * as OpenApiPlugin from 'docusaurus-plugin-openapi-docs';
import {themes as prismThemes} from 'prism-react-renderer';
import {GlobExcludeDefault} from '@docusaurus/utils';
import {undeliveredFeatureGlobs} from './src/features';

const repoUrl = 'https://github.com/RobertDeRose/nixstasis';

// The product page in the repository's site/ directory owns the Pages root; the docs live under docs/.
const siteBaseUrl = '/nixstasis/';
const baseUrl = `${siteBaseUrl}docs/`;
// Docusaurus prefixes baseUrl to every root-relative link, so the product page is addressed as baseUrl's
// parent; pathname:// keeps it a plain link instead of a client-side route.
const productPageHref = `pathname://${baseUrl}../`;

// Each spec in docs/reference/openapi renders into a generated, git-ignored
// docs/reference/api/<name> directory; `npm run gen-api` regenerates them.
const apiSpecs = ['device', 'e2e', 'report'];
const openApiConfig: Record<string, OpenApiPlugin.Options> = Object.fromEntries(
  apiSpecs.map((name) => [
    name,
    {
      specPath: `docs/reference/openapi/${name}-api.yaml`,
      outputDir: `docs/reference/api/${name}`,
      sidebarOptions: {groupPathsBy: 'tag', categoryLinkSource: 'tag'},
    },
  ]),
);

const config: Config = {
  title: 'Nixstasis',
  tagline: 'IoT monitoring and remote access',
  favicon: 'img/nixstasis-logo.svg',
  url: 'https://robertderose.github.io',
  baseUrl,
  trailingSlash: false,
  // The product page reads the same localStorage key, so the color mode carries between the two.
  storage: {type: 'localStorage', namespace: false},

  // Rspack-based build; the OpenAPI theme does not bundle under webpack's module concatenation.
  // Rspack's persistent cache is off because concurrent builds (docs:serve plus the hk docs step)
  // corrupt it and crash Rspack.
  future: {
    faster: {
      swcJsLoader: true,
      swcJsMinimizer: true,
      swcHtmlMinimizer: true,
      lightningCssMinimizer: true,
      mdxCrossCompilerCache: true,
      rspackBundler: true,
      rspackPersistentCache: false,
      ssgWorkerThreads: true,
      gitEagerVcs: true,
    },
    v4: {removeLegacyPostBuildHeadAttribute: true},
  },

  onBrokenLinks: 'throw',
  onBrokenAnchors: 'throw',

  markdown: {
    // .md pages are CommonMark; only .mdx pages are parsed as MDX.
    format: 'detect',
    mermaid: true,
    hooks: {
      onBrokenMarkdownLinks: 'throw',
      onBrokenMarkdownImages: 'throw',
    },
  },
  themes: [
    '@docusaurus/theme-mermaid',
    'docusaurus-theme-openapi-docs',
    [
      '@easyops-cn/docusaurus-search-local',
      {hashed: true, docsDir: 'docs', docsRouteBasePath: '/', indexBlog: false, indexPages: false},
    ],
  ],

  staticDirectories: ['static'],
  clientModules: ['./src/clientModules/index.ts'],

  presets: [
    [
      'classic',
      {
        docs: {
          path: 'docs',
          routeBasePath: '/',
          sidebarPath: './sidebars.ts',
          // Only completed work is published; undelivered feature designs stay out of the site.
          exclude: [...GlobExcludeDefault, ...undeliveredFeatureGlobs()],
          editUrl: `${repoUrl}/edit/dev/website/`,
          docItemComponent: '@theme/ApiItem',
        },
        blog: false,
        pages: {path: 'src/pages'},
        // Brand tokens are shared with the product page in the repository's site/ directory.
        theme: {customCss: ['../site/brand.css', './src/css/custom.css']},
      } satisfies Preset.Options,
    ],
  ],

  plugins: [
    [
      'docusaurus-plugin-openapi-docs',
      {id: 'api', docsPluginId: 'classic', config: openApiConfig},
    ],
  ],

  themeConfig: {
    colorMode: {respectPrefersColorScheme: true},
    // Brand colors are applied in src/css/custom.css; base themes keep Mermaid's palette neutral.
    // Mermaid sizes boxes with this font, so it must match the site's body font.
    mermaid: {
      theme: {light: 'neutral', dark: 'dark'},
      options: {fontFamily: "'IBM Plex Sans', sans-serif", themeVariables: {fontFamily: "'IBM Plex Sans', sans-serif"}},
    },
    navbar: {
      title: 'Nixstasis',
      logo: {alt: 'Nixstasis logo', src: 'img/nixstasis-logo.svg', href: productPageHref, target: '_self'},
      items: [
        {to: '/', label: 'Docs', position: 'left', activeBaseRegex: '.*'},
        {href: repoUrl, label: 'GitHub', position: 'right'},
      ],
    },
    docs: {sidebar: {hideable: true}},
    languageTabs: [
      {highlight: 'bash', language: 'curl', logoClass: 'curl'},
      {highlight: 'go', language: 'go', logoClass: 'go'},
      {highlight: 'python', language: 'python', logoClass: 'python'},
      {highlight: 'javascript', language: 'nodejs', logoClass: 'nodejs'},
    ],
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['elixir', 'go', 'bash', 'yaml', 'json', 'toml'],
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
